#!/usr/bin/env python3
"""Opt-in, unprivileged *battery* telemetry; never total laptop/adapter power.

collect owns storage until terminated; watch is entirely read-only. A retained
state-directory inode is the flock anchor (clear never unlinks it). The fixed
CRC-protected ring is <2 MB and holds at most eight hours at a two-second cadence.
Only collect creates storage. No daemon is started implicitly by watch.

Power is positive out of batteries, negative into them. Missing/inconsistent
measurements stay null. Multiple batteries require complete energy/power data;
percentage is energy-weighted, differing pack voltages have no aggregate voltage,
and temperature is the hottest explicitly battery-exposed temperature available.
Energy statistics integrate adjacent valid powers only, never across gaps.
Display downsampling preserves global and per-bucket extrema for every metric;
local detail is necessarily lossy. Every omitted gap is propagated to the next
selected original sample via gap_before, so no segment bridges a discontinuity.
"""

import argparse
from collections import deque
import fcntl
import json
import math
import os
from pathlib import Path
import signal
import stat
import struct
import sys
import time
import zlib

INTERVAL = 2.0
RETENTION = 28800
CAPACITY = 14400
GAP_SECONDS = 6.0
METRICS = ("battery_power_w", "percentage", "voltage_v", "energy_wh", "temperature_c")
STATUSES = ("unknown", "charging", "discharging", "full", "not-charging", "mixed")
HEADER = struct.Struct("<8sII")
PAYLOAD = struct.Struct("<Q6dBBBB48s")
CRC = struct.Struct("<I")
RECORD_SIZE = PAYLOAD.size + CRC.size
MAGIC = b"VPWR0001"
HISTORY = "history.bin"
LATEST = "latest.json"
TEMP = ".latest.tmp"
ARTIFACTS = (HISTORY, LATEST, TEMP)


def text(path, name):
    try:
        return (path / name).read_text().strip()
    except (OSError, UnicodeError):
        return None


def number(path, name, scale=1.0):
    try:
        value = float(text(path, name)) / scale
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def positive(value):
    return value if value is not None and value >= 0 else None


def total(values):
    return sum(values) if values and all(v is not None for v in values) else None


def empty_sample(timestamp, error=None):
    sample = dict.fromkeys(METRICS)
    sample.update(timestamp=timestamp, ac_online=None, status="unknown")
    if error:
        sample["error"] = error[:48]
    return sample


