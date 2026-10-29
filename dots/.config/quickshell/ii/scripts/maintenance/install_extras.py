#!/usr/bin/env python3
"""Installs what the setup assistant's Extras step picked, without a terminal.

The password comes once, on the first line of stdin. It is checked with sudo, then given to every later
sudo through an askpass helper that reads it from a file in a folder only you can open, removed at the end.
Repository packages go through pacman, AUR ones through yay or paru, and the components are kept in
Velora's saved selection (`velora deps --add`), so updates keep them.

Progress goes to stdout: "::phase <password|repo|aur|record>" before each part; other lines are the
tools' own output. Exit codes: 0 done, 3 wrong password, 4 no AUR helper, 5 no administrator rights,
1 a tool failed.

usage: install_extras.py [--dry-run] [--repo a,b] [--aur c,d] [--components x,y]
"""
import argparse
import os
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PROMPT = "[velora-password]"
VELORA = Path(__file__).resolve().parent / "velora.sh"
COLORS = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def phase(name):
    print(f"::phase {name}", flush=True)


def check_password(password):
    """sudo asks again after a wrong password. It is stopped right there, so a typo costs one failed
    attempt instead of three (pam_faillock locks the account after three). Returns ok, wrong or denied."""
    process = subprocess.Popen(["sudo", "-S", "-k", "-p", PROMPT, "true"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                               stderr=subprocess.PIPE, env=dict(os.environ, LANG="C.UTF-8", LC_ALL="C.UTF-8"),
                               start_new_session=True)
    # Read at the first prompt, whatever it says (sudoers may replace ours)
    try:
        process.stdin.write(password.encode() + b"\n")
        process.stdin.flush()
    except BrokenPipeError:
        pass
    said = ""
    # Asking again: our prompt a second time, the message before it, or (with a prompt and message of
    # its own) still waiting long after a wrong password's delay of about two seconds
    deadline = time.monotonic() + 8
    while said.count(PROMPT) < 2 and "Sorry, try again" not in said:
        ready, _, _ = select.select([process.stderr], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        chunk = os.read(process.stderr.fileno(), 4096)
        if not chunk:  # Done
            if process.wait() == 0:
                return "ok"
            if "incorrect password" in said:
                return "wrong"
            print(said.replace(PROMPT, "").strip(), flush=True)
            return "denied"
        said += chunk.decode(errors="replace")
    process.kill()
    process.wait()
    return "wrong"


def askpass(password):
    """The helper sudo runs for the password (SUDO_ASKPASS), and the password, in a folder only you can open."""
    folder = Path(tempfile.mkdtemp(prefix="velora-askpass-", dir=os.environ.get("XDG_RUNTIME_DIR") or None))
    secret = folder / "password"
    with os.fdopen(os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
        file.write(password + "\n")
    helper = folder / "askpass"
    with os.fdopen(os.open(helper, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700), "w") as file:
        file.write(f"#!/bin/sh\nexec cat -- {shlex.quote(str(secret))}\n")
    return folder, helper


def run(command, environment):
    """Runs a tool, passing on its output line by line (the last part of lines redrawn with \\r); returns its exit code."""
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               env=environment, start_new_session=True, text=True, errors="replace", bufsize=1)
    for line in process.stdout:
        line = COLORS.sub("", line.rstrip("\n").split("\r")[-1]).strip()
        if line:
            print(line, flush=True)
    return process.wait()


def dry_run(args, password):
    """Goes through the motions: "wrong" is a wrong password, "fail" fails while installing."""
    phase("password")
    time.sleep(1.2)
    if password == "wrong":
        return 3
    for name, packages in (("repo", args.repo), ("aur", args.aur)):
        if not packages:
            continue
        phase(name)
        for package in packages:
            print(f"Would install {package}", flush=True)
            time.sleep(0.8)
            if password == "fail":
                print(f"error: failed to retrieve some files ({package})", flush=True)
                return 1
    if args.components:
        phase("record")
        print("Would keep " + ", ".join(args.components) + " in Velora's selection", flush=True)
        time.sleep(0.5)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dry-run", action="store_true")
    for name in ("repo", "aur", "components"):
        parser.add_argument(f"--{name}", default="", type=lambda text: [item for item in text.split(",") if item])
    args = parser.parse_args()
    password = sys.stdin.readline().rstrip("\n")
    if args.dry_run:
        return dry_run(args, password)

    phase("password")
    verdict = check_password(password)
    if verdict != "ok":
        return 3 if verdict == "wrong" else 5
    # Closing the assistant stops this; the folder with the password goes with it
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    folder, helper = askpass(password)
    try:
        environment = dict(os.environ, SUDO_ASKPASS=str(helper))
        if args.repo:
            phase("repo")
            if run(["sudo", "-A", "pacman", "-S", "--needed", "--noconfirm", "--", *args.repo], environment) != 0:
                return 1
        if args.aur:
            phase("aur")
            aur_helper = shutil.which("yay") or shutil.which("paru")
            if not aur_helper:
                print("No AUR helper: install yay or paru, or run 'velora deps' in a terminal.", flush=True)
                return 4
            review = ["--answerclean", "None", "--answerdiff", "None", "--answeredit", "None"] \
                if Path(aur_helper).name == "yay" else ["--skipreview"]
            if run([aur_helper, "-S", "--needed", "--noconfirm", "--sudoflags=-A", *review, "--", *args.aur], environment) != 0:
                return 1
        if args.components:
            # A failed record must be reported, otherwise later updates lose the selected components.
            phase("record")
            if run([str(VELORA), "deps", "--add", ",".join(args.components), "--skip-packages"], environment) != 0:
                return 1
        return 0
    finally:
        shutil.rmtree(folder, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
