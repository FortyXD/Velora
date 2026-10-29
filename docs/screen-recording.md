# Screen recording

Open **Settings → Tools → Screen recording**. The bar and sidebar recording
buttons use these settings. Click again to stop, or cancel area selection/countdown.
**Right-click the camera button in the bar** to open settings directly at the
recording section, already scrolled into view. Right-click does not start or stop
recording; left-click keeps its recording/cancellation behavior.
The recording indicator and timer start only after encoder/muxer initialization;
“saved” is reported only after the encoder exits and the video stream is verified.

## Settings

- **Area:** region selection (default), or the focused monitor. Escape cancels region
  selection. Explicit region actions use the shell's region picker; the default
  button uses `slurp`. Both accept logical coordinates, including scaled monitors
  and monitors to the left of the primary display.
- **Audio:** silent, system sound (default), microphone only, or system + microphone.
  Unlike the previous illogical-impulse button, the microphone is **not enabled by
  default**. Select both explicitly to restore that behavior. A muted device records
  silence; use normal sound settings to adjust volume/mute before recording.
- **Devices:** follow the system default at launch, or pin a particular output/input.
  System sound records exactly one playback monitor. A missing selected device is
  an error, not permission to choose another microphone. Device switching during a
  recording is not supported. Refresh the device list after plugging in a device.
  “Both” creates a private temporary audio mix and removes it after finalization;
  it does not intentionally change the default playback device.
- **Frame rate:** 30 FPS for lower CPU/disk usage; 60 FPS for smoother motion.
- **Quality:** H.264 `libx264`, `veryfast` preset, CRF 18 (high), 23 (balanced/default),
  or 28 (smaller files). Lower CRF means larger, higher-quality video. Encoding is
  software-based, not a promise of hardware acceleration. Odd pixel sizes are padded
  to even dimensions for H.264/yuv420p compatibility. Audio uses AAC.
- **Container:** MP4 for compatibility; MKV for better resilience to interrupted
  recording. Neither replaces stopping normally to finalize the file.
- **Delay:** 0/3/5/10 seconds, after area selection. Capture always waits briefly for
  overlays to disappear. Click the button again to cancel the countdown.
- **Folder:** XDG Videos by default; if XDG Videos is disabled or points to home,
  `~/Videos` is used. Custom paths are respected, not silently relocated. Filenames
  are unique even for recordings started in the same second.

Settings apply to the next recording, not to one already running.

## Shortcuts and compatibility

| Shortcut | Action |
| --- | --- |
| Super+Shift+R / Super+Alt+R | Region with configured audio |
| Ctrl+Alt+R | Focused screen, explicitly silent |
| Super+Shift+Alt+R | Focused screen, system sound |
| Ctrl+Super+Alt+R | Focused screen, system + microphone |

Any recording action stops the active owned recording instead of starting a second
one. Explicit modes override only the corresponding configured setting.

The executable `scripts/videos/record.sh` remains the entry point. It accepts
`--region 'X,Y WxH'`, `--select-region`, `--fullscreen`, `--sound`, `--silent`, and legacy `--mic`
(system + microphone; `--sound --mic` remains valid). `stop`, `status` (JSON), and
`sources` (JSON) are also available. The shell exposes `recorder.toggle`,
`recorder.stop`, `recorder.status`, and `region.recordWithMic` IPC.

The settings deep link is `QS_SETTINGS_PAGE=tools QS_SETTINGS_SECTION=screen-recording`.
The section ID is stable across UI languages; settings wait for the page/layout
before revealing it rather than relying on a translated search query.

## Troubleshooting and safety

Dependencies: Python 3, `wf-recorder`, `ffmpeg`/`ffprobe`, `slurp`, `hyprctl`, and
`pactl` (PulseAudio compatibility through PipeWire works). Notifications use
`notify-send` when available. Unsupported `wf-recorder -t` is deliberately not used.

The last error is visible in the recording settings and notifications. Private,
bounded diagnostics/state live under `$XDG_RUNTIME_DIR/velora-recorder/`:
`error.log` and `state.json`. Encoder failures, unavailable audio devices, invalid
settings/folders, and selection failures do not masquerade as successful recordings.
After fixing an error, click record again. Escape cancellation is not an error.
Hyprland's monitor lock (`solitaryBlockedBy` containing `LOCK`) and explicit
DPMS-off state are checked before selection/capture and again after countdown.
Unlock/wake the recording monitor before retrying. Missing monitor fields on older
Hyprland versions are treated as unknown, not as locked/off. If capture nevertheless
cannot initialize, startup fails after 15 seconds rather than waiting forever.

Only this controller's identity-validated processes are stopped; an unrelated
`wf-recorder` is never killed. Recording survives a shell reload. If the controller
itself crashes before publishing child ownership, an intermediate same-PID gate
cannot execute the selector/encoder: it waits for publication and is protected by
an unignorable Linux parent-death signal. After publication the gate switches to
TERM for the selector or INT for the encoder and execs the target; initialized
files can therefore finalize normally on owner death. The next stop/toggle recovers
any published child and
removes only its uniquely tagged mixer modules before allowing a new recording.
Audio cleanup failures retain ownership information and an actionable error; press
Stop again after the audio server becomes available.

Stopping waits up to two seconds after SIGINT. A live controller may then terminate
and, after another two seconds, kill an encoder **only** if it has observed no
encoder initialization and the output is still absent/empty. Initialized recordings
(including buffered, zero-byte MKV) are never force-killed. A crashed controller's
missing readiness flag cannot prove that its orphan never initialized, so recovery
also never force-kills an uncertain recorder orphan. Unresponsive initialized or
uncertain encoders produce a bounded, actionable error and retain child/file/mixer
ownership instead of hanging the command or permitting a duplicate recording.
Press Stop to retry finalization. A permanently hung initialized encoder still
requires external diagnosis; preserving its file takes priority over forced exit.

For isolated validation, set `VELORA_RECORDER_CONFIG` and `VELORA_RECORDER_RUNTIME`,
or use `--config PATH --runtime-dir PATH`; the normal config and recording are not
modified. Automated tests use fake encoders/audio devices and never capture the
user's desktop or microphone.
