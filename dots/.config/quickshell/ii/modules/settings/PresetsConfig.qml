pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.presets

SettingsDetailPage {
    id: root

    readonly property var systemPresets: Presets.presets.filter(preset => !root.isBarOnly(preset))
    // Whole looks with their own wallpaper come first, plain styles after
    readonly property var allLooks: systemPresets.filter(preset => root.hasWallpaper(preset))
    property bool liveOnly: false // Only looks with a moving wallpaper
    readonly property var lookPresets: root.allLooks.filter(preset => !root.liveOnly || Presets.isLive(preset))
    readonly property var stylePresets: systemPresets.filter(preset => !root.hasWallpaper(preset))
    readonly property var barPresets: Presets.presets.filter(preset => root.isBarOnly(preset))
    property string selectedId: ""
    readonly property var selectedPreset: selectedId ? Presets.find(selectedId) : null
    property var chosenCategories: []
    property PresetCoverCache coverCache: PresetCoverCache {}
    sectionTitles: ({
        preview: selectedPreset ? Translation.tr(selectedPreset.name) : Translation.tr("Preview"),
        save: Translation.tr("Save current settings"),
        importPreset: Translation.tr("Import a preset")
    })

    function openPreview(preset, trigger) {
        trigger.forceActiveFocus();
        selectedId = preset.id;
        chosenCategories = Presets.categoriesOf(preset);
        tab = "preview";
        // Disabling the catalog can clear the window's focus before tabChanged is delivered.
        detailHistory = [{ key: overviewKey, focus: trigger }];
    }
    onSelectedPresetChanged: {
        if (tab !== "preview") return;
        if (!selectedPreset) navigateBack();
        else chosenCategories = chosenCategories.filter(part => Presets.categoriesOf(selectedPreset).includes(part));
    }

    function isBarOnly(preset) {
        const categories = Presets.categoriesOf(preset);
        return categories.length === 1 && categories[0] === "bar";
    }

    function hasWallpaper(preset) {
        const motion = preset.wallpaperAnimations;
        return !!(motion?.wallpaper || motion?.config?.background?.shaderWallpaper?.name || Presets.previewOf(preset));
    }

    // Applying happens in the shell, which owns the bar and the theme
    function applyPreset(id, categories) {
        if (!id || !categories.length) return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "apply", id, categories.join(",")]);
        refreshTimer.restart();
    }

    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: Presets.load()
    }

    function partSummary(part) {
        if (part === "windows") {
            const options = selectedPreset?.windows?.hyprland ?? {};
            const mode = options["shell:windowMode"] ?? HyprlandSettings.windowMode;
            if (mode === "floating") return Translation.tr("Free windows");
            if (mode === "canvas") return Translation.tr("Infinite canvas");
            return Translation.tr("Tiling") + " · " + (options["general:layout"] ?? HyprlandSettings.get("general:layout", "dwindle"));
        }
        if (part === "lock") {
            const lock = selectedPreset?.lock?.config?.lock ?? {};
            const details = [];
            if (lock.layout !== undefined) details.push(lock.layout ? Translation.tr("Custom layout") : Translation.tr("Default layout"));
            if (lock.dim !== undefined) details.push(Translation.tr("Dimming %1%").arg(Math.round(lock.dim * 100)));
            if (lock.blur) details.push(lock.blur.enable === false ? Translation.tr("Blur off")
                : Translation.tr("Blur %1").arg(lock.blur.radius ?? Config.options.lock.blur.radius));
            if (lock.animations) details.push(Translation.tr("Motion") + " · " + Translation.tr(({full: "Full motion", calm: "Calm", none: "Off"})[lock.animations] ?? lock.animations));
            if (lock.animatedWallpaper !== undefined) details.push(Translation.tr(lock.animatedWallpaper ? "Animated wallpaper" : "Still wallpaper"));
            if (lock.showLockedText !== undefined) details.push(Translation.tr(lock.showLockedText ? "Show lock label" : "Hide lock label"));
            const clockStyle = selectedPreset?.lock?.config?.background?.widgets?.clock?.styleLocked;
            if (clockStyle) details.push(Translation.tr("Clock") + " · " + clockStyle);
            return details.join(" · ");
        }
        return "";
    }

    component PresetGrid: GridLayout {
        id: grid
        required property var presets
        Layout.fillWidth: true
        columns: width >= 550 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 12
        rowSpacing: 10
        Repeater {
            model: grid.presets
            delegate: PresetCard {
                id: card
                required property var modelData
                preset: modelData
                viewport: root.scrollerOf(card)
                coverCache: root.coverCache
                pageShown: root.pageShown && overview.shown
                onClicked: root.openPreview(preset, card)
                onQuickApply: root.applyPreset(preset.id, categories)
            }
            onItemAdded: root.searchContentChanged()
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overview
            key: "overview"
            page: root

            ContentSection {
                title: Translation.tr("Your look")
                icon: "home"
                Flow {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    spacing: 6
                    SettingsToolButton {
                        visible: !!Presets.defaultPreset
                        materialIcon: "home"
                        mainText: Translation.tr("Return to my look")
                        onClicked: root.applyPreset(Presets.defaultPreset.id, Presets.categoriesOf(Presets.defaultPreset))
                    }
                    SettingsToolButton {
                        visible: Presets.hasBackup
                        materialIcon: "undo"
                        mainText: Translation.tr("Undo the last preset")
                        onClicked: {
                            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "undo"]);
                            refreshTimer.restart();
                        }
                    }
                    SettingsToolButton {
                        materialIcon: "bookmark_add"
                        mainText: Translation.tr("Remember my current look")
                        onClicked: {
                            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "saveDefault", Presets.defaultPreset?.name ?? ""]);
                            refreshTimer.restart();
                        }
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 465 ? 2 : 1
                    uniformCellWidths: true
                    columnSpacing: 6
                    rowSpacing: 0
                    SettingsBranchLink {
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        branch: saveBranch
                        buttonIcon: "add"
                        title: Translation.tr("Create a preset")
                    }
                    SettingsBranchLink {
                        Layout.preferredWidth: 1
                        Layout.minimumWidth: 0
                        branch: importBranch
                        buttonIcon: "content_paste"
                    }
                }
            }
            ContentSection {
                icon: "auto_awesome_mosaic"
                title: Translation.tr("Looks")
                card: false
                ConfigSelectionArray {
                    visible: root.allLooks.some(preset => Presets.isLive(preset))
                    currentValue: root.liveOnly
                    onSelected: value => root.liveOnly = value
                    options: [
                        {displayName: Translation.tr("All looks"), icon: "apps", value: false},
                        {displayName: Translation.tr("With a moving wallpaper"), icon: "motion_photos_on", value: true}
                    ]
                }
                PresetGrid { presets: root.lookPresets }
            }
            ContentSection {
                icon: "style"
                title: Translation.tr("Styles")
                description: Translation.tr("Keep your wallpaper and change how everything else looks and moves")
                card: false
                PresetGrid { presets: root.stylePresets }
            }
            ContentSection {
                icon: "toast"
                title: Translation.tr("Bar presets")
                card: false
                PresetGrid { presets: root.barPresets }
            }
        }

        SettingsBranch {
            id: previewBranch
            key: "preview"
            page: root
            ContentSection {
                visible: !!root.selectedPreset
                icon: "compare"
                card: false
                title: root.selectedPreset ? Translation.tr(root.selectedPreset.name) : ""
                Loader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: item?.implicitHeight ?? 0
                    active: previewBranch.shown && !!root.selectedPreset
                    sourceComponent: PresetComparison {
                        preset: root.selectedPreset
                        categories: root.chosenCategories
                        coverCache: root.coverCache
                        pageShown: root.pageShown && previewBranch.shown
                    }
                    onLoaded: Qt.callLater(() => { if (item && root.pageShown && previewBranch.shown) item.focusDivider(); })
                }
            }
            ContentSection {
                visible: !!root.selectedPreset
                title: Translation.tr("Parts to apply")
                Repeater {
                    model: Presets.categoriesOf(root.selectedPreset)
                    delegate: ConfigSwitch {
                        required property string modelData
                        readonly property var entry: Presets.categories.find(part => part.id === modelData)
                        objectName: "previewPart-" + modelData
                        buttonIcon: entry?.icon ?? ""
                        text: entry?.name ?? ""
                        description: root.partSummary(modelData)
                        autoToggle: false
                        checked: root.chosenCategories.includes(modelData)
                        onClicked: root.chosenCategories = checked
                            ? root.chosenCategories.filter(part => part !== modelData)
                            : [...root.chosenCategories, modelData]
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    spacing: 6
                    SettingsToolButton {
                        objectName: "applyPresetSelection"
                        materialIcon: "check"
                        mainText: Translation.tr("Apply selected")
                        enabled: root.chosenCategories.length > 0
                        onClicked: {
                            root.applyPreset(root.selectedId, root.chosenCategories);
                            root.navigateBack();
                        }
                    }
                    SettingsToolButton {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy as text")
                        onClicked: Quickshell.clipboardText = Presets.exportText(root.selectedId)
                    }
                    SettingsToolButton {
                        visible: root.selectedPreset?.kind === "user"
                        materialIcon: "delete"
                        mainText: Translation.tr("Delete")
                        onClicked: {
                            Presets.remove(root.selectedId);
                            root.navigateBack();
                        }
                    }
                }
            }
            ContentSection {
                visible: !!root.selectedPreset?.credits
                title: Translation.tr("Artwork")
                ConfigNavRow {
                    buttonIcon: "attribution"
                    title: root.selectedPreset?.credits?.author ?? ""
                    description: root.selectedPreset?.credits?.license ?? ""
                    enabled: !!root.selectedPreset?.credits?.page
                    trailingIcon: enabled ? "open_in_new" : ""
                    onClicked: Qt.openUrlExternally(root.selectedPreset.credits.page)
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    visible: !!text
                    text: [root.selectedPreset?.credits?.copyright,
                        Translation.tr(root.selectedPreset?.credits?.restrictions ?? "")].filter(Boolean).join("\n")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
        SettingsBranch {
            id: saveBranch
            page: root
            key: "save"
            ContentSection {
                id: saveSection
                icon: "bookmark_add"
                title: Translation.tr("Save current settings")
                description: Translation.tr("Keep your look as a preset to come back to or share")

                property var categories: Presets.categoryIds.slice()

                ConfigTextRow {
                    id: nameField
                    icon: "label"
                    label: Translation.tr("Name")
                    placeholderText: Translation.tr("My setup")
                }
                ConfigTextRow {
                    id: descriptionField
                    icon: "notes"
                    label: Translation.tr("Description")
                }
                Repeater {
                    model: Presets.categories
                    delegate: ConfigSwitch {
                        required property var modelData
                        buttonIcon: modelData.icon
                        text: modelData.name
                        autoToggle: false
                        checked: saveSection.categories.includes(modelData.id)
                        onClicked: saveSection.categories = checked
                            ? saveSection.categories.filter(category => category !== modelData.id)
                            : [...saveSection.categories, modelData.id]
                    }
                }
                DialogButton {
                    buttonText: Translation.tr("Save preset")
                    enabled: nameField.value.trim().length > 0 && saveSection.categories.length > 0
                    onClicked: {
                        Presets.saveCurrent(nameField.value.trim(), descriptionField.value.trim(), saveSection.categories);
                        nameField.value = "";
                        descriptionField.value = "";
                    }
                }
            }
        }
        SettingsBranch {
            id: importBranch
            page: root
            key: "importPreset"
            ContentSection {
                id: importSection
                icon: "content_paste"
                title: Translation.tr("Import a preset")
                description: Translation.tr("Paste a preset someone shared as text")

                property var pasted: null

                DialogButton {
                    buttonText: Translation.tr("Paste from clipboard")
                    onClicked: importSection.pasted = Presets.parse(Quickshell.clipboardText)
                }

                ColumnLayout {
                    visible: importSection.pasted !== null
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: importSection.pasted?.error ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                        text: importSection.pasted?.error ?? Translation.tr("“%1” is ready to import.").arg(importSection.pasted?.preset?.name ?? "")
                        textFormat: Text.PlainText
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: (importSection.pasted?.commands?.length ?? 0) > 0
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colError
                        text: Translation.tr("Bar widgets can run the commands below automatically or when you interact with them.")
                    }
                    Repeater {
                        model: importSection.pasted?.commands ?? []
                        delegate: StyledText {
                            required property string modelData
                            Layout.fillWidth: true
                            wrapMode: Text.WrapAnywhere
                            text: modelData
                            textFormat: Text.PlainText
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    RowLayout {
                        spacing: 6
                        DialogButton {
                            visible: !!importSection.pasted?.preset
                            buttonText: Translation.tr("Import")
                            onClicked: {
                                Presets.importPreset(importSection.pasted.preset);
                                importSection.pasted = null;
                            }
                        }
                        DialogButton {
                            buttonText: Translation.tr("Cancel")
                            onClicked: importSection.pasted = null
                        }
                    }
                }
            }
        }
    }
}
