import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A choice drawn as a little picture of the bar: its background (hug, float, rect, islands, none)
 * or how its widget groups look (filled, outlined, no pills).
 */
RippleButton {
    id: root
    property string variant // hug | float | rect | islands | none | filled | outlined | bare
    property string label
    property bool selected: false

    readonly property color screenColor: Appearance.colors.colLayer3
    readonly property color barColor: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    readonly property color pillColor: ColorUtils.transparentize(root.barColor, 0.55)

    implicitWidth: 112
    implicitHeight: 96
    buttonRadius: Appearance.rounding.normal
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover

    contentItem: ColumnLayout {
        spacing: 6
        Rectangle { // Top of a screen
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 92
            implicitHeight: 52
            radius: 8
            color: root.screenColor
            border.width: root.selected ? 2 : 0
            border.color: Appearance.colors.colPrimary
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: ["filled", "outlined", "bare"].includes(root.variant) ? groupsPicture : backgroundPicture
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        }
    }

    Component {
        id: backgroundPicture
        Item {
            // The bar
            Rectangle {
                visible: ["hug", "float", "rect"].includes(root.variant)
                x: root.variant === "float" ? 6 : 0
                y: root.variant === "float" ? 6 : 0
                width: parent.width - x * 2
                height: 12
                radius: root.variant === "float" ? 6 : 0
                color: ColorUtils.transparentize(root.barColor, 0.25)
            }
            // Hugging corners: the bar flows into the screen corners
            Repeater {
                model: root.variant === "hug" ? [0, 1] : []
                delegate: RoundCorner {
                    required property int modelData
                    x: modelData === 0 ? 0 : parent.width - width
                    y: 12
                    implicitSize: 7
                    color: ColorUtils.transparentize(root.barColor, 0.25)
                    corner: modelData === 0 ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight
                }
            }
            // Islands or bare widgets
            Row {
                visible: root.variant === "islands" || root.variant === "none"
                x: 6
                y: 6
                spacing: 4
                Repeater {
                    model: [16, 30, 14]
                    delegate: Rectangle {
                        required property int modelData
                        width: modelData
                        height: 12
                        radius: 6
                        color: root.variant === "islands" ? ColorUtils.transparentize(root.barColor, 0.25) : "transparent"
                        border.width: root.variant === "none" ? 1 : 0
                        border.color: root.pillColor
                    }
                }
            }
        }
    }

    Component {
        id: groupsPicture
        Item {
            Rectangle { // Bar
                width: parent.width
                height: 18
                color: ColorUtils.transparentize(root.barColor, 0.8)
            }
            Row {
                x: 6
                y: 4
                spacing: 5
                Repeater {
                    model: [18, 28, 14]
                    delegate: Rectangle {
                        required property int modelData
                        width: modelData
                        height: 10
                        radius: 5
                        color: root.variant === "filled" ? root.pillColor : "transparent"
                        border.width: root.variant === "outlined" ? 1 : 0
                        border.color: root.barColor
                        Row { // The widgets inside
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: Math.max(1, Math.floor(parent.parent.width / 10))
                                delegate: Rectangle {
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: root.barColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
