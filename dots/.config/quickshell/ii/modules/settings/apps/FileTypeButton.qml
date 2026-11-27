pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

SettingsAction {
    id: root
    required property bool pageActive
    property bool failed: false
    property bool awaitingResult: false
    readonly property bool settingsSearchable: true
    readonly property string buttonIcon: "folder_open"
    readonly property string description: Translation.tr("Choose or drop a file to set the default app for its type")
    readonly property string searchText: text + " " + description
    signal resolved(var type)

    text: Translation.tr("Choose a file…")
    Accessible.description: awaitingResult ? Translation.tr("Checking…") : description
    implicitHeight: 42
    implicitWidth: contentItem.implicitWidth + 2 * horizontalPadding
    horizontalPadding: 13
    buttonRadius: Appearance.rounding.small
    colBackground: dropTarget.containsDrag ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
    colBackgroundHover: dropTarget.containsDrag ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
    enabled: pageActive && !query.running
    onClicked: {
        failed = false;
        dialog.open();
    }
    onPageActiveChanged: {
        if (pageActive) return;
        awaitingResult = false;
        failed = false;
        if (dialog?.visible) dialog.close();
    }

    function isLocalFile(url) {
        return /^file:(?:\/\/(?:localhost)?\/|\/(?!\/))/i.test(url.toString());
    }
    function singleLocalFile(event) {
        return event.hasUrls && event.urls.length === 1 && isLocalFile(event.urls[0]);
    }
    function inspectFile(url) {
        if (!pageActive || query.running) return;
        failed = !isLocalFile(url);
        if (failed) return;
        awaitingResult = true;
        query.command = [Quickshell.shellPath("scripts/helper"), "apps", "inspect", "file", url.toString(), Translation.languageCode];
        query.running = true;
    }

    contentItem: RowLayout {
        spacing: 7
        MaterialSymbol {
            text: dropTarget.containsDrag ? "download" : root.awaitingResult ? "hourglass_top" : root.buttonIcon
            iconSize: 19
            color: Appearance.colors.colPrimary
            scale: dropTarget.containsDrag ? 1.12 : 1
            Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(140); easing.type: Easing.OutCubic } }
        }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer3
        }
    }
    StyledToolTip {
        text: root.description
        extraVisibleCondition: root.enabled && !dialog.visible && !dropTarget.containsDrag
        delay: 550
    }
    DropArea {
        id: dropTarget
        anchors.fill: parent
        onEntered: drag => { drag.accepted = root.singleLocalFile(drag); }
        onDropped: drop => {
            if (!root.singleLocalFile(drop)) return;
            root.inspectFile(drop.urls[0]);
            drop.acceptProposedAction();
        }
    }
    FileDialog {
        id: dialog
        objectName: "associationFileDialog"
        parentWindow: root.Window.window
        title: root.text
        fileMode: FileDialog.OpenFile
        onVisibleChanged: {
            if (visible || !root.pageActive) return;
            const window = parentWindow;
            if (window?.active && !window.activeFocusItem) window.requestActivate();
        }
        onAccepted: root.inspectFile(selectedFile)
        onRejected: if (root.pageActive) root.forceActiveFocus()
    }
    Process {
        id: query
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            if (!root.awaitingResult) return;
            root.awaitingResult = false;
            let type;
            if (code === 0 && status === 0) {
                try { type = JSON.parse(output.text); } catch (error) {}
            }
            if (type?.mime) root.resolved(type);
            else root.failed = true;
        }
    }
}
