import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Loads one bar widget and gives it the same frame everywhere: hidden on narrow screens per
 * `hideAt`, laid out from the catalog (elastic → fills, fillHeight), context for the widget.
 * While the bar is edited, widgets that show nothing get a placeholder so they can be grabbed.
 */
Item {
    id: root

    required property var itemData
    required property QtObject factory
    property bool vertical: false
    property int tier: 0
    property bool zoneHovered: false
    property bool inPill: false
    property bool editing: false
    property bool dragHidden: false // The edit overlay is dragging this one

    readonly property string uid: itemData?.uid ?? ""
    readonly property string type: itemData?.type ?? ""
    readonly property var meta: BarWidgetCatalog.get(type)
    readonly property var options: itemData?.options ?? ({})
    readonly property var item: loader.item
    readonly property bool tierVisible: !((itemData?.hideAt ?? 0) > 0 && tier >= itemData.hideAt)
    readonly property bool elastic: meta?.elastic ?? false
    readonly property bool fills: itemData?.fill ?? item?.barFill ?? elastic
    readonly property bool shown: loader.status === Loader.Ready && (item?.barVisible ?? true)
    // Takes part in the layout: shown, or kept grabbable while editing
    readonly property bool present: shown || editing
    readonly property bool placeholder: editing && (!shown || (vertical ? loader.implicitHeight : loader.implicitWidth) < 4)
    // Width that doesn't follow the free space, for balancing the center
    readonly property real rigidLength: present && !elastic ? (vertical ? implicitHeight : implicitWidth) : 0

    visible: present
    opacity: dragHidden ? 0.35 : 1
    implicitWidth: placeholder && !vertical ? Math.max(28, shown ? loader.implicitWidth : 0) : loader.implicitWidth
    implicitHeight: placeholder && vertical ? Math.max(28, shown ? loader.implicitHeight : 0) : loader.implicitHeight

    Layout.fillWidth: !vertical && fills
    Layout.fillHeight: vertical ? fills : (meta?.fillHeight ?? false)
    Layout.alignment: vertical ? Qt.AlignHCenter : 0

    Loader {
        id: loader
        anchors.fill: parent
        visible: root.shown
        active: root.meta !== null && root.tierVisible && root.factory.gate(root.type)
        sourceComponent: root.factory.component(root.type, root.vertical)
        onLoaded: item.host = root
    }

    Rectangle { // Frame shown while editing: hovered and selected widgets stand out
        readonly property bool selected: GlobalStates.barEditSelection === root.uid
        readonly property bool hovered: GlobalStates.barEditHovered === root.uid
        visible: root.editing && !root.dragHidden
        z: 1
        anchors {
            fill: parent
            margins: -2
        }
        radius: Appearance.rounding.small
        color: selected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
            : hovered ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9) : "transparent"
        border.width: selected ? 2 : 1
        border.color: selected ? Appearance.colors.colPrimary
            : hovered ? Appearance.colors.colOutline : ColorUtils.transparentize(Appearance.colors.colOutline, 0.5)
    }

    Loader { // Stand-in for widgets that show nothing right now
        active: root.placeholder
        anchors.centerIn: parent
        sourceComponent: Rectangle {
            implicitWidth: 24
            implicitHeight: 24
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.meta?.icon ?? "help"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }
        }
    }
}
