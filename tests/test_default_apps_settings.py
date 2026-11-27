"""Exercise the production General, Default Apps and About pages with private XDG associations."""
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the settings test runtime')
class DefaultAppsSettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_role_and_format_choices_in_the_settings_window(self):
        probe = r'''
    property int step: 0
    property var page: currentPageItem
    TestCase {
        id: input
        when: false
        Component.onCompleted: Quickshell.watchFiles = false
    }
    FileView {
        id: newApp
        path: Quickshell.env("XDG_DATA_DIRS") + "/applications/test-late.desktop"
        blockWrites: true
    }
    function item(name) { return input.findChild(page, name); }
    function check(ok, message) {
        if (!ok) { console.log("CHECK_FAIL", step, message, page?.errorMessage); Qt.quit(); }
        return ok;
    }
    function globalResult(name) {
        return searchView.results.find(result => result.item?.objectName === name);
    }
    function mouse(button) { input.mouseClick(button, button.width / 2, button.height / 2); }
    function sampleUrl(name) { return "file://" + Quickshell.env("XDG_DATA_DIRS") + "/" + encodeURIComponent(name); }
    function advance() {
        const p = root.page;
        if (!Config.ready || !p?.pageShown) {
            if (!root.searching) return;
        }
        if (p?.activeJob || p?.needsRead) return;
        const picker = root.item("defaultAppPicker");
        switch (root.step) {
        case 0:
            if (!p?.loaded || root.item("assignment-browser").reveal < 1) return;
            if (!root.check(p.currentNames.browser === "Firefox" && !root.item("assignment-browser").compact, "wide assignments")) return;
            if (!root.check(p.dailyRoles.every(id => root.item("assignment-" + id).appName), "six actions show confirmed assignments")) return;
            if (!root.check(!root.item("inspectLocalFile").pageActive && !root.item("inspectLocalFile").awaitingResult, "no file lookup on overview")) return;
            break;
        case 1:
            if (!root.check(root.item("suggested-browser-test-firefox.desktop").chosen, "current browser marked inline")) return;
            root.mouse(root.item("suggested-browser-test-chromium.desktop"));
            break;
        case 2:
            if (!root.check(p.currentNames.browser === "Chromium" && !picker.visible, "inline choice changes browser")) return;
            root.item("default-browser").forceActiveFocus(Qt.TabFocusReason);
            input.keyClick(Qt.Key_Down);
            if (!root.check(root.item("default-mail").activeFocus, "keyboard moves between assignments")) return;
            input.keyClick(Qt.Key_Return);
            if (!root.check(root.item("assignment-mail").expanded && root.item("assignment-mail").reveal < 1,
                "another action is expanding in place")) return;
            break;
        case 3: {
            if (!picker.visible) {
                if (root.item("assignment-mail").reveal < 1) return;
                root.item("browse-mail").clicked();
                return;
            }
            if (!picker.opened) return;
            const search = input.findChild(picker.contentItem, "appPickerSearch");
            if (!root.check(search.activeFocus && picker.role === "mail", "mail picker focuses search")) return;
            search.text = "test-firefox";
            if (!root.check(picker.apps.length === 1 && picker.apps[0].id === "test-firefox.desktop", "filtered apps")) return;
            input.keyClick(Qt.Key_Return);
            break;
        }
        case 4:
            if (picker.visible) return;
            if (!root.check(!!p.roles.mail.current.webmail && !!root.item("assignment-mail").provider, "mail assignment shows provider")) return;
            break;
        case 5:
            root.item("roleWebmail").selected("proton");
            break;
        case 6:
            if (!root.check(p.roles.mail.current.webmail === "proton", "webmail persisted")) return;
            break;
        case 7:
            root.mouse(root.item("default-terminal"));
            break;
        case 8:
            if (root.item("assignment-terminal").reveal < 1) return;
            root.item("editRoleCommand").clicked();
            root.item("roleCommandInput").text = "kitty --single-instance";
            input.keyClick(Qt.Key_Return);
            break;
        case 9:
            if (picker.visible) return;
            if (!root.check(p.roles.terminal.current.command === "kitty --single-instance", "custom terminal saved")) return;
            p.write(["set", "browser", "absent.desktop"]);
            break;
        case 10:
            if (!root.check(!!p.errorMessage && p.currentNames.browser === "Chromium", "failed write preserves the confirmed app")) return;
            p.write(["set-mime", "test-editor.desktop", "text/csv"]);
            sidebar.searchText = ".jpg";
            break;
        case 11: {
            const hit = root.globalResult("format-images");
            if (!hit) return;
            searchView.resultChosen(hit.pageIndex, hit.item);
            break;
        }
        case 12:
            if (p.tab !== "formats") return;
            root.item("formatSearch").text = ".pdf";
            if (!root.check(root.item("format-pdf").visible && !root.item("format-images").visible && root.item("inspectLocalFile").enabled, "extension search and file action")) return;
            root.item("format-pdf").clicked();
            break;
        case 13:
            if (!picker.opened) return;
            if (!root.check(picker.description.includes("PDF"), "format scope before changing")) return;
            picker.choose(picker.apps.findIndex(app => app.id === "test-reader.desktop"));
            break;
        case 14:
            if (picker.visible) return;
            if (!root.check(p.roles.pdf.current.app?.id === "test-reader.desktop", "PDF handler persisted")) return;
            root.item("formatSearch").text = ".csv";
            root.item("mime-text/csv").clicked();
            break;
        case 15:
            if (!picker.opened) return;
            picker.choose(picker.apps.findIndex(app => app.id === "ask"));
            break;
        case 16:
            if (!root.check(!p.types.some(type => type.mime === "text/csv"), "forget remembered type")) return;
            sidebar.searchText = "Code editor";
            break;
        case 17: {
            const hit = root.globalResult("default-code");
            if (!hit) return;
            searchView.resultChosen(hit.pageIndex, hit.item);
            break;
        }
        case 18:
            if (p.tab !== "overview" || root.item("assignment-code").reveal < 1) return;
            root.item("browse-code").clicked();
            break;
        case 19:
            if (!picker.opened) return;
            if (!root.check(picker.role === "code", "chooser belongs to globally located task")) return;
            input.keyClick(Qt.Key_Escape);
            break;
        case 20:
            if (picker.visible) return;
            if (!root.check(root.item("browse-code").activeFocus, "Escape returns focus to the expanded action")) return;
            root.width = 760; root.height = 500; sidebar.expandOverride = true;
            Config.options.language.ui = "ru_RU";
            break;
        case 21:
            if (root.item("commands")?.title !== "Инструменты рабочего стола") return;
            sidebar.expandOverride = true;
            root.item("commands").clicked();
            if (!root.check(p.tab === "commands" && p.navigationTrail.length === 1, "desktop tools branch")) return;
            root.item("shell-command-taskManager").customEntered("btop");
            if (!root.check(Config.options.apps.taskManager === "btop", "custom shell command")) return;
            root.goBack();
            break;
        case 22:
            if (!root.check(root.item("assignment-code").compact && root.item("default-code").text === "Запускать редактор кода",
                "compact localized assignments: " + root.item("dailyRoleAssignments").width + " / " + root.item("default-code").text)) return;
            root.openPage("general");
            break;
        case 23: {
            if (root.currentPageData.key !== "general" || !p.systemDisk) return;
            const storage = root.item("general-storage"), updates = root.item("general-updates");
            if (!root.check(storage.title === "Хранилище" && updates.y >= storage.y + storage.height, "status cards stack")) return;
            if (!root.check(!root.item("systemResources") && !!root.item("generalQuickSettings"), "quick controls in place of live resources")) return;
            root.item("generalEnergySaving").clicked();
            if (!root.check(root.item("generalEnergySaving").checked === PowerSaving.active && PowerSaving.active, "energy control uses the shared setting")) return;
            root.item("generalEnergySaving").clicked();
            NotificationPreferences.setQuiet(true, 30);
            if (!root.check(root.item("generalQuietMode").checked && root.item("generalQuietMode").description.length > 0, "scheduled quiet state shown")) return;
            NotificationPreferences.setQuiet(false);
            Config.options.apps.taskManager = "touch " + Quickshell.env("XDG_DATA_DIRS") + "/monitor-opened";
            root.item("openSystemMonitor").clicked();
            p.updateStatus = {error: "offline"};
            if (!root.check(updates.detail === "offline" && updates.statusIcon === "warning", "update check error")) return;
            p.updateStatus = {available:true, installation_pending:true, behind:0};
            if (!root.check(updates.value === "Завершить обновление", "already downloaded upgrade")) return;
            p.updateStatus = {available:true, latest_version:"9.1", checked_at:"2025-01-20T15:00:00Z"};
            if (!root.check(updates.value.includes("9.1") && updates.detail.length > 0, "available update and check time")) return;
            root.item("general-about").clicked();
            break;
        }
        case 24:
            if (root.currentPageData.key !== "about" || !p.kernel) return;
            if (!root.check(root.currentPageData.parentKey === "general" && p.processor, "About opens under General with hardware details")) return;
            root.item("copySystemDetails").clicked();
            if (!root.check(Quickshell.clipboardText.includes(p.kernel) && Quickshell.clipboardText.includes(p.processor), "copy actual device details")) return;
            Config.options.appearance.animationSpeed = 0;
            break;
        case 25: {
            const cover = root.item("aboutCover");
            if (!root.check(cover.progress === 1 && !cover.animating && !root.item("replayAboutAnimation").visible, "static cover with motion disabled")) return;
            Config.options.appearance.animationSpeed = 1;
            root.item("replayAboutAnimation").clicked();
            if (!root.check(cover.animating && cover.progress < 1, "logo replay starts")) return;
            root.goBack();
            break;
        }
        case 26:
            if (root.currentPageData.key !== "general") return;
            if (!root.check(!input.findChild(root.pageItemAt(root.pages.findIndex(entry => entry.key === "about")), "aboutCover").animating, "cover stops when hidden")) return;
            root.item("general-apps").clicked();
            break;
        case 27:
            if (root.currentPageData.key !== "apps" || !p.loaded) return;
            if (!root.check(p.currentNames.browser === "Chromium" && p.currentNames.pdf === "Okular", "persisted after returning")) return;
            root.item("default-mail").clicked();
            break;
        case 28:
            if (!picker.visible) {
                if (root.item("assignment-mail").reveal < 1) return;
                root.item("browse-mail").clicked();
                return;
            }
            if (!picker.opened) return;
            picker.choose(picker.apps.findIndex(app => app.id === "ask"));
            break;
        case 29:
            if (picker.visible) return;
            if (!root.check(p.roles.mail.current.ask && !root.item("assignment-mail").provider, "ask every time replaces webmail")) return;
            p.write(["set-mime", "test-editor.desktop", "text/csv", "text/markdown"]);
            root.item("formats").clicked();
            break;
        case 30:
            if (!root.check(p.types.length === 2, "two remembered types")) return;
            root.item("clearRememberedApps").clicked();
            break;
        case 31:
            if (!root.check(p.types.length === 0 && p.roles.pdf.current.app.id === "test-reader.desktop", "bulk reset preserves group assignments")) return;
            root.goBack();
            root.item("default-browser").clicked();
            break;
        case 32:
            if (root.item("assignment-browser").reveal < 1) return;
            root.item("suggested-browser-test-firefox.desktop").forceActiveFocus(Qt.TabFocusReason);
            input.keyClick(Qt.Key_Return);
            break;
        case 33:
            if (picker.visible) return;
            if (!root.check(p.currentNames.browser === "Firefox" && root.item("suggested-browser-test-firefox.desktop").activeFocus, "keyboard selection keeps focus on the chosen app")) return;
            p.write(["set", "code", "test-late.desktop"]);
            break;
        case 34:
            if (!root.check(!!p.errorMessage, "missing app is reported")) return;
            newApp.setText("[Desktop Entry]\nType=Application\nName=New editor\nExec=true\nCategories=IDE;\n");
            root.item("retryDefaultApps").clicked();
            break;
        case 35:
            if (!root.check(!p.errorMessage && p.currentNames.code === "New editor", "retry saves the original assignment")) return;
            Config.options.appearance.animationSpeed = 0;
            root.item("default-text").clicked();
            if (!root.check(root.item("assignment-text").reveal === 1 && root.item("assignment-browser").reveal === 0,
                "reduced motion sets the final layout immediately")) return;
            Config.options.appearance.animationSpeed = 1;
            root.item("formats").clicked();
            break;
        case 36: {
            const button = root.item("inspectLocalFile");
            const url = root.sampleUrl("sample image.jpg");
            if (!root.check(button.enabled && !button.awaitingResult && !picker.visible, "opening file types starts with search and file groups")) return;
            if (!root.check(button.singleLocalFile({hasUrls: true, urls: [url]})
                && !button.singleLocalFile({hasUrls: true, urls: [url, url]})
                && !button.singleLocalFile({hasUrls: true, urls: ["https://example.org"]})
                && !button.singleLocalFile({hasUrls: true, urls: ["file://remotehost/example.jpg"]}), "accepts a single local file")) return;
            button.inspectFile(url);
            break;
        }
        case 37:
            if (!picker.opened) return;
            if (!root.check(picker.mime === "image/jpeg" && !picker.role && picker.fileName === "sample image.jpg"
                && picker.description.includes(".jpg"), "choosing a file opens the exact-type picker directly")) return;
            picker.choose(picker.apps.findIndex(app => app.id === "test-editor.desktop"));
            break;
        case 38:
            if (picker.visible) return;
            root.item("inspectLocalFile").inspectFile(root.sampleUrl("sample image.jpg"));
            break;
        case 39:
            if (!picker.opened) return;
            if (!root.check(picker.currentId === "test-editor.desktop", "a new lookup marks the saved JPEG assignment")) return;
            input.keyClick(Qt.Key_Escape);
            break;
        case 40: {
            if (picker.visible) return;
            if (!root.check(root.item("inspectLocalFile").activeFocus, "Escape returns to the file button")) return;
            const dialog = root.item("associationFileDialog");
            dialog.currentFolder = "file://" + Quickshell.env("XDG_DATA_DIRS");
            dialog.selectedFile = root.sampleUrl("sample file.pdf");
            input.keyClick(Qt.Key_Return);
            break;
        }
        case 41: {
            const dialog = root.item("associationFileDialog");
            if (!dialog.visible) return;
            dialog.accept();
            break;
        }
        case 42:
            if (!picker.opened) return;
            if (!root.check(picker.inspected?.name === "sample file.pdf" && picker.currentId === "test-reader.desktop", "file dialog resolves the current PDF reader")) return;
            input.keyClick(Qt.Key_Escape);
            break;
        case 43:
            if (picker.visible) return;
            root.item("inspectLocalFile").inspectFile(root.sampleUrl("missing-file.pdf"));
            break;
        case 44:
            if (root.item("inspectLocalFile").awaitingResult) return;
            if (!root.check(root.item("fileLookupError").visible && !picker.visible, "a missing file shows an inline error")) return;
            root.item("inspectLocalFile").inspectFile(root.sampleUrl("sample file.pdf"));
            break;
        case 45:
            if (!picker.opened) return;
            if (!root.check(!root.item("fileLookupError").visible && picker.currentId === "test-reader.desktop", "retry succeeds and cancel preserves the default")) return;
            picker.close();
            break;
        case 46:
            if (picker.visible) return;
            root.item("inspectLocalFile").inspectFile(root.sampleUrl("sample file.pdf"));
            root.goBack();
            break;
        case 47:
            if (!root.check(p.tab === "overview" && !picker.visible, "leaving file types dismisses a pending lookup")) return;
            root.item("formats").clicked();
            break;
        case 48:
            if (!root.check(!picker.visible, "returning does not reopen the previous file")) return;
            if (!root.item("inspectLocalFile").enabled) return;
            console.log("DRIVER_PASS"); Qt.quit(); return;
        }
        root.step++;
    }
    Timer { interval: 150; running: true; onTriggered: { root.advance(); restart(); } }
    Timer { interval: 39000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.step, root.page?.errorMessage); Qt.quit(); } }
'''
        host = (pages.SHELL / 'settings.qml').read_text().replace('import QtQuick.Controls', 'import QtTest\nimport QtQuick.Controls', 1)
        host = host.replace('    id: root\n', '    id: root\n' + probe, 1)
        with tempfile.TemporaryDirectory() as tmp:
            share = Path(tmp)
            applications = share / 'applications'
            applications.mkdir()
            for name, label, category, mime in [
                ('firefox', 'Firefox', 'WebBrowser', 'x-scheme-handler/http;x-scheme-handler/https;text/html'),
                ('chromium', 'Chromium', 'WebBrowser', 'x-scheme-handler/http;x-scheme-handler/https;text/html'),
                ('editor', 'Editor', 'TextEditor', 'text/plain'),
                ('reader', 'Okular', 'Viewer', 'application/pdf'),
            ]:
                (applications / f'test-{name}.desktop').write_text(
                    f'[Desktop Entry]\nType=Application\nName={label}\nExec=true\nCategories={category};\nMimeType={mime};\n')
            (share / 'mime').symlink_to('/usr/share/mime')
            (share / 'icons').symlink_to('/usr/share/icons')
            (share / 'sample file.pdf').write_bytes(b'%PDF-1.4\n%%EOF\n')
            (share / 'sample image.jpg').write_bytes(b'\xff\xd8\xff\xe0\x00\x10JFIF\x00' + bytes(16) + b'\xff\xd9')
            (share / 'mimeapps.list').write_text('[Default Applications]\nx-scheme-handler/https=test-firefox.desktop;\n')
            with patch.dict(os.environ, {'XDG_DATA_DIRS': str(share), 'XDG_CONFIG_DIRS': str(share)}):
                output = pages.SettingsPagesTests().run_driver(host, settings_page='apps')
            monitor_opened = (share / 'monitor-opened').exists()
        self.assertIn('DRIVER_PASS', output, output[-8000:])
        self.assertTrue(monitor_opened, 'The configured system monitor was launched')
        components = ('GeneralConfig.qml', 'GeneralQuickSettings.qml', 'About.qml', 'AboutCover.qml', 'VeloraLogo.qml', 'DefaultAppsConfig.qml', 'AppPickerPopup.qml', 'SettingsAction.qml', 'SettingsToolButton.qml', '/settings/apps/')
        settings_log = '\n'.join(line for line in output.splitlines() if any(component in line for component in components))
        pages.SettingsPagesTests().assert_clean(settings_log)
        self.assertNotRegex(settings_log, r'Binding loop|recursive rearrange')

    def test_quiet_switch_calls_the_running_shell(self):
        popen = pages.subprocess.Popen
        server = None

        def run_named_instance(args, **options):
            nonlocal server
            if args[:2] == [pages.QS, '-p']:
                # The desktop owns notification IPC. Settings observes the resulting state on disk.
                shell = Path(args[2]).parent
                config = Path(options['env']['XDG_CONFIG_HOME']) / 'quickshell' / 'ii'
                config.mkdir(parents=True)
                for child in shell.iterdir():
                    if child.name != 'shell.qml':
                        (config / child.name).symlink_to(child)
                (config / 'shell.qml').write_text('import Quickshell\nimport qs.services\n'
                    'ShellRoot { readonly property var notifications: Notifications }\n')
                server = popen([pages.QS, '-c', 'ii', '--no-color'], **options)
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline and server.poll() is None:
                    ipc = pages.subprocess.run([pages.QS, '-c', 'ii', 'ipc', 'show'],
                        env=options['env'], capture_output=True, text=True, timeout=3)
                    if ipc.returncode == 0 and 'setSilent' in ipc.stdout + ipc.stderr:
                        break
                    time.sleep(0.1)
                else:
                    self.fail('The desktop notification IPC did not start')
            return popen(args, **options)

        probe = r'''
    property int stage: 0
    readonly property var notificationServer: Notifications
    property bool savedQuiet: false
    TestCase { id: input; when: false; windowShown: root.visible }
    FileView {
        path: Persistent.filePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.savedQuiet = JSON.parse(text()).notifications?.silent ?? false
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!Config.ready || !Persistent.ready || !root.currentPageItem?.pageShown || !root.notificationServer) return;
            const control = input.findChild(root.currentPageItem, "generalQuietMode");
            if (!control?.enabled) return;
            if (root.stage === 0) {
                control.forceActiveFocus(Qt.TabFocusReason);
                input.keyClick(Qt.Key_Return);
                root.stage++;
            } else if (root.stage === 1 && root.savedQuiet && control.checked && NotificationPreferences.silent) {
                control.click();
                root.stage++;
            } else if (root.stage === 2 && !root.savedQuiet && !control.checked && !NotificationPreferences.silent) {
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: {
        const row = input.findChild(root.currentPageItem, "generalQuietMode");
        console.log("CHECK_FAIL quiet switch", root.stage, row?.checked, row?.checkable, row?.enabled, NotificationPreferences.silent,
                    NotificationPreferences.state.silent, input.findChild(root.currentPageItem, "generalQuickSettings")?.quietError);
        Qt.quit();
    } }
'''
        host = (pages.SHELL / 'settings.qml').read_text().replace('import QtQuick.Controls', 'import QtTest\nimport QtQuick.Controls', 1)
        host = host.replace('    id: root\n', '    id: root\n' + probe, 1)
        try:
            with patch.object(pages.subprocess, 'Popen', run_named_instance):
                output = pages.SettingsPagesTests().run_driver(host, settings_page='general')
        finally:
            if server is not None:
                server.terminate()
                server.wait(timeout=5)
        self.assertIn('DRIVER_PASS', output, output[-6000:])
