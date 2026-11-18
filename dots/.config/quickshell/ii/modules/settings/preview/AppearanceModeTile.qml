import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions

SchemeTile {
    id: root
    required property bool dark
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color paper: ColorUtils.mix(accent, dark ? "#161616" : "#fffdfa", dark ? 0.07 : 0.09)
    readonly property color sampleInk: ColorUtils.mix(accent, dark ? "#fffdfa" : "#191919", 0.22)

    label: dark ? Translation.tr("Dark") : Translation.tr("Light")
    selected: dark === Appearance.m3colors.darkmode
    Accessible.name: label
    Accessible.checkable: true
    Accessible.checked: selected
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: 1
    implicitWidth: 120
    frameWidth: Math.max(50, Math.min(148, width - 18))
    frameHeight: Math.round(frameWidth * 0.53)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 6
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: ColorUtils.mix(root.accent, root.paper, root.dark ? 0.41 : 0.68) }
            GradientStop { position: 1; color: root.paper }
        }
        Rectangle {
            x: parent.width * 0.10
            y: parent.height * 0.17
            width: parent.width * 0.55
            height: parent.height * 0.56
            radius: 5
            color: ColorUtils.mix(root.sampleInk, root.paper, root.dark ? 0.23 : 0.18)
        }
        Rectangle {
            x: parent.width * 0.36
            y: parent.height * 0.32
            width: parent.width * 0.54
            height: parent.height * 0.55
            radius: 5
            color: root.paper
            border.width: 1
            border.color: ColorUtils.mix(root.sampleInk, root.paper, 0.20)
            Column {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle { width: parent.parent.width * 0.38; height: 4; radius: 2; color: root.sampleInk }
                Rectangle { width: parent.parent.width * 0.58; height: 3; radius: 2; color: ColorUtils.mix(root.sampleInk, root.paper, 0.30) }
            }
        }
    }
}
