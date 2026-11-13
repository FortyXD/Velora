"""Run the actual QML JavaScript entrypoints with a recording executor boundary."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dots/.config/quickshell/ii/services/Ai.qml"


def function(name):
    found = re.search(r"    function " + name + r"\(([^\n]*)\) \{\n(.*?)\n    \}", SOURCE.read_text(), re.S)
    if not found:
        raise AssertionError(name)
    params = re.sub(r":\s*\w+", "", found[1])
    return f"function {name}({params}) {{\n{found[2]}\n}}\n"


@unittest.skipUnless(shutil.which("node"), "Node is needed for the JavaScript boundary harness")
class AiExecutionTests(unittest.TestCase):
    def run_js(self, body):
        script = '''const assert = require('assert');
String.prototype.arg = function(value) { return this.replace(/%[1-9]/,String(value)); };
const Translation = {tr:s=>s};
const outputs = [], calls = [];
const Assistant = {allowed:true, submitTool(...args) { calls.push(args); return this.allowed; }};
const root = {problem:'', messageIDs:[], messageByID:{}, addMessage:(...v)=>outputs.push(v), responseFinished:()=>{}};
const requester = {makeRequest:()=>{calls.push(['model']);}};
let remoteConsent = '', remoteSystemPrompt = '', status = '';
const contextFingerprint = ()=>'current';
const addFunctionOutputMessage = (...v)=>outputs.push(v);
const Config = {options:{policies:{ai:2}},setNestedValue:()=>{throw new Error('Unsafe direct config mutation');}};
const GlobalStates = {screenLocked:false};
const Quickshell = {execDetached:()=>{throw new Error('Unsafe direct process execution');}};
'''
        script += function("approveCommand") + function("rejectCommand") + function("handleFunctionCall") + body
        run = subprocess.run(["node"], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_exact_command_handoff_and_busy_rejection(self):
        self.run_js('''
const command = "printf '%s' '$(touch /outside)'; echo safe";
const message = {functionPending:true,functionCall:{name:'run_shell_command',args:{command}},functionName:'run_shell_command'};
Assistant.allowed=false; approveCommand(message); assert.equal(message.functionPending,true);
Assistant.allowed=true; approveCommand(message); assert.equal(message.functionPending,false);
assert.deepEqual(calls[1],['terminal_run',{command,network:false},command,'sidebar']);
approveCommand(message); assert.equal(calls.length,2);
''')

    def test_config_bypass_and_unrecognized_tools_are_denied(self):
        self.run_js('''
handleFunctionCall('set_shell_config',{key:'policies.ai',value:1},{});
handleFunctionCall('get_shell_config',{},{});
handleFunctionCall('delete_everything',{},{});
approveCommand({functionPending:true,functionCall:{name:'delete_everything'}});
assert.equal(calls.length,0); assert.equal(outputs.length,3);
''')

    def test_context_consent_cannot_authorize_changed_messages(self):
        self.run_js('''
const stale={functionPending:true,functionCall:{name:'remote_context',args:{fingerprint:'stale'}}};
approveCommand(stale); assert.equal(calls.length,0); assert.equal(remoteConsent,'');
const fresh={functionPending:true,functionCall:{name:'remote_context',args:{fingerprint:'current'}}};
approveCommand(fresh); assert.equal(remoteConsent,'current'); assert.deepEqual(calls,[['model']]);
''')

    def test_lock_and_disabled_policy_reject_late_approvals(self):
        self.run_js('''
const message={functionPending:true,functionCall:{name:'run_shell_command',args:{command:'touch file'}}};
GlobalStates.screenLocked=true; approveCommand(message);
GlobalStates.screenLocked=false; Config.options.policies.ai=0; approveCommand(message);
assert.equal(calls.length,0);
''')


if __name__ == "__main__":
    unittest.main()
