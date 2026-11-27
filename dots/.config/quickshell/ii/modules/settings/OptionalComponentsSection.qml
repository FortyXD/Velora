pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    id: root
    property bool pageShown: false
    property bool updateBusy: false
    property var components: []
    property string pending: ""
    property string problem: ""
    readonly property string tool: Quickshell.shellPath("scripts/maintenance/velora.sh")
    title: Translation.tr("Optional components")
    icon: "extension"
    function refresh() {
        if (pageShown && !scan.running) scan.running = true;
        if (pageShown) OfflineTranslator.checkInstalled();
    }
    function mark(id, status) {
        const records = Object.assign({}, Config.options.updates.componentAttempts);
        if (status) records[id] = status; else delete records[id];
        Config.options.updates.componentAttempts = records;
    }
    onPageShownChanged: refresh()
    Component.onCompleted: refresh()
    Process {
        id: scan
        command: [root.tool, "components", "--json"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                root.components = JSON.parse(text).filter(item => !item.required);
                for (const item of root.components) {
                    const attempt = Config.options.updates.componentAttempts?.[item.id];
                    if (attempt && item.installed) root.mark(item.id, "");
                    else if (attempt === "verify") root.mark(item.id, "failed");
                }
                root.problem = "";
            } catch (_) {
                root.problem = Translation.tr("Could not check installed components");
            }
        } }
        onExited: code => { if (code !== 0) root.problem = Translation.tr("Could not check installed components"); }
    }
    Process {
        id: installer
        onExited: code => {
            root.mark(root.pending, code === 0 ? "verify" : "failed");
            root.pending = "";
            root.refresh();
        }
    }
    ConfigNavRow {
        visible: !!root.problem
        title: root.problem
        trailingIcon: "refresh"
        onClicked: root.refresh()
    }
    Repeater {
        model: root.components
        delegate: ConfigNavRow {
            required property var modelData
            readonly property string attempt: Config.options.updates.componentAttempts?.[modelData.id] ?? ""
            title: Translation.tr(modelData.description)
            description: modelData.installed ? Translation.tr("Installed") : root.pending === modelData.id ? Translation.tr("Installing…")
                : attempt === "failed" ? Translation.tr("Installation failed · Retry") : modelData.missing < modelData.packages || attempt
                ? Translation.tr("Incomplete · Resume installation") : Translation.tr("Missing · Install")
            buttonIcon: modelData.installed ? "check_circle" : "download"
            enabled: !modelData.installed && !root.pending && !root.updateBusy
            onClicked: {
                root.pending = modelData.id;
                root.mark(root.pending, "started");
                installer.command = ["kitty", "--title", "Velora", root.tool, "deps", "--add", root.pending];
                installer.running = true;
            }
        }
    }
    ConfigNavRow {
        title: Translation.tr("Offline translator")
        description: OfflineTranslator.installed ? Translation.tr("Installed") : OfflineTranslator.installing ? OfflineTranslator.installStatus :
            OfflineTranslator.installError || (OfflineTranslator.partial ? Translation.tr("Resume download") : Translation.tr("Download"))
        buttonIcon: OfflineTranslator.installed ? "check_circle" : "download"
        enabled: OfflineTranslator.checked && !OfflineTranslator.installed && !OfflineTranslator.installing
        onClicked: OfflineTranslator.install()
    }
}
