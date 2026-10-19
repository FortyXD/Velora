import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A run of bar widgets: either one bare widget or several sharing a pill background.
 */
Item {
    id: root

    required property var segment // { pill, items }
    required property QtObject factory
    property bool vertical: false
    property int tier: 0
    property bool zoneHovered: false

    readonly property bool pill: segment?.pill ?? false
    readonly property var items: segment?.items ?? []
    property real padding: !pill ? 0 : items.length === 1 ? (BarWidgetCatalog.get(items[0].type)?.pillPadding ?? 5) : 5

    readonly property list<var> hosts: {
        let result = [];
        for (let i = 0; i < repeater.count; i++) {
            const host = repeater.itemAt(i);
            if (host) result.push(host);
        }
        return result;
    }
    readonly property int shownCount: hosts.filter(host => host.shown).length
    readonly property bool fills: hosts.some(host => host.shown && host.fills)
    readonly property real rigidWidth: shownCount === 0 ? 0
        : hosts.reduce((sum, host) => sum + host.rigidWidth, 0) + gridLayout.columnSpacing * (shownCount - 1) + padding * 2

    visible: shownCount > 0
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    Rectangle {
        id: background
        visible: root.pill
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: Config.options?.bar.borderless ? "transparent" : Appearance.colors.colLayer1
        radius: Appearance.rounding.small
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        // A pill centers its row like BarGroup; a bare widget is centered by the layout itself,
        // which rounds the same way the zone layouts always have
        anchors {
            verticalCenter: root.vertical || !root.pill ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical && root.pill ? parent.horizontalCenter : undefined
            left: root.vertical && root.pill ? undefined : parent.left
            right: root.vertical && root.pill ? undefined : parent.right
            top: root.vertical || !root.pill ? parent.top : undefined
            bottom: root.vertical || !root.pill ? parent.bottom : undefined
            margins: root.padding
        }
        columnSpacing: 4
        rowSpacing: 12

        Repeater {
            id: repeater
            model: root.items
            delegate: BarItemHost {
                required property var modelData
                itemData: modelData
                factory: root.factory
                vertical: root.vertical
                tier: root.tier
                zoneHovered: root.zoneHovered
            }
        }
    }
}
