import QtQuick
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Desktop widget drawn on a card. The look follows background.widgets.cardStyle:
 * "tonal" (accent container), "surface" (neutral) or "transparent" (text straight on the wallpaper).
 * Put a single layout with `anchors.fill: parent` inside; the card sizes itself to it.
 */
AbstractBackgroundWidget {
    id: root

    default property alias cardData: contentArea.data
    property real padding: 18

    readonly property string cardStyle: root.widgetSettings.cardStyle
    readonly property bool tonal: root.cardStyle === "tonal"
    readonly property bool surface: root.cardStyle === "surface"
    readonly property bool transparentCard: !root.tonal && !root.surface
    needsColText: root.transparentCard

    // Colors for the content, matching the card style
    readonly property color colOnCard: root.tonal ? root.widgetColors.colOnPrimaryContainer
        : root.surface ? root.widgetColors.colOnSurface : root.colText
    readonly property color colOnCardVariant: root.tonal ? ColorUtils.transparentize(root.widgetColors.colOnPrimaryContainer, 0.3)
        : root.surface ? root.widgetColors.colOnSurfaceVariant : ColorUtils.transparentize(root.colText, 0.3)
    readonly property color colAccent: root.transparentCard ? root.colText : root.widgetColors.colPrimary
    readonly property color colOnAccent: root.transparentCard ? (root.dominantColorIsDark ? "black" : "white") : root.widgetColors.colOnPrimary
    readonly property color colLayer: root.tonal ? ColorUtils.mix(root.widgetColors.colPrimaryContainer, root.widgetColors.colOnPrimaryContainer, 0.85)
        : root.surface ? root.widgetColors.colLayer4Base : ColorUtils.transparentize(root.colText, 0.82)

    implicitWidth: cardBackground.implicitWidth
    implicitHeight: cardBackground.implicitHeight

    // Rises a little when it appears
    transform: Translate {
        id: entranceTranslate
        y: 14
    }
    Component.onCompleted: entranceAnim.start()
    NumberAnimation {
        id: entranceAnim
        target: entranceTranslate
        property: "y"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    StyledDropShadow {
        target: cardBackground
        visible: !root.transparentCard
    }

    Rectangle {
        id: cardBackground
        anchors.fill: parent
        implicitWidth: (contentArea.children[0]?.implicitWidth ?? 0) + root.padding * 2
        implicitHeight: (contentArea.children[0]?.implicitHeight ?? 0) + root.padding * 2
        radius: Appearance.rounding.verylarge
        color: root.tonal ? root.widgetColors.colPrimaryContainer
            : root.surface ? ColorUtils.transparentize(root.widgetColors.colLayer2Base, 0.08) : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Item {
            id: contentArea
            anchors {
                fill: parent
                margins: root.padding
            }
        }
    }
}
