pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.sidebars

/**
 * Both sidebars, made of parts you arrange freely: any part can go in either sidebar, alone or as a tab.
 * The picture of the chosen sidebar stays in place on the left (drag parts, click one, hide one with the
 * eye); beside it are the picked part's settings, the sidebar's own settings, and parts to add.
 */
ContentPage {
    id: page
    fitToWindow: true
    maxContentWidth: 1100

    property string side: "right"
    property string selectedUid: ""
    readonly property var selected: page.selectedUid.length > 0 ? SidebarLayout.find(page.selectedUid) : null
    onSideChanged: if (page.selected && page.selected.side !== page.side) page.selectedUid = ""

    function select(uid) {
        const found = uid.length > 0 ? SidebarLayout.find(uid) : null;
        if (found) page.side = found.side;
        page.selectedUid = found ? uid : "";
        if (found) pane.scrollTo(0);
    }

    // Every part of both sidebars, pages of tabs too, for the inspectors
    readonly property var everyPart: {
        let list = [];
        for (const side of SidebarLayout.sides) {
            for (const part of SidebarLayout.parts(side)) {
                list.push({ "side": side, "part": part, "group": null });
                for (const tab of part.tabs ?? []) list.push({ "side": side, "part": tab, "group": part });
            }
        }
        return list;
    }

    // Where a new part goes: into the picked tabs (or the tabs of a picked page) when it can be a tab
    readonly property var targetTabs: {
        if (!page.selected) return null;
        if (page.selected.part.type === "tabs") return page.selected.part;
        return page.selected.group;
    }

    Shortcut {
        sequence: StandardKey.Undo
        enabled: page.pageShown && SidebarLayout.canUndo
        onActivated: SidebarLayout.undo()
    }
    Shortcut {
        sequence: "Escape"
        enabled: page.pageShown && page.selectedUid.length > 0
        onActivated: page.selectedUid = ""
    }

    GridLayout {
        id: layout
        readonly property bool wide: width >= 700
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: layout.wide ? 2 : 1
        columnSpacing: 20
        rowSpacing: 12

        // ---- The sidebar, pinned ----
        ColumnLayout {
            Layout.preferredWidth: layout.wide ? 300 : -1
            Layout.fillWidth: !layout.wide
            Layout.fillHeight: layout.wide
            Layout.preferredHeight: layout.wide ? -1 : Math.max(220, Math.min(340, page.height * 0.42))
            spacing: 10

            ConfigSelectionArray {
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

            SidebarPartsMockup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.preferredWidth: Math.round(Math.min(300, 280 * Appearance.sizes.sidebarWidth / 460 + 20))
                side: page.side
                selectedUid: page.selectedUid
                onPartClicked: uid => page.select(page.selectedUid === uid ? "" : uid)
                onPartRemoved: uid => {
                    const found = SidebarLayout.find(page.selectedUid);
                    if (page.selectedUid === uid || found?.group?.uid === uid) page.selectedUid = "";
                }
            }
        }

        // ---- Settings beside it ----
        SettingsScrollPane {
            id: pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18

            // The picked part (every part has one, laid out for search; only the picked one shows).
            // In a column without spacing, so the folded ones take no room at all.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: page.everyPart
                    delegate: PartInspector {
                        required property var modelData
                        part: modelData.part
                        side: modelData.side
                        group: modelData.group
                        selectedUid: page.selectedUid
                        onSelectRequested: uid => page.select(uid)
                    }
                }
            }

            // The sidebar itself, one block per side (the other one is folded, for search)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                model: ["right", "left"]
                delegate: ColumnLayout {
                    id: sideBlock
                    required property string modelData
                    readonly property bool current: page.side === sideBlock.modelData
                    function settingsReveal() {
                        if (sideBlock.current) return false;
                        page.side = sideBlock.modelData;
                        return true;
                    }
                    Layout.fillWidth: true
                    Layout.preferredHeight: sideBlock.current ? implicitHeight : 0
                    opacity: sideBlock.current ? 1 : 0
                    clip: true
                    spacing: 18

                    ContentSection {
                        icon: sideBlock.modelData === "left" ? "left_panel_open" : "right_panel_open"
                        title: sideBlock.modelData === "left" ? Translation.tr("Left sidebar") : Translation.tr("Right sidebar")
                        description: sideBlock.modelData === "left"
                            ? Translation.tr("Opens from the left: click the left side of the bar or press Super+A. Inside it, Ctrl+O makes it wider, Ctrl+P keeps it open next to windows, Ctrl+D turns it into a window.")
                            : Translation.tr("Opens from the right: click the right side of the bar or press Super+N.")

                        ConfigSlider {
                            buttonIcon: "width"
                            text: Translation.tr("Width")
                            description: Translation.tr("The same for both sidebars; the left one can open wider")
                            usePercentTooltip: false
                            from: 340
                            to: 640
                            value: Config.options.sidebar.width
                            valueText: `${Math.round(value)} px`
                            onMoved: Config.options.sidebar.width = Math.round(value / 10) * 10
                        }
                        ConfigSwitch {
                            visible: sideBlock.modelData === "left"
                            buttonIcon: "width_wide"
                            text: Translation.tr("Open it wide")
                            description: Translation.tr("Ctrl+O switches the width while it's open")
                            autoToggle: false
                            checked: Config.options.sidebar.left.extendedByDefault
                            onClicked: Config.options.sidebar.left.extendedByDefault = !Config.options.sidebar.left.extendedByDefault
                        }
                        ConfigSwitch {
                            visible: sideBlock.modelData === "right"
                            buttonIcon: "memory"
                            text: Translation.tr("Open it instantly")
                            description: Translation.tr("Keeps the right sidebar ready in memory (about 15 MB)")
                            autoToggle: false
                            checked: Config.options.sidebar.keepRightSidebarLoaded
                            onClicked: Config.options.sidebar.keepRightSidebarLoaded = !Config.options.sidebar.keepRightSidebarLoaded
                        }
                        ConfigNavRow {
                            buttonIcon: sideBlock.modelData === "left" ? "south_west" : "south_east"
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
                                    SidebarLayout.reset(sideBlock.modelData);
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            }

            // ---- Parts to add ----
            ContentSection {
                icon: "add_circle"
                title: page.targetTabs ? Translation.tr("Add to these tabs") : Translation.tr("Add a part")
                description: page.targetTabs ? Translation.tr("Parts that can be a tab go into the picked tabs; the others go after them")
                    : Translation.tr("A part that can be in only one place moves here from where it is")

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
                                delegate: RippleButton {
                                    id: addChip
                                    required property string modelData
                                    readonly property var meta: SidebarCatalog.part(modelData)
                                    readonly property var found: SidebarLayout.findType(modelData)
                                    readonly property bool intoTabs: page.targetTabs !== null && !!meta.tabbable
                                    // Here already: a click picks it instead (unless it can be added again)
                                    readonly property bool here: addChip.found !== null && addChip.found.side === page.side && addChip.meta.limit !== "none"
                                        && !(addChip.intoTabs && addChip.found.group?.uid !== page.targetTabs.uid)
                                    readonly property bool elsewhere: addChip.found !== null && addChip.found.side !== page.side && addChip.meta.limit === "shell"
                                    readonly property bool settingsSearchable: true
                                    readonly property string searchText: `${meta.name} ${meta.description}`
                                    text: meta.name
                                    implicitHeight: 34
                                    leftPadding: 10
                                    rightPadding: 14
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: addChip.here ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                    colBackgroundHover: addChip.here ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
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
                                    contentItem: RowLayout {
                                        spacing: 6
                                        MaterialSymbol {
                                            text: addChip.here ? "check" : addChip.elsewhere ? "swap_horiz" : addChip.meta.icon
                                            iconSize: 17
                                            color: addChip.here ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                        }
                                        StyledText {
                                            text: addChip.meta.name
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: addChip.here ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                        }
                                    }
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
