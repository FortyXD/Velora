import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page

    readonly property var systemPresets: Presets.presets.filter(preset => !page.isBarOnly(preset))
    // Whole looks with their own wallpaper come first, plain styles after
    readonly property var lookPresets: systemPresets.filter(preset => Presets.previewOf(preset).length > 0)
    readonly property var stylePresets: systemPresets.filter(preset => Presets.previewOf(preset).length === 0)
    readonly property var barPresets: Presets.presets.filter(preset => page.isBarOnly(preset))
    property string expandedId: "" // Preset whose apply options are open
    property var chosenCategories: []

    function isBarOnly(preset) {
        const categories = Presets.categoriesOf(preset);
        return categories.length === 1 && categories[0] === "bar";
    }

    // Applying happens in the shell, which owns the bar and the theme
    function applyPreset(id, categories) {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "apply", id, categories.join(",")]);
        refreshTimer.restart();
    }

    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: Presets.load()
    }

    component CategoryIcon: MaterialSymbol {
        required property string category
        text: Presets.categories.find(entry => entry.id === category)?.icon ?? "help"
        iconSize: 16
        color: Appearance.colors.colSubtext
    }

    component PresetCard: Rectangle {
        id: card
        required property var preset
        readonly property bool expanded: page.expandedId === preset.id
        readonly property var categories: Presets.categoriesOf(preset)
        readonly property string preview: Presets.previewOf(preset)
        readonly property bool settingsSearchable: true
        property string searchText: `${Translation.tr(preset.name)} ${Translation.tr(preset.description ?? "")}`

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: cardColumn.implicitHeight
        radius: Appearance.rounding.large
        color: card.expanded ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 0

            Item { // Wallpaper of the preset
                id: previewBox
                visible: card.preview.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.round(width * 9 / 16)

                Loader {
                    id: previewLoader
                    anchors.fill: parent
                    active: card.preview.length > 0
                    sourceComponent: card.preview.startsWith("http") ? remotePreview : localPreview
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: previewBox.width
                            height: previewBox.height
                            radius: card.radius
                            Rectangle { // Only the top corners are round
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.radius
                            }
                        }
                    }
                }
                Component {
                    id: remotePreview
                    RemoteImage {
                        url: card.preview
                    }
                }
                Component {
                    id: localPreview
                    StyledImage {
                        source: card.preview
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: previewBox.width * 2
                        asynchronous: true
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Item {
                        implicitWidth: 44
                        implicitHeight: 44
                        MaterialShape {
                            anchors.fill: parent
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: card.expanded ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: card.preset.icon ?? "bookmark"
                            iconSize: 22
                            fill: 1
                            color: card.expanded ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Translation.tr(card.preset.name)
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: card.expanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                            Rectangle {
                                visible: !!card.preset.isDefault
                                implicitWidth: defaultLabel.implicitWidth + 12
                                implicitHeight: defaultLabel.implicitHeight + 4
                                radius: height / 2
                                color: Appearance.colors.colPrimary
                                StyledText {
                                    id: defaultLabel
                                    anchors.centerIn: parent
                                    text: Translation.tr("Default")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr(card.preset.description ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    DialogButton {
                        buttonText: card.expanded ? Translation.tr("Close") : Translation.tr("Apply")
                        onClicked: {
                            if (card.expanded) {
                                page.expandedId = "";
                            } else if (card.categories.length === 1) {
                                page.applyPreset(card.preset.id, card.categories);
                            } else {
                                page.chosenCategories = card.categories.slice();
                                page.expandedId = card.preset.id;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: card.categories
                        delegate: CategoryIcon {
                            required property string modelData
                            category: modelData
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        text: card.preset.credits
                            ? Translation.tr("Photo: %1 · %2").arg(card.preset.credits.author).arg(card.preset.credits.license)
                            : card.preset.kind === "user" ? Translation.tr("Yours") : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!card.preset.credits?.page
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(card.preset.credits.page)
                        }
                    }
                }

                ColumnLayout { // What to take from the preset
                    visible: card.expanded
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Apply these parts:")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    Repeater {
                        model: card.categories
                        delegate: ConfigSwitch {
                            required property string modelData
                            Layout.fillWidth: true
                            buttonIcon: Presets.categories.find(entry => entry.id === modelData)?.icon ?? "help"
                            text: Presets.categories.find(entry => entry.id === modelData)?.name ?? modelData
                            autoToggle: false
                            checked: page.chosenCategories.includes(modelData)
                            onClicked: page.chosenCategories = checked
                                ? page.chosenCategories.filter(category => category !== modelData)
                                : [...page.chosenCategories, modelData]
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        DialogButton {
                            buttonText: Translation.tr("Apply selected")
                            enabled: page.chosenCategories.length > 0
                            onClicked: {
                                page.applyPreset(card.preset.id, page.chosenCategories);
                                page.expandedId = "";
                            }
                        }
                        DialogButton {
                            buttonText: Translation.tr("Copy as text")
                            onClicked: Quickshell.clipboardText = Presets.exportText(card.preset.id)
                        }
                        DialogButton {
                            visible: card.preset.kind === "user"
                            buttonText: Translation.tr("Delete")
                            colEnabled: Appearance.colors.colError
                            onClicked: {
                                Presets.remove(card.preset.id);
                                page.expandedId = "";
                            }
                        }
                    }
                }
            }
        }
    }

    component PresetGrid: GridLayout {
        property var presets: []
        Layout.fillWidth: true
        columns: width > 620 ? 2 : 1
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: parent.presets
            delegate: PresetCard {
                required property var modelData
                preset: modelData
            }
        }
    }

    ContentSection {
        visible: Presets.defaultPreset !== null
        icon: "home"
        title: Translation.tr("Your look")
        description: Translation.tr("Your wallpaper, bar, theme, dock and motion as you saved them. Come back to them any time.")

        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Return to my look")
                onClicked: page.applyPreset(Presets.defaultPreset.id, Presets.categoriesOf(Presets.defaultPreset))
            }
            DialogButton {
                buttonText: Translation.tr("Save the current setup as my look")
                onClicked: {
                    Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "saveDefault", Presets.defaultPreset.name]);
                    refreshTimer.restart();
                }
            }
        }
    }

    ContentSection {
        icon: "auto_awesome_mosaic"
        title: Translation.tr("Looks")
        description: Translation.tr("A whole look in one click: wallpaper, colors, bar, dock and widgets, and motion. Pick which parts to take.")

        RowLayout {
            visible: Presets.hasBackup
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "history"
                iconSize: 20
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Your settings from before the last preset are kept.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            DialogButton {
                buttonText: Translation.tr("Undo the last preset")
                onClicked: {
                    Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "undo"]);
                    refreshTimer.restart();
                }
            }
        }

        PresetGrid {
            presets: page.lookPresets
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Styles")
        description: Translation.tr("Keep your wallpaper and change how everything else looks and moves")

        PresetGrid {
            presets: page.stylePresets
        }
    }

    ContentSection {
        icon: "toast"
        title: Translation.tr("Bar presets")
        description: Translation.tr("Change only the bar's layout and look")

        Repeater {
            model: page.barPresets
            delegate: PresetCard {
                required property var modelData
                preset: modelData
            }
        }
    }

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
            }
            StyledText {
                Layout.fillWidth: true
                visible: (importSection.pasted?.commands?.length ?? 0) > 0
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
                text: Translation.tr("Its bar runs these commands when you click its widgets. Import it only if you trust them:")
            }
            Repeater {
                model: importSection.pasted?.commands ?? []
                delegate: StyledText {
                    required property string modelData
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    text: modelData
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
