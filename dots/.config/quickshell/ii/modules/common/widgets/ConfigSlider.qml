import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

/**
 * Settings row: icon tile, title with optional description, a slider and its current value.
 */
RowLayout {
    id: root
    spacing: 12
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 4
    Layout.bottomMargin: 4
    opacity: root.enabled ? 1 : 0.4

    property string text: ""
    property string buttonIcon: ""
    property string description: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: 0
    property real to: 1
    property real textWidth: 150
    property bool showValue: true
    property string valueText: root.usePercentTooltip
        ? `${Math.round(((slider.value - slider.from) / (slider.to - slider.from)) * 100)}%`
        : `${Math.round(slider.value)}`

    signal moved() // Only when the user drags, not when the value is set from outside

    readonly property bool settingsSearchable: true
    property string searchText: `${root.text} ${root.description}`

    ConfigIconTile {
        icon: root.buttonIcon ?? ""
    }

    ColumnLayout {
        Layout.fillWidth: false
        Layout.preferredWidth: Math.max(root.textWidth, (root.width - 80) * 0.42)
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        trackColor: Appearance.colors.colLayer3
        onMoved: root.moved()
        from: root.from
        to: root.to
    }

    StyledText {
        visible: root.showValue
        Layout.preferredWidth: 44
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        font.family: Appearance.font.family.numbers
        font.variableAxes: Appearance.font.variableAxes.numbers
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
}
