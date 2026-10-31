import QtQuick
import QtTest

Item {
    SignalSpy { id: events; target: ConnectivityBackend; signalName: "event" }

    TestCase {
        name: "ConnectivityBackend"

        function hello(protocol, agents) {
            ConnectivityBackend.handleLine(JSON.stringify({ type: "hello", protocol: protocol ?? 2, agents: agents ?? false }));
        }

        function init() {
            events.clear();
            ConnectivityBackend.process.writes = [];
            ConnectivityBackend.process.running = true;
            ConnectivityBackend.problem = "";
            ConnectivityBackend.failures = 0;
            ConnectivityBackend.pending = ({});
            ConnectivityBackend.ready = false;
            ConnectivityBackend.network = ({});
            ConnectivityBackend.bluetooth = ({});
            ConnectivityBackend.restarts.stop();
        }

        function test_requests_before_hello_fail_right_away() {
            let answer = null;
            ConnectivityBackend.call("ping", {}, (result, error) => answer = error);
            compare(answer.code, "unavailable");
            compare(ConnectivityBackend.process.writes.length, 0);
        }

        function test_hello_makes_it_ready() {
            hello();
            verify(ConnectivityBackend.ready);
            compare(ConnectivityBackend.problem, "");
            verify(!ConnectivityBackend.agentsActive);
            hello(2, true);
            verify(ConnectivityBackend.agentsActive);
        }

        function test_another_version_is_refused_and_tried_again_later() {
            hello(99);
            verify(!ConnectivityBackend.ready);
            compare(ConnectivityBackend.problem, "version");
            verify(!ConnectivityBackend.process.running);
            ConnectivityBackend.process.exited(0, 0);
            compare(ConnectivityBackend.problem, "version");
            verify(ConnectivityBackend.restarts.running);
            // An update has rebuilt it
            ConnectivityBackend.process.running = true;
            hello(2);
            compare(ConnectivityBackend.problem, "");
            verify(ConnectivityBackend.ready);
        }

        function test_requests_are_one_json_line_each() {
            hello();
            ConnectivityBackend.call("network.join", { ssid: "Home", password: "pass" }, null);
            const writes = ConnectivityBackend.process.writes;
            compare(writes.length, 1);
            compare(writes[0].indexOf("\n"), writes[0].length - 1);
            const message = JSON.parse(writes[0]);
            compare(message.method, "network.join");
            compare(message.params.password, "pass");
            verify(message.id > 0);
        }

        function test_answers_reach_their_callbacks_by_id() {
            hello();
            const answers = {};
            ConnectivityBackend.call("a", {}, (result, error) => answers.a = { result, error });
            ConnectivityBackend.call("b", {}, (result, error) => answers.b = { result, error });
            const ids = ConnectivityBackend.process.writes.map(line => JSON.parse(line).id);
            ConnectivityBackend.handleLine(JSON.stringify({ type: "response", id: ids[1], ok: false, error: { code: "failed", message: "no" } }));
            compare(answers.a, undefined);
            compare(answers.b.error.code, "failed");
            compare(answers.b.result, null);
            ConnectivityBackend.handleLine(JSON.stringify({ type: "response", id: ids[0], ok: true, result: { x: 1 } }));
            compare(answers.a.result.x, 1);
            compare(answers.a.error, null);
        }

        function test_snapshots_and_events_land_in_place() {
            hello();
            ConnectivityBackend.handleLine(JSON.stringify({ type: "snapshot", domain: "network", data: { available: true } }));
            verify(ConnectivityBackend.network.available);
            ConnectivityBackend.handleLine(JSON.stringify({ type: "snapshot", domain: "bluetooth", data: { powered: true } }));
            verify(ConnectivityBackend.bluetooth.powered);
            ConnectivityBackend.handleLine(JSON.stringify({ type: "event", name: "prompt", data: { kind: "pin" } }));
            compare(events.count, 1);
            compare(events.signalArguments[0][0], "prompt");
            compare(events.signalArguments[0][1].kind, "pin");
        }

        function test_broken_lines_are_ignored() {
            hello();
            ConnectivityBackend.handleLine("{not json");
            verify(ConnectivityBackend.ready);
        }

        function test_exit_fails_what_was_waiting_and_restarts() {
            hello();
            let answer = null;
            ConnectivityBackend.call("slow", {}, (result, error) => answer = error);
            ConnectivityBackend.process.exited(1, 0);
            compare(answer.code, "unavailable");
            verify(!ConnectivityBackend.ready);
            compare(ConnectivityBackend.problem, "crashed");
            verify(ConnectivityBackend.restarts.running);
            compare(ConnectivityBackend.restarts.interval, 1000);
        }

        function test_restarts_back_off_and_a_good_run_resets_them() {
            ConnectivityBackend.startedAt = Date.now();
            ConnectivityBackend.process.exited(1, 0);
            compare(ConnectivityBackend.restarts.interval, 1000);
            ConnectivityBackend.process.exited(1, 0);
            compare(ConnectivityBackend.restarts.interval, 2000);
            ConnectivityBackend.process.exited(1, 0);
            compare(ConnectivityBackend.restarts.interval, 4000);
            for (let i = 0; i < 10; i++) ConnectivityBackend.process.exited(1, 0);
            compare(ConnectivityBackend.restarts.interval, 30000);
            ConnectivityBackend.startedAt = Date.now() - 60000;
            ConnectivityBackend.process.exited(1, 0);
            compare(ConnectivityBackend.restarts.interval, 1000);
        }

        function test_a_missing_program_is_told_apart() {
            ConnectivityBackend.process.exited(127, 0);
            compare(ConnectivityBackend.problem, "missing");
            ConnectivityBackend.problem = "";
            ConnectivityBackend.process.exited(126, 0);
            compare(ConnectivityBackend.problem, "missing");
        }

        function test_a_clean_exit_isnt_a_crash() {
            ConnectivityBackend.process.exited(0, 0);
            compare(ConnectivityBackend.problem, "");
        }

        function test_the_command_line_holds_no_data_and_agents_are_opt_in() {
            verify(ConnectivityBackend.process.command.indexOf("--agents") < 0);
            ConnectivityBackend.agents = true;
            verify(ConnectivityBackend.process.command.indexOf("--agents") >= 0);
            ConnectivityBackend.agents = false;
        }
    }
}
