import QtQuick
import qs.services
import qs.modules.common

/**
 * The next few hours of Weather.hourly in a row: time, icon, temperature.
 */
Row {
    id: root
    property int count: 6
    property int step: 2 // Every other hour fits more of the day
    property color colText: Appearance.colors.colOnLayer1
    property color colSubtext: Appearance.colors.colSubtext
    property real iconSize: 22
    property real cellWidth: 44
    spacing: 0

    Repeater {
        model: Weather.hourly.filter((hour, index) => index % root.step === 0).slice(0, root.count)
        delegate: Column {
            id: hourColumn
            required property var modelData
            width: root.cellWidth
            spacing: 2
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hourColumn.modelData.time
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colSubtext
            }
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Icons.getWeatherIcon(hourColumn.modelData.code, hourColumn.modelData.night) ?? "cloud"
                iconSize: root.iconSize
                fill: 1
                color: root.colText
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hourColumn.modelData.temp
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.colText
            }
        }
    }
}
