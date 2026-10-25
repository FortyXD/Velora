pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.settings.preview

/**
 * Everything about one sidebar part, on the Sidebars page: what it is, moving and hiding it, taking it
 * to the other sidebar or into tabs, its options, and editors for the parts that hold a list (the top
 * row's buttons, quick toggles, tabs, quick tools). Only the selected part's card shows, but every card
 * stays laid out (height 0) so settings search finds its options; revealing one selects it.
 */
ColumnLayout {
    id: root
    required property var part
    required property string side
    property var group: null // The tabs part this is a page of
    property string selectedUid: ""
    signal selectRequested(string uid)

    readonly property bool selected: root.selectedUid === root.part.uid
    readonly property var meta: SidebarCatalog.part(root.part.type)
    readonly property var options: SidebarLayout.optionsOf(root.part)
    readonly property bool shown: SidebarLayout.shown(root.part)
    readonly property var siblings: root.group ? root.group.tabs : SidebarLayout.parts(root.side)
    readonly property int index: root.siblings.findIndex(p => p.uid === root.part.uid)
    readonly property var tabsHere: SidebarLayout.parts(root.side).filter(p => p.type === "tabs")

    readonly property bool settingsSearchable: true
    readonly property string title: root.meta?.name ?? ""
    readonly property string icon: root.meta?.icon ?? "tab"
    readonly property string searchText: `${root.title} ${root.meta?.description ?? ""} ${(root.meta?.options ?? []).map(o => o.label).join(" ")}`
    function settingsReveal() {
        if (root.selected) return false;
        root.selectRequested(root.part.uid);
        return true;
    }

    Layout.fillWidth: true
    Layout.preferredHeight: root.selected ? implicitHeight : 0
    opacity: root.selected ? 1 : 0
    clip: true
    spacing: 10

    // ---- What it is ----

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Item {
            implicitWidth: 44
            implicitHeight: 44
            MaterialShape {
                anchors.fill: parent
                shape: MaterialShape.Shape.Cookie7Sided
                color: root.shown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 22
                fill: root.shown ? 1 : 0
                color: root.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: [root.side === "left" ? Translation.tr("Left sidebar") : Translation.tr("Right sidebar"),
                       root.group ? Translation.tr("a tab of %1").arg(SidebarCatalog.part("tabs").name) : "",
                       root.shown ? "" : Translation.tr("hidden")].filter(t => t.length > 0).join(" · ")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        IconAction {
            symbol: "close"
            tip: Translation.tr("Back to the whole sidebar")
            onClicked: root.selectRequested("")
        }
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.meta?.description ?? ""
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
    }

    // ---- Moving and hiding ----

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Chip {
            symbol: "arrow_upward"
            text: root.group ? Translation.tr("Earlier") : Translation.tr("Higher")
            enabled: root.index > 0
            onClicked: SidebarLayout.moveBy(root.part.uid, -1)
        }
        Chip {
            symbol: "arrow_downward"
            text: root.group ? Translation.tr("Later") : Translation.tr("Lower")
            enabled: root.index >= 0 && root.index < root.siblings.length - 1
            onClicked: SidebarLayout.moveBy(root.part.uid, 1)
        }
        Chip {
            symbol: root.part.hidden ? "visibility" : "visibility_off"
            text: root.part.hidden ? Translation.tr("Show") : Translation.tr("Hide")
            onClicked: SidebarLayout.setHidden(root.part.uid, !root.part.hidden)
        }
        Chip {
            visible: !root.group
            symbol: root.side === "left" ? "right_panel_open" : "left_panel_open"
            text: root.side === "left" ? Translation.tr("Move to the right sidebar") : Translation.tr("Move to the left sidebar")
            onClicked: SidebarLayout.moveToOtherSide(root.part.uid)
        }
        Repeater { // Into one of the tabs of this sidebar
            model: !root.group && (root.meta?.tabbable ?? false) ? root.tabsHere : []
            delegate: Chip {
                required property var modelData
                required property int index
                symbol: "tab_move"
                text: root.tabsHere.length > 1 ? Translation.tr("Into tabs %1").arg(index + 1) : Translation.tr("Into tabs")
                onClicked: SidebarLayout.move(root.part.uid, root.side, -1, modelData.uid)
            }
        }
        Chip {
            visible: root.group !== null
            symbol: "tab_close_right"
            text: Translation.tr("Out of the tabs")
            onClicked: SidebarLayout.takeOutOfTabs(root.part.uid)
        }
        Chip {
            visible: root.group !== null && root.group.options?.style !== "rail"
            symbol: "swipe"
            text: Translation.tr("No tab, swipe to it")
            active: !!root.part.swipeOnly
            onClicked: SidebarLayout.setField(root.part.uid, "swipeOnly", !root.part.swipeOnly)
        }
        Chip {
            symbol: "delete"
            text: Translation.tr("Remove")
            onClicked: {
                root.selectRequested("");
                SidebarLayout.remove(root.part.uid);
            }
        }
    }

    // Turned off on another page
    RowLayout {
        visible: !SidebarLayout.allowed(root.part.type)
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            text: "info"
            iconSize: 18
            color: Appearance.colors.colError
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.part.type === "sliders" ? Translation.tr("No slider is chosen, so it doesn't show.")
                : root.meta?.policy === "ai" ? Translation.tr("The assistant is turned off on the Search & AI page.")
                : Translation.tr("The image browser is turned off.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colError
        }
        Chip {
            symbol: "check"
            text: Translation.tr("Turn on")
            onClicked: SidebarLayout.allow(root.part.type)
        }
    }

    // ---- Options ----

    ContentSection {
        visible: optionsRepeater.count > 0 || editorLoader.active || linksRepeater.count > 0
        icon: "tune"
        title: Translation.tr("Settings")

        Repeater {
            id: optionsRepeater
            model: (root.meta?.options ?? []).filter(spec => !spec.when || root.options[spec.when.key] === spec.when.value)
            delegate: Loader {
                id: optionLoader
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData.kind === "slider" ? sliderOption : modelData.kind === "choice" ? choiceOption : switchOption
                onLoaded: item.spec = optionLoader.modelData
            }
        }

        Loader {
            id: editorLoader
            Layout.fillWidth: true
            active: (root.meta?.editor ?? "").length > 0
            sourceComponent: ({ "headerButtons": headerButtonsEditor, "quickToggles": quickTogglesEditor,
                "tabs": tabsEditor, "tools": toolsEditor })[root.meta?.editor] ?? null
        }

        Repeater {
            id: linksRepeater
            model: root.meta?.links ?? []
            delegate: ConfigNavRow {
                required property var modelData
                buttonIcon: modelData.icon
                title: modelData.label
                onClicked: ApplicationWindow.window?.openPage(modelData.page, modelData.section)
            }
        }
    }

    Component {
        id: switchOption
        ConfigSwitch {
            property var spec: ({})
            buttonIcon: spec.icon ?? ""
            text: spec.label ?? ""
            description: spec.description ?? ""
            autoToggle: false
            checked: !!SidebarLayout.optionValue(root.part, spec)
            onClicked: SidebarLayout.setOption(root.part.uid, spec, !checked)
        }
    }
    Component {
        id: sliderOption
        ConfigSlider {
            property var spec: ({})
            readonly property real step: spec.step ?? 1
            buttonIcon: spec.icon ?? ""
            text: spec.label ?? ""
            description: spec.description ?? ""
            usePercentTooltip: false
            from: spec.from ?? 0
            to: spec.to ?? 1
            value: SidebarLayout.optionValue(root.part, spec) ?? from
            valueText: spec.unit === "%" ? (value > 0 ? `${Math.round(value * 100)}%` : Translation.tr("Auto"))
                : spec.unit ? `${Math.round(value)} ${spec.unit}` : `${Math.round(value)}`
            onMoved: SidebarLayout.setOption(root.part.uid, spec, Math.round(value / step) * step)
        }
    }
    Component {
        id: choiceOption
        ContentSubsection {
            id: choiceBlock
            property var spec: ({})
            title: spec.label ?? ""
            ConfigSelectionArray {
                currentValue: SidebarLayout.optionValue(root.part, choiceBlock.spec)
                options: (choiceBlock.spec.choices ?? []).map(choice => ({ "displayName": choice.label, "icon": choice.icon, "value": choice.value }))
                onSelected: value => SidebarLayout.setOption(root.part.uid, choiceBlock.spec, value)
            }
        }
    }

    // ---- Editors ----

    Component {
        id: headerButtonsEditor
        Flow {
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 6
            spacing: 6
            readonly property var buttons: root.options.buttons ?? SidebarCatalog.headerButtons.map(b => b.id)
            Repeater {
                model: SidebarCatalog.headerButtons
                delegate: Chip {
                    required property var modelData
                    symbol: modelData.icon
                    text: modelData.name
                    active: parent.buttons.includes(modelData.id)
                    onClicked: SidebarLayout.setOptionKey(root.part.uid, "buttons",
                        active ? parent.buttons.filter(id => id !== modelData.id) : [...parent.buttons, modelData.id])
                }
            }
        }
    }

    Component {
        id: quickTogglesEditor
        ColumnLayout {
            spacing: 8
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 4
                SchemeTile {
                    id: androidTile
                    label: Translation.tr("Tiles")
                    frameWidth: 112
                    frameHeight: 64
                    selected: Config.options.sidebar.quickToggles.style === "android"
                    onClicked: Config.options.sidebar.quickToggles.style = "android"
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 4
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.ink }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.faint }
                    }
                }
                SchemeTile {
                    id: classicTile
                    label: Translation.tr("Round buttons")
                    frameWidth: 112
                    frameHeight: 64
                    selected: Config.options.sidebar.quickToggles.style === "classic"
                    onClicked: Config.options.sidebar.quickToggles.style = "classic"
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                width: 16
                                height: 16
                                radius: 8
                                color: index === 0 ? classicTile.ink : classicTile.faint
                            }
                        }
                    }
                }
            }
            ConfigSlider {
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "view_column"
                text: Translation.tr("Columns")
                usePercentTooltip: false
                from: 2
                to: 8
                value: Config.options.sidebar.quickToggles.android.columns
                valueText: `${Math.round(value)}`
                onMoved: Config.options.sidebar.quickToggles.android.columns = Math.round(value)
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                wrapMode: Text.Wrap
                text: Config.options.sidebar.quickToggles.style === "android"
                    ? Translation.tr("Drag a toggle to move it, click it to make it wide or narrow, × removes it. Add more from the list under it.")
                    : Translation.tr("Drag a button to move it, × removes it. Add more from the list under it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            QuickTogglesEditor {
                Layout.bottomMargin: 8
            }
        }
    }

    Component {
        id: tabsEditor
        ColumnLayout {
            spacing: 4
            StyledText {
                Layout.leftMargin: 12
                text: Translation.tr("Tabs")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            Repeater {
                model: root.part.tabs ?? []
                delegate: RowLayout {
                    id: pageRow
                    required property var modelData
                    required property int index
                    readonly property var pageMeta: SidebarCatalog.part(modelData.type)
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 8
                    spacing: 6
                    MaterialSymbol {
                        text: pageRow.pageMeta?.icon ?? "tab"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                        opacity: pageRow.modelData.hidden ? 0.4 : 1
                    }
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: root.selectRequested(pageRow.modelData.uid)
                        contentItem: StyledText {
                            text: (pageRow.pageMeta?.name ?? "") + (pageRow.modelData.swipeOnly ? ` · ${Translation.tr("swipe only")}` : "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: pageRow.modelData.hidden ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                        }
                    }
                    IconAction {
                        symbol: "arrow_upward"
                        tip: Translation.tr("Earlier")
                        enabled: pageRow.index > 0
                        onClicked: SidebarLayout.moveBy(pageRow.modelData.uid, -1)
                    }
                    IconAction {
                        symbol: "arrow_downward"
                        tip: Translation.tr("Later")
                        enabled: pageRow.index < (root.part.tabs ?? []).length - 1
                        onClicked: SidebarLayout.moveBy(pageRow.modelData.uid, 1)
                    }
                    IconAction {
                        symbol: pageRow.modelData.hidden ? "visibility_off" : "visibility"
                        tip: pageRow.modelData.hidden ? Translation.tr("Show") : Translation.tr("Hide")
                        onClicked: SidebarLayout.setHidden(pageRow.modelData.uid, !pageRow.modelData.hidden)
                    }
                    IconAction {
                        symbol: "close"
                        tip: Translation.tr("Remove")
                        onClicked: SidebarLayout.remove(pageRow.modelData.uid)
                    }
                }
            }
            StyledText {
                Layout.leftMargin: 12
                Layout.topMargin: 6
                text: Translation.tr("Add a tab")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 6
                spacing: 6
                Repeater {
                    model: Object.keys(SidebarCatalog.parts).filter(type => SidebarCatalog.part(type).tabbable
                        && !(root.part.tabs ?? []).some(tab => tab.type === type))
                    delegate: Chip {
                        required property string modelData
                        readonly property var elsewhere: SidebarLayout.findType(modelData)
                        symbol: SidebarCatalog.part(modelData).icon
                        text: SidebarCatalog.part(modelData).name
                        dim: elsewhere !== null
                        onClicked: SidebarLayout.insert(root.side, modelData, -1, root.part.uid)
                        StyledToolTip {
                            text: parent.elsewhere ? Translation.tr("Already in a sidebar · click to move it into these tabs") : SidebarCatalog.part(parent.modelData).description
                        }
                    }
                }
            }
        }
    }

    Component {
        id: toolsEditor
        ColumnLayout {
            id: toolsColumn
            spacing: 6
            readonly property var items: root.options.items ?? SidebarCatalog.defaultTools
            function setItems(list) {
                SidebarLayout.setOptionKey(root.part.uid, "items", list);
            }
            StyledText {
                Layout.leftMargin: 12
                text: Translation.tr("Tools")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                spacing: 6
                Repeater {
                    model: SidebarCatalog.tools
                    delegate: Chip {
                        required property var modelData
                        symbol: modelData.icon
                        text: modelData.name
                        active: toolsColumn.items.includes(modelData.id)
                        onClicked: toolsColumn.setItems(active ? toolsColumn.items.filter(id => id !== modelData.id) : [...toolsColumn.items, modelData.id])
                    }
                }
            }
            StyledText {
                Layout.leftMargin: 12
                Layout.topMargin: 4
                text: Translation.tr("Apps")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 6
                spacing: 6
                Repeater {
                    model: toolsColumn.items.filter(id => id.startsWith("app:"))
                    delegate: Chip {
                        required property string modelData
                        symbol: "close"
                        text: TaskbarApps.displayName(modelData.slice(4))
                        active: true
                        onClicked: toolsColumn.setItems(toolsColumn.items.filter(id => id !== modelData))
                    }
                }
                Chip {
                    symbol: "add"
                    text: Translation.tr("Add an app")
                    onClicked: appPicker.open()
                }
            }
            AppPickerPopup {
                id: appPicker
                title: Translation.tr("Add an app to the quick tools")
                excludedIds: toolsColumn.items.filter(id => id.startsWith("app:")).map(id => id.slice(4))
                onPicked: entry => toolsColumn.setItems([...toolsColumn.items, `app:${entry.id}`])
            }
        }
    }

    // ---- Pieces ----

    component IconAction: RippleButton {
        id: iconAction
        property string symbol
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        opacity: iconAction.enabled ? 1 : 0.35
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: iconAction.symbol
            iconSize: 18
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: iconAction.tip
        }
    }

    // A pill with an icon; `active` marks what's on
    component Chip: RippleButton {
        id: chip
        property string symbol
        property bool active: false
        property bool dim: false
        readonly property bool settingsSearchable: true
        readonly property string searchText: chip.text
        implicitHeight: 34
        leftPadding: 10
        rightPadding: 14
        buttonRadius: Appearance.rounding.full
        opacity: chip.enabled ? (chip.dim ? 0.7 : 1) : 0.4
        colBackground: chip.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: chip.active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol {
                text: chip.active && chip.symbol !== "close" ? "check" : chip.symbol
                iconSize: 17
                color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: chip.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
        }
    }
}
