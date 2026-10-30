# Wi-Fi credentials

Settings and the sidebar use the same inline password form. Enter connects,
Escape closes the request, and the eye reveals the password. A repeat NetworkManager
request reopens that form without an extra “update saved password” step. A saved
profile is not proof that a password is available; “Joined before” only describes
connection history. **Details** in the sidebar opens Velora Settings → Wi-Fi;
it does not launch KDE's network editor. Hidden networks support Open, WPA2
Personal and WPA3 Personal. Enterprise, WEP and other security types are not
configurable on this page; Velora shows a clear unsupported-security message
instead of opening an unrelated KDE window.

The credential helper needs `python-gobject` and `libnm` (included in the Arch
shell dependencies). It starts lazily per UI process, registers a native
NetworkManager secret agent, and handles only the current operation's UUID/path.
A per-user lock prevents the settings process and shell from competing. Missing
runtime dependencies, a stopped NetworkManager or a crashed helper produce a
recoverable inline error; try connecting again to restart the helper.

Passwords travel through the helper's stdin and private NetworkManager D-Bus
calls, never command arguments, environment variables, temporary files or logs.
Fields clear on submit/cancel and repeated requests never reuse a rejected
password. Whitespace is preserved; WPA2 passphrases are 8–63 UTF-8 bytes or a
64-digit hexadecimal PSK, while WPA3 SAE uses 1–63 UTF-8 bytes. Python/Qt cannot
guarantee erasure of all copies in process memory.

## Saving and cancellation

New profiles are initially in memory with autoconnect disabled. Only after a
successful connection does the helper ask NetworkManager to persist the profile
and enable autoconnect. An unsuccessful new profile may remain in NM's memory
until restart; no retry deletes a profile. Existing UUIDs, permissions and other
settings are preserved. An NM-owned replacement password is merged after
success, first retrieving only that owned profile's other secrets so omitted
secrets are not lost, and using a version check to reject concurrent changes.
No custom plaintext store or keyring is created.

Existing `AGENT_OWNED` / `NOT_SAVED` ownership is never silently changed. When a
replacement is supplied for such a profile, this helper cannot durably save it;
the connection can succeed but displays a **connected, password not saved**
warning. Save denials, read denials, version conflicts and save timeouts also
produce that warning, not a failed-connection message. An ordinary successful
connection using an external agent's existing credentials needs no rewrite and
no warning. Use the advanced editor/keyring to manage those passwords.

Attempts time out after 60 seconds of backend work, but not while awaiting your
password. **Cancel** rejects the outstanding credential request. During activation,
**Stop waiting** cancels the client request and dismisses the form; NetworkManager
may still finish connecting. This deliberately never sends DeactivateConnection:
NM has no atomic “deactivate only if still activating” operation, so even an
exact-object state check could race success and disconnect a healthy link. An
already successful connection is never torn down by a late cancel or helper exit.
Cancelled attempts are not saved by this helper. On EOF it waits up to 65 seconds
for outstanding async cleanup, without disconnecting anything. Starting a different
Wi-Fi connection can itself interrupt the old link.

## Offline validation

`python3 -m unittest discover -s tests -v` includes fake-NM state-machine and
persistence tests, actual unregistered libnm secret-agent vfunc dispatch tests,
and real Qt/Quickshell tests of the production service/form with a JSONL fixture.
No test activates or disconnects the user's network. These are not a substitute
for persistence/cancellation checks against a separate disposable NM daemon;
real activation and daemon-side disk persistence were deliberately not exercised
on the user's system.
