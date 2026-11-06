# Advanced power analytics

Open **Settings → Battery → Power analytics** and enable **Advanced power analytics**.
The feature is off by default. It does not change charging, battery protection,
power profiles, or the firmware.

- The main shell samples local system batteries every **2 seconds**, including
  when the settings window is closed. The settings process is only a reader.
- Select **20 minutes**, **1 hour**, or **8 hours**, then **Net power**, **Charge**,
  or **Voltage**. Range changes cross-fade using the settings animation theme;
  reduced-motion/energy-saving preferences are respected.
- Positive battery watts mean discharge; negative watts mean charging. These
  are **not** the adapter's input wattage or the entire laptop's consumption
  while plugged in. Those values often are not available in Linux sysfs.
- There are no samples before enablement or during sleep. Gaps and unavailable
  sensor readings are not connected or replaced with zero. Hover values refer
  to retained real samples, not interpolated measurements.
- Charged/used Wh integrate adjacent valid battery-power measurements, excluding
  gaps. Summaries use all raw samples; charts use a bounded, extrema-preserving
  selection. Curves are monotone between those points, without artificial peaks.
- While enabled, the battery popup and settings power reading use this source
  instead of UPower's slower cached rate. Missing or stale readings show `—`;
  disabling restores the ordinary UPower source.

## Storage and privacy

The history lives in `$XDG_STATE_HOME/quickshell/user/power-analytics/`
(normally `~/.local/state/quickshell/user/power-analytics/`). A fixed-size binary
ring holds up to **14,400 records** (8 hours), approximately **1.54 MiB**, plus a
small current-sample JSON file. Records are overwritten in place, not appended
forever or rewritten as a complete JSON history every two seconds. Directory
permissions are 0700 and data files 0600. No data is uploaded.

Turning analytics **off** stops the collector before deleting all measurement
files and clearing the displayed history. An empty directory is retained as the
process-lock anchor; it contains no recorded data. Turning it back on starts a
new history. A normal shell restart while still enabled retains recent history
and marks the interruption as a gap.

Multiple system batteries use complete energy-weighted percentages and signed
net power. Missing pack data stays unavailable; incompatible pack voltages are
not combined into a fictional voltage. Battery temperature is only read if the
battery itself exposes it, never substituted with CPU temperature.

## Focused checks

```sh
python -m unittest discover -s tests -p 'test_power*.py' -v
```

Nine dependency-free backend tests cover sampling/sign/unit conversion,
multiple batteries, monotonic cadence, retention/restart/CRC, downsampling/gaps,
energy integration, lock and symlink safety, and real collect/watch/clear
processes with private fake sysfs. A source-contract test checks the default-off
schema, shell-only ownership, and settings/popup wiring. Two optional Qt-backed
tests exercise chart math/rendering/transitions and the actual QML opt-in/cleanup
lifecycle, including a settings-only reader. The production Battery bindings are
checked against fake UPower: enabled analytics must not fall back for missing,
null, stale, or future samples; disabling restores the ordinary source.
Qt/Quickshell tests use private HOME/XDG directories, an offscreen software
renderer, a nonexistent session bus, and a fake collector. No root access,
network, real telemetry collection, or changes to real power settings/data are
needed. Full desktop visual and real-hardware validation are separate checks.
