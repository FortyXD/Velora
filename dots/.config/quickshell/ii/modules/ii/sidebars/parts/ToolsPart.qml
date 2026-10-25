pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A grid of tools and apps, a click away (options: items, columns, labels). An item is a tool from
 * SidebarCatalog.tools or "app:<desktop id>". Tools that act on the screen close the sidebars first.
 */
Rectangle {
    id: root
    property Item host: null
    readonly property var options: root.host?.options ?? {}
    readonly property var items: (root.options.items ?? SidebarCatalog.defaultTools).filter(id => id.startsWith("app:") || SidebarCatalog.tool(id))
    readonly property int columns: Math.max(3, Math.min(6, root.options.columns ?? 4))
    readonly property bool labels: root.options.labels ?? true

    implicitHeight: grid.implicitHeight + 16
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    // Runs after the sidebar has gone, so it isn't in a screenshot or in the way of picking
    function afterClosing(action) {
        GlobalStates.closeSidebars();
        delayed.action = action;
        delayed.restart();
    }
    Timer {
        id: delayed
        property var action: null
        interval: 300
        onTriggered: delayed.action?.()
    }
    function global(name) {
        root.afterClosing(() => Hyprland.dispatch(`hl.dsp.global("quickshell:${name}")`));
    }

    function run(id) {
        if (id.startsWith("app:")) {
            GlobalStates.closeSidebars();
            TaskbarApps.launch(id.slice(4), 0);
            return;
        }
        switch (id) {
            case "screenshot": root.global("regionScreenshot"); break;
            case "ocr": root.global("regionOcr"); break;
            case "lens": root.global("regionSearch"); break;
            case "emoji": root.global("overviewEmojiToggle"); break;
            case "clipboardSearch": root.global("overviewClipboardToggle"); break;
            case "record":
                if (ScreenRecorder.recording) ScreenRecorder.toggle();
                else root.afterClosing(() => ScreenRecorder.toggle());
                break;
            case "colorPicker": root.afterClosing(() => Quickshell.execDetached([Quickshell.shellPath("scripts/colors/pick-color.sh")])); break;
            case "songRec": SongRec.toggleRunning(); break;
            case "qr": root.afterClosing(() => Quickshell.execDetached([Quickshell.shellPath("scripts/toolbox/open.sh"), "qr"])); break;
            case "converter": root.afterClosing(() => Quickshell.execDetached([Quickshell.shellPath("scripts/toolbox/open.sh"), "converter"])); break;
            case "keyboard": root.afterClosing(() => GlobalStates.oskOpen = !GlobalStates.oskOpen); break;
        }
    }

    GridLayout {
        id: grid
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
        }
        columns: root.columns
        columnSpacing: 4
        rowSpacing: 4
        uniformCellWidths: true

        Repeater {
            model: root.items
            delegate: RippleButton {
                id: toolButton
                required property string modelData
                readonly property bool isApp: modelData.startsWith("app:")
                readonly property var tool: isApp ? null : SidebarCatalog.tool(modelData)
                readonly property bool active: (modelData === "record" && ScreenRecorder.recording) || (modelData === "songRec" && SongRec.running)
                readonly property string label: isApp ? TaskbarApps.displayName(modelData.slice(4))
                    : active && modelData === "record" ? Translation.tr("Stop") : (tool?.name ?? "")
                Layout.fillWidth: true
                implicitHeight: root.labels ? 62 : 44
                buttonRadius: Appearance.rounding.small
                toggled: toolButton.active
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.run(modelData)
                altAction: () => { if (modelData === "songRec") SongRec.toggleMonitorSource(); }

                contentItem: ColumnLayout {
                    spacing: 2
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 24
                        implicitHeight: 24
                        MaterialSymbol {
                            visible: !toolButton.isApp
                            anchors.centerIn: parent
                            text: toolButton.active && toolButton.modelData === "record" ? "stop_circle" : (toolButton.tool?.icon ?? "")
                            iconSize: 22
                            color: toolButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        IconImage {
                            visible: toolButton.isApp
                            anchors.fill: parent
                            source: toolButton.isApp ? Quickshell.iconPath(TaskbarApps.iconFor(toolButton.modelData.slice(4)), "application-x-executable") : ""
                        }
                    }
                    StyledText {
                        visible: root.labels
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: toolButton.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: toolButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
                StyledToolTip {
                    text: toolButton.modelData === "songRec" ? Translation.tr("%1 · right click: listen to %2").arg(toolButton.label).arg(SongRec.monitorSourceString) : toolButton.label
                }
            }
        }
    }
}
