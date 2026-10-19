import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * Loads one bar widget and gives it the same frame everywhere: hidden on narrow screens per
 * `hideAt`, laid out from the catalog (elastic → fills, fillHeight), context for the widget.
 */
Loader {
    id: root

    required property var itemData
    required property QtObject factory
    property bool vertical: false
    property int tier: 0
    property bool zoneHovered: false

    readonly property string type: itemData?.type ?? ""
    readonly property var meta: BarWidgetCatalog.get(type)
    readonly property var options: itemData?.options ?? ({})
    readonly property bool tierVisible: !((itemData?.hideAt ?? 0) > 0 && tier >= itemData.hideAt)
    readonly property bool elastic: meta?.elastic ?? false
    readonly property bool fills: itemData?.fill ?? item?.barFill ?? elastic
    readonly property bool shown: status === Loader.Ready && (item?.barVisible ?? true)
    // Width that doesn't follow the free space, for balancing the center
    readonly property real rigidWidth: shown && !elastic ? implicitWidth : 0

    active: meta !== null && tierVisible && factory.gate(type)
    sourceComponent: factory.component(type)
    visible: shown

    Layout.fillWidth: !vertical && fills
    Layout.fillHeight: vertical ? fills : (meta?.fillHeight ?? false)

    onLoaded: item.host = root
}
