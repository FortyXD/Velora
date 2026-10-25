import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The parts of one sidebar, top to bottom (SidebarLayout). Parts that fill share the free height;
 * a tabs part with a share of its own keeps it while another part takes the rest.
 */
ColumnLayout {
    id: root
    required property string side
    property bool open: false
    property bool editMode: false // Quick toggles being arranged (the edit button of the top row)
    signal dialogRequested(string name)

    readonly property var parts: SidebarLayout.shownParts(root.side)
    readonly property bool hasToggles: root.parts.some(part => part.type === "toggles")

    function fills(part) {
        return SidebarCatalog.part(part.type)?.fill ?? false;
    }
    function shareOf(part) {
        return part.type === "tabs" ? (part.options?.share ?? 0) : 0;
    }
    // Something takes the rest of the height, so parts with a share keep to it
    readonly property bool hasRest: root.parts.some(part => root.fills(part) && root.shareOf(part) <= 0)

    readonly property var hosts: {
        let list = [];
        for (let i = 0; i < repeater.count; i++) {
            const host = repeater.itemAt(i);
            if (host) list.push(host);
        }
        return list;
    }
    readonly property var mainTabs: root.hosts.find(host => host.type === "tabs" && host.item)?.item ?? null

    function cycleTabs(step) {
        root.mainTabs?.cycle(step);
    }
    function focusMain() {
        if (root.mainTabs) root.mainTabs.focusCurrent();
    }
    function snap() {
        root.mainTabs?.snap();
    }

    spacing: 10

    Repeater {
        id: repeater
        model: root.parts
        delegate: SidebarPartHost {
            id: host
            required property var modelData
            part: modelData
            column: root
            visible: host.partVisible
            readonly property real share: root.shareOf(modelData)
            readonly property bool fillsNow: root.fills(modelData) && !host.collapsed
            readonly property real minHeight: SidebarCatalog.part(modelData.type)?.minHeight ?? 0
            readonly property bool takesRest: host.fillsNow && (host.share <= 0 || !root.hasRest)
            Layout.fillWidth: true
            Layout.fillHeight: host.takesRest
            Layout.minimumHeight: host.fillsNow ? host.minHeight : -1
            Layout.preferredHeight: !host.fillsNow ? (host.item?.implicitHeight ?? 0)
                : (host.share > 0 && root.hasRest) ? Math.max(host.minHeight, Math.round(root.height * host.share))
                : host.minHeight
            Layout.verticalStretchFactor: host.takesRest ? 1 : -1
        }
    }

    // Keeps the parts at the top when none of them takes the free height
    Item {
        visible: !root.parts.some(part => root.fills(part))
        Layout.fillHeight: true
    }

    StyledText {
        visible: root.parts.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        text: Translation.tr("Nothing here yet. Add parts on the Sidebars page of the settings.")
        color: Appearance.colors.colSubtext
    }
}
