#!/usr/bin/env python3
"""Disposable Arch desktop VM. All product builds and tests run in the guest.

prepare --image IMAGE; start; guest 'COMMAND'; screenshot NAME; stop
The host project is exported read-only. The guest works in /home/velora/Velora.
Set VELORA_QEMU_DIR to keep images and evidence outside this source checkout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
STATE = Path(os.environ.get("VELORA_QEMU_DIR", ROOT / "artifacts/qemu")).absolute()
PORT = int(os.environ.get("VELORA_QEMU_SSH_PORT", "22229"))


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def ssh_args():
    return ["ssh", "-i", str(STATE / "id_ed25519"), "-p", str(PORT),
            "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new", "-o", f"UserKnownHostsFile={STATE / 'known_hosts'}",
            "velora@127.0.0.1"]


def qmp(command, arguments=None):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(10)
        connection.connect(str(STATE / "qmp.sock"))
        stream = connection.makefile("rwb")
        stream.readline()
        for request in [{"execute": "qmp_capabilities"}, {"execute": command, "arguments": arguments or {}}]:
            stream.write(json.dumps(request).encode() + b"\n")
            stream.flush()
            while True:
                answer = json.loads(stream.readline())
                if "error" in answer:
                    raise RuntimeError(answer["error"])
                if "return" in answer:
                    break
        return answer["return"]


def prepare(image):
    STATE.mkdir(parents=True, exist_ok=True)
    image = image.absolute()
    checksum = Path(str(image) + ".SHA256")
    if not checksum.exists():
        raise RuntimeError("Download the official image's .SHA256 file alongside it first")
    expected = checksum.read_text().split()[0]
    with image.open("rb") as source:
        actual = hashlib.file_digest(source, "sha256").hexdigest()
    if expected != actual:
        raise RuntimeError("Arch image checksum mismatch")
    if not (STATE / "disk.qcow2").exists():
        run("qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", image, STATE / "disk.qcow2", "64G")
    if not (STATE / "id_ed25519").exists():
        run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", STATE / "id_ed25519")
    public_key = (STATE / "id_ed25519.pub").read_text().strip()
    (STATE / "user-data").write_text("""#cloud-config
hostname: velora-qemu
users:
  - name: velora
    groups: [wheel, video, audio]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    ssh_authorized_keys:
      - """ + public_key + """
chpasswd:
  expire: false
  users:
    - name: velora
      password: velora-test
      type: text
ssh_pwauth: false
disable_root: true
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
runcmd:
  - [systemctl, enable, --now, sshd]
  - [mkdir, -p, /mnt/velora-source]
  - [mount, -t, 9p, -o, 'trans=virtio,version=9p2000.L,ro', velora_source, /mnt/velora-source]
  - [touch, /var/lib/velora-qemu-ready]
