import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A status icon standing on its own in the bar. Hidden while `active` is false;
 * when `clickable`, a left click emits `activated`.
 */
MouseArea {
    id: root

    property var host: null
    property bool active: true
    property bool clickable: false
    property string tooltipText: ""
    readonly property bool barVisible: active
    readonly property bool hovered: containsMouse
    default property alias content: container.data

    signal activated()

    implicitWidth: host?.vertical ? Appearance.sizes.baseVerticalBarWidth : container.implicitWidth + 8
    implicitHeight: host?.vertical ? container.implicitHeight + 8 : Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: clickable ? Qt.LeftButton : Qt.NoButton
    cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()

    Item {
        id: container
        anchors.centerIn: parent
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    PopupToolTip {
        extraVisibleCondition: root.tooltipText.length > 0
        text: root.tooltipText
    }
}
