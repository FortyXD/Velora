import QtQuick
import QtQuick.Layouts
import qs.modules.common

Item {
    id: root
    property bool expanded: false
    default property alias content: body.data
    property real progress: expanded ? 1 : 0
    implicitHeight: body.implicitHeight * progress
    visible: progress > 0
    enabled: expanded
    clip: true
    opacity: progress
    Behavior on progress {
        NumberAnimation {
            duration: Appearance.scaledDuration(root.expanded ? 300 : 220)
            easing.type: Easing.InOutCubic
        }
    }
    ColumnLayout {
        id: body
        width: parent.width
        y: -6 * (1 - root.progress)
        spacing: 8
    }
}
