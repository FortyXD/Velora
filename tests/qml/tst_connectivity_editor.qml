import QtQuick
import QtTest

Item {
    SignalSpy { id: reloaded; target: ProfileEditor; signalName: "reloaded" }

    TestCase {
        name: "ProfileEditor"

        function lastCall() {
            return ConnectivityBackend.calls[ConnectivityBackend.calls.length - 1];
        }

        function opened(fields) {
            ProfileEditor.open("u");
            lastCall().done({ fields: Object.assign({ "connection.id": "Home", "connection.type": "802-11-wireless" }, fields ?? {}), revision: "r1" }, null);
            ConnectivityBackend.calls = [];
        }

        function init() {
            ProfileEditor.close();
            ProfileEditor.saving = false;
            ProfileEditor.loading = false;
            ConnectivityBackend.calls = [];
            reloaded.clear();
        }

        function test_opening_reads_the_profile() {
            ProfileEditor.open("u");
            compare(lastCall().method, "network.profile");
            compare(lastCall().params.uuid, "u");
            verify(ProfileEditor.loading);
            lastCall().done({ fields: { "connection.id": "Home", "connection.type": "vpn" }, revision: "r1" }, null);
            verify(!ProfileEditor.loading);
            compare(ProfileEditor.title, "Home");
            compare(ProfileEditor.connectionType, "vpn");
            compare(ProfileEditor.revision, "r1");
            verify(ProfileEditor.active);
            verify(!ProfileEditor.dirty);
            compare(reloaded.count, 1);
        }

        function test_a_late_answer_for_another_profile_is_ignored() {
            ProfileEditor.open("a");
            const first = lastCall();
            ProfileEditor.open("b");
            first.done({ fields: { "connection.id": "A" }, revision: "x" }, null);
            compare(ProfileEditor.title, "");
            verify(ProfileEditor.loading);
        }

        function test_a_failed_read_shows_why() {
            ProfileEditor.open("u");
            lastCall().done(null, { code: "not_found", message: "gone" });
            compare(ProfileEditor.errorText, "gone");
        }

        function test_changes_sit_on_top_and_undoing_one_clears_it() {
            opened({ "connection.autoconnect": true });
            compare(ProfileEditor.value("connection.autoconnect"), true);
            ProfileEditor.set("connection.autoconnect", false);
            compare(ProfileEditor.value("connection.autoconnect"), false);
            verify(ProfileEditor.dirty);
            ProfileEditor.set("connection.autoconnect", true);
            verify(!ProfileEditor.dirty, "back to what's stored isn't a change");
            compare(ProfileEditor.value("missing", "fallback"), "fallback");
        }

        function test_lists_compare_by_content() {
            opened({ "ipv4.dns": ["1.1.1.1"] });
            ProfileEditor.set("ipv4.dns", ["1.1.1.1"]);
            verify(!ProfileEditor.dirty);
            ProfileEditor.set("ipv4.dns", ["8.8.8.8"]);
            verify(ProfileEditor.dirty);
        }

        function test_a_vpns_dictionary_entries_read_one_by_one() {
            opened({ "vpn.data": { remote: "a" }, "vpn.secrets": { password: "s" } });
            compare(ProfileEditor.value("vpn.data.remote"), "a");
            compare(ProfileEditor.value("vpn.secrets.password"), "s");
            compare(ProfileEditor.value("vpn.data.other", "none"), "none");
            ProfileEditor.set("vpn.data.remote", "b");
            compare(ProfileEditor.value("vpn.data.remote"), "b");
            ProfileEditor.set("vpn.data.remote", "a");
            verify(!ProfileEditor.dirty);
        }

        function test_clearing_a_section_marks_each_stored_key() {
            opened({ "802-1x.identity": "me", "802-1x.eap": ["peap"] });
            ProfileEditor.set("802-1x.password", "typed");
            ProfileEditor.clearSection("802-1x");
            compare(ProfileEditor.changes["802-1x.identity"], null);
            compare(ProfileEditor.changes["802-1x.eap"], null);
            verify(!("802-1x.password" in ProfileEditor.changes), "what was only typed just goes");
        }

        function test_saving_sends_only_the_changes_with_the_revision() {
            opened();
            ProfileEditor.set("connection.id", "New");
            ProfileEditor.save();
            verify(ProfileEditor.saving);
            compare(lastCall().method, "network.saveProfile");
            compare(lastCall().params.uuid, "u");
            compare(lastCall().params.revision, "r1");
            compare(Object.keys(lastCall().params.changes), ["connection.id"]);
            lastCall().done(null, null);
            verify(!ProfileEditor.saving);
            verify(ProfileEditor.justSaved);
            verify(!ProfileEditor.dirty);
            compare(lastCall().method, "network.profile", "it reads back what was stored");
        }

        function test_a_failed_save_keeps_the_edits() {
            opened();
            ProfileEditor.set("ipv4.gateway", "x");
            ProfileEditor.save();
            lastCall().done(null, { code: "invalid", message: "ipv4.gateway: not an address" });
            verify(ProfileEditor.dirty);
            compare(ProfileEditor.errorText, "ipv4.gateway: not an address");
            verify(!ProfileEditor.conflict);
        }

        function test_a_conflict_is_flagged() {
            opened();
            ProfileEditor.set("connection.id", "x");
            ProfileEditor.save();
            lastCall().done(null, { code: "conflict", message: "changed" });
            verify(ProfileEditor.conflict);
            ProfileEditor.discard();
            verify(!ProfileEditor.dirty);
        }

        function test_only_one_save_at_a_time() {
            opened();
            ProfileEditor.set("connection.id", "x");
            ProfileEditor.save();
            const count = ConnectivityBackend.calls.length;
            ProfileEditor.save();
            compare(ConnectivityBackend.calls.length, count);
        }

        function test_a_new_profile_is_created_then_opened() {
            ProfileEditor.startNew("vpn", "org.example.vpn", { "connection.id": "Work" });
            verify(ProfileEditor.isNew && ProfileEditor.active);
            compare(ProfileEditor.connectionType, "vpn");
            compare(ProfileEditor.title, "Work");
            ProfileEditor.save();
            compare(lastCall().method, "network.addProfile");
            compare(lastCall().params.connectionType, "vpn");
            compare(lastCall().params.vpnService, "org.example.vpn");
            lastCall().done({ uuid: "new-uuid" }, null);
            verify(!ProfileEditor.isNew);
            compare(ProfileEditor.uuid, "new-uuid");
            compare(lastCall().params.uuid, "new-uuid");
        }

        function test_a_new_profile_counts_every_value_as_a_change() {
            ProfileEditor.startNew("802-3-ethernet", "", {});
            ProfileEditor.set("connection.id", "");
            verify(ProfileEditor.dirty);
        }

        function test_secrets_are_read_on_request_and_dropped() {
            opened();
            compare(ProfileEditor.secrets, ({}));
            ProfileEditor.readSecrets(null);
            compare(lastCall().method, "network.secrets");
            lastCall().done({ secrets: [{ section: "802-11-wireless-security", key: "psk", value: "x" }, { section: "vpn", key: "password", value: "y" }] }, null);
            compare(ProfileEditor.secrets["802-11-wireless-security.psk"], "x");
            compare(ProfileEditor.secrets["vpn.secrets.password"], "y");
            ProfileEditor.forgetSecrets();
            compare(ProfileEditor.secrets, ({}));
        }

        function test_a_new_profile_has_no_secrets_to_read() {
            ProfileEditor.startNew("vpn", "x", {});
            let called = false;
            ProfileEditor.readSecrets(() => called = true);
            verify(called);
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_opening_another_with_changes_pending_asks_first() {
            opened();
            ProfileEditor.set("connection.id", "x");
            ProfileEditor.requestOpen("other");
            compare(ProfileEditor.pendingOpen, "other");
            compare(ProfileEditor.uuid, "u");
            verify(ProfileEditor.dirty);
            ProfileEditor.open(ProfileEditor.pendingOpen);
            compare(ProfileEditor.pendingOpen, "");
            compare(ProfileEditor.uuid, "other");
            verify(!ProfileEditor.dirty);
        }

        function test_opening_the_same_one_keeps_the_changes() {
            opened();
            ProfileEditor.set("connection.id", "x");
            ProfileEditor.requestOpen("u");
            compare(ProfileEditor.pendingOpen, "");
            verify(ProfileEditor.dirty);
        }

        function test_opening_with_nothing_pending_goes_straight_there() {
            opened();
            ProfileEditor.requestOpen("other");
            compare(ProfileEditor.uuid, "other");
        }
    }
}