""")
    (STATE / "meta-data").write_text("instance-id: velora-desktop-v1\nlocal-hostname: velora-qemu\n")
    run("xorriso", "-as", "mkisofs", "-quiet", "-V", "cidata", "-J", "-r", "-o", STATE / "seed.iso",
        STATE / "user-data", STATE / "meta-data")
    firmware = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
    if not firmware.exists():
        raise RuntimeError("Install the edk2-ovmf host package")
    if not (STATE / "OVMF_VARS.fd").exists():
        shutil.copyfile(firmware.with_name("OVMF_VARS.4m.fd"), STATE / "OVMF_VARS.fd")
    (STATE / "image.json").write_text(json.dumps({"image": str(image), "sha256": actual, "source": str(ROOT)}, indent=2) + "\n")


def start():
    if (STATE / "qmp.sock").exists():
        try:
            qmp("query-status")
            print("VM already running")
            return
        except (OSError, RuntimeError):
            pass
    for name in ["qmp.sock", "vnc.sock"]:
        (STATE / name).unlink(missing_ok=True)
    accel = os.environ.get("VELORA_QEMU_ACCEL", "kvm" if os.access("/dev/kvm", os.R_OK | os.W_OK) else "tcg")
    if accel not in ("kvm", "tcg"):
        raise ValueError("VELORA_QEMU_ACCEL must be kvm or tcg")
    command = ["qemu-system-x86_64", "-machine", f"q35,accel={accel}", "-cpu", "host" if accel == "kvm" else "max",
               "-smp", "4", "-m", "8192", "-device", "virtio-vga", "-display", "none",
               "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd",
               "-drive", f"if=pflash,format=raw,file={STATE / 'OVMF_VARS.fd'}",
               "-drive", f"file={STATE / 'disk.qcow2'},if=none,id=osdisk,format=qcow2",
               "-device", "virtio-blk-pci,drive=osdisk,bootindex=1",
               "-drive", f"file={STATE / 'seed.iso'},format=raw,media=cdrom,readonly=on",
               "-netdev", f"user,id=net0,hostfwd=tcp:127.0.0.1:{PORT}-:22", "-device", "virtio-net-pci,netdev=net0",
               "-virtfs", f"local,path={ROOT},mount_tag=velora_source,security_model=none,readonly=on",
               "-device", "qemu-xhci", "-device", "usb-tablet", "-device", "virtio-rng-pci",
               "-audiodev", "none,id=audio", "-device", "intel-hda", "-device", "hda-duplex,audiodev=audio",
               "-qmp", f"unix:{STATE / 'qmp.sock'},server=on,wait=off", "-vnc", f"unix:{STATE / 'vnc.sock'}",
               "-serial", f"file:{STATE / 'serial.log'}", "-pidfile", str(STATE / "qemu.pid"), "-daemonize"]
    run(*command)
    print(f"QEMU started ({accel}); SSH port {PORT}; guest password: velora-test")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    subs.add_parser("prepare").add_argument("--image", required=True, type=Path)
    subs.add_parser("start")
    subs.add_parser("stop").add_argument("--force", action="store_true", help="Cut VM power; use only for a guest stuck before OS boot")
    subs.add_parser("status")
    subs.add_parser("guest").add_argument("script")
    subs.add_parser("screenshot").add_argument("name")
    subs.add_parser("sync")
    subs.add_parser("collect")
    subs.add_parser("quicklook-tour")
    subs.add_parser("key").add_argument("keys")
    subs.add_parser("type").add_argument("text")
    move = subs.add_parser("move")
    move.add_argument("x", type=float)
    move.add_argument("y", type=float)
    mouse = subs.add_parser("click")
    mouse.add_argument("x", type=float)
    mouse.add_argument("y", type=float)
    subs.add_parser("snapshot").add_argument("name")
    subs.add_parser("restore-snapshot").add_argument("name")
    subs.add_parser("sequence").add_argument("steps", help="JSON list of [key|click|move|type|screenshot|wait, arguments...]")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.image)
    elif args.command == "start":
        start()
    elif args.command == "stop":
        qmp("quit" if args.force else "system_powerdown")
    elif args.command == "status":
        print(json.dumps(qmp("query-status")))
    elif args.command == "guest":
        raise SystemExit(subprocess.call([*ssh_args(), args.script]))
    elif args.command == "sync":
        run(*ssh_args(), "set -e; sudo mkdir -p /mnt/velora-source; mountpoint -q /mnt/velora-source || sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro velora_source /mnt/velora-source; mkdir -p ~/Velora; rsync -a --exclude=.git --exclude-from=/mnt/velora-source/.gitignore /mnt/velora-source/ ~/Velora/")
    elif args.command == "quicklook-tour":
        for name in ("video", "audio", "pdf", "text", "archive"):
            qmp("send-key", {"keys": [{"type": "qcode", "data": "right"}], "hold-time": 80})
            time.sleep(1.2)
            qmp("screendump", {"filename": str(STATE / f"quicklook-{name}.png"), "format": "png"})
    elif args.command == "collect":
        run("rsync", "-a", "-e", " ".join(ssh_args()[:-1]), "velora@127.0.0.1:/home/velora/evidence/", str(STATE) + "/")
    elif args.command == "key":
        qmp("send-key", {"keys": [{"type": "qcode", "data": key} for key in args.keys.split("+")], "hold-time": 80})
    elif args.command == "type":
        names = {"-": "minus", " ": "spc", ".": "dot", "/": "slash", "_": "minus"}
        for character in args.text:
            key = names.get(character, character.lower())
            keys = ([{"type": "qcode", "data": "shift"}] if character.isupper() or character == "_" else [])
            keys.append({"type": "qcode", "data": key})
            qmp("send-key", {"keys": keys, "hold-time": 40})
            time.sleep(.06)
    elif args.command in ("click", "move"):
        qmp("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": round(args.x * 32767)}},
            {"type": "abs", "data": {"axis": "y", "value": round(args.y * 32767)}}]})
        if args.command == "click":
            time.sleep(.08)
            qmp("input-send-event", {"events": [{"type": "btn", "data": {"button": "left", "down": True}}]})
            time.sleep(.08)
            qmp("input-send-event", {"events": [{"type": "btn", "data": {"button": "left", "down": False}}]})
    elif args.command in ("snapshot", "restore-snapshot"):
        if not args.name.replace("-", "").isalnum():
            raise ValueError("Use a simple snapshot name")
        try:
            qmp("query-status")
        except (OSError, RuntimeError):
            pass
        else:
            raise RuntimeError("Power down the guest first: disk snapshots require a clean shutdown")
        run("qemu-img", "snapshot", "-c" if args.command == "snapshot" else "-a", args.name, STATE / "disk.qcow2")
        if args.command == "snapshot":
            shutil.copyfile(STATE / "OVMF_VARS.fd", STATE / (args.name + "-OVMF.fd"))
        else:
            shutil.copyfile(STATE / (args.name + "-OVMF.fd"), STATE / "OVMF_VARS.fd")
    elif args.command == "sequence":
        for step in json.loads(args.steps):
            if step[0] == "wait":
                time.sleep(min(float(step[1]), 10))
            elif step[0] in ("key", "click", "move", "type", "screenshot"):
                run(os.sys.executable, Path(__file__), *map(str, step))
            else:
                raise ValueError("Unsupported sequence step")
    elif args.command == "screenshot":
        if Path(args.name).name != args.name:
            raise ValueError("Use a screenshot name, not a path")
        time.sleep(0.6)  # Let the compositor present the most recent input/layout.
        path = STATE / (args.name + ".png")
        qmp("screendump", {"filename": str(path), "format": "png"})
        print(path)


if __name__ == "__main__":
    main()
