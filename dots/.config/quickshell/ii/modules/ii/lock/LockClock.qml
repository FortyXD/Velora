import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.clock

/**
 * The lock screen clock: the cookie or the digital one (background.widgets.clock.styleLocked),
 * with "Locked" under it.
 */
Item {
    id: root
    readonly property string clockStyle: Config.options.background.widgets.clock.styleLocked
    property color colText: Appearance.colors.colOnLayer0

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 10

        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.clockStyle === "cookie"
            visible: active
            sourceComponent: CookieClock {}
        }
        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.clockStyle !== "cookie"
            visible: active
            sourceComponent: DigitalClock {
                colText: root.colText
            }
        }

        Rectangle {
            id: lockedChip
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Config.options.lock.showLockedText
            implicitWidth: lockedRow.implicitWidth + 10 * 2
            implicitHeight: lockedRow.implicitHeight + 5 * 2
            radius: Appearance.rounding.small
            color: root.clockStyle === "cookie" ? Appearance.colors.colSecondaryContainer : "transparent"
            Row {
                id: lockedRow
                anchors.centerIn: parent
                spacing: 4
                readonly property color textColor: root.clockStyle === "cookie" ? Appearance.colors.colOnSecondaryContainer : root.colText
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "lock"
                    iconSize: Appearance.font.pixelSize.huge
                    color: lockedRow.textColor
                    style: Text.Raised
                    styleColor: Appearance.colors.colShadow
                }
                ClockText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Locked")
                    color: lockedRow.textColor
                    font {
                        pixelSize: Appearance.font.pixelSize.large
                        weight: Font.Normal
                    }
                    style: Text.Raised
                    styleColor: Appearance.colors.colShadow
                }
            }
        }
    }
}
