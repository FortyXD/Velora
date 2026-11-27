pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: clockColumn
    spacing: 4

    property var options: Config.options.background.widgets.clock
    property bool isVertical: clockColumn.options.digital.vertical
    property color colText: Appearance.colors.colOnSecondaryContainer
    property var textHorizontalAlignment: Text.AlignHCenter

    // Time
    ClockText {
        id: timeTextTop
        text: clockColumn.isVertical ? DateTime.time.split(":")[0].padStart(2, "0") : DateTime.time
        color: clockColumn.colText
        horizontalAlignment: Text.AlignHCenter
        font {
            pixelSize: clockColumn.options.digital.font.size
            weight: clockColumn.options.digital.font.weight
            family: clockColumn.options.digital.font.family
            variableAxes: ({
                    "wdth": clockColumn.options.digital.font.width,
                    "ROND": clockColumn.options.digital.font.roundness
                })
        }
    }

    Loader {
        Layout.topMargin: -40
        Layout.fillWidth: true
        active: clockColumn.isVertical
        visible: active
        sourceComponent: ClockText {
            id: timeTextBottom
            text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
            color: clockColumn.colText
            horizontalAlignment: clockColumn.textHorizontalAlignment
            font {
                pixelSize: timeTextTop.font.pixelSize
                weight: timeTextTop.font.weight
                family: timeTextTop.font.family
                variableAxes: timeTextTop.font.variableAxes
            }
        }
    }

    // Date
    ClockText {
        visible: clockColumn.options.digital.showDate
        Layout.topMargin: -20
        Layout.fillWidth: true
        text: DateTime.longDate
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }

    // Quote
    ClockText {
        visible: clockColumn.options.quote.enable && clockColumn.options.quote.text.length > 0
        font.pixelSize: Appearance.font.pixelSize.normal
        text: clockColumn.options.quote.text
        animateChange: false
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }
}
