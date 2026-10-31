pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

/**
 * The connection profile being edited in settings: what the service holds (`fields`), what was changed on
 * top (`changes`), and saving that. Only the changes are ever sent, so whatever the form doesn't cover stays
 * as it is. Fields are named `section.key`, or `vpn.data.key` and `vpn.secrets.key` for a VPN's dictionaries.
 */
Singleton {
    id: root

    property string uuid: ""
    property string revision: ""
    property string newType: "" // Set while creating a profile of this type
    property string newVpnService: ""
    property var fields: ({})
    property var changes: ({})
    property var secrets: ({}) // Those read so far: `section.key` → value. Dropped when no longer on screen.
    property bool loading: false
    property bool saving: false
    property string errorText: ""
    property bool conflict: false
    property bool justSaved: false

    readonly property bool isNew: root.newType.length > 0
    readonly property bool active: root.uuid.length > 0 || root.isNew
    readonly property bool dirty: Object.keys(root.changes).length > 0
    readonly property string connectionType: root.isNew ? root.newType : (root.fields["connection.type"] ?? "")
    readonly property string title: root.value("connection.id", "")

    // A field shows its stored value again: the form reloaded, or a change was undone
    signal reloaded()

    function stored(key: string): var {
        for (const name of ["vpn.data.", "vpn.secrets."]) {
            if (key.startsWith(name)) return root.fields[name.slice(0, -1)]?.[key.slice(name.length)];
        }
        return root.fields[key];
    }

    function value(key: string, fallback): var {
        const current = key in root.changes ? root.changes[key] : root.stored(key);
        return current ?? fallback;
    }

    function same(a, b): bool {
        return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
    }

    function set(key: string, newValue): void {
        const next = Object.assign({}, root.changes);
        if (root.same(root.stored(key), newValue) && !root.isNew) delete next[key];
        else next[key] = newValue;
        root.changes = next;
        root.errorText = "";
        root.justSaved = false;
    }

    function clearSection(section: string): void {
        const next = Object.assign({}, root.changes);
        for (const key of Object.keys(next))
            if (key.startsWith(section + ".")) delete next[key];
        for (const key of Object.keys(root.fields))
            if (key.startsWith(section + ".")) next[key] = null;
        root.changes = next;
        root.justSaved = false;
    }

    function reset(): void {
        root.fields = ({});
        root.changes = ({});
        root.secrets = ({});
        root.revision = "";
        root.errorText = "";
        root.conflict = false;
        root.justSaved = false;
    }

    function open(uuid: string): void {
        root.pendingOpen = "";
        root.reset();
        root.newType = "";
        root.newVpnService = "";
        root.uuid = uuid;
        root.reload();
    }

    function startNew(connectionType: string, vpnService: string, initial: var): void {
        root.reset();
        root.uuid = "";
        root.newVpnService = vpnService ?? "";
        root.newType = connectionType;
        root.changes = initial ?? {};
        root.reloaded();
    }

    // Another profile asked for while this one has changes: the editor page asks what to do with them
    property string pendingOpen: ""

    function requestOpen(uuid: string): void {
        if (root.dirty && uuid !== root.uuid) root.pendingOpen = uuid;
        else if (uuid !== root.uuid || !root.dirty) root.open(uuid);
    }

    function close(): void {
        root.reset();
        root.uuid = "";
        root.newType = "";
        root.newVpnService = "";
    }

    function discard(): void {
        root.changes = ({});
        root.errorText = "";
        root.reloaded();
    }

    function reload(): void {
        if (root.uuid.length === 0) return;
        const wanted = root.uuid;
        root.loading = true;
        ConnectivityBackend.call("network.profile", { uuid: wanted }, (result, error) => {
            if (root.uuid !== wanted) return;
            root.loading = false;
            if (error) {
                root.errorText = Translation.tr(error.message);
                return;
            }
            root.fields = result.fields;
            root.revision = result.revision;
            root.conflict = false;
            root.reloaded();
        });
    }

    function save(done): void {
        if (root.saving) return;
        root.saving = true;
        root.errorText = "";
        const finish = (uuid, error) => {
            root.saving = false;
            if (error) {
                root.conflict = error.code === "conflict";
                root.errorText = Translation.tr(error.message);
            } else {
                root.justSaved = true;
                root.changes = ({});
                root.secrets = ({});
                root.uuid = uuid;
                root.newType = "";
                root.reload();
            }
            if (done) done(error);
        };
        if (root.isNew) {
            ConnectivityBackend.call("network.addProfile", { connectionType: root.newType, vpnService: root.newVpnService, changes: root.changes },
                (result, error) => finish(result?.uuid ?? "", error));
        } else {
            ConnectivityBackend.call("network.saveProfile", { uuid: root.uuid, revision: root.revision, changes: root.changes },
                (result, error) => finish(root.uuid, error));
        }
    }

    /** Reads this profile's saved secrets into `secrets`, to show one of them. */
    function readSecrets(done): void {
        if (root.uuid.length === 0) {
            if (done) done(null);
            return;
        }
        ConnectivityBackend.call("network.secrets", { uuid: root.uuid }, (result, error) => {
            if (error) {
                root.errorText = Translation.tr(error.message);
            } else {
                const found = {};
                for (const secret of result.secrets)
                    found[secret.section === "vpn" ? `vpn.secrets.${secret.key}` : `${secret.section}.${secret.key}`] = secret.value;
                root.secrets = found;
            }
            if (done) done(error);
        });
    }

    function forgetSecrets(): void {
        root.secrets = ({});
    }
}
