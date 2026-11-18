import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.waffle.looks
import "window-layout.js" as WindowLayout

Rectangle {
    id: root

    required property int workspaceId
    property bool choosingDesktop: false
    property string windowToMove: ""
    color: choosingDesktop ? Looks.colors.bg1Base : ColorUtils.transparentize(Looks.colors.bg1Base, 0.5)
    readonly property real openProgress: TouchpadGestures.overview.progress
    opacity: openProgress

    function chooseDesktop(address) {
        windowToMove = address;
        choosingDesktop = true;
        workspaceListView.currentIndex = Math.max(0, Math.min(workspaceId - 1, workspaceListView.count - 1));
        workspaceListView.positionViewAtIndex(workspaceListView.currentIndex, ListView.Contain);
        workspaceListView.forceActiveFocus();
    }

    function backToWindows() {
        choosingDesktop = false;
        windowToMove = "";
        desktopButton.forceActiveFocus();
    }

    function selectDesktop(id) {
        if (!choosingDesktop || id < 1 || id > workspaceListView.count) return;
        if (windowToMove) {
            const client = HyprlandData.windowByAddress[windowToMove];
            if (!client || id === client.workspace.id) {
                backToWindows();
                return;
            }
            TouchpadGestures.leaveOverview(`hl.dsp.window.move({ workspace = ${id}, follow = false, window = "address:${windowToMove}" })`);
        } else {
            TouchpadGestures.leaveOverview(`hl.dsp.focus({ workspace = ${id} })`);
        }
    }

    // Windows
    property real maxWindowHeight: 290
    property real maxWindowWidth: 738
    property real padding: 52
    property real spacing: 25
    readonly property list<var> toplevels: ToplevelManager.toplevels.values.filter(t => {
        const client = HyprlandData.clientForToplevel(t);
        return client && client.workspace.id === root.workspaceId;
    })
    readonly property list<var> arrangedToplevels: {
        const maxRowWidth = width - padding * 2;
        const count = toplevels.length;
        const resultLayout = [];

        var i = 0;
        while (i < count) {
            var row = [];
            var rowWidth = 0;
            var j = i;

            while (j < count) {
                const toplevel = toplevels[j];
                const client = HyprlandData.clientForToplevel(toplevel);
                const scaledSize = WindowLayout.scaleWindow(client, maxWindowWidth, maxWindowHeight);

                if (rowWidth + scaledSize.width <= maxRowWidth || row.length === 0) {
                    row.push(toplevel);
                    rowWidth += scaledSize.width;
                    j++;
                } else {
                    break;
                }
            }

            resultLayout.push(row);
            i = j;
        }
        return resultLayout;
    }

    MouseArea {
        z: 0
        anchors.fill: parent
        onClicked: {
            GlobalStates.overviewOpen = false;
        }
    }

    // Windows
    WListView {
        id: windowListView
        visible: !root.choosingDesktop
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: (desktopButton.y - height) / 2
        }
        spacing: root.spacing
        topMargin: root.padding
        bottomMargin: root.padding
        leftMargin: root.padding
        rightMargin: root.padding
        height: Math.max(0, Math.min(contentHeight + topMargin + bottomMargin, desktopButton.y))

        interactive: height < contentHeight
        clip: root.openProgress > 0.99

        model: ScriptModel {
            values: root.arrangedToplevels
        }
        delegate: RowLayout {
            id: clientRow
            required property var modelData
            spacing: root.spacing
            anchors.horizontalCenter: parent?.horizontalCenter ?? undefined

            Repeater {
                model: ScriptModel {
                    values: clientRow.modelData
                }
                delegate: Item {
                    id: clientGridArea
                    required property int index
                    required property var modelData
                    implicitWidth: windowItem.openedSize.width
                    implicitHeight: windowItem.openedSize.height + windowItem.titleBarImplicitHeight

                    TaskViewWindow {
                        id: windowItem
                        readonly property real mappedX: (hyprlandClient?.at[0] ?? 0) - clientRow.x - clientGridArea.x - root.padding
                        readonly property real mappedY: (hyprlandClient?.at[1] ?? 0) - clientRow.y - windowListView.y - root.padding
                        transform: Scale {
                            xScale: 1 + (1 - root.openProgress) * (windowItem.fullSize.width / Math.max(1, windowItem.openedSize.width) - 1)
                            yScale: 1 + (1 - root.openProgress) * (windowItem.fullSize.height / Math.max(1, windowItem.openedSize.height) - 1)
                        }
                        x: mappedX * (1 - root.openProgress)
                        y: mappedY * (1 - root.openProgress)
                        onMoveRequested: root.chooseDesktop(windowItem.address)

                        Layout.alignment: Qt.AlignTop
                        maxHeight: root.maxWindowHeight
                        maxWidth: root.maxWindowWidth
                        toplevel: clientGridArea.modelData
                    }
                }
            }
        }
    }

    WButton {
        id: desktopButton
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        icon.name: root.choosingDesktop ? "arrow-left" : "desktop"
        text: root.choosingDesktop ? Translation.tr("Back") : Translation.tr("Choose a desktop")
        colBackground: Looks.colors.bgPanelFooterBackground
        onClicked: root.choosingDesktop ? root.backToWindows() : root.chooseDesktop("")
    }

    Column {
        id: desktopPage
        visible: root.choosingDesktop
        anchors.centerIn: parent
        width: Math.max(0, root.width - 32)
        spacing: 12
        onVisibleChanged: if (visible) enter.restart()

        NumberAnimation {
            id: enter
            target: desktopPage
            property: "scale"
            from: 0.97
            to: 1
            duration: Appearance.scaledDuration(150)
            easing.type: Easing.OutCubic
        }

        WText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.windowToMove ? Translation.tr("Move window to desktop") : Translation.tr("Choose a desktop")
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, workspaceListView.contentWidth + 18)
            height: Math.min(174, root.height * 0.55)
            border.color: Looks.colors.bg2Border
            border.width: 1
            radius: Looks.radius.large
            color: Looks.colors.bgPanelFooterBackground

            WListView {
                id: workspaceListView
                anchors.fill: parent
                anchors.margins: 8
                flickableDirection: Flickable.HorizontalFlick
                orientation: ListView.Horizontal
                interactive: contentWidth > width
                keyNavigationEnabled: true
                clip: true
                spacing: 4
                Keys.onReturnPressed: root.selectDesktop(currentIndex + 1)
                Keys.onEnterPressed: root.selectDesktop(currentIndex + 1)
                model: root.choosingDesktop ? Math.max(1, ...HyprlandData.workspaceIds) + 1 : 0
                delegate: TaskViewWorkspace {
                    required property int index
                    workspace: index + 1
                    newWorkspace: index === workspaceListView.count - 1
                    currentDesktop: workspace === root.workspaceId
                    keyboardSelected: workspaceListView.activeFocus && ListView.isCurrentItem
                    onClicked: root.selectDesktop(workspace)
                }
            }
        }
    }
}
