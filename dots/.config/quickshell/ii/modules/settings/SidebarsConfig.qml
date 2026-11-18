pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.sidebars
import qs.modules.settings.barLayout

/**
 * Both sidebars, made of parts you arrange freely: any part can go in either sidebar, alone or as a tab.
 * The part catalog sits between the two previews. Switching sides slides all three together.
 */
ContentPage {
    id: page
    readonly property bool canNavigateBack: page.selected !== null || page.dragType.length > 0
    function navigateBack() {
        if (page.dragType) page.cancelCatalogDrag();
        else page.select("");
    }
    navigationTrail: {
        const trail = [{key: page.side, title: page.side === "left" ? Translation.tr("Left sidebar") : Translation.tr("Right sidebar")}];
        if (page.selected) trail.push({key: page.selectedUid, title: SidebarCatalog.part(page.selected.part.type)?.name ?? Translation.tr("Part")});
        return trail;
    }
    function navigateToSection(key) {
        if (!key || key === "left" || key === "right") { if (key) page.side = key; page.select(""); }
    }
    fitToWindow: true
    maxContentWidth: 1100
    readonly property alias popupPane: popupArea
    SettingsPopupArea {
        id: popupArea
        parent: page.Window.window?.settingsPageViewport ?? page
        column: pane
    }

    property string side: "right"
    property string selectedUid: ""
    readonly property var selected: page.selectedUid.length > 0 ? SidebarLayout.find(page.selectedUid) : null
    onSideChanged: {
        page.cancelCatalogDrag();
        if (page.selected && page.selected.side !== page.side) page.select("");
        settingsPopup.close();
    }
    onPageShownChanged: if (!pageShown) { page.cancelCatalogDrag(); partPopup.close(); settingsPopup.close(); }
    onSelectedChanged: if (!selected) partPopup.close()

    function select(uid) {
        const found = uid.length > 0 ? SidebarLayout.find(uid) : null;
        if (found) page.side = found.side;
        page.selectedUid = found ? uid : "";
        if (found) {
            settingsPopup.close();
            partPopup.open();
        }
        else partPopup.close();
    }

    // Where a new part goes: into the picked tabs (or the tabs of a picked page) when it can be a tab
    readonly property var targetTabs: {
        if (!page.selected) return null;
        if (page.selected.part.type === "tabs") return page.selected.part;
        return page.selected.group;
    }

    property string dragType: ""
    property point dragPosition
    readonly property var dropTarget: {
        if (!dragType || !workspace.contains(workspace.mapFromItem(null, dragPosition.x, dragPosition.y))) return null;
        const preview = previews.itemAt(page.side === "left" ? 0 : 1)?.item;
        return preview?.catalogTargetAt(dragPosition.x, dragPosition.y, dragType) ?? null;
    }
    function moveCatalogDrag(sceneX, sceneY) {
        if (!dragType) return;
        dragPosition = Qt.point(sceneX, sceneY);
        const p = ghost.parent.mapFromItem(null, sceneX, sceneY);
        ghost.x = p.x - ghost.offset.x;
        ghost.y = p.y - ghost.offset.y;
    }
    function cancelCatalogDrag() {
        dragType = "";
    }
    function finishCatalogDrag(sceneX, sceneY) {
        if (!dragType) return;
        const type = dragType;
        const canceled = sceneX === -1 && sceneY === -1;
        if (!canceled) moveCatalogDrag(sceneX, sceneY);
        const target = dropTarget;
        cancelCatalogDrag();
        if (canceled || !target) return;
        const found = SidebarLayout.catalogPart(page.side, type);
        const limit = SidebarCatalog.part(type).limit;
        if (!found || limit === "none" || (limit === "sidebar" && found.side !== page.side)) {
            SidebarLayout.insert(page.side, type, target.index, target.groupUid);
        } else {
            const sameList = found.side === page.side && (found.group?.uid ?? "") === target.groupUid;
            // The guide names a gap in the current list. move() takes an index after detaching the part.
            const index = sameList && found.index < target.index ? target.index - 1 : target.index;
            if (!sameList || found.index !== index) SidebarLayout.move(found.part.uid, page.side, index, target.groupUid);
        }
    }

    WidgetChip {
        id: ghost
        property point offset
        parent: page.Overlay.overlay ?? page.Window.window?.contentItem ?? page
        visible: page.dragType.length > 0
        enabled: false
        z: 1000
        pill: true; selected: true
    }
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: page.pageShown && SidebarLayout.canUndo
        onActivated: SidebarLayout.undo()
    }
    Shortcut {
        sequence: "Escape"
        enabled: page.pageShown && page.canNavigateBack && !page.Window.window?.settingsPageViewport
        onActivated: page.navigateBack()
    }

    SettingsPopup {
        id: partPopup
        objectName: "sidebarPartPopup"
        pane: page.popupPane
        property var displayed: null
        title: displayed ? SidebarCatalog.part(displayed.part.type)?.name ?? "" : ""
        onAboutToShow: displayed = page.selected
        onClosed: { page.selectedUid = ""; displayed = null; }
        Connections {
            target: page
            function onSelectedChanged() { if (page.selected) partPopup.displayed = page.selected; }
        }
        Loader {
            Layout.fillWidth: true
            active: partPopup.displayed !== null
            sourceComponent: PartInspector {
                objectName: "sidebarPartInspector"
                showHeader: false
                popupPane: page.popupPane
                part: partPopup.displayed?.part ?? ({})
                side: partPopup.displayed?.side ?? page.side
                group: partPopup.displayed?.group ?? null
                selectedUid: part.uid ?? ""
                onSelectRequested: uid => page.select(uid)
            }
        }
    }

    SettingsPopup {
        id: settingsPopup
        objectName: "sidebarSettingsPopup"
        pane: page.popupPane
        title: Translation.tr("Sidebar settings")
        ContentSection {
            icon: page.side === "left" ? "left_panel_open" : "right_panel_open"
            title: page.side === "left" ? Translation.tr("Left sidebar") : Translation.tr("Right sidebar")
            description: page.side === "left"
                ? Translation.tr("Opens from the left: click the left side of the bar or press Super+A. Inside it, Ctrl+O makes it wider, Ctrl+P keeps it open next to windows, Ctrl+D turns it into a window.")
                : Translation.tr("Opens from the right: click the right side of the bar or press Super+N.")

            ConfigSlider {
                buttonIcon: "width"
                text: Translation.tr("Width")
                description: Translation.tr("The same for both sidebars; the left one can open wider")
                usePercentTooltip: false
                from: 340
                to: 640
                defaultValue: 460
                defaultValueText: "460 px"
                value: Config.options.sidebar.width
                valueText: `${Math.round(value)} px`
                onMoved: Config.options.sidebar.width = Math.round(value / 10) * 10
            }
            ConfigSwitch {
                visible: page.side === "left"
                buttonIcon: "width_wide"
                text: Translation.tr("Open it wide")
                description: Translation.tr("Ctrl+O switches the width while it's open")
                autoToggle: false
                checked: Config.options.sidebar.left.extendedByDefault
                onClicked: Config.options.sidebar.left.extendedByDefault = !Config.options.sidebar.left.extendedByDefault
            }
            ConfigSwitch {
                visible: page.side === "right"
                buttonIcon: "memory"
                text: Translation.tr("Open it instantly")
                description: Translation.tr("Keeps the right sidebar ready in memory (about 15 MB)")
                autoToggle: false
                checked: Config.options.sidebar.keepRightSidebarLoaded
                onClicked: Config.options.sidebar.keepRightSidebarLoaded = !Config.options.sidebar.keepRightSidebarLoaded
            }
            ConfigNavRow {
                buttonIcon: page.side === "left" ? "south_west" : "south_east"
                title: Translation.tr("Hot corners")
                description: Translation.tr("Open sidebars by pushing the pointer into a corner of the screen")
                onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Hot corners"))
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                spacing: 6
                DialogButton {
                    buttonText: Translation.tr("Undo")
                    enabled: SidebarLayout.canUndo
                    onClicked: SidebarLayout.undo()
                }
                DialogButton {
                    buttonText: Translation.tr("Default layout")
                    onClicked: {
                        page.selectedUid = "";
                        SidebarLayout.reset(page.side);
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    ConfigSelectionArray {
        objectName: "sidebarSidePicker"
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: false
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: 0
        currentValue: page.side
        onSelected: newValue => page.side = newValue
        options: [
            { displayName: Translation.tr("Left sidebar"), icon: "left_panel_open", value: "left" },
            { displayName: Translation.tr("Right sidebar"), icon: "right_panel_open", value: "right" }
        ]
    }

    Item {
        id: workspace
        objectName: "sidebarWorkspace"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        readonly property real previewWidth: Math.round(Math.min(width * 0.38, 300, 280 * Appearance.sizes.sidebarWidth / 460 + 20))
        readonly property real gap: width < 540 ? 12 : 20
        readonly property real travel: previewWidth + gap
        readonly property bool animateSwitch: page.pageShown && Appearance.animationSpeed > 0
        readonly property real destination: page.side === "right" ? 1 : 0
        property real rightFraction: 1
        function slideToSide() {
            sideMotion.stop();
            if (!animateSwitch) { rightFraction = destination; return; }
            sideMotion.to = destination;
            sideMotion.duration = Math.round(Appearance.animation.elementMove.duration * Math.abs(destination - rightFraction));
            sideMotion.start();
        }
        onDestinationChanged: slideToSide()
        onAnimateSwitchChanged: if (!animateSwitch) {
            sideMotion.stop();
            rightFraction = destination;
        }
        NumberAnimation {
            id: sideMotion
            target: workspace; property: "rightFraction"
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }

        Repeater {
            id: previews
            model: ["left", "right"]
            delegate: Loader {
                id: preview
                required property string modelData
                objectName: modelData + "SidebarPreview"
                x: modelData === "left" ? pane.x - workspace.travel : pane.x + pane.width + workspace.gap
                width: workspace.previewWidth
                height: workspace.height
                z: 1
                visible: x + width > 0 && x < workspace.width
                active: page.side === modelData || visible
                enabled: page.side === modelData
                sourceComponent: SidebarPartsMockup {
                    side: preview.modelData
                    selectedUid: page.selectedUid
                    catalogTarget: page.side === side ? page.dropTarget : null
                    onPartClicked: uid => page.select(page.selectedUid === uid ? "" : uid)
                    onPartRemoved: uid => {
                        const found = page.selected;
                        if (page.selectedUid === uid || found?.group?.uid === uid) page.select("");
                    }
                }
            }
        }

        SettingsScrollPane {
            id: pane
            objectName: "sidebarCatalogPane"
            x: Math.round(workspace.travel * (1 - workspace.rightFraction))
            width: Math.max(0, workspace.width - workspace.travel)
            height: workspace.height
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DialogButton {
                    objectName: "sidebarSettingsButton"
                    buttonText: Translation.tr("Sidebar settings")
                    readonly property bool settingsSearchable: true
                    readonly property string searchText: [buttonText, Translation.tr("Width"), Translation.tr("Open it instantly"),
                        Translation.tr("Open it wide"), Translation.tr("Hot corners"), Translation.tr("Default layout")].join(" ")
                    text: buttonText
                    function settingsReveal() { settingsPopup.open(); return false; }
                    onClicked: settingsPopup.open()
                }
            }

            // ---- Parts to add ----
            ContentSection {
                icon: "add_circle"
                title: page.targetTabs ? Translation.tr("Add to these tabs") : Translation.tr("Add a part")
                description: page.targetTabs ? Translation.tr("Parts that can be a tab go into the picked tabs; the others go after them")
                    : Translation.tr("Drag a part into the sidebar to place it, or click to set it up.")

                Repeater {
                    model: SidebarCatalog.categories
                    delegate: ContentSubsection {
                        id: categoryBlock
                        required property var modelData
                        title: modelData.name
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: SidebarCatalog.typesIn(categoryBlock.modelData.id)
                                delegate: WidgetChip {
                                    id: addChip
                                    required property string modelData
                                    objectName: "sidebarCatalog-" + modelData
                                    readonly property var meta: SidebarCatalog.part(modelData)
                                    readonly property var found: SidebarLayout.catalogPart(page.side, modelData)
                                    readonly property bool intoTabs: page.targetTabs !== null && !!meta.tabbable
                                    // Here already: a click picks it instead (unless it can be added again)
                                    readonly property bool here: addChip.found !== null && addChip.found.side === page.side && addChip.meta.limit !== "none"
                                        && !(addChip.intoTabs && addChip.found.group?.uid !== page.targetTabs.uid)
                                    readonly property bool elsewhere: addChip.found !== null && addChip.found.side !== page.side && addChip.meta.limit === "shell"
                                    readonly property bool settingsSearchable: true
                                    readonly property string searchText: `${meta.name} ${meta.description} ${(meta.options ?? []).map(o => o.label + " " + (o.description ?? "")).join(" ")}`
                                    label: meta.name
                                    icon: elsewhere ? "swap_horiz" : meta.icon
                                    present: here
                                    pill: here
                                    dimmed: page.dragType === modelData
                                    radius: height / 2
                                    implicitHeight: 34
                                    activeFocusOnTab: true
                                    border.width: activeFocus ? 2 : 0
                                    border.color: Appearance.colors.colPrimary
                                    Accessible.role: Accessible.Button
                                    Accessible.name: label
                                    Accessible.onPressAction: clicked()
                                    Keys.onSpacePressed: clicked()
                                    Keys.onReturnPressed: clicked()
                                    Keys.onEnterPressed: clicked()
                                    function settingsReveal() {
                                        if (addChip.found) page.select(addChip.found.part.uid);
                                        return false;
                                    }
                                    onClicked: {
                                        if (addChip.here) {
                                            page.select(addChip.found.part.uid);
                                            return;
                                        }
                                        const uid = addChip.intoTabs
                                            ? SidebarLayout.insert(page.side, modelData, -1, page.targetTabs.uid)
                                            : SidebarLayout.insert(page.side, modelData, -1);
                                        Qt.callLater(() => page.select(uid));
                                    }
                                    onDragStarted: (sceneX, sceneY, offsetX, offsetY) => {
                                        ghost.label = label;
                                        ghost.icon = meta.icon;
                                        ghost.offset = Qt.point(offsetX, offsetY);
                                        page.dragType = modelData;
                                        page.moveCatalogDrag(sceneX, sceneY);
                                    }
                                    onDragMoved: (sceneX, sceneY) => page.moveCatalogDrag(sceneX, sceneY)
                                    onDragEnded: (sceneX, sceneY) => page.finishCatalogDrag(sceneX, sceneY)
                                    StyledToolTip {
                                        text: addChip.here ? Translation.tr("Already here · click to set it up")
                                            : addChip.elsewhere ? Translation.tr("On the other sidebar · click to move it here")
                                            : addChip.meta.description
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
