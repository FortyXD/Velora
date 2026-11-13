"""Focused, dependency-free backend tests; all storage/sysfs fixtures are private."""
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/scripts/power/analytics.py"
# Do not leave generated files next to the production script.
spec = importlib.util.spec_from_file_location("power_analytics", SCRIPT)
analytics = importlib.util.module_from_spec(spec)
previous_bytecode = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    spec.loader.exec_module(analytics)
finally:
    sys.dont_write_bytecode = previous_bytecode


class PowerAnalyticsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sysfs = self.root / "sysfs"
        self.sysfs.mkdir()
        self.state = self.root / "state"

    def supply(self, name, **fields):
        path = self.sysfs / name
        path.mkdir(exist_ok=True)
        for key, value in fields.items():
            (path / key).write_text(str(value))
        return path

    def battery(self, name="BAT0", **fields):
        defaults = dict(type="Battery", scope="System", present=1,
                        status="Discharging", energy_now=20000000,
                        energy_full=40000000, voltage_now=12000000,
                        power_now=6000000, temp=321)
        defaults.update(fields)
        return self.supply(name, **defaults)

    def sample(self, timestamp, power=5, **extra):
        sample = analytics.empty_sample(timestamp)
        sample.update(battery_power_w=power, percentage=50, voltage_v=12,
                      energy_wh=20, temperature_c=30, status="discharging")
        sample.update(extra)
        return sample

    def command(self, command, *arguments):
        return [sys.executable, str(SCRIPT), command, "--state-dir", str(self.state), *arguments]

    def start(self, command, *arguments):
        process = subprocess.Popen(self.command(command, *arguments), stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.stop, process)
        return process

    @staticmethod
    def stop(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        for stream in (process.stdout, process.stderr):
            if stream:
                stream.close()

    def line(self, process, timeout=5):
        ready, _, _ = select.select([process.stdout], [], [], timeout)
        self.assertTrue(ready, "watch did not produce an update")
        line = process.stdout.readline()
        self.assertTrue(line, "watch exited unexpectedly")
        return json.loads(line)

    def latest(self, after=None, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = json.loads((self.state / analytics.LATEST).read_text())
                if after is None or value["timestamp"] > after:
                    return value
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.025)
        self.fail("collector did not atomically publish latest")

    def test_sysfs_conversions_sign_missing_and_peripherals(self):
        battery = self.battery()
        self.supply("hid-mouse-battery", type="Battery", scope="Device", power_now=99999999)
        self.supply("controller", type="Battery", power_now=99999999)
        self.supply("BATmouse", type="Battery", scope="Device", power_now=99999999)
        self.supply("AC", type="Mains", online=1)
        sample, topology = analytics.sample_sysfs(self.sysfs, 100)
        self.assertEqual(topology, ("BAT0",))
        self.assertEqual(sample, self.sample(100, 6, temperature_c=32.1, ac_online=True))
        for key in ("energy_now", "energy_full", "power_now"):
            (battery / key).unlink()
        self.supply("BAT0", charge_now=2000000, charge_full=4000000,
                    current_now=-500000, status="Charging")
        sample, _ = analytics.sample_sysfs(self.sysfs, 101)
        self.assertEqual(sample["energy_wh"], 24)
        self.assertEqual(sample["percentage"], 50)
        self.assertEqual(sample["battery_power_w"], -6)
        (battery / "voltage_now").unlink()
        (battery / "temp").unlink()
        self.supply("thermal_zone0", type="x86_pkg_temp", temp=90000)
        sample, _ = analytics.sample_sysfs(self.sysfs, 102)
        for key in ("energy_wh", "battery_power_w", "voltage_v", "temperature_c", "percentage"):
            self.assertIsNone(sample[key])
        self.supply("BAT0", status="Full", capacity=140)
        sample, _ = analytics.sample_sysfs(self.sysfs, 103)
        self.assertIsNone(sample["battery_power_w"])
        self.assertEqual(sample["percentage"], 100)
        self.supply("BAT0", power_now=0, status="Not charging")
        sample, _ = analytics.sample_sysfs(self.sysfs, 104)
        self.assertEqual(sample["battery_power_w"], 0)
        self.assertEqual(sample["status"], "not-charging")
        self.supply("BAT0", power_now=2000000, status="Unknown")
        sample, _ = analytics.sample_sysfs(self.sysfs, 105)
        self.assertIsNone(sample["battery_power_w"])

    def test_multiple_batteries_complete_aggregation_only(self):
        self.battery()
        other = self.battery("BAT1", status="Charging", energy_now=30000000,
                             energy_full=60000000, power_now=2000000,
                             voltage_now=15000000, temp=380)
        self.supply("AC", type="Mains", online=0)
        self.supply("USB", type="USB_C")
        sample, _ = analytics.sample_sysfs(self.sysfs, 100)
        self.assertEqual(sample["status"], "mixed")
        self.assertEqual(sample["energy_wh"], 50)
        self.assertEqual(sample["battery_power_w"], 4)
        self.assertEqual(sample["percentage"], 50)
        self.assertIsNone(sample["voltage_v"])
        self.assertIsNone(sample["ac_online"])
        self.assertEqual(sample["temperature_c"], 38)
        (other / "power_now").unlink()
        (other / "energy_now").unlink()
        (other / "energy_full").unlink()
        sample, _ = analytics.sample_sysfs(self.sysfs, 101)
        for key in ("battery_power_w", "energy_wh", "percentage"):
            self.assertIsNone(sample[key])
        self.supply("BAT1", present=0)
        sample, topology = analytics.sample_sysfs(self.sysfs, 102)
        self.assertEqual(topology, ("BAT0",))
        self.assertEqual(sample["battery_power_w"], 6)

    def test_exact_monotonic_cadence_no_catchup_busyloop(self):
        clock = [100.0]
        sleeps = []

        def sleep(seconds):
            self.assertGreater(seconds, 0)
            sleeps.append(seconds)
            clock[0] += seconds

        cadence = analytics.Cadence(lambda: clock[0], sleep)
        measured = []
        for _ in range(5):
            cadence.wait()
            measured.append(clock[0])
            clock[0] += 0.125  # measurement/serialization work does not drift cadence
        self.assertEqual(measured, [100, 102, 104, 106, 108])
        clock[0] += 17
        cadence.wait()
        late = clock[0]
        cadence.wait()
        self.assertEqual(clock[0], late + 2)
        self.assertEqual(analytics.INTERVAL, 2)
        self.assertTrue(all(delay <= 2 for delay in sleeps))

    def test_bounded_ring_retention_restart_and_crc_recovery(self):
        directory = analytics.open_directory(self.state, create=True)
        self.addCleanup(os.close, directory)
        analytics.exclusive(directory)
        ring = analytics.Ring(directory)
        try:
            for i in range(analytics.CAPACITY + 9):
                ring.append(self.sample(1000 + 2 * i, power=i % 19))
            size = (self.state / analytics.HISTORY).stat().st_size
            self.assertLess(size, 2_000_000)
            records = analytics.read_records(ring.fd)
            self.assertEqual(len(records), analytics.CAPACITY)
            self.assertEqual(records[0][1]["timestamp"], 1018)
            last_seq, last = records[-1]
            # A torn record is skipped, not interpreted as zero power.
            offset = analytics.HEADER.size + ((last_seq - 2) % analytics.CAPACITY) * analytics.RECORD_SIZE
            os.pwrite(ring.fd, b"broken", offset)
            self.assertEqual(len(analytics.read_records(ring.fd)), analytics.CAPACITY - 1)
        finally:
            ring.close()
        ring = analytics.Ring(directory)
        try:
            self.assertEqual(ring.sequence, last_seq)
            now = last["timestamp"] + analytics.RETENTION + 20
            ring.append(self.sample(now, gap_before=True))
            records = analytics.read_records(ring.fd)
            self.assertEqual(len(records), 1)  # expired measurements physically zeroed
            self.assertEqual(records[0][1]["timestamp"], now)
            self.assertEqual((self.state / analytics.HISTORY).stat().st_size, size)
            ring.append(self.sample(now - 1))  # wall-clock rollback
            records = analytics.read_records(ring.fd)
            self.assertEqual(len(records), 1)
            self.assertTrue(records[0][1]["gap_before"])
        finally:
            ring.close()

    def test_downsample_all_metric_extrema_and_propagated_gaps(self):
        samples = [self.sample(1000 + i * 2, power=(i % 31) - 10) for i in range(14400)]
        for index, metric in enumerate(analytics.METRICS):
            samples[101 + index * 203][metric] = -1000 - index
            samples[102 + index * 203][metric] = 1000 + index
        # More discontinuities than the point cap; omitted gaps must carry forward.
        for i in range(1, len(samples), 9):
            samples[i]["gap_before"] = True
        result = analytics.downsample(samples, 300)
        self.assertLessEqual(len(result), 300)
        self.assertEqual(result[0]["timestamp"], samples[0]["timestamp"])
        self.assertEqual(result[-1]["timestamp"], samples[-1]["timestamp"])
        times = [s["timestamp"] for s in result]
        self.assertEqual(times, sorted(set(times)))
        self.assertEqual(result, analytics.downsample(samples, 300))
        for metric in analytics.METRICS:
            self.assertEqual(min(s[metric] for s in result), min(s[metric] for s in samples))
            self.assertEqual(max(s[metric] for s in result), max(s[metric] for s in samples))
        previous = -1
        for sample in result:
            index = int((sample["timestamp"] - 1000) / 2)
            original = samples[index]
            self.assertEqual({k: v for k, v in sample.items() if k != "gap_before"},
                             {k: v for k, v in original.items() if k != "gap_before"})
            if any(s.get("gap_before") for s in samples[previous + 1:index + 1]):
                self.assertTrue(sample.get("gap_before"))
            previous = index
        sparse = [self.sample(0), self.sample(2), self.sample(100), self.sample(102)]
        # Snapshot normally marks raw gaps; downsampler also detects raw time gaps.
        many = [self.sample(i * 2 + (100 if i >= 400 else 0)) for i in range(1000)]
        reduced = analytics.downsample(many, 300)
        self.assertTrue(any(s.get("gap_before") for s in reduced if s["timestamp"] >= 900))
        self.assertEqual(analytics.downsample(sparse, 300), sparse)
        # Missing one metric must survive display reduction without breaking others.
        missing = [self.sample(1000 + 2 * i) for i in range(1000)]
        missing[10]["battery_power_w"] = None
        missing[20]["voltage_v"] = None
        reduced = analytics.downsample(missing, 300)
        previous_index = -1
        for sample in reduced:
            index = int((sample["timestamp"] - 1000) / 2)
            for key in ("battery_power_w", "voltage_v"):
                if any(s[key] is None for s in missing[previous_index + 1:index + 1]):
                    self.assertIn(key, sample.get("gaps_before", []))
            previous_index = index
        self.assertTrue(any("battery_power_w" in s.get("gaps_before", []) for s in reduced))

    def test_stats_gaps_missing_and_signed_energy(self):
        samples = [self.sample(0, 10), self.sample(2, -10),
                   self.sample(100, 100), self.sample(102, 100, gap_before=True),
                   self.sample(104, None)]
        stats = analytics.statistics(samples)
        self.assertEqual(stats["power_min"], -10)
        self.assertEqual(stats["power_max"], 100)
        self.assertEqual(stats["power_mean"], 50)
        self.assertAlmostEqual(stats["energy_in_wh"], 5 / 3600)
        self.assertAlmostEqual(stats["energy_out_wh"], 5 / 3600)
        self.assertTrue(all(v is None for v in analytics.statistics([]).values()))
        self.assertIsNone(analytics.statistics([self.sample(0, 10)])["energy_out_wh"])
        directory = analytics.open_directory(self.state, create=True)
        try:
            ring = analytics.Ring(directory)
            for sample in samples:
                ring.append(sample)
            ring.close()
        finally:
            os.close(directory)
        result = analytics.snapshot(self.state, 1200, 300, now=104)
        self.assertEqual(result["sample_count"], 5)
        self.assertEqual([s["timestamp"] for s in result["points"]], [0, 2, 100, 102, 104])
        self.assertTrue(result["points"][2]["gap_before"])
        self.assertEqual(result["window_start"], -1096)  # no fabricated points before enable
        crc_state = self.root / "crc-gap"
        directory = analytics.open_directory(crc_state, create=True)
        ring = analytics.Ring(directory)
        try:
            for timestamp in (1000, 1002, 1004):
                ring.append(self.sample(timestamp, 10))
            os.pwrite(ring.fd, b"bad", analytics.HEADER.size + analytics.RECORD_SIZE)
        finally:
            ring.close()
            os.close(directory)
        result = analytics.snapshot(crc_state, 1200, 300, now=1004)
        self.assertEqual(result["sample_count"], 2)
        self.assertTrue(result["points"][1]["gap_before"])
        self.assertIsNone(result["stats"]["energy_out_wh"])

    def test_owner_clear_lock_inode_and_symlink_safety(self):
        directory = analytics.open_directory(self.state, create=True)
        analytics.exclusive(directory)
        ring = analytics.Ring(directory)
        ring.append(self.sample(time.time()))
        ring.close()
        inode = self.state.stat().st_ino
        try:
            self.assertEqual(analytics.snapshot(self.state, 1200, 300)["sample_count"], 1)
            with self.assertRaises(RuntimeError):
                analytics.clear(self.state)
            other = analytics.open_directory(self.state)
            try:
                with self.assertRaises(RuntimeError):
                    analytics.exclusive(other)
            finally:
                os.close(other)
            self.assertTrue((self.state / analytics.HISTORY).exists())
        finally:
            os.close(directory)
        target = self.root / "unrelated"
        target.write_text("keep")
        (self.state / analytics.LATEST).symlink_to(target)
        analytics.clear(self.state)  # unlink symlink itself, never traverse it
        self.assertEqual(target.read_text(), "keep")
        self.assertEqual(self.state.stat().st_ino, inode)
        self.assertEqual(list(self.state.iterdir()), [])
        alias = self.root / "alias"
        alias.symlink_to(self.state, target_is_directory=True)
        with self.assertRaises(OSError):
            analytics.clear(alias)
        with self.assertRaises(OSError):
            analytics.open_directory(alias / "child", create=True)
        self.assertFalse((self.state / "child").exists())
        # Refuse hard-linked rings as well as symlinks.
        os.link(target, self.state / analytics.HISTORY)
        directory = analytics.open_directory(self.state)
        try:
            with self.assertRaises(PermissionError):
                analytics.Ring(directory)
        finally:
            os.close(directory)
        self.assertEqual(target.read_text(), "keep")

    def test_process_collect_watch_clear_and_no_recreation(self):
        self.battery()
        collector = self.start("collect", "--sysfs-root", str(self.sysfs))
        first = self.latest()
        self.assertEqual(first["battery_power_w"], 6)
        self.assertTrue(first["gap_before"])
        duplicate = subprocess.run(self.command("collect", "--sysfs-root", str(self.sysfs)),
                                   capture_output=True, text=True, timeout=3)
        self.assertEqual(duplicate.returncode, 1)
        self.assertEqual(duplicate.stdout, "")
        blocked = subprocess.run(self.command("clear"), capture_output=True, text=True, timeout=3)
        self.assertEqual(blocked.returncode, 1)
        second = self.latest(after=first["timestamp"])
        self.assertAlmostEqual(second["timestamp"] - first["timestamp"], 2, delta=0.35)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o700)
        for path in self.state.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        watcher = self.start("watch", "--window-seconds", "1200", "--points", "300")
        output = self.line(watcher)
        self.assertGreaterEqual(output["sample_count"], 2)
        self.assertEqual(output["latest"]["battery_power_w"], 6)
        self.assertEqual(set(output), {"latest", "points", "window_start", "window_end", "sample_count", "stats"})
        # Topology change marks an observed discontinuity without making up zeros.
        self.battery("BAT1", power_now=2000000)
        changed = self.latest(after=second["timestamp"])
        self.assertTrue(changed["gap_before"])
        self.assertEqual(changed["battery_power_w"], 8)
        collector.terminate()
        stdout, stderr = collector.communicate(timeout=3)
        self.assertEqual(collector.returncode, 0)
        self.assertEqual((stdout, stderr), ("", ""))
        # A shell reload resumes the same bounded history but marks discontinuity.
        restarted = self.start("collect", "--sysfs-root", str(self.sysfs))
        resumed = self.latest(after=changed["timestamp"])
        self.assertTrue(resumed["gap_before"])
        self.assertGreaterEqual(analytics.snapshot(self.state, 1200, 300)["sample_count"], 4)
        self.stop(restarted)
        inode = self.state.stat().st_ino
        cleared = subprocess.run(self.command("clear"), capture_output=True, text=True, timeout=3)
        self.assertEqual(cleared.returncode, 0, cleared.stderr)
        self.assertEqual(self.state.stat().st_ino, inode)
        self.assertEqual(list(self.state.iterdir()), [])
        # A watch already running must not recreate storage after disable.
        for _ in range(3):
            output = self.line(watcher)
            if output["sample_count"] == 0:
                break
        self.assertIsNone(output["latest"])
        self.assertEqual(output["points"], [])
        self.assertEqual(list(self.state.iterdir()), [])

    def test_missing_readonly_watch_clear_and_sampling_error(self):
        result = analytics.snapshot(self.state, 28800, 300, now=100)
        self.assertEqual(result["sample_count"], 0)
        self.assertFalse(self.state.exists())
        cleared = subprocess.run(self.command("clear"), capture_output=True, text=True, timeout=3)
        self.assertEqual(cleared.returncode, 0)
        self.assertFalse(self.state.exists())
        watcher = self.start("watch", "--window-seconds", "28800", "--points", "300")
        self.assertIsNone(self.line(watcher)["latest"])
        self.assertFalse(self.state.exists())
        self.stop(watcher)
        collector = self.start("collect", "--sysfs-root", str(self.root / "absent"))
        failed = self.latest()
        self.assertIn("error", failed)
        self.assertEqual(failed["status"], "unknown")
        self.assertIsNone(failed["battery_power_w"])
        self.assertIsNone(failed["percentage"])
        snapshot = analytics.snapshot(self.state, 1200, 300)
        self.assertIn("error", snapshot["latest"])
        collector.terminate()
        stdout, stderr = collector.communicate(timeout=3)
        self.assertEqual((stdout, stderr), ("", ""))
        analytics.clear(self.state)
        self.assertEqual(list(self.state.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
