import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A time readout (mm:ss) that turns into a field when clicked, to type a new time:
 * "10" for minutes, "10:30", "1:05:00", "90s", "1h 20m". Enter applies (timeEntered), Esc cancels.
 */
Item {
    id: root
    property int seconds: 0
    property real pixelSize: 40
    property string fontFamily: "" // Empty: the usual font
    property color color: Appearance.m3colors.m3onSurface
    property bool editable: true
    property bool editing: false
    signal timeEntered(int seconds)

    function startEditing() {
        if (!root.editable) return;
        field.text = DateUtils.formatDuration(root.seconds);
        field.invalid = false;
        root.editing = true;
        field.forceActiveFocus();
        field.selectAll();
    }

    implicitWidth: root.editing ? Math.max(field.implicitWidth, label.implicitWidth) : label.implicitWidth
    implicitHeight: label.implicitHeight

    StyledText {
        id: label
        anchors.centerIn: parent
        visible: !root.editing
        text: DateUtils.formatDuration(root.seconds)
        font.pixelSize: root.pixelSize
        font.family: root.fontFamily.length > 0 ? root.fontFamily : Appearance.font.family.main
        color: root.color
    }
    MouseArea {
        anchors.fill: label
        visible: !root.editing && root.editable
        readonly property bool hovered: containsMouse // For the tooltip
        cursorShape: Qt.IBeamCursor
        hoverEnabled: true
        onClicked: root.startEditing()
        StyledToolTip {
            text: Translation.tr("Click to type a time: 10, 25:00 or 1h 30m")
        }
    }

    TextField {
        id: field
        property bool invalid: false
        anchors.centerIn: parent
        visible: root.editing
        width: Math.max(implicitWidth, label.implicitWidth + 24)
        horizontalAlignment: Text.AlignHCenter
        font.family: label.font.family
        font.pixelSize: root.pixelSize * 0.8
        color: field.invalid ? Appearance.colors.colError : root.color
        selectedTextColor: Appearance.colors.colOnSecondaryContainer
        selectionColor: Appearance.colors.colSecondaryContainer
        padding: 2
        cursorDelegate: Rectangle {
            width: 2
            color: Appearance.colors.colPrimary
            visible: field.cursorVisible
        }
        background: Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            radius: 1
            color: field.invalid ? Appearance.colors.colError : Appearance.colors.colPrimary
        }
        onTextEdited: field.invalid = false
        onAccepted: {
            const seconds = DateUtils.parseDuration(field.text);
            if (seconds <= 0) {
                field.invalid = true;
                return;
            }
            root.editing = false;
            root.timeEntered(seconds);
        }
        Keys.onEscapePressed: root.editing = false
        onActiveFocusChanged: if (!activeFocus) root.editing = false
    }
}