def sample_sysfs(root, timestamp=None):
    """Return (public sample, topology); sysfs device links are intentional."""
    timestamp = time.time() if timestamp is None else timestamp
    sample = empty_sample(timestamp)
    paths = sorted(Path(root).iterdir())  # missing/unreadable root is an error
    batteries, online, topology = [], [], []
    for path in paths:
        kind = text(path, "type")
        scope = text(path, "scope")
        if scope and scope.lower() == "device":
            continue
        if kind != "Battery":
            if kind in ("Mains", "USB", "USB_C", "USB_PD", "USB_PD_DRP", "Wireless"):
                value = number(path, "online")
                online.append(bool(value) if value in (0, 1) else None)
            continue
        # Missing scope is conventional for ACPI BAT* supplies, not peripherals.
        if scope != "System" and not (scope in (None, "Unknown") and path.name.startswith("BAT")):
            continue
        if number(path, "present") == 0:
            continue
        topology.append(path.name)
        state = (text(path, "status") or "unknown").lower().replace(" ", "-")
        if state not in STATUSES[:-1]:
            state = "unknown"
        voltage = number(path, "voltage_now", 1e6)
        if voltage is not None and voltage <= 0:
            voltage = None
        energy = positive(number(path, "energy_now", 1e6))
        full = positive(number(path, "energy_full", 1e6))
        if energy is None:
            charge = positive(number(path, "charge_now", 1e6))
            if charge is not None and voltage is not None:
                energy = charge * voltage
        if full is None:
            charge_full = positive(number(path, "charge_full", 1e6))
            if charge_full is not None and voltage is not None:
                full = charge_full * voltage
        rate = number(path, "power_now", 1e6)
        if rate is None:
            current = number(path, "current_now", 1e6)
            if current is not None and voltage is not None:
                rate = current * voltage
        power = None
        if rate is not None:
            if state == "discharging":
                power = abs(rate)
            elif state == "charging":
                power = -abs(rate)
            elif rate == 0:
                power = 0.0  # measured zero, not an inference from missing data
        capacity = number(path, "capacity")
        if capacity is not None:
            capacity = min(100.0, max(0.0, capacity))
        if energy is not None and full is not None and full > 0:
            capacity = min(100.0, max(0.0, 100 * energy / full))
        batteries.append(dict(status=state, energy=energy, full=full,
                              power=power, voltage=voltage, capacity=capacity,
                              temperature=number(path, "temp", 10)))
    sample["ac_online"] = (True if any(v is True for v in online) else
                           False if online and all(v is False for v in online) else None)
    if not batteries:
        sample["error"] = "No system battery telemetry available"
        return sample, tuple(topology)
    states = {b["status"] for b in batteries}
    sample["status"] = states.pop() if len(states) == 1 else "mixed"
    sample["energy_wh"] = total([b["energy"] for b in batteries])
    sample["battery_power_w"] = total([b["power"] for b in batteries])
    volts = [b["voltage"] for b in batteries]
    if all(v is not None for v in volts) and max(volts) - min(volts) < 1e-6:
        sample["voltage_v"] = volts[0]
    if len(batteries) == 1:
        sample["percentage"] = batteries[0]["capacity"]
    elif all(b["full"] is not None and b["full"] > 0 and b["capacity"] is not None
             for b in batteries):
        sample["percentage"] = sum(b["capacity"] * b["full"] for b in batteries) / sum(b["full"] for b in batteries)
    temperatures = [b["temperature"] for b in batteries if b["temperature"] is not None]
    sample["temperature_c"] = max(temperatures) if temperatures else None
    if all(sample[key] is None for key in METRICS):
        sample["error"] = "System battery measurements unavailable"
    return sample, tuple(topology)


def open_directory(path, create=False):
    """Traverse with dirfds/O_NOFOLLOW, rejecting symlinks at every component."""
    path = os.path.abspath(os.fspath(path))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in Path(path).parts[1:]:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        info = os.fstat(fd)
        if info.st_uid != os.getuid():
            raise PermissionError("state directory must be owned by current user")
        if create:
            os.fchmod(fd, 0o700)
        return fd
    except BaseException:
        os.close(fd)
        raise


