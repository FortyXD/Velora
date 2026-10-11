pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root

    readonly property var monitors: HyprlandMonitors.monitors
    property string selectedName: ""
    readonly property var selected: HyprlandMonitors.monitorByName(root.selectedName) ?? root.monitors.find(m => m.focused) ?? root.monitors[0] ?? null
    readonly property var selectedSpec: HyprlandMonitors.spec(root.selected)
    readonly property var selectedMode: HyprlandMonitors.parseMode(root.selectedSpec?.mode)
    readonly property var selectedModes: HyprlandMonitors.modes(root.selected)
    readonly property int enabledCount: root.monitors.filter(m => !HyprlandMonitors.spec(m).disabled).length

    function isBuiltIn(monitor) {
        return monitor.name.startsWith("eDP") || monitor.name.startsWith("LVDS") || monitor.name.startsWith("DSI");
    }
    function displayName(monitor) {
        if (!monitor) return "";
        return root.isBuiltIn(monitor) ? Translation.tr("Built-in display") : (monitor.model?.trim() || monitor.description || monitor.name);
    }
    function rateText(rate) {
        const value = Number(rate);
        return Math.abs(value - Math.round(value)) < 0.05 ? `${Math.round(value)} Hz` : `${value.toFixed(2)} Hz`;
    }

    // Resolutions, biggest first; the largest is what the panel is made for
    readonly property var resolutions: {
        let seen = new Set();
        let list = [];
        for (const mode of root.selectedModes) {
            const key = `${mode.width}x${mode.height}`;
            if (seen.has(key)) continue;
            seen.add(key);
            list.push(mode);
        }
        return list.sort((a, b) => b.width * b.height - a.width * a.height);
    }
    readonly property var rates: root.selectedModes
        .filter(mode => mode.width === root.selectedMode?.width && mode.height === root.selectedMode?.height)
        .map(mode => mode.rate)
        .filter((rate, index, list) => list.indexOf(rate) === index)
        .sort((a, b) => Number(b) - Number(a))

    function setResolution(key) {
        const [width, height] = key.split("x").map(Number);
        // The fastest refresh rate this resolution has
        const best = root.selectedModes.filter(mode => mode.width === width && mode.height === height)
            .sort((a, b) => Number(b.rate) - Number(a.rate))[0];
        if (!best) return;
        const mode = `${width}x${height}@${best.rate}`;
        let changes = { mode: mode };
        // Keep the scale valid for the new size
        const scales = HyprlandMonitors.scalesFor(mode);
        if (!scales.includes(Number(root.selectedSpec.scale))) {
            changes.scale = scales.reduce((closest, scale) => Math.abs(scale - root.selectedSpec.scale) < Math.abs(closest - root.selectedSpec.scale) ? scale : closest, scales[0]);
        }
        HyprlandMonitors.change(root.selected.name, changes);
    }

    // Brightness lives in the shell, so the slider talks to it
    property var brightness: ({}) // output -> percent, -1 when it can't be changed
    function readBrightness() {
        brightnessProc.command = ["bash", "-c", root.monitors.map(m =>
            `printf '%s %s\\n' '${m.name}' "$(qs -c ii ipc call brightness get '${m.name}' 2>/dev/null || echo -1)"`).join("; ")];
        brightnessProc.running = true;
    }
    onMonitorsChanged: if (root.monitors.length > 0 && !brightnessProc.running) root.readBrightness()
    Process {
        id: brightnessProc
        stdout: StdioCollector {
            onStreamFinished: {
                let values = {};
                for (const line of text.split("\n")) {
                    const [name, value] = line.trim().split(" ");
                    if (name) values[name] = parseInt(value);
                }
                root.brightness = values;
            }
        }
    }
    Timer {
        id: brightnessTimer
        interval: 60
        property string output: ""
        property int percent: 0
        onTriggered: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "brightness", "set", output, `${percent}`])
    }

    property bool nightLightOn: false
    function readNightLight() {
        nightLightProc.running = false;
        nightLightProc.running = true;
    }
    Process {
        id: nightLightProc
        running: true
        command: ["qs", "-c", "ii", "ipc", "call", "nightLight", "isOn"]
        stdout: StdioCollector {
            onStreamFinished: root.nightLightOn = text.trim() === "true"
        }
    }
    Timer {
        id: nightLightReread
        interval: 400
        onTriggered: root.readNightLight()
    }

    readonly property var times: {
        let list = [];
        for (let minutes = 0; minutes < 24 * 60; minutes += 30) {
            const text = `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
            list.push({ displayName: text, value: text });
        }
        return list;
    }

    ContentSection {
        title: Translation.tr("Arrangement")
        description: root.monitors.length > 1
            ? Translation.tr("Drag the displays to match how they stand on your desk. Click one to change it below.")
            : Translation.tr("Connect another display to arrange them here")

        Item {
            id: arrangement
            Layout.fillWidth: true
            Layout.margins: 12
            implicitHeight: 220

            // Every output that shows something, in desktop coordinates
            readonly property var boxes: root.monitors.map(monitor => {
                const spec = HyprlandMonitors.spec(monitor);
                const size = HyprlandMonitors.logicalSize(spec);
                const position = HyprlandMonitors.position(spec);
                return { name: monitor.name, monitor: monitor, disabled: !!spec.disabled, mirrored: !!spec.mirror,
                         x: position.x, y: position.y, width: size.width, height: size.height };
            }).filter(box => !box.disabled && !box.mirrored)
            readonly property real minX: Math.min(...boxes.map(b => b.x), 0)
            readonly property real minY: Math.min(...boxes.map(b => b.y), 0)
            readonly property real maxX: Math.max(...boxes.map(b => b.x + b.width), 1)
            readonly property real maxY: Math.max(...boxes.map(b => b.y + b.height), 1)
            readonly property real zoom: Math.min((width - 24) / (maxX - minX), (height - 24) / (maxY - minY))
            readonly property real offsetX: (width - (maxX - minX) * zoom) / 2
            readonly property real offsetY: (height - (maxY - minY) * zoom) / 2

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
            }

            // Put a dropped display next to the closest edge of another one, then start the desktop at 0,0
            function drop(name, x, y) {
                const moving = boxes.find(b => b.name === name);
                const others = boxes.filter(b => b.name !== name);
                if (!moving || others.length === 0) return;
                let best = null;
                for (const other of others) {
                    const clampY = value => Math.max(other.y - moving.height + 1, Math.min(other.y + other.height - 1, value));
                    const clampX = value => Math.max(other.x - moving.width + 1, Math.min(other.x + other.width - 1, value));
                    const snap = (value, edges) => edges.reduce((current, edge) => Math.abs(edge - value) < 60 ? edge : current, value);
                    const candidates = [
                        { x: other.x + other.width, y: snap(clampY(y), [other.y, other.y + other.height - moving.height]) },
                        { x: other.x - moving.width, y: snap(clampY(y), [other.y, other.y + other.height - moving.height]) },
                        { x: snap(clampX(x), [other.x, other.x + other.width - moving.width]), y: other.y - moving.height },
                        { x: snap(clampX(x), [other.x, other.x + other.width - moving.width]), y: other.y + other.height }
                    ];
                    for (const candidate of candidates) {
                        const distance = Math.hypot(candidate.x - x, candidate.y - y);
                        if (!best || distance < best.distance) best = Object.assign({ distance: distance }, candidate);
                    }
                }
                let placed = boxes.map(b => b.name === name ? Object.assign({}, b, { x: Math.round(best.x), y: Math.round(best.y) }) : b);
                const left = Math.min(...placed.map(b => b.x));
                const top = Math.min(...placed.map(b => b.y));
                let positions = {};
                for (const box of placed) {
                    const position = `${box.x - left}x${box.y - top}`;
                    if (position !== HyprlandMonitors.spec(box.monitor).position) positions[box.name] = position;
                }
                if (Object.keys(positions).length > 0) HyprlandMonitors.arrange(positions);
            }

            Repeater {
                model: arrangement.boxes
                delegate: Rectangle {
                    id: screenBox
                    required property var modelData
                    readonly property bool isSelected: root.selected?.name === screenBox.modelData.name
                    readonly property real homeX: arrangement.offsetX + (modelData.x - arrangement.minX) * arrangement.zoom
                    readonly property real homeY: arrangement.offsetY + (modelData.y - arrangement.minY) * arrangement.zoom
                    x: homeX
                    y: homeY
                    width: modelData.width * arrangement.zoom - 4
                    height: modelData.height * arrangement.zoom - 4
                    radius: Appearance.rounding.small
                    color: screenBox.isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    border.width: screenBox.isSelected ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    z: dragArea.drag.active ? 2 : 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 2
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.isBuiltIn(screenBox.modelData.monitor) ? "laptop_chromebook" : "desktop_windows"
                            iconSize: 22
                            color: screenBox.isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: root.displayName(screenBox.modelData.monitor)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: screenBox.isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: screenBox.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: arrangement.boxes.length > 1 ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                        drag.target: arrangement.boxes.length > 1 ? screenBox : null
                        drag.threshold: 4
                        onPressed: root.selectedName = screenBox.modelData.name
                        onReleased: {
                            const moved = Math.abs(screenBox.x - screenBox.homeX) >= 2 || Math.abs(screenBox.y - screenBox.homeY) >= 2;
                            const x = (screenBox.x - arrangement.offsetX) / arrangement.zoom + arrangement.minX;
                            const y = (screenBox.y - arrangement.offsetY) / arrangement.zoom + arrangement.minY;
                            // Dragging replaced the bindings; follow the saved position again
                            screenBox.x = Qt.binding(() => screenBox.homeX);
                            screenBox.y = Qt.binding(() => screenBox.homeY);
                            if (moved) arrangement.drop(screenBox.modelData.name, x, y);
                        }
                    }
                }
            }
        }

        ConfigSelectionArray {
            visible: root.monitors.length > 1
            currentValue: root.selected?.name ?? ""
            onSelected: value => root.selectedName = value
            options: root.monitors.map(monitor => ({
                displayName: root.displayName(monitor),
                icon: root.isBuiltIn(monitor) ? "laptop_chromebook" : "desktop_windows",
                value: monitor.name
            }))
        }
    }

    ContentSection {
        visible: root.selected !== null
        title: root.displayName(root.selected)
        description: root.selected ? `${root.selected.name} · ${root.selected.make?.trim() ?? ""} ${root.selected.model?.trim() ?? ""}` : ""

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Use this display")
            description: root.enabledCount <= 1 && !root.selectedSpec?.disabled ? Translation.tr("The only display in use can't be turned off") : ""
            enabled: !(root.enabledCount <= 1 && !root.selectedSpec?.disabled)
            autoToggle: false
            checked: !root.selectedSpec?.disabled
            onClicked: HyprlandMonitors.change(root.selected.name, { disabled: checked })
        }

        ConfigComboRow {
            enabled: !root.selectedSpec?.disabled
            icon: "aspect_ratio"
            text: Translation.tr("Resolution")
            currentValue: root.selectedMode ? `${root.selectedMode.width}x${root.selectedMode.height}` : ""
            options: root.resolutions.map((mode, index) => ({
                displayName: `${mode.width} × ${mode.height}`,
                value: `${mode.width}x${mode.height}`,
                description: index === 0 ? Translation.tr("Recommended") : ""
            }))
            onSelected: value => root.setResolution(value)
        }
        ConfigComboRow {
            enabled: !root.selectedSpec?.disabled
            icon: "speed"
            text: Translation.tr("Refresh rate")
            description: Translation.tr("Higher is smoother, lower uses less power")
            currentValue: root.rates.find(rate => Math.abs(Number(rate) - Number(root.selectedMode?.rate)) < 0.05) ?? root.selectedMode?.rate
            options: root.rates.map(rate => ({ displayName: root.rateText(rate), value: rate }))
            onSelected: value => HyprlandMonitors.change(root.selected.name, { mode: `${root.selectedMode.width}x${root.selectedMode.height}@${value}` })
        }
        ConfigComboRow {
            enabled: !root.selectedSpec?.disabled
            icon: "zoom_in"
            text: Translation.tr("Scale")
            description: Translation.tr("Makes text and windows bigger. Only sizes this resolution divides into evenly are offered.")
            currentValue: Math.round(Number(root.selectedSpec?.scale ?? 1) * 1000000) / 1000000
            options: HyprlandMonitors.scalesFor(root.selectedSpec?.mode).map(scale => {
                const size = HyprlandMonitors.logicalSize(Object.assign({}, root.selectedSpec, { scale: scale, transform: 0 }));
                return { displayName: `${Math.round(scale * 100)}%`, value: scale, description: Translation.tr("Looks like %1 × %2").arg(size.width).arg(size.height) };
            })
            onSelected: value => HyprlandMonitors.change(root.selected.name, { scale: value })
        }
        ConfigComboRow {
            enabled: !root.selectedSpec?.disabled
            icon: "screen_rotation"
            text: Translation.tr("Orientation")
            currentValue: root.selectedSpec?.transform ?? 0
            options: [
                { displayName: Translation.tr("Landscape"), value: 0, icon: "crop_landscape" },
                { displayName: Translation.tr("Portrait"), value: 1, icon: "crop_portrait" },
                { displayName: Translation.tr("Landscape (flipped)"), value: 2, icon: "crop_landscape" },
                { displayName: Translation.tr("Portrait (flipped)"), value: 3, icon: "crop_portrait" }
            ]
            onSelected: value => HyprlandMonitors.change(root.selected.name, { transform: value })
        }
        ConfigComboRow {
            visible: root.monitors.length > 1
            enabled: !root.selectedSpec?.disabled
            icon: "screen_share"
            text: Translation.tr("Show the same picture as")
            description: Translation.tr("Mirrors another display instead of extending the desktop")
            currentValue: root.selectedSpec?.mirror ?? ""
            options: [
                { displayName: Translation.tr("Nothing, extend the desktop"), value: "" },
                ...root.monitors.filter(m => m.name !== root.selected?.name && !HyprlandMonitors.spec(m).mirror)
                    .map(m => ({ displayName: root.displayName(m), value: m.name, description: m.name }))
            ]
            onSelected: value => HyprlandMonitors.change(root.selected.name, { mirror: value })
        }
        ConfigComboRow {
            enabled: !root.selectedSpec?.disabled
            icon: "animation"
            text: Translation.tr("Variable refresh rate")
            description: Translation.tr("Only for displays that support it")
            currentValue: root.selectedSpec?.vrr ?? -1
            options: [
                { displayName: Translation.tr("Like the other displays"), value: -1, description: Translation.tr("Uses the setting below") },
                { displayName: Translation.tr("Off"), value: 0 },
                { displayName: Translation.tr("On"), value: 1 },
                { displayName: Translation.tr("Fullscreen only"), value: 2 }
            ]
            onSelected: value => HyprlandMonitors.change(root.selected.name, { vrr: value < 0 ? undefined : value }, false)
        }
        ConfigSlider {
            visible: (root.brightness[root.selected?.name] ?? -1) >= 0
            enabled: !root.selectedSpec?.disabled
            buttonIcon: "brightness_6"
            text: Translation.tr("Brightness")
            from: 0
            to: 100
            usePercentTooltip: false
            valueText: `${Math.round(value)}%`
            value: root.brightness[root.selected?.name] ?? 0
            onMoved: {
                brightnessTimer.output = root.selected.name;
                brightnessTimer.percent = Math.round(value);
                brightnessTimer.restart();
            }
        }
        ConfigNavRow {
            visible: Object.keys(HyprlandMonitors.overrides).length > 0
            buttonIcon: "restart_alt"
            title: Translation.tr("Go back to the config files")
            description: Translation.tr("Forget the changes made here for every display")
            trailingIcon: ""
            onClicked: HyprlandMonitors.resetAll()
        }
    }

    ContentSection {
        title: Translation.tr("Night light")
        description: Translation.tr("Warmer colors in the evening are easier on the eyes")

        ConfigSwitch {
            buttonIcon: "nightlight"
            text: Translation.tr("Night light")
            autoToggle: false
            checked: root.nightLightOn
            onClicked: {
                root.nightLightOn = !root.nightLightOn;
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "nightLight", "toggle"]);
                nightLightReread.restart();
            }
        }
        ConfigSlider {
            buttonIcon: "thermostat"
            text: Translation.tr("Color temperature")
            description: Translation.tr("Lower is warmer")
            from: 2500
            to: 6500
            usePercentTooltip: false
            valueText: `${Math.round(value / 100) * 100} K`
            value: Config.options.light.night.colorTemperature
            onMoved: Config.options.light.night.colorTemperature = Math.round(value / 100) * 100
        }
        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Turn on by schedule")
            checked: Config.options.light.night.automatic
            onCheckedChanged: Config.options.light.night.automatic = checked
        }
        ConfigComboRow {
            enabled: Config.options.light.night.automatic
            icon: "bedtime"
            text: Translation.tr("From")
            searchable: false
            maximumWidth: 140
            currentValue: Config.options.light.night.from
            options: root.times
            onSelected: value => Config.options.light.night.from = value
        }
        ConfigComboRow {
            enabled: Config.options.light.night.automatic
            icon: "wb_sunny"
            text: Translation.tr("Until")
            searchable: false
            maximumWidth: 140
            currentValue: Config.options.light.night.to
            options: root.times
            onSelected: value => Config.options.light.night.to = value
        }
    }

    ContentSection {
        title: Translation.tr("Refresh rate")
        description: Translation.tr("Variable refresh rate lowers flicker and stutter in games on displays that support it")

        HyprChoice {
            option: "misc:vrr"
            fallback: 0
            title: Translation.tr("Variable refresh rate")
            choices: [
                { displayName: Translation.tr("Off"), icon: "close", value: 0 },
                { displayName: Translation.tr("On"), icon: "check", value: 1 },
                { displayName: Translation.tr("Fullscreen only"), icon: "fullscreen", value: 2 }
            ]
        }
    }

    ContentSection {
        title: Translation.tr("Waking the screen")

        HyprSwitch {
            option: "misc:mouse_move_enables_dpms"
            fallback: true
            buttonIcon: "mouse"
            text: Translation.tr("Moving the mouse turns the screen on")
        }
        HyprSwitch {
            option: "misc:key_press_enables_dpms"
            fallback: true
            buttonIcon: "keyboard"
            text: Translation.tr("Pressing a key turns the screen on")
        }
    }

    ContentSection {
        title: Translation.tr("Look")

        ConfigNavRow {
            buttonIcon: "rounded_corner"
            title: Translation.tr("Screen corners")
            onClicked: ApplicationWindow.window?.openPage("appearance", Translation.tr("Screen corners"))
        }
        ConfigNavRow {
            buttonIcon: "edit_document"
            title: Translation.tr("Edit monitor rules by hand")
            description: "monitors.lua"
            trailingIcon: "open_in_new"
            onClicked: Qt.openUrlExternally(`file://${FileUtils.trimFileProtocol(Directories.config)}/hypr/monitors.lua`)
        }
    }

    // Asks to keep a change that could have left a screen black; goes back by itself otherwise
    Popup {
        parent: Overlay.overlay
        anchors.centerIn: parent
        visible: HyprlandMonitors.confirming
        modal: true
        closePolicy: Popup.NoAutoClose
        padding: 24
        width: 400

        background: Item {
            StyledRectangularShadow {
                target: confirmBackground
            }
            Rectangle {
                id: confirmBackground
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }
        Overlay.modal: Rectangle {
            color: Appearance.colors.colScrim
        }

        contentItem: ColumnLayout {
            spacing: 14
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Keep these display settings?")
                wrapMode: Text.Wrap
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Going back to the previous ones in %1 s").arg(HyprlandMonitors.secondsLeft)
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Go back")
                    onClicked: HyprlandMonitors.revert()
                }
                DialogButton {
                    buttonText: Translation.tr("Keep")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colEnabled: Appearance.colors.colOnPrimary
                    onClicked: HyprlandMonitors.keep()
                }
            }
        }
    }
}
