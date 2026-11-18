import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 4
    // Show the configured discharge ranges even on a desktop with no battery.
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 12
        spacing: 10
        StyledText { text: "0%"; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
        Rectangle {
            id: track
            Layout.fillWidth: true
            implicitHeight: 12
            radius: 6
            color: ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colLayer2, 0.32)
            Rectangle {
                width: track.width * Math.max(Config.options.battery.critical, Config.options.battery.low) / 100
                height: parent.height
                radius: 6
                color: ColorUtils.mix("#e5ad53", Appearance.colors.colPrimary, 0.7)
            }
            Rectangle {
                width: track.width * Config.options.battery.critical / 100
                height: parent.height
                radius: 6
                color: ColorUtils.mix("#e87577", Appearance.colors.colError, 0.7)
            }
            Rectangle {
                visible: Config.options.battery.automaticSuspend
                x: Math.min(track.width - width, track.width * Config.options.battery.suspend / 100)
                anchors.verticalCenter: parent.verticalCenter
                width: 2; height: 18; radius: 1
                color: Appearance.colors.colOnLayer2
            }
        }
        StyledText { text: "100%"; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 490 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 8
        ConfigSpinBox {
            icon: "warning"
            text: Translation.tr("Low warning (%)")
            value: Config.options.battery.low
            from: 0; to: 100; stepSize: 5
            onValueChanged: Config.options.battery.low = value
        }
        ConfigSpinBox {
            icon: "dangerous"
            text: Translation.tr("Critical warning (%)")
            value: Config.options.battery.critical
            from: 0; to: 100; stepSize: 5
            onValueChanged: Config.options.battery.critical = value
        }
    }
}
