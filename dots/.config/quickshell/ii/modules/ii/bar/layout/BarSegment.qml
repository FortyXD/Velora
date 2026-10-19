import qs.modules.common
import qs.modules.common.widgets
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
    property bool editing: false

    readonly property bool pill: segment?.pill ?? false
    readonly property var items: segment?.items ?? []
    readonly property var soleMeta: items.length === 1 ? BarWidgetCatalog.get(items[0].type) : null
    property real padding: !pill ? 0 : vertical ? (soleMeta?.verticalPillPadding ?? 8) : (soleMeta?.pillPadding ?? 5)

    readonly property list<var> hosts: {
        let result = [];
        for (let i = 0; i < repeater.count; i++) {
            const host = repeater.itemAt(i);
            if (host) result.push(host);
        }
        return result;
    }
    readonly property int shownCount: hosts.filter(host => host.present).length
    readonly property bool fills: hosts.some(host => host.present && host.fills)
    readonly property real rigidLength: shownCount === 0 ? 0
        : hosts.reduce((sum, host) => sum + host.rigidLength, 0) + (vertical ? gridLayout.rowSpacing : gridLayout.columnSpacing) * (shownCount - 1) + padding * 2

    visible: shownCount > 0
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    readonly property bool islands: Config.options.bar.style.islands
    // Effective look of pills; the older `borderless` switch means no pills
    readonly property string pillStyle: Config.options.bar.borderless ? "none" : Config.options.bar.style.pillStyle

    Loader { // Islands float over the wallpaper, so they get a shadow
        active: root.pill && root.islands && Config.options.bar.floatStyleShadow
        anchors.fill: background
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined
            target: background
        }
    }

    Rectangle {
        id: background
        visible: root.pill && (root.islands || root.pillStyle !== "none")
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: root.islands ? Appearance.colors.colBarBackground
            : root.pillStyle === "filled" ? Appearance.colors.colLayer1 : "transparent"
        radius: root.islands ? (Config.options.bar.style.radius >= 0 ? Config.options.bar.style.radius : Appearance.rounding.normal)
            : Appearance.rounding.small
        border.width: root.islands || root.pillStyle === "outlined" ? 1 : 0
        border.color: root.islands ? Appearance.colors.colLayer0Border : Appearance.colors.colOutlineVariant
    }

    // A vertical pill with several widgets separates them with thin lines
    readonly property bool verticalSeparators: vertical && pill && !islands && shownCount > 1

    Repeater {
        model: root.verticalSeparators ? root.hosts.filter(host => host.present).slice(1) : []
        delegate: Rectangle {
            required property var modelData
            z: 1
            x: (root.width - width) / 2
            y: gridLayout.y + modelData.y - gridLayout.rowSpacing / 2
            width: root.width - Appearance.sizes.baseBarHeight / 3 * 2
            height: 1
            color: Appearance.colors.colOutlineVariant
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        // A pill centers its row like BarGroup; a bare widget spans the bar's thickness and is
        // centered by the layout itself, which rounds the same way the zone layouts always have
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
        }
        height: root.vertical ? root.height - root.padding * 2 : (root.pill ? implicitHeight : root.height)
        width: root.vertical ? (root.pill ? implicitWidth : root.width) : root.width - root.padding * 2
        columnSpacing: 4
        rowSpacing: root.verticalSeparators ? 25 : 12

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
                inPill: root.pill
                editing: root.editing
            }
        }
    }
}
