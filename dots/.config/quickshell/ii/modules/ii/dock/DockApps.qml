import qs.services
import QtQuick
import Quickshell

/**
 * Pinned and running apps. Tiles widen and shrink as apps come and go, and
 * neighbours follow them, so no add or remove transitions are needed.
 */
Item {
    id: root
    required property DockContext dock

    implicitWidth: listView.contentWidth
    implicitHeight: dock.barHeight

    ListView {
        id: listView
        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false
        currentIndex: -1
        spacing: 0
        cacheBuffer: 4000

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }

        move: Transition {
            NumberAnimation {
                property: "x"
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
        moveDisplaced: Transition {
            NumberAnimation {
                property: "x"
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        delegate: DockAppButton {
            dock: root.dock
            baseCenter: root.x + x - listView.contentX + width / 2
        }
    }
}