def owned_file(directory, name, flags):
    fd = os.open(name, flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        os.close(fd)
        raise PermissionError("unsafe telemetry file")
    if flags & os.O_RDWR or flags & os.O_WRONLY:
        os.fchmod(fd, 0o600)
    return fd


def exclusive(directory):
    try:
        fcntl.flock(directory, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("collector/clear already owns state directory") from None


def encode(sequence, sample):
    values = [sample["timestamp"]] + [sample.get(k) for k in METRICS]
    values = [float("nan") if v is None else v for v in values]
    ac = sample.get("ac_online")
    payload = PAYLOAD.pack(sequence, *values, STATUSES.index(sample["status"]),
                           2 if ac is None else int(ac), int(bool(sample.get("gap_before"))),
                           0, sample.get("error", "").encode("utf-8")[:48])
    return payload + CRC.pack(zlib.crc32(payload))


def decode(record):
    if len(record) != RECORD_SIZE:
        return None
    payload = record[:-CRC.size]
    if zlib.crc32(payload) != CRC.unpack(record[-CRC.size:])[0]:
        return None
    sequence, *fields = PAYLOAD.unpack(payload)
    timestamp = fields[0]
    values = fields[1:6]
    state, ac, gap, _, error = fields[6:]
    if not sequence or not math.isfinite(timestamp) or state >= len(STATUSES) or ac > 2:
        return None
    sample = {k: v if math.isfinite(v) else None for k, v in zip(METRICS, values)}
    sample.update(timestamp=timestamp, status=STATUSES[state], ac_online=None if ac == 2 else bool(ac))
    if gap:
        sample["gap_before"] = True
    error = error.split(b"\0", 1)[0].decode("utf-8", errors="replace")
    if error:
        sample["error"] = error
    return sequence, sample


def read_records(fd):
    if os.fstat(fd).st_size != HEADER.size + CAPACITY * RECORD_SIZE:
        raise ValueError("invalid telemetry ring size")
    if os.pread(fd, HEADER.size, 0) != HEADER.pack(MAGIC, CAPACITY, RECORD_SIZE):
        raise ValueError("invalid telemetry ring header")
    data = os.pread(fd, CAPACITY * RECORD_SIZE, HEADER.size)
    records = []
    for index in range(CAPACITY):
        item = decode(data[index * RECORD_SIZE:(index + 1) * RECORD_SIZE])
        if item and (item[0] - 1) % CAPACITY == index:
            records.append(item)
    return sorted(records, key=lambda item: item[0])


class Ring:
    def __init__(self, directory):
        self.fd = owned_file(directory, HISTORY, os.O_RDWR | os.O_CREAT)
        try:
            if os.fstat(self.fd).st_size == 0:
                os.ftruncate(self.fd, HEADER.size + CAPACITY * RECORD_SIZE)
                os.pwrite(self.fd, HEADER.pack(MAGIC, CAPACITY, RECORD_SIZE), 0)
            records = read_records(self.fd)
            self.sequence = records[-1][0] if records else 0
            self.entries = deque((seq, s["timestamp"]) for seq, s in records)
            self.last_time = records[-1][1]["timestamp"] if records else None
        except BaseException:
            os.close(self.fd)
            raise

    def close(self):
        os.close(self.fd)

    def erase(self, sequence):
        os.pwrite(self.fd, bytes(RECORD_SIZE), HEADER.size + ((sequence - 1) % CAPACITY) * RECORD_SIZE)

    def append(self, sample):
        now = sample["timestamp"]
        # Wall-clock rollback is a discontinuity; future records cannot be graphed.
        if self.last_time is not None and now < self.last_time:
            retained = deque()
            for seq, timestamp in self.entries:
                if timestamp > now:
                    self.erase(seq)
                else:
                    retained.append((seq, timestamp))
            self.entries = retained
            sample["gap_before"] = True
        while self.entries and self.entries[0][1] < now - RETENTION:
            self.erase(self.entries.popleft()[0])
        self.sequence += 1
        while self.entries and self.entries[0][0] <= self.sequence - CAPACITY:
            self.entries.popleft()
        offset = HEADER.size + ((self.sequence - 1) % CAPACITY) * RECORD_SIZE
        os.pwrite(self.fd, encode(self.sequence, sample), offset)
        self.entries.append((self.sequence, now))
        self.last_time = now


def write_latest(directory, sample):
    try:
        os.unlink(TEMP, dir_fd=directory)
    except FileNotFoundError:
        pass
    fd = owned_file(directory, TEMP, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    try:
        data = (json.dumps(sample, separators=(",", ":"), allow_nan=False) + "\n").encode()
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(TEMP, LATEST, src_dir_fd=directory, dst_dir_fd=directory)
    except BaseException:
        try:
            os.unlink(TEMP, dir_fd=directory)
        except FileNotFoundError:
            pass
        raise


def downsample(samples, limit):
    if len(samples) <= limit:
        return [dict(s) for s in samples]
    # Up to 12 selections per bucket (endpoints + extrema of five metrics).
    # A separate global extrema reserve guarantees preservation at small limits.
    required = {0, len(samples) - 1}
    for key in METRICS:
        valid = [i for i, s in enumerate(samples) if s.get(key) is not None]
        if valid:
            required.update((min(valid, key=lambda i: samples[i][key]),
                             max(valid, key=lambda i: samples[i][key])))
    if len(required) > limit:
        raise ValueError("point limit cannot preserve global metric extrema")
    selected = set(required)
    bucket_count = max(1, (limit - len(required)) // (2 + 2 * len(METRICS)))
    start, end = samples[0]["timestamp"], samples[-1]["timestamp"]
    buckets = [[] for _ in range(bucket_count)]
    for i, sample in enumerate(samples):
        bucket = min(bucket_count - 1, int((sample["timestamp"] - start) / max(end - start, 1e-9) * bucket_count))
        buckets[bucket].append(i)
    candidates = set()
    for bucket in buckets:
        if not bucket:
            continue
        candidates.update((bucket[0], bucket[-1]))
        for key in METRICS:
            valid = [i for i in bucket if samples[i].get(key) is not None]
            if valid:
                candidates.update((min(valid, key=lambda i: samples[i][key]),
                                   max(valid, key=lambda i: samples[i][key])))
    selected.update(sorted(candidates - selected)[:limit - len(selected)])
    # Use remaining capacity for the largest discontinuity boundaries.
    gaps = [i for i in range(1, len(samples)) if samples[i].get("gap_before")]
    for i in sorted(gaps, key=lambda i: (-(samples[i]["timestamp"] - samples[i-1]["timestamp"]), i)):
        for index in (i, i - 1):
            if len(selected) < limit:
                selected.add(index)
    # Even if a complete short segment is omitted, carry its gap forward.
    result, previous = [], -1
    gap_prefix = [0]
    missing_prefix = {key: [0] for key in METRICS}
    for i, sample in enumerate(samples):
        gap_prefix.append(gap_prefix[-1] + bool(sample.get("gap_before")) +
                          bool(i and sample["timestamp"] - samples[i-1]["timestamp"] > GAP_SECONDS))
        for key in METRICS:
            missing_prefix[key].append(missing_prefix[key][-1] + (sample.get(key) is None))
    for index in sorted(selected):
        sample = dict(samples[index])
        if gap_prefix[index + 1] > gap_prefix[previous + 1]:
            sample["gap_before"] = True
        missing = [key for key in METRICS if missing_prefix[key][index + 1] > missing_prefix[key][previous + 1]]
        if missing:
            sample["gaps_before"] = missing
        result.append(sample)
        previous = index
    return result


def statistics(samples):
    powers = [s["battery_power_w"] for s in samples if s.get("battery_power_w") is not None]
    result = {"power_min": min(powers) if powers else None,
              "power_max": max(powers) if powers else None,
              "power_mean": sum(powers) / len(powers) if powers else None,
              "energy_in_wh": None, "energy_out_wh": None}
    for a, b in zip(samples, samples[1:]):
        dt = b["timestamp"] - a["timestamp"]
        p, q = a.get("battery_power_w"), b.get("battery_power_w")
        if p is None or q is None or b.get("gap_before") or not 0 < dt <= GAP_SECONDS:
            continue
        if result["energy_in_wh"] is None:
            result["energy_in_wh"] = result["energy_out_wh"] = 0.0
        if p * q < 0:
            crossing = dt * abs(p) / (abs(p) + abs(q))
            areas = (p * crossing / 2, q * (dt - crossing) / 2)
        else:
            areas = ((p + q) * dt / 2,)
        for area in areas:
            result["energy_out_wh" if area >= 0 else "energy_in_wh"] += abs(area) / 3600
    return result


def snapshot(state_dir, window, points, now=None):
    now = time.time() if now is None else now
    records = []
    try:
        directory = open_directory(state_dir)
    except FileNotFoundError:
        directory = None
    if directory is not None:
        try:
            try:
                fd = owned_file(directory, HISTORY, os.O_RDONLY)
            except FileNotFoundError:
                fd = None
            if fd is not None:
                try:
                    records = read_records(fd)
                finally:
                    os.close(fd)
        finally:
            os.close(directory)
    selected = [(seq, s) for seq, s in records if now - min(window, RETENTION) <= s["timestamp"] <= now]
    selected.sort(key=lambda item: (item[1]["timestamp"], item[0]))
    # A torn record is a gap even if only one two-second sample is missing.
    for (previous_seq, a), (sequence, b) in zip(selected, selected[1:]):
        if sequence != previous_seq + 1 or b["timestamp"] - a["timestamp"] > GAP_SECONDS:
            b["gap_before"] = True
    samples = [s for _, s in selected]
    return {"latest": samples[-1] if samples else None,
            "points": downsample(samples, points), "window_start": now - window,
            "window_end": now, "sample_count": len(samples), "stats": statistics(samples)}


class Cadence:
    """Monotonic deadlines; late wakeups skip ticks instead of catch-up bursts."""
    def __init__(self, clock=time.monotonic, sleep=time.sleep):
        self.clock, self.sleep = clock, sleep
        self.deadline = clock()

    def wait(self):
        remaining = self.deadline - self.clock()
        if remaining > 0:
            self.sleep(remaining)
        now = self.clock()
        self.deadline += INTERVAL
        if self.deadline <= now:
            self.deadline = now + INTERVAL


def boot_time():
    return time.clock_gettime(time.CLOCK_BOOTTIME)


def collect(state_dir, sysfs_root):
    directory = open_directory(state_dir, create=True)
    ring = None
    try:
        exclusive(directory)
        ring = Ring(directory)
        cadence = Cadence()
        previous_boot, previous_epoch, topology = None, None, None
        while True:
            cadence.wait()
            now, boot = time.time(), boot_time()
            try:
                sample, current_topology = sample_sysfs(sysfs_root, now)
            except (OSError, ValueError) as error:
                sample = empty_sample(now, "Battery telemetry unavailable: " + str(error))
                current_topology = None
            if (previous_boot is None or boot - previous_boot > GAP_SECONDS or
                    now <= previous_epoch or now - previous_epoch > GAP_SECONDS or
                    topology != current_topology):
                sample["gap_before"] = True
            ring.append(sample)
            write_latest(directory, sample)
            previous_boot, previous_epoch, topology = boot, now, current_topology
    finally:
        if ring is not None:
            ring.close()
        os.close(directory)


def clear(state_dir):
    try:
        directory = open_directory(state_dir)
    except FileNotFoundError:
        return
    try:
        exclusive(directory)
        for name in ARTIFACTS:
            try:
                os.unlink(name, dir_fd=directory)
            except FileNotFoundError:
                pass
    finally:
        os.close(directory)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("collect", "watch", "clear"):
        sub = commands.add_parser(command)
        sub.add_argument("--state-dir", required=True)
        if command == "collect":
            sub.add_argument("--sysfs-root", default="/sys/class/power_supply")
        if command == "watch":
            sub.add_argument("--window-seconds", type=int, choices=(1200, 3600, 28800), required=True)
            sub.add_argument("--points", type=int, default=300, choices=range(12, 301), metavar="12..300")
    args = parser.parse_args(argv)

    def stop(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        if args.command == "collect":
            collect(args.state_dir, args.sysfs_root)
        elif args.command == "clear":
            clear(args.state_dir)
        else:
            cadence = Cadence()
            errors = 0
            while True:
                cadence.wait()
                try:
                    output = snapshot(args.state_dir, args.window_seconds, args.points)
                except (OSError, ValueError) as error:
                    now = time.time()
                    output = {"latest": None, "points": [], "window_start": now - args.window_seconds,
                              "window_end": now, "sample_count": 0, "stats": statistics([]),
                              "error": str(error)[:160]}
                    if errors < 3:
                        print("power analytics: " + str(error)[:160], file=sys.stderr)
                        errors += 1
                print(json.dumps(output, separators=(",", ":"), allow_nan=False), flush=True)
        return 0
    except (KeyboardInterrupt, BrokenPipeError):
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print("power analytics: " + str(error)[:160], file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
