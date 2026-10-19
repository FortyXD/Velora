import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The bar's content built from a layout object: background, then the start and end zones at the
 * screen edges and the three center zones in a centered row. With `balanceCenter`, the zones on
 * both sides of the center get the same width, so the center stays in the middle of the screen.
 */
Item {
    id: root

    property bool vertical: false
    property var layoutData: vertical ? BarLayout.vertical : BarLayout.horizontal

    property var screen: root.QsWindow.window?.screen
    readonly property int tier: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2
        : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (tier == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened
        : (tier == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth
    readonly property bool balanceCenter: layoutData?.balanceCenter ?? false
    // Both sides of the center grow together when either needs more room
    readonly property real centerSideWidth: Math.max(centerSideModuleWidth, centerStartZone.rigidWidth + 12, centerEndZone.rigidWidth + 12)

    readonly property var zones: layoutData?.zones ?? ({})
    readonly property var actions: layoutData?.actions ?? ({})

    BarWidgetFactory {
        id: factory
    }

    component CenterSeparator: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 1
        implicitHeight: Appearance.sizes.baseBarHeight / 3
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    BarZone {
        id: startZone
        zoneName: "start"
        items: root.zones.start ?? []
        actions: root.actions.start ?? ({})
        factory: factory
        tier: root.tier
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleRow.left
        }
        outerSide: "left"
        outerPadding: Appearance.rounding.screenRounding
        innerPadding: Appearance.rounding.screenRounding
        spacing: 10
    }

    Row {
        id: middleRow
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4

        BarZone {
            id: centerStartZone
            zoneName: "centerStart"
            items: root.zones.centerStart ?? []
            actions: root.actions.centerStart ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            fixedLength: root.balanceCenter ? root.centerSideWidth : -1
            visible: hasContent || root.balanceCenter
            align: "end"
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerStartZone.hasContent && centerZone.hasContent
        }

        BarZone {
            id: centerZone
            zoneName: "center"
            items: root.zones.center ?? []
            actions: root.actions.center ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            visible: hasContent
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerZone.hasContent && centerEndZone.hasContent
        }

        BarZone {
            id: centerEndZone
            zoneName: "centerEnd"
            items: root.zones.centerEnd ?? []
            actions: root.actions.centerEnd ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            fixedLength: root.balanceCenter ? root.centerSideWidth : -1
            visible: hasContent || root.balanceCenter
        }
    }

    BarZone {
        id: endZone
        zoneName: "end"
        items: root.zones.end ?? []
        actions: root.actions.end ?? ({})
        factory: factory
        tier: root.tier
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleRow.right
            right: parent.right
        }
        outerSide: "right"
        outerPadding: Appearance.rounding.screenRounding
        innerPadding: 4
        spacing: 5
        align: "end"
    }
}
