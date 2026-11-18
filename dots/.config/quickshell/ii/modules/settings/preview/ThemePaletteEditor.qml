pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root
    required property bool pageShown
    property bool editing: false
    property string role: "primary"
    readonly property var labels: ({
        primary: Translation.tr("Primary color"), secondary: Translation.tr("Secondary color"),
        tertiary: Translation.tr("Tertiary color"), surface_container: Translation.tr("Surface"),
        on_surface: Translation.tr("Text")
    })
    readonly property var palette: Config.options.appearance.palette
    readonly property color saved: Appearance.m3colors.roleColor(role)

    spacing: 0
    onPageShownChanged: if (!pageShown) editing = false

    function save(value) {
        const overrides = Object.assign({}, palette.roleOverrides);
        if (value) overrides[role] = value;
        else delete overrides[role];
        palette.roleOverrides = overrides;
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width < 360 ? 3 : 5
        uniformCellWidths: true
        rowSpacing: 4
        columnSpacing: 4
        Repeater {
            model: ["primary", "secondary", "tertiary", "surface_container", "on_surface"]
            delegate: RippleButton {
                id: chip
                required property string modelData
                readonly property bool chosen: root.editing && root.role === modelData
                readonly property color swatch: Appearance.m3colors.roleColor(modelData)
                objectName: "paletteRole_" + modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                padding: 3
                Accessible.name: root.labels[modelData] + " " + swatch.toString().toUpperCase()
                Accessible.checkable: true
                Accessible.checked: chosen
                onClicked: {
                    const wasChosen = chosen;
                    root.role = modelData;
                    root.editing = !wasChosen;
                    if (root.editing) editor.item?.readSaved();
                }
                contentItem: ColumnLayout {
                    spacing: 4
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 7
                        color: chip.swatch
                        Behavior on color { ColorAnimation { duration: Appearance.scaledDuration(140) } }
                        border.width: chip.chosen || chip.visualFocus ? 2 : 1
                        border.color: chip.chosen || chip.visualFocus ? Appearance.colors.colOnLayer2 : Appearance.colors.colOutlineVariant
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: chip.chosen ? "check" : "edit"
                            iconSize: 18
                            color: Appearance.m3colors.contrastingInk(chip.swatch, Appearance.colors.colOnLayer2)
                            opacity: chip.chosen || chip.hovered || chip.visualFocus ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(120) } }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.labels[chip.modelData]
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Math.min(10, font.pixelSize)
                        color: chip.chosen ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Item {
        id: disclosure
        Layout.fillWidth: true
        implicitHeight: root.editing ? editor.implicitHeight + 12 : 0
        clip: true
        enabled: root.editing
        Behavior on implicitHeight { NumberAnimation { duration: Appearance.scaledDuration(180); easing.type: Easing.OutCubic } }
        Loader {
            id: editor
            y: 12
            width: parent.width
            active: root.pageShown && (root.editing || disclosure.implicitHeight > 0)
            sourceComponent: GridLayout {
                id: picker
                objectName: "palettePicker"
                columns: width >= 430 ? 2 : 1
                columnSpacing: 16
                rowSpacing: 8
                property real hue: 0
                property real saturation: 0
                property real brightness: 1
                readonly property color draft: Qt.hsva(hue, saturation, brightness, 1)
                readonly property string hex: draft.toString().toUpperCase()
                property bool changed: false

                function setColor(value) {
                    const color = Qt.color(value);
                    if (color.hsvHue >= 0) hue = color.hsvHue;
                    saturation = color.hsvSaturation;
                    brightness = color.hsvValue;
                }
                function readSaved() {
                    changed = false;
                    setColor(root.saved);
                    field.text = hex;
                }
                function updateField() {
                    changed = true;
                    field.text = hex;
                }
                Component.onCompleted: readSaved()
                Connections {
                    target: root
                    function onSavedChanged() { if (!picker.changed) picker.readSaved(); }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 175
                    spacing: 2
                    Rectangle {
                        id: plane
                        objectName: "paletteColorPlane"
                        Layout.fillWidth: true
                        implicitHeight: 85
                        radius: 7
                        activeFocusOnTab: true
                        Accessible.name: Translation.tr("Saturation and brightness")
                        Keys.onPressed: event => {
                            const step = 0.02;
                            switch (event.key) {
                            case Qt.Key_Left: picker.saturation = ColorUtils.clamp01(picker.saturation - step); break;
                            case Qt.Key_Right: picker.saturation = ColorUtils.clamp01(picker.saturation + step); break;
                            case Qt.Key_Down: picker.brightness = ColorUtils.clamp01(picker.brightness - step); break;
                            case Qt.Key_Up: picker.brightness = ColorUtils.clamp01(picker.brightness + step); break;
                            default: return;
                            }
                            event.accepted = true;
                            picker.updateField();
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "white" }
                            GradientStop { position: 1; color: Qt.hsva(picker.hue, 1, 1, 1) }
                        }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: "black" }
                            }
                        }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            x: (parent.width - width) * picker.saturation
                            y: (parent.height - height) * (1 - picker.brightness)
                            color: picker.draft
                            border.width: 2; border.color: "white"
                            Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 7; color: "transparent"; border.color: "#70202020" }
                        }
                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            cursorShape: Qt.CrossCursor
                            function movePoint(x, y) {
                                picker.saturation = ColorUtils.clamp01(x / width);
                                picker.brightness = 1 - ColorUtils.clamp01(y / height);
                                picker.updateField();
                            }
                            onPressed: event => { plane.forceActiveFocus(Qt.MouseFocusReason); movePoint(event.x, event.y); }
                            onPositionChanged: event => { if (pressed) movePoint(event.x, event.y); }
                        }
                    }
                    Slider {
                        id: hueBar
                        objectName: "paletteHue"
                        Layout.fillWidth: true
                        implicitHeight: 25
                        leftPadding: 8; rightPadding: 8
                        value: picker.hue
                        stepSize: 1 / 360
                        Accessible.name: Translation.tr("Hue")
                        onMoved: { picker.hue = value; picker.updateField(); }
                        background: Rectangle {
                            x: hueBar.leftPadding; width: hueBar.availableWidth
                            anchors.verticalCenter: parent.verticalCenter
                            height: 8; radius: 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#ff0000" }
                                GradientStop { position: 1/6; color: "#ffff00" }
                                GradientStop { position: 2/6; color: "#00ff00" }
                                GradientStop { position: 3/6; color: "#00ffff" }
                                GradientStop { position: 4/6; color: "#0000ff" }
                                GradientStop { position: 5/6; color: "#ff00ff" }
                                GradientStop { position: 1; color: "#ff0000" }
                            }
                        }
                        handle: Rectangle {
                            x: hueBar.leftPadding + hueBar.visualPosition * (hueBar.availableWidth - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 7
                            color: Qt.hsva(picker.hue, 1, 1, 1)
                            border.width: 2; border.color: hueBar.visualFocus ? Appearance.colors.colPrimary : "white"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 220
                    spacing: 5
                    ColorQuantizer {
                        id: wallpaperColors
                        readonly property string path: Config.options.background.wallpaperPath
                        readonly property string still: FileUtils.isVideoPath(path) ? Config.options.background.thumbnailPath : path
                        source: still.startsWith("/") ? "file://" + still.split("/").map(encodeURIComponent).join("/") : still
                        depth: 3
                        rescaleSize: 48
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Wallpaper colors")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: Array.from(new Set([Appearance.m3colors.generatedRoles[root.role],
                                ...Array.from(wallpaperColors.colors, c => c.toString())].map(c => c.toUpperCase()))).slice(0, 5)
                            delegate: RippleButton {
                                id: suggestion
                                required property string modelData
                                objectName: "paletteSuggestion"
                                implicitWidth: 23; implicitHeight: 23
                                padding: 1
                                buttonRadius: width / 2
                                Accessible.name: Translation.tr("Wallpaper colors") + " " + modelData
                                onClicked: { picker.setColor(modelData); picker.updateField(); }
                                contentItem: Rectangle {
                                    color: suggestion.modelData; radius: width / 2
                                    border.width: suggestion.visualFocus || suggestion.hovered || picker.hex === suggestion.modelData ? 2 : 1
                                    border.color: picker.hex === suggestion.modelData || suggestion.visualFocus ? Appearance.colors.colOnLayer2 : Appearance.colors.colOutlineVariant
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            implicitWidth: 28; implicitHeight: 28; radius: 7
                            color: picker.draft; border.color: Appearance.colors.colOutlineVariant
                        }
                        MaterialTextField {
                            id: field
                            objectName: "paletteHex"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 76
                            Accessible.name: Translation.tr("Hex color")
                            placeholderText: "#RRGGBB"
                            font.family: Appearance.font.family.monospace
                            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{6}/ }
                            onTextEdited: {
                                picker.changed = true;
                                if (acceptableInput) picker.setColor(text.startsWith("#") ? text : "#" + text);
                            }
                            onAccepted: apply.clicked()
                        }
                        RippleButton {
                            objectName: "paletteCopy"
                            implicitWidth: 32; implicitHeight: 32
                            Accessible.name: Translation.tr("Copy")
                            enabled: field.acceptableInput
                            onClicked: { Quickshell.clipboardText = picker.hex; copied.restart(); }
                            contentItem: MaterialSymbol {
                                text: copied.running ? "check" : "content_copy"; iconSize: 17
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                color: Appearance.colors.colOnLayer2
                            }
                            Timer { id: copied; interval: 1000 }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            objectName: "paletteReset"
                            buttonText: Translation.tr("Use theme color")
                            enabled: !!root.palette.roleOverrides?.[root.role] || picker.changed
                            onClicked: {
                                if (root.palette.roleOverrides?.[root.role]) root.save("");
                                picker.readSaved();
                            }
                        }
                        DialogButton {
                            id: apply
                            objectName: "paletteApply"
                            buttonText: Translation.tr("Apply")
                            enabled: field.acceptableInput && picker.hex !== root.saved.toString().toUpperCase()
                            colBackground: enabled ? Appearance.colors.colPrimary : "transparent"
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colEnabled: Appearance.colors.colOnPrimary
                            onClicked: { if (enabled) { root.save(picker.hex); picker.readSaved(); } }
                        }
                    }
                }
            }
        }
    }
}
