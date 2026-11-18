import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    readonly property bool settingsSearchable: true
    readonly property string title: Translation.tr("Status")
    readonly property string searchText: [title, Translation.tr("Charge"), Translation.tr("Battery power")].join(" ")
    readonly property real charge: Math.max(0, Math.min(1, Battery.percentage))
    readonly property color accent: Battery.available && Battery.isLow ? Appearance.colors.colError
        : ColorUtils.mix("#52bd98", Appearance.colors.colPrimary, 0.76)
    readonly property color ink: Appearance.colors.colOnLayer2

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 36
    radius: Appearance.rounding.normal
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2, 0.23) }
        GradientStop { position: 1; color: Appearance.colors.colLayer2 }
    }
    border.width: 1
    border.color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2, 0.32)

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 20 }
        spacing: 18
        Item {
            id: gauge
            implicitWidth: 104
            implicitHeight: 104

            Shape {
                anchors.fill: parent
                visible: Battery.available
                ShapePath {
                    strokeWidth: 8
                    strokeColor: ColorUtils.mix(root.accent, Appearance.colors.colLayer2, 0.25)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 52; centerY: 52; radiusX: 46; radiusY: 46; startAngle: 130; sweepAngle: 280 }
                }
                ShapePath {
                    strokeWidth: 8
                    strokeColor: root.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 52; centerY: 52; radiusX: 46; radiusY: 46; startAngle: 130; sweepAngle: 280 * root.charge }
                }
            }
            StyledText {
                visible: Battery.available
                anchors.centerIn: parent
                text: Math.round(root.charge * 100) + "%"
                color: root.ink
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }
            Rectangle {
                visible: !Battery.available
                anchors.centerIn: parent
                width: 80; height: 80; radius: 24
                color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2, 0.16)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "laptop_chromebook"
                    iconSize: 50
                    color: root.ink
                }
            }
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                width: 27; height: 25; radius: 10
                color: root.accent
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: PowerSaving.onBattery && Battery.available ? "battery_android_full" : "power"
                    iconSize: 18
                    color: "#152820"
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Battery.isCharging ? Translation.tr("Charging battery") : Battery.available && PowerSaving.onBattery
                    ? Translation.tr("On battery") : Translation.tr("External power")
                color: root.ink
                font.family: Appearance.font.family.title
                font.pixelSize: 25
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    if (!Battery.available) return Translation.tr("No battery");
                    const watts = Battery.energyRateAvailable && Number.isFinite(Battery.energyRate)
                        ? Battery.energyRate.toFixed(2) + " W" : "—";
                    const seconds = Battery.isCharging ? Battery.timeToFull : PowerSaving.onBattery ? Battery.timeToEmpty : 0;
                    if (!(seconds > 0)) return Translation.tr("Battery power") + "  " + watts;
                    const duration = Translation.tr("%1 h %2 min").arg(Math.floor(seconds / 3600)).arg(Math.floor(seconds / 60) % 60);
                    return watts + "   ·   " + (Battery.isCharging ? Translation.tr("Full in %1") : Translation.tr("%1 left")).arg(duration);
                }
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: PowerSaving.active ? Translation.tr("Energy saving is on") : Translation.tr("Energy saving is off")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        DialogButton {
            buttonText: PowerSaving.active ? Translation.tr("Turn off") : Translation.tr("Turn on")
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            onClicked: PowerSaving.toggle()
        }
    }
}
