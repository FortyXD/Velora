#!/usr/bin/env python3
"""Return visible access points together with saved NetworkManager profile UUIDs."""

import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor


def nmcli(*args):
    environment = os.environ.copy()
    environment.update(LANG="C", LC_ALL="C")
    return subprocess.run(
        ["nmcli", *args], capture_output=True, text=True, encoding="utf-8",
        errors="replace", env=environment, check=False,
    )


def fields(line):
    """Split nmcli terse fields, where colons and backslashes are escaped."""
    result = []
    value = []
    escaped = False
    for character in line:
        if escaped:
            value.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            result.append("".join(value))
            value = []
        else:
            value.append(character)
    if escaped:
        value.append("\\")
    result.append("".join(value))
    return result


def saved_profiles():
    result = nmcli("-t", "-f", "UUID,TYPE", "connection", "show")
    if result.returncode:
        return {}
    uuids = []
    for line in result.stdout.splitlines():
        values = fields(line)
        if len(values) >= 2 and values[1] in ("wifi", "802-11-wireless"):
            uuids.append(values[0])

    def profile(uuid):
        # A profile name is not necessarily its SSID. Avoid --show-secrets here:
        # it prompts polkit and emits profile-change events for every saved Wi-Fi.
        detail = nmcli(
            "--escape", "no", "-g", "802-11-wireless.ssid",
            "connection", "show", "uuid", uuid,
        )
        if detail.returncode:
            return None
        ssid = detail.stdout.strip()
        if not ssid:
            return None
        return ssid, {"uuid": uuid, "hasCredentials": True}

    profiles = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        for entry in pool.map(profile, uuids):
            if entry is None:
                continue
            ssid, candidate = entry
            if ssid not in profiles or (candidate["hasCredentials"] and not profiles[ssid]["hasCredentials"]):
                profiles[ssid] = candidate
    return profiles


def visible_networks(profiles):
    result = nmcli(
        "-t", "-f", "IN-USE,SIGNAL,FREQ,SSID,BSSID,SECURITY",
        "device", "wifi", "list", "--rescan", "no",
    )
    if result.returncode:
        return [], result.stderr.strip().splitlines()[0] if result.stderr.strip() else "NetworkManager unavailable"
    networks = {}
    for line in result.stdout.splitlines():
        values = fields(line)
        if len(values) < 6 or not values[3]:
            continue
        try:
            strength = int(values[1])
            frequency = int(values[2].split()[0])
        except ValueError:
            continue
        ssid = values[3]
        network = {
            "active": values[0] == "*",
            "strength": strength,
            "frequency": frequency,
            "ssid": ssid,
            "bssid": values[4],
            "security": values[5],
            "savedUuid": profiles.get(ssid, {}).get("uuid", ""),
            "savedCredentials": not values[5] or profiles.get(ssid, {}).get("hasCredentials", False),
        }
        previous = networks.get(ssid)
        if previous is None or (network["active"], strength) > (previous["active"], previous["strength"]):
            networks[ssid] = network
    return list(networks.values()), ""


def main():
    networks, error = visible_networks(saved_profiles())
    print(json.dumps({"networks": networks, "error": error}, ensure_ascii=False))


if __name__ == "__main__":
    main()
