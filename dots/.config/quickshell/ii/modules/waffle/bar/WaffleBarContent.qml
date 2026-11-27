import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar.tasks
import qs.modules.waffle.bar.tray

Rectangle {
    id: root

    color: Looks.colors.bg0
    implicitHeight: 48
    
    Rectangle {
        id: border
        anchors {
            left: parent.left
            right: parent.right
            top: Config.options.waffles.bar.bottom ? parent.top : undefined
            bottom: Config.options.waffles.bar.bottom ? undefined : parent.bottom
        }
        color: Looks.colors.bg0Border
        implicitHeight: 1
    }

    AiThinkingIndicator {
        id: activityStar
        active: !GlobalStates.screenLocked && (Ai.nativeGenerating || Assistant.thinking)
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
    }

    BarGroupRow {
        id: bloatRow
        anchors.left: parent.left
        anchors.leftMargin: activityStar.active ? activityStar.implicitWidth + 8 : 0
        opacity: Config.options.waffles.bar.leftAlignApps ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: Looks.transition.opacity.createObject(this)
        }

        WidgetsButton {}
    }

    BarGroupRow {
        id: appsRow
        anchors.leftMargin: activityStar.active && Config.options.waffles.bar.leftAlignApps ? activityStar.implicitWidth + 8 : 0
        anchors.left: undefined
        anchors.horizontalCenter: parent.horizontalCenter

        states: State {
            name: "left"
            when: Config.options.waffles.bar.leftAlignApps
            AnchorChanges {
                target: appsRow
                anchors.left: parent.left
                anchors.horizontalCenter: undefined
            }
        }

        transitions: Transition {
            animations: Looks.transition.anchor.createObject(this)
        }

        StartButton {}
        SearchButton {}
        TaskViewButton {}
        Tasks {}
    }

    BarGroupRow {
        id: systemRow
        anchors.right: parent.right
        FadeLoader {
            Layout.fillHeight: true
            shown: Config.options.waffles.bar.leftAlignApps
            sourceComponent: WidgetsButton {}
        }
        Tray {}
        UpdatesButton {}
        SystemButton {}
        TimeButton {}
    }

    component BarGroupRow: RowLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0
    }
}
