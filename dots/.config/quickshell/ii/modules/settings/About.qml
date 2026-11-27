pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    bottomContentPadding: 24
    property string version: ""
    property string processor: ""
    property string kernel: ""
    readonly property string session: [SystemInfo.username, SystemInfo.desktopEnvironment, SystemInfo.windowingSystem].filter(Boolean).join(" · ")

    FileView {
        path: root.pageShown ? "/proc/cpuinfo" : ""
        onLoaded: root.processor = text().match(/^(?:model name|Hardware|cpu model)\s*:\s*(.+)/mi)?.[1]?.trim() || ""
    }
    FileView {
        path: root.pageShown ? "/proc/sys/kernel/osrelease" : ""
        onLoaded: root.kernel = text().trim()
    }
    FileView {
        path: root.pageShown ? (Quickshell.env("XDG_STATE_HOME") || FileUtils.trimFileProtocol(Directories.home) + "/.local/state") + "/velora/update.json" : ""
        watchChanges: root.pageShown
        onFileChanged: reload()
        onLoaded: {
            try { root.version = JSON.parse(text()).current_version || ""; }
            catch (_) { root.version = ""; }
        }
        onLoadFailed: root.version = ""
    }
    function copyDetails() {
        const facts = [[Translation.tr("Processor"), processor], [Translation.tr("Linux kernel"), kernel], [Translation.tr("Session"), session]];
        const lines = [["Velora", version].filter(Boolean).join(" "), SystemInfo.distroName, ...facts.filter(pair => pair[1]).map(pair => pair.join(" · "))];
        Quickshell.clipboardText = lines.join("\n");
        copied.restart();
    }
    Timer { id: copied; interval: 1700 }

    AboutCover {
        objectName: "aboutCover"
        pageActive: root.pageShown
        version: root.version
        onUpdatesRequested: ApplicationWindow.window?.openPage("updates")
    }

    component Fact: RowLayout {
        id: fact
        required property string label
        required property string value
        required property string symbol
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol { text: fact.symbol; iconSize: 19; color: Appearance.colors.colSubtext }
        StyledText {
            Layout.preferredWidth: device.width >= 500 ? 134 : 84
            text: fact.label
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallie
        }
        StyledText {
            Layout.fillWidth: true
            text: fact.value || "—"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.weight: Font.Medium
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("This computer")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
            }
            SettingsAction {
                id: copy
                objectName: "copySystemDetails"
                text: copied.running ? Translation.tr("Copied") : Translation.tr("Copy details")
                implicitWidth: contentItem.implicitWidth + 14
                implicitHeight: 32
                horizontalPadding: 7
                onClicked: root.copyDetails()
                contentItem: RowLayout {
                    spacing: 5
                    MaterialSymbol { text: copied.running ? "check" : "content_copy"; iconSize: 16; color: Appearance.colors.colPrimary }
                    StyledText { text: copy.text; color: Appearance.colors.colPrimary; font.pixelSize: Appearance.font.pixelSize.smaller }
                }
            }
        }
        Rectangle {
            id: device
            objectName: "aboutDevice"
            readonly property bool settingsSearchable: true
            readonly property string title: Translation.tr("This computer")
            readonly property string buttonIcon: "computer"
            readonly property string searchText: [title, Translation.tr("Processor"), root.processor, Translation.tr("Linux kernel"), root.kernel,
                Translation.tr("Session"), root.session, Translation.tr("Copy details")].join(" ")
            Layout.fillWidth: true
            implicitHeight: facts.implicitHeight + 26
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: facts
                x: 16; y: 13; width: device.width - 32
                spacing: 10
                Fact { label: Translation.tr("Processor"); value: root.processor; symbol: "memory" }
                Fact { label: Translation.tr("Linux kernel"); value: root.kernel; symbol: "developer_board" }
                Fact { label: Translation.tr("Session"); value: root.session; symbol: "account_circle" }
            }
        }
    }

    component StartAction: SettingsAction {
        id: action
        required property string symbol
        required property string detail
        required property string keywords
        readonly property bool settingsSearchable: true
        readonly property string searchText: [text, detail, keywords].join(" ")
        readonly property string buttonIcon: symbol
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        implicitHeight: contentItem.implicitHeight + 24
        horizontalPadding: 14
        verticalPadding: 12
        Accessible.description: detail
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: RowLayout {
            spacing: 10
            MaterialSymbol { text: action.symbol; iconSize: 22; color: Appearance.colors.colPrimary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                StyledText { Layout.fillWidth: true; text: action.text; wrapMode: Text.Wrap; font.weight: Font.DemiBold }
                StyledText { Layout.fillWidth: true; text: action.detail; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            }
            MaterialSymbol { text: "arrow_forward"; iconSize: 17; color: Appearance.colors.colSubtext }
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 515 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 10
        rowSpacing: 6
        StartAction {
            objectName: "aboutTour"
            symbol: "explore"
            text: Translation.tr("Quick tour")
            detail: Translation.tr("Try the desktop shortcuts and gestures")
            keywords: Translation.tr("Take the quick tour")
            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "tour", "start"])
        }
        StartAction {
            objectName: "aboutSetup"
            symbol: "auto_fix_high"
            text: Translation.tr("Setup assistant")
            detail: Translation.tr("Choose a layout, theme and apps")
            keywords: Translation.tr("Run the setup assistant")
            onClicked: Quickshell.execDetached(["qs", "-p", FileUtils.trimFileProtocol(Quickshell.shellPath("onboarding.qml"))])
        }
    }

    component ResourceLink: ConfigNavRow {
        id: link
        required property string address
        visible: !!address
        implicitHeight: Math.max(38, contentItem.implicitHeight + 8)
        trailingIcon: "open_in_new"
        Accessible.name: title
        Accessible.description: address
        onClicked: Qt.openUrlExternally(address)
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 565 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 14
        rowSpacing: 12
        ContentSection {
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            title: Translation.tr("Velora project")
            icon: "deployed_code"
            description: Translation.tr("Based on end-4/dots-hyprland")
            ResourceLink { buttonIcon: "code"; title: Translation.tr("Repository"); address: "https://github.com/FortyXD/Velora" }
            ResourceLink { buttonIcon: "auto_stories"; title: Translation.tr("Documentation"); address: "https://github.com/FortyXD/Velora#readme" }
            ResourceLink { buttonIcon: "bug_report"; title: Translation.tr("Report a Bug"); address: "https://github.com/FortyXD/Velora/issues" }
            ResourceLink { buttonIcon: "fork_right"; title: Translation.tr("Upstream project"); address: "https://github.com/end-4/dots-hyprland" }
            ResourceLink { buttonIcon: "favorite"; title: Translation.tr("Support end-4"); address: "https://github.com/sponsors/end-4" }
        }
        ContentSection {
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            visible: !!(SystemInfo.homeUrl || SystemInfo.documentationUrl || SystemInfo.supportUrl || SystemInfo.bugReportUrl || SystemInfo.privacyPolicyUrl)
            title: SystemInfo.distroName
            icon: "computer"
            ResourceLink { buttonIcon: "language"; title: Translation.tr("Website"); address: SystemInfo.homeUrl }
            ResourceLink { buttonIcon: "auto_stories"; title: Translation.tr("Documentation"); address: SystemInfo.documentationUrl }
            ResourceLink { buttonIcon: "support"; title: Translation.tr("Help & Support"); address: SystemInfo.supportUrl }
            ResourceLink { buttonIcon: "bug_report"; title: Translation.tr("Report a Bug"); address: SystemInfo.bugReportUrl }
            ResourceLink { buttonIcon: "policy"; title: Translation.tr("Privacy Policy"); address: SystemInfo.privacyPolicyUrl }
        }
    }
}
