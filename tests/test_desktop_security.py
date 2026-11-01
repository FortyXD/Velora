"""Exercise untrusted desktop content with Qt and executable fakes, without a desktop or network."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST_RUNNER = shutil.which('qmltestrunner6') or next(
    (str(path) for path in (Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner'))
     if path.is_file()), None)


def production(path):
    return '\n'.join(line for line in (SHELL / path).read_text().splitlines()
                     if not line.startswith(('import qs', 'import Quickshell')))


@unittest.skipUnless(QT_TEST_RUNNER, 'Qt 6 Quick Test is not installed')
class DesktopSecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='velora-desktop-security-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Singleton.qml').write_text('import QtQuick\nQtObject { default property list<QtObject> content }')
        (self.root / 'Process.qml').write_text(
            'import QtQuick\nQtObject { property bool running; property var command; property QtObject stdout; '
            'property string workingDirectory; property bool stdinEnabled; property var environment: ({}); '
            'property var writes: []; signal started(); signal exited(int code,int status); '
            'function write(value) { writes = writes.concat([value]); } '
            'Component.onCompleted: Probe.jobs=Probe.jobs.concat([this]) }')
        (self.root / 'StdioCollector.qml').write_text(
            'import QtQuick\nQtObject { property string text; signal streamFinished() }')
        stubs = {
            'Probe': 'property var jobs: []',
            'Config': 'property var options: ({networking:{userAgent:"audit-agent"}})',
            'Directories': 'property string latexOutput:"/unused"',
            'Appearance': 'property var font:({pixelSize:{normal:12}}); property var colors:({colOnLayer1:"white"})',
        }
        for name, body in stubs.items():
            (self.root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
        (self.root / 'qmldir').write_text('\n'.join(f'singleton {name} 1.0 {name}.qml' for name in stubs))
        for name in ('FileUtils', 'StringUtils', 'CurlUtils'):
            (self.root / f'{name}.qml').write_text('import QtQuick\n' + production(f'modules/common/functions/{name}.qml'))
            with (self.root / 'qmldir').open('a') as file:
                file.write(f'\nsingleton {name} 1.0 {name}.qml\n')
        (self.root / 'ImageDownloaderProcess.qml').write_text(production('modules/common/utils/ImageDownloaderProcess.qml'))
        (self.root / 'LatexRenderer.qml').write_text(production('services/LatexRenderer.qml').replace(
            'id: root', 'id: root\nproperty bool auditExecuted: false', 1))
        with (self.root / 'qmldir').open('a') as file:
            file.write('\nsingleton LatexRenderer 1.0 LatexRenderer.qml\n')

    def qml(self, body):
        test = self.root / 'tst_security.qml'
        test.write_text('import QtQuick\nimport QtTest\nTestCase { name:"DesktopSecurity"\n' + body + '\n}')
        result = subprocess.run([QT_TEST_RUNNER, '-input', str(test), '-o', '-,txt'],
                                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                                     'QT_QPA_PLATFORMTHEME': 'generic'}, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotRegex(result.stdout + result.stderr, 'ReferenceError|TypeError')
        return result.stdout

    def download_command(self, url, destination):
        output = self.qml('''
            Component { id: download; ImageDownloaderProcess {} }
            function test_command() {
                const job = download.createObject(this, {sourceUrl: URL, filePath: DESTINATION});
                console.log("COMMAND=" + JSON.stringify(job.command));
            }
        '''.replace('URL', json.dumps(url)).replace('DESTINATION', json.dumps(str(destination))))
        return json.loads(re.search(r'COMMAND=(\[.*\])', output).group(1))

    def fake_curl(self):
        binary = self.root / 'bin'
        binary.mkdir()
        curl = binary / 'curl'
        curl.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]
pathlib.Path(os.environ['CALLS']).write_text(json.dumps(args))
pathlib.Path(args[args.index('-o')+1]).write_text('downloaded')
sys.exit(int(os.environ.get('CURL_EXIT','0')))
''')
        curl.chmod(0o755)
        return {**os.environ, 'PATH': str(binary) + ':/usr/bin', 'CALLS': str(self.root / 'calls.json')}

    def test_remote_image_url_is_not_executed_and_path_with_spaces_works(self):
        marker = self.root / 'injected'
        url = "https://example.invalid/'$(printf injected > " + str(marker) + ")'"
        destination = self.root / "path with spaces and ' quotes" / 'image'
        command = self.download_command(url, destination)
        result = subprocess.run(command, env=self.fake_curl(), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(destination.read_text(), 'downloaded')
        args = json.loads((self.root / 'calls.json').read_text())
        self.assertEqual(args[-2:], ['--', url])
        self.assertEqual(args[args.index('--user-agent') + 1], 'audit-agent')

    def test_failed_download_preserves_destination_and_cleans_partial_file(self):
        destination = self.root / 'image'
        command = self.download_command('https://example.invalid/image', destination)
        env = self.fake_curl()
        env['CURL_EXIT'] = '22'
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 22)
        self.assertFalse(destination.exists())
        self.assertEqual(list(self.root.glob('image.part.*')), [])

    def test_predictable_partial_symlink_is_not_followed(self):
        victim = self.root / 'victim'
        victim.write_text('preserved')
        destination = self.root / 'image'
        (self.root / 'image.part').symlink_to(victim)
        result = subprocess.run(self.download_command('https://example.invalid/image', destination),
                                env=self.fake_curl(), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(victim.read_text(), 'preserved')
        self.assertEqual(destination.read_text(), 'downloaded')

    def test_latex_expression_remains_one_argument(self):
        self.qml(r'''
            function test_literal_expression() {
                const expression = 'x", (root.auditExecuted = true), "x' + "\n\\frac{a}{b} ' $(echo bad)";
                const result = LatexRenderer.requestRender(expression);
                compare(LatexRenderer.auditExecuted, false);
                compare(Probe.jobs.length, 1);
                compare(Probe.jobs[0].command[0], "/opt/MicroTeX/LaTeX");
                compare(Probe.jobs[0].command[2], "-input=" + expression);
                compare(Probe.jobs[0].workingDirectory, "/opt/MicroTeX");
                verify(result[1]);
            }
        ''')

    def test_latex_pending_requests_are_deduplicated_and_failed_renders_retry(self):
        self.qml('''
            SignalSpy { id: rendered; target: LatexRenderer; signalName:"renderFinished" }
            function test_lifecycle() {
                const result = LatexRenderer.requestRender("x+1");
                verify(result[1]);
                verify(!LatexRenderer.requestRender("x+1")[1]);
                compare(Probe.jobs.length, 1);
                compare(rendered.count, 0);
                Probe.jobs[0].exited(1, 0);
                compare(rendered.count, 0);
                verify(!LatexRenderer.processedHashes.includes(result[0]));
                verify(LatexRenderer.requestRender("x+1")[1]);
                compare(Probe.jobs.length, 2);
                Probe.jobs[1].exited(0, 0);
                compare(rendered.count, 1);
                verify(LatexRenderer.processedHashes.includes(result[0]));
                verify(!LatexRenderer.requestRender("x+1")[1]);
                compare(Probe.jobs.length, 2);
                compare(rendered.count, 2);
            }
        ''')

    def test_remote_filenames_cannot_escape_download_directory(self):
        self.qml('''
            function test_filenames() {
                const urls = ["https://example.invalid/..%2f..%2f.config%2fautostart%2fx.desktop",
                    "https://example.invalid/%2e%2e", "https://example.invalid/.", "https://example.invalid/",
                    "https://example.invalid/%00x", "https://example.invalid/%5cx", "https://example.invalid/%ZZ"];
                for (const url of urls) {
                    const name = FileUtils.fileNameForUrl(url);
                    verify(name.length > 0);
                    verify(name !== "." && name !== "..");
                    verify(!/[\\\\/\\x00-\\x1f\\x7f]/.test(name));
                }
                compare(FileUtils.fileNameForUrl("https://example.invalid/image%20name.jpg?token=abc#view"), "image name.jpg");
            }
        ''')

    @unittest.skipUnless(shutil.which('lua'), 'Lua is not installed')
    def test_preset_keys_and_values_remain_literal_in_generated_lua(self):
        source = (SHELL / 'services/HyprlandSettings.qml').read_text()
        functions = source[source.index('    function luaValue('):source.index('    function buildLua(')]
        (self.root / 'HyprlandSerialization.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { id:root\n' + functions + '\n}')
        with (self.root / 'qmldir').open('a') as file:
            file.write('\nsingleton HyprlandSerialization 1.0 HyprlandSerialization.qml\n')
        key = 'decoration:x"] = (function() _G.auditExecuted=true; return 1 end)(), ["y'
        value = 'quote" newline\ncarriage\rslash\\ tab\t control\x01'
        output = self.qml('''
            function test_serialize() {
                const config = {};
                config[KEY] = 7;
                config["input:kb_layout"] = VALUE;
                console.log("LUA=" + JSON.stringify(HyprlandSerialization.configLua(config)));
            }
        '''.replace('KEY', json.dumps(key)).replace('VALUE', json.dumps(value)))
        lua = json.loads(re.search(r'LUA=(".*")', output).group(1))
        script = '_G.auditExecuted=false; local seen; hl={config=function(value) seen=value end};\n' + lua
        script += '\nassert(not _G.auditExecuted, "preset key executed as Lua source")\n'
        script += 'assert(seen.decoration[ [==[' + key.split(':', 1)[1] + ']==] ] == 7)\n'
        # Byte values avoid sharing the production serializer or Lua's newline normalization.
        script += 'assert(seen.input.kb_layout == string.char(' + ','.join(str(byte) for byte in value.encode()) + '))\n'
        result = subprocess.run(['lua', '-'], input=script, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr + '\n' + lua)

    def test_cloud_service_account_is_sent_only_over_stdin(self):
        (self.root / 'MultiTurnProcess.qml').write_text(production('modules/common/utils/MultiTurnProcess.qml'))
        (self.root / 'GoogleCloud.qml').write_text(production('services/GoogleCloud.qml'))
        stubs = {
            'Quickshell': 'function shellPath(path) { return "/test/" + path; }',
            'KeyringStorage': 'property bool loaded:true; property var keyringData: ({googleCloud:{serviceAccountKey:{project_id:"test",private_key:"private sentinel"}}}); signal dataChanged(); function fetchKeyringData() {}',
        }
        for name, body in stubs.items():
            (self.root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
        with (self.root / 'qmldir').open('a') as file:
            for name in ['GoogleCloud', *stubs]:
                file.write(f'\nsingleton {name} 1.0 {name}.qml\n')
        self.qml('''
            function test_private_input() {
                GoogleCloud.getToken();
                const process = Probe.jobs[0];
                compare(process.command.length, 1);
                verify(!JSON.stringify(process.command).includes("private sentinel"));
                verify(!JSON.stringify(process.environment).includes("private sentinel"));
                process.started();
                compare(JSON.parse(process.writes[0]).private_key, "private sentinel");
                verify(!process.stdinEnabled);
                process.stdout.text = '{"token":"test token","expiry":1893456000}';
                process.stdout.streamFinished();
                verify(GoogleCloud.tokenReady);
                verify(!GoogleCloud.tokenError);
                compare(GoogleCloud.token, "test token");
            }
        ''')

    def test_private_runtime_paths_and_cleanup_arguments(self):
        (self.root / 'Directories.qml').write_text(production('modules/common/Directories.qml'))
        stubs = {
            'Quickshell': 'property int processId:123; property var commands:[]; function shellPath(path) { return "/test/" + path; } function execDetached(command) { commands=commands.concat([command]); }',
            'SystemInfo': 'property string username:"audit"',
        }
        for name, body in stubs.items():
            (self.root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
        with (self.root / 'qmldir').open('a') as file:
            for name in stubs:
                file.write(f'\nsingleton {name} 1.0 {name}.qml\n')
        self.qml('''
            function test_private_paths() {
                verify(Directories.temporary.endsWith("/velora-123"));
                verify(!Directories.temporary.startsWith("/tmp/quickshell"));
                for (const path of [Directories.tempImages, Directories.cliphistDecode, Directories.screenshotTemp])
                    verify(path.startsWith(Directories.temporary + "/"));
                const cleanup = Quickshell.commands.filter(command => command[0] === "bash");
                compare(cleanup.length, 4);
                for (const command of cleanup) {
                    compare(command.length, 5);
                    compare(command[3], "cleanup");
                    verify(!command[2].includes(command[4]));
                }
            }
        ''')

    def test_hyprland_helper_paths_and_values_are_arguments(self):
        (self.root / 'HyprlandConfig.qml').write_text(production('services/HyprlandConfig.qml'))
        (self.root / 'Directories.qml').write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property string config:"/home/with spaces/.config" }')
        stubs = {
            'Quickshell': 'property var commands:[]; function shellPath(path) { return "/checkout with spaces/"+path; } function execDetached(command) { commands=commands.concat([command]); }',
            'Hyprland': 'signal rawEvent(var event)',
        }
        for name, body in stubs.items():
            (self.root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
        with (self.root / 'qmldir').open('a') as file:
            for name in ['HyprlandConfig', *stubs]:
                file.write(f'\nsingleton {name} 1.0 {name}.qml\n')
        self.qml('''
            function test_arguments() {
                const value = 'a"$(printf injected)';
                HyprlandConfig.set("decoration:screen_shader", value);
                HyprlandConfig.setMany({"debug:damage_tracking":1});
                HyprlandConfig.reset("decoration:screen_shader");
                HyprlandConfig.resetMany(["debug:damage_tracking"]);
                compare(Quickshell.commands.length, 4);
                for (const command of Quickshell.commands) {
                    compare(command[0], "/checkout with spaces/scripts/helper");
                    compare(command[1], "hypr-config");
                    compare(command[3], "/home/with spaces/.config/hypr/hyprland/shellOverrides/main.lua");
                }
                compare(Quickshell.commands[0][6], value);
                compare(Quickshell.commands[1][6], "1");
            }
        ''')

    def test_wallpaper_provider_keys_use_curl_stdin_including_download_ping(self):
        (self.root / 'OnlineWallpapers.qml').write_text(production('services/OnlineWallpapers.qml'))
        shutil.copytree(SHELL / 'services/onlineWallpapers', self.root / 'onlineWallpapers')
        (self.root / 'IpcHandler.qml').write_text('import QtQuick\nQtObject { property string target }')
        stubs = {
            'Quickshell': 'property var screens:[]; property var commands:[]; function shellPath(path) { return "/test/"+path; } function execDetached(command) { commands=commands.concat([command]); }',
            'Hyprland': 'property var focusedMonitor:null',
            'Config': 'property var options:({networking:{userAgent:"audit"},background:{online:{disabledProviders:[],provider:"unsplash",downloadDir:"",fitScreen:false,subreddits:[]}}})',
            'Directories': 'property string pictures:"/pictures"; property string cache:"/cache"',
            'KeyringStorage': 'property var keyringData:({wallpaperKeys:{unsplash:"private-unsplash",pixabay:"private-pixabay"}}); property bool loaded:true; function fetchKeyringData(){}',
            'Translation': 'function tr(text){return text;}',
        }
        for name, body in stubs.items():
            (self.root / f'{name}.qml').write_text(f'pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}')
        with (self.root / 'qmldir').open('a') as file:
            for name in ['OnlineWallpapers', 'Quickshell', 'Hyprland', 'KeyringStorage', 'Translation']:
                file.write(f'\nsingleton {name} 1.0 {name}.qml\n')
        self.qml('''
            function test_private_requests() {
                OnlineWallpapers.search("nature");
                const process = Probe.jobs[0];
                verify(!JSON.stringify(process.command).includes("private-unsplash"));
                compare(process.command.slice(-2).join(" "), "--config -");
                process.started();
                verify(process.writes[0].includes("Authorization: Client-ID private-unsplash"));
                verify(!process.stdinEnabled);
                OnlineWallpapers.setProvider("pixabay");
                Config.options = Object.assign({}, Config.options); // Stand-in's nested plain object has no notify signal.
                OnlineWallpapers.search("nature");
                process.started();
                verify(process.writes[1].includes("key=private-pixabay"));
                verify(!JSON.stringify(process.command).includes("private-pixabay"));
                OnlineWallpapers.download({id:"image",provider:"unsplash",downloadPing:"https://api.unsplash.com/test",
                    full:"https://example.invalid/image",fileExt:"jpg"});
                const ping = Probe.jobs[1];
                ping.started();
                verify(ping.writes[0].includes("private-unsplash"));
                verify(!JSON.stringify(ping.command).includes("private-unsplash"));
                verify(!JSON.stringify(Quickshell.commands).includes("private-unsplash"));
                let rejected = false;
                try { CurlUtils.config("https://example.invalid", ["Authorization: key\\r\\nX-Injected: yes"]); }
                catch (error) { rejected = true; }
                verify(rejected);
            }
        ''')

    def test_ai_authorization_headers_use_private_file_descriptors(self):
        methods = []
        for name in ('OpenAi', 'Mistral', 'Gemini'):
            source = (SHELL / f'services/ai/{name}ApiStrategy.qml').read_text()
            start = source.index('    function buildAuthorizationHeader(')
            end = source.index('\n    }', start) + len('\n    }')
            methods.append(source[start:end].replace('buildAuthorizationHeader', f'header{name}'))
        source = (SHELL / 'services/ai/GeminiApiStrategy.qml').read_text()
        start = source.index('    function buildEndpoint(')
        end = source.index('\n    }', start) + len('\n    }')
        methods.append(source[start:end].replace('model: AiModel', 'model'))
        (self.root / 'HeaderBuilder.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {\n' + '\n'.join(methods) + '\n}')
        with (self.root / 'qmldir').open('a') as file:
            file.write('\nsingleton HeaderBuilder 1.0 HeaderBuilder.qml\n')
        output = self.qml('''
            function test_headers() {
                console.log("HEADERS=" + JSON.stringify([HeaderBuilder.headerOpenAi("API_KEY"),
                    HeaderBuilder.headerMistral("API_KEY"), HeaderBuilder.headerGemini("API_KEY")]));
                compare(HeaderBuilder.buildEndpoint({endpoint:"https://example.invalid/generate?alt=sse"}),
                    "https://example.invalid/generate?alt=sse");
            }
        ''')
        snippets = json.loads(re.search(r'HEADERS=(\[.*\])', output).group(1))
        binary = self.root / 'bin'
        binary.mkdir()
        curl = binary / 'curl'
        curl.write_text('''#!/usr/bin/python3
import json,pathlib,sys
args=sys.argv[1:]
print(json.dumps({'args':args,'header':pathlib.Path(args[args.index('-H')+1][1:]).read_text()}))
''')
        curl.chmod(0o755)
        for snippet, expected in zip(snippets, ('Authorization: Bearer ', 'Authorization: Bearer ', 'x-goog-api-key: ')):
            result = subprocess.run(['bash', '-s'], input='curl ' + snippet + '\n',
                                    env={**os.environ, 'PATH': str(binary) + ':/usr/bin', 'API_KEY':'private sentinel'},
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            value = json.loads(result.stdout)
            self.assertEqual(value['header'], expected + 'private sentinel\n')
            self.assertNotIn('private sentinel', json.dumps(value['args']))


class DesktopScriptSecurityTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('qs'), 'Quickshell is not installed')
    def test_real_latex_renderer_retries_after_missing_binary_and_directory(self):
        with tempfile.TemporaryDirectory(prefix='velora-latex-retry-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            binary = root / 'binary with spaces'
            binary.mkdir()
            executable = binary / 'LaTeX'
            executable.write_text('''#!/usr/bin/python3
import json,os,pathlib,sys
pathlib.Path(os.environ['LATEX_ARGS']).write_text(json.dumps({'args':sys.argv[1:],'cwd':os.getcwd()}))
for arg in sys.argv[1:]:
 if arg.startswith('-output='): pathlib.Path(arg[8:]).write_text('<svg/>')
''')
            executable.chmod(0o755)
            source = (SHELL / 'services/LatexRenderer.qml').read_text().replace('import qs.modules.common\n', '')
            (root / 'LatexRenderer.qml').write_text(source)
            (root / 'Directories.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property string latexOutput:' + json.dumps(str(root)) + ' }')
            (root / 'Appearance.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property var font:({pixelSize:{normal:12}}); property var colors:({colOnLayer1:"white"}) }')
            (root / 'qmldir').write_text(''.join(f'singleton {name} 1.0 {name}.qml\n'
                                                for name in ('LatexRenderer', 'Directories', 'Appearance')))
            expression = 'x"; $(printf injected); \\frac{a}{b}'
            (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id:root
    property int stage:0
    property int polls:0
    Component.onCompleted: {
        LatexRenderer.microtexBinaryDir = "/nonexistent/velora-audit";
        LatexRenderer.requestRender(EXPRESSION);
    }
    Timer { interval:50; repeat:true; running:true; onTriggered: {
        if (++root.polls > 60) { console.log("LATEX_RETRY_TIMEOUT"); Qt.quit(); return; }
        if (Object.keys(LatexRenderer.pendingHashes).length !== 0) return;
        if (root.stage === 0) {
            root.stage = 1;
            LatexRenderer.microtexBinaryDir = BINARY;
            LatexRenderer.microtexBinaryName = "missing-binary";
            LatexRenderer.requestRender(EXPRESSION);
        } else if (root.stage === 1) {
            root.stage = 2;
            LatexRenderer.microtexBinaryName = "LaTeX";
            LatexRenderer.requestRender(EXPRESSION);
        }
    } }
    Connections { target:LatexRenderer; function onRenderFinished(hash,path) {
        console.log(root.stage === 2 ? "LATEX_RETRY_PASS" : "LATEX_RETRY_FAIL");
        Qt.quit();
    } }
}
'''.replace('EXPRESSION', json.dumps(expression)).replace('BINARY', json.dumps(str(binary))))
            env = {key: value for key, value in os.environ.items()
                   if key not in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_SESSION_ID')}
            env.update(HOME=str(root), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'),
                       XDG_CACHE_HOME=str(root / 'cache'), DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent', QT_QPA_PLATFORM='offscreen',
                       QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='generic', LATEX_ARGS=str(root / 'args.json'))
            result = subprocess.run(['qs', '-p', str(root / 'shell.qml'), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('LATEX_RETRY_PASS', result.stdout + result.stderr)
            args = json.loads((root / 'args.json').read_text())
            self.assertEqual(args['args'][1], '-input=' + expression)
            self.assertEqual(args['cwd'], str(binary))

    @unittest.skipUnless(shutil.which('jq'), 'jq is not installed')
    def test_capture_fallbacks_keep_images_private_and_cancel_without_consumers(self):
        with tempfile.TemporaryDirectory(prefix='velora-capture-fallback-') as directory:
            root = Path(directory)
            binary = root / 'bin'
            binary.mkdir()
            fake = '''#!/usr/bin/python3
import json,os,pathlib,stat,sys
name=pathlib.Path(sys.argv[0]).name
with open(os.environ['CALLS'],'a') as f: f.write(name+'\\n')
if name=='slurp':
 if os.environ.get('CANCEL'): sys.exit(1)
 print('0,0 100x100')
elif name=='grim':
 p=pathlib.Path(sys.argv[-1]); p.write_bytes(b'png')
 pathlib.Path(os.environ['IMAGE']).write_text(json.dumps({'path':str(p),'mode':stat.S_IMODE(p.stat().st_mode)}))
elif name=='curl': print('{"files":[{"url":"https://example.invalid/image.png"}]}')
elif name=='tesseract':
 print('List of available languages (1):\\neng' if '--list-langs' in sys.argv else 'recognized text')
elif name=='wl-copy': pathlib.Path(os.environ['TEXT']).write_text(sys.stdin.read())
'''
            for name in ('slurp', 'grim', 'curl', 'tesseract', 'wl-copy', 'xdg-open'):
                path = binary / name
                path.write_text(fake)
                path.chmod(0o755)
            env = {**os.environ, 'PATH': str(binary) + ':/usr/bin', 'TMPDIR': str(root),
                   'CALLS': str(root / 'calls'), 'IMAGE': str(root / 'image.json'), 'TEXT': str(root / 'text')}
            for name in ('snip_to_search.sh', 'region_ocr.sh'):
                script = PROJECT / 'dots/.config/hypr/hyprland/scripts' / name
                with self.subTest(script=name, cancelled=False):
                    result = subprocess.run([str(script)], env=env, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    image = json.loads((root / 'image.json').read_text())
                    self.assertEqual(image['mode'], 0o600)
                    self.assertFalse(Path(image['path']).exists())
                with self.subTest(script=name, cancelled=True):
                    (root / 'calls').write_text('')
                    result = subprocess.run([str(script)], env={**env, 'CANCEL':'1'}, capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual((root / 'calls').read_text(), 'slurp\n')
                    self.assertEqual(list(root.glob('tmp*.png')), [])
            self.assertEqual((root / 'text').read_text(), 'recognized text\n')

    @unittest.skipUnless(shutil.which('jq'), 'jq is not installed')
    def test_music_recognition_waits_for_nonempty_matches_and_cleans_fifo(self):
        with tempfile.TemporaryDirectory(prefix='velora-music-') as directory:
            root = Path(directory)
            binary = root / 'bin'
            binary.mkdir()
            (binary / 'pactl').write_text('#!/bin/sh\nif [ "$1" = get-default-sink ]; then echo output; else echo output.monitor; fi\n')
            (binary / 'songrec').write_text('''#!/usr/bin/python3
import json,os,pathlib,stat,time
p=pathlib.Path(os.readlink('/proc/self/fd/1'))
pathlib.Path(os.environ['FIFO_LOG']).write_text(json.dumps({'path':str(p),'parent_mode':stat.S_IMODE(p.parent.stat().st_mode)}))
print('{"matches": []}',flush=True)
print('{"matches": [{}], "track":{"title":"matched"}}',flush=True)
time.sleep(1)
''')
            for path in binary.iterdir(): path.chmod(0o755)
            result = subprocess.run([str(SHELL / 'scripts/musicRecognition/recognize-music.sh'), '-t', '2'],
                                    env={**os.environ, 'PATH': str(binary) + ':/usr/bin', 'TMPDIR': str(root),
                                         'FIFO_LOG': str(root / 'fifo.json')}, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['track']['title'], 'matched')
            fifo = json.loads((root / 'fifo.json').read_text())
            self.assertEqual(fifo['parent_mode'], 0o700)
            self.assertFalse(Path(fifo['path']).parent.exists())

    @unittest.skipUnless(shutil.which('qs'), 'Quickshell is not installed')
    def test_real_quickshell_delivers_ai_script_over_stdin(self):
        source = (SHELL / 'services/Ai.qml').read_text()
        start = source.index('        command: ["bash", "-s"]')
        fragment = source[start:source.index('        function markDone()', start)]
        fragment = fragment.replace('        property AiMessageData message\n', '').replace(
            '        property ApiStrategy currentStrategy\n', '')
        with tempfile.TemporaryDirectory(prefix='velora-ai-pipe-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            shell = root / 'shell.qml'
            shell.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Process { id:requester
''' + fragment + '''
        stdout: StdioCollector {
            onStreamFinished: {
                console.log(text === "request sentinel" ? "REQUEST_PIPE_PASS" : "REQUEST_PIPE_FAIL");
                Qt.quit();
            }
        }
    }
    Component.onCompleted: {
        requester.pendingScript = "printf '%s' 'request sentinel'\\n";
        requester.stdinEnabled = true;
        requester.running = true;
    }
    Timer { interval:5000; running:true; onTriggered: { console.log("REQUEST_PIPE_TIMEOUT"); Qt.quit(); } }
}
''')
            env = {key: value for key, value in os.environ.items()
                   if key not in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_SESSION_ID')}
            env.update(HOME=str(root), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'),
                       XDG_CACHE_HOME=str(root / 'cache'), DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent', QT_QPA_PLATFORM='offscreen',
                       QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='generic')
            result = subprocess.run(['qs', '-p', str(shell), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('REQUEST_PIPE_PASS', result.stdout + result.stderr)
            self.assertNotIn('REQUEST_PIPE_FAIL', result.stdout + result.stderr)

    def test_cloud_token_wrapper_keeps_stdin_private_and_supports_spaces(self):
        with tempfile.TemporaryDirectory(prefix='velora-cloud-') as directory:
            root = Path(directory)
            venv = root / 'virtual env'
            (venv / 'bin').mkdir(parents=True)
            python = venv / 'bin/python'
            python.write_text('#!/usr/bin/python3\nimport json,sys\nprint(json.dumps({"args":sys.argv[1:],"input":sys.stdin.read()}))\n')
            python.chmod(0o755)
            result = subprocess.run([str(SHELL / 'services/gCloud/token-from-key-venv.sh')],
                                    input='{"private_key":"private sentinel"}', text=True, capture_output=True,
                                    env={**os.environ, 'ILLOGICAL_IMPULSE_VIRTUAL_ENV': str(venv)}, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output['input'], '{"private_key":"private sentinel"}')
            self.assertEqual(len(output['args']), 1)
            self.assertNotIn('private sentinel', json.dumps(output['args']))

    @unittest.skipUnless(shutil.which('jq'), 'jq is not installed')
    def test_wallpaper_classifier_quotes_prompt_and_cleans_private_image(self):
        with tempfile.TemporaryDirectory(prefix='velora-wallpaper-ai-') as directory:
            root = Path(directory)
            binary = root / 'bin'
            binary.mkdir()
            fake = '''#!/usr/bin/python3
import json,os,pathlib,stat,sys
name=pathlib.Path(sys.argv[0]).name
if name=='magick':
 p=pathlib.Path(sys.argv[-1]);p.write_bytes(b'jpeg')
 pathlib.Path(os.environ['IMAGE_LOG']).write_text(json.dumps({'path':str(p),'mode':stat.S_IMODE(p.stat().st_mode)}))
elif name=='secret-tool': print('{"apiKeys":{"gemini":"test-key"}}')
elif name=='curl':
 pathlib.Path(os.environ['PAYLOAD_LOG']).write_text(pathlib.Path(sys.argv[sys.argv.index('--data-binary')+1][1:]).read_text())
 assert 'test-key' not in str(sys.argv)
 assert pathlib.Path(sys.argv[sys.argv.index('-H')+1][1:]).read_text() == 'x-goog-api-key: test-key\\n'
 print('{"candidates":[{"content":{"parts":[{"text":"abstract"}]}}]}')
'''
            for name in ('magick', 'secret-tool', 'curl'):
                path = binary / name
                path.write_text(fake)
                path.chmod(0o755)
            prompt = 'quoted "prompt" with\nnew line and \\ slash'
            result = subprocess.run([str(SHELL / 'scripts/ai/gemini-categorize-wallpaper.sh'),
                                     str(root / 'image with spaces.jpg'), 'test-model', prompt],
                                    env={**os.environ, 'PATH': str(binary) + ':/usr/bin', 'TMPDIR': str(root),
                                         'IMAGE_LOG': str(root / 'image.json'), 'PAYLOAD_LOG': str(root / 'payload.json')},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'abstract')
            self.assertEqual(json.loads((root / 'payload.json').read_text())['contents'][0]['parts'][1]['text'], prompt)
            image = json.loads((root / 'image.json').read_text())
            self.assertEqual(image['mode'], 0o600)
            self.assertFalse(Path(image['path']).exists())


if __name__ == '__main__':
    unittest.main()
