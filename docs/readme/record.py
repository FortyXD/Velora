#!/usr/bin/env python3
"""Record a real Wayland desktop, or encode an existing recording for the README.

Run in a separate demo account/session. This records the selected monitor as-is;
it does not create windows, replace QML components, or change desktop settings.
"""
import argparse
import json
from pathlib import Path
import signal
import subprocess
import time


def encode(source, destination, width, fps):
    metadata = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(source)
    ]))
    duration = float(metadata["format"]["duration"])
    if duration < 1:
        raise ValueError("Record at least one second before encoding a loop.")
    # Native UI transitions stay intact. Only the final half-second blends back
    # to the opening frame, avoiding a hard cut at the GIF's loop boundary.
    filters = (
        f"[0:v]fps={fps},scale={width}:-2:flags=lanczos,split=2[body][head];"
        "[head]trim=end_frame=1,setpts=PTS-STARTPTS,"
        "tpad=stop_mode=clone:stop_duration=0.6[still];"
        f"[body][still]xfade=transition=fade:duration=0.5:offset={duration - .5:.3f},"
        f"trim=duration={duration:.3f},split[a][b];"
        "[a]palettegen=stats_mode=diff[p];"
        "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
    )
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-filter_complex_threads", "2",
        "-y", "-i", str(source), "-filter_complex", filters, "-loop", "0", str(destination)
    ], check=True)
    print(f"{destination}: {duration:.1f} seconds, {destination.stat().st_size / 1048576:.2f} MiB")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Destination GIF")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--input", type=Path, help="Encode an existing MP4")
    source.add_argument("--monitor", help="Record this real Wayland output (see hyprctl monitors)")
    parser.add_argument("--seconds", type=float, default=12, help="Recording duration; default 12")
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--fps", type=int, default=20)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".gif":
        parser.error("--output must end in .gif")
    if args.seconds < 1 or args.width < 160 or not 1 <= args.fps <= 30:
        parser.error("Use at least 1 second, width >= 160, and 1–30 fps")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    recording = args.input or args.output.with_suffix(".mp4")
    if args.monitor:
        if recording.exists():
            parser.error(f"Recording already exists: {recording}")
        process = subprocess.Popen([
            "wf-recorder", "-o", args.monitor, "-r", "30", "--no-damage",
            "-c", "libx264", "-p", "preset=veryfast", "-p", "crf=18", "-f", str(recording)
        ])
        try:
            time.sleep(args.seconds)
        except KeyboardInterrupt:
            pass
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
            process.wait(timeout=20)
        if process.returncode != 0:
            raise SystemExit(f"wf-recorder exited with {process.returncode}")
    if not recording.is_file():
        parser.error(f"Recording does not exist: {recording}")
    encode(recording, args.output, args.width, args.fps)


if __name__ == "__main__":
    main()
