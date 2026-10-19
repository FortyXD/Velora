import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Shows the first line of a shell command's output, refreshed on an interval, like a waybar
 * custom module. Clicks, middle clicks and scrolling can run commands of their own.
 */
MouseArea {
    id: root

    property var host: null
    readonly property var options: host?.options ?? ({})
    readonly property string command: options.command ?? ""
    readonly property int interval: options.interval ?? 5
    readonly property string icon: options.icon ?? ""
    property string key: ""
    readonly property string output: BarCommands.outputs[key] ?? ""
    readonly property string firstLine: output.split("\n")[0] ?? ""
    readonly property int maxLength: options.maxLength ?? 40
    readonly property string shownText: firstLine.length > maxLength ? firstLine.slice(0, maxLength - 1) + "…" : firstLine
    readonly property bool barVisible: shownText.length > 0 || icon.length > 0
    readonly property bool hovered: containsMouse

    function resubscribe() {
        if (root.key.length > 0) BarCommands.unsubscribe(root.key);
        root.key = BarCommands.subscribe(root.command, root.interval);
    }
    function runAndRefresh(command) {
        if (!command || command.trim().length === 0) return;
        BarCommands.runDetached(command);
        refreshTimer.restart();
    }

    onCommandChanged: resubscribe()
    onIntervalChanged: resubscribe()
    Component.onCompleted: resubscribe()
    Component.onDestruction: BarCommands.unsubscribe(root.key)

    implicitWidth: row.implicitWidth + 8
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: mouse => runAndRefresh(mouse.button === Qt.MiddleButton ? root.options.middleClickCommand : root.options.clickCommand)
    onWheel: wheel => {
        const command = wheel.angleDelta.y > 0 ? root.options.scrollUpCommand : root.options.scrollDownCommand;
        if (!command) {
            wheel.accepted = false;
            return;
        }
        runAndRefresh(command);
    }

    Timer { // Show the effect of a click soon instead of on the next interval
        id: refreshTimer
        interval: 300
        onTriggered: BarCommands.refresh(root.key)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: Appearance.font.pixelSize.larger
            color: root.host?.inPill ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0
        }
        StyledText {
            visible: root.shownText.length > 0
            text: root.shownText
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.host?.inPill ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0
        }
    }

    PopupToolTip {
        extraVisibleCondition: (root.options.tooltip ?? "").length > 0 || root.output.length > root.shownText.length
        text: (root.options.tooltip ?? "").length > 0 ? root.options.tooltip : root.output
    }
}
