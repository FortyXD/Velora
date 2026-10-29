pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import QtQuick
import QtQuick.Layouts

/**
 * Screens. Each one gets its sharpest mode, its fastest refresh and a scale for its size as soon as the
 * step opens (gone again by itself unless kept, HyprlandMonitors' countdown). The screens are drawn as
 * they're arranged: drag one beside another, pick one to change its resolution and size, or show
 * their names on the screens themselves.
 */
PageScaffold {
    id: root
    title: Translation.tr("Your screens")
    subtitle: Translation.tr("Set up for their size and sharpness. Drag them to match your desk, pick one to change it.")
    scrollable: true

    readonly property bool checked: root.flow.displayChecked
    property string selected: ""
    readonly property var monitors: HyprlandMonitors.monitors.filter(monitor => !monitor.disabled)
    readonly property var selectedMonitor: root.monitors.find(monitor => monitor.name === root.selected) ?? root.monitors[0] ?? null

    function bestMode(monitor) {
        const modes = HyprlandMonitors.modes(monitor);
        modes.sort((a, b) => (b.width * b.height - a.width * a.height) || (Number(b.rate) - Number(a.rate)));
        const best = modes[0];
        return best ? `${best.width}x${best.height}@${best.rate}` : "";
    }
    // Comfortable text: about 160 dots per inch on a laptop held close, 110 on a monitor further away
    function recommendedScale(monitor, mode) {
        const parsed = HyprlandMonitors.parseMode(mode);
        const millimeters = monitor.physicalWidth ?? 0;
        if (!parsed || !(millimeters > 0)) return 1;
        const dpi = parsed.width / (millimeters / 25.4);
        const builtIn = /^(eDP|LVDS|DSI)/.test(monitor.name);
        const wanted = Math.max(1, dpi / (builtIn ? 160 : 110));
        const scales = HyprlandMonitors.scalesFor(mode);
        return scales.reduce((best, scale) => Math.abs(scale - wanted) < Math.abs(best - wanted) ? scale : best, scales[0] ?? 1);
    }
    function change(name, changes) {
        if (root.flow.dryRun) console.info("[Onboarding] Would change", name, JSON.stringify(changes));
        else HyprlandMonitors.change(name, changes, true);
    }
    function applyRecommended() {
        if (root.checked || root.flow.step !== "display") return;
        for (const monitor of HyprlandMonitors.monitors) {
            if (monitor.disabled) continue;
            const mode = root.bestMode(monitor);
            if (!mode) continue;
            const scale = root.recommendedScale(monitor, mode);
            const current = HyprlandMonitors.parseMode(HyprlandMonitors.spec(monitor).mode);
            const wanted = HyprlandMonitors.parseMode(mode);
            const same = current?.width === wanted?.width && current?.height === wanted?.height
                && Math.abs(Number(current?.rate) - Number(wanted?.rate)) < 1
                && Math.abs(Number(HyprlandMonitors.spec(monitor).scale) - scale) < 0.01;
            if (!same) root.change(monitor.name, { "mode": mode, "scale": scale });
        }
        root.flow.displayChecked = true;
    }
    Connections {
        target: HyprlandMonitors
        function onReadyChanged() {
            if (HyprlandMonitors.ready && !root.checked) root.applyRecommended();
        }
    }
    Component.onCompleted: {
        if (HyprlandMonitors.ready) root.applyRecommended();
        else HyprlandMonitors.refresh();
    }

    // Kept, or back on their own
    Reveal {
        order: 1
        visible: HyprlandMonitors.confirming
        Rectangle {
            width: parent.width
            implicitHeight: confirmRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer
            RowLayout {
                id: confirmRow
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 16
                spacing: 12
                CircularProgress {
                    implicitSize: 28
                    lineWidth: 3
                    value: HyprlandMonitors.secondsLeft / HyprlandMonitors.confirmSeconds
                    colPrimary: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Does it look right? Otherwise it goes back in %1 s").arg(HyprlandMonitors.secondsLeft)
                    color: Appearance.colors.colOnSecondaryContainer
                }
                RippleButton {
                    implicitHeight: 36
                    implicitWidth: revertText.implicitWidth + 28
                    buttonRadius: height / 2
                    onClicked: HyprlandMonitors.revert()
                    contentItem: StyledText {
                        id: revertText
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Go back")
                    }
                }
                RippleButton {
                    implicitHeight: 36
                    implicitWidth: keepText.implicitWidth + 28
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: HyprlandMonitors.keep()
                    contentItem: StyledText {
                        id: keepText
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Keep")
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // The desk: screens as they're arranged, to scale
    Reveal {
        order: 2
        Rectangle {
            id: desk
            width: parent.width
            implicitHeight: 250
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            readonly property var boxes: root.monitors.map(monitor => {
                const spec = HyprlandMonitors.spec(monitor);
                const size = HyprlandMonitors.logicalSize(spec);
                const position = HyprlandMonitors.position(spec);
                return { "name": monitor.name, "x": position.x, "y": position.y, "w": size.width, "h": size.height, "monitor": monitor };
            })
            readonly property real minX: Math.min(...desk.boxes.map(box => box.x), 0)
            readonly property real minY: Math.min(...desk.boxes.map(box => box.y), 0)
            readonly property real spanX: Math.max(...desk.boxes.map(box => box.x + box.w), 1) - desk.minX
            readonly property real spanY: Math.max(...desk.boxes.map(box => box.y + box.h), 1) - desk.minY
            // Room above for the button, around for dragging
            readonly property real unit: Math.min((width - 80) / desk.spanX, (height - 90) / desk.spanY)
            readonly property real offsetX: (width - desk.spanX * desk.unit) / 2
            readonly property real offsetY: 50 + (height - 70 - desk.spanY * desk.unit) / 2

            // Dropped near another screen: put beside it, edges touching
            function place(name, centerX, centerY) {
                const others = desk.boxes.filter(box => box.name !== name);
                const moved = desk.boxes.find(box => box.name === name);
                if (!moved || others.length === 0) return;
                const anchor = others.reduce((best, box) => {
                    const distance = Math.hypot(box.x + box.w / 2 - centerX, box.y + box.h / 2 - centerY);
                    return distance < best.distance ? { "box": box, "distance": distance } : best;
                }, { "box": others[0], "distance": Infinity }).box;
                const dx = centerX - (anchor.x + anchor.w / 2), dy = centerY - (anchor.y + anchor.h / 2);
                let x, y;
                if (Math.abs(dx) / anchor.w > Math.abs(dy) / anchor.h) {
                    x = dx > 0 ? anchor.x + anchor.w : anchor.x - moved.w;
                    y = anchor.y;
                } else {
                    x = anchor.x;
                    y = dy > 0 ? anchor.y + anchor.h : anchor.y - moved.h;
                }
                const positions = {};
                positions[name] = `${Math.round(x)}x${Math.round(y)}`;
                if (root.flow.dryRun) console.info("[Onboarding] Would arrange", JSON.stringify(positions));
                else HyprlandMonitors.arrange(positions);
            }

            Repeater {
                model: desk.boxes
                delegate: Rectangle {
                    id: screenBox
                    required property var modelData
                    readonly property bool chosen: (root.selectedMonitor?.name ?? "") === modelData.name
                    readonly property real homeX: desk.offsetX + (modelData.x - desk.minX) * desk.unit
                    readonly property real homeY: desk.offsetY + (modelData.y - desk.minY) * desk.unit
                    x: homeX
                    y: homeY
                    width: modelData.w * desk.unit
                    height: modelData.h * desk.unit
                    radius: Appearance.rounding.small
                    color: chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    z: drag.drag.active ? 2 : 1
                    Behavior on x { enabled: !drag.drag.active; NumberAnimation { duration: Motion.ms(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
                    Behavior on y { enabled: !drag.drag.active; NumberAnimation { duration: Motion.ms(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial } }
                    Behavior on color { ColorAnimation { duration: Motion.ms(200) } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: /^(eDP|LVDS|DSI)/.test(screenBox.modelData.name) ? "laptop" : "desktop_windows"
                            iconSize: 22
                            color: screenBox.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: screenBox.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: screenBox.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${Math.round(screenBox.modelData.w)} × ${Math.round(screenBox.modelData.h)}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: screenBox.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        cursorShape: drag.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: desk.boxes.length > 1 ? screenBox : null
                        onPressed: root.selected = screenBox.modelData.name
                        onReleased: {
                            if (!drag.drag.active && Math.abs(screenBox.x - screenBox.homeX) < 4) return;
                            const centerX = (screenBox.x + screenBox.width / 2 - desk.offsetX) / desk.unit + desk.minX;
                            const centerY = (screenBox.y + screenBox.height / 2 - desk.offsetY) / desk.unit + desk.minY;
                            screenBox.x = Qt.binding(() => screenBox.homeX);
                            screenBox.y = Qt.binding(() => screenBox.homeY);
                            desk.place(screenBox.modelData.name, centerX, centerY);
                        }
                    }
                }
            }

            RippleButton {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                implicitHeight: 32
                implicitWidth: identifyRow.implicitWidth + 24
                buttonRadius: height / 2
                colBackground: Appearance.colors.colLayer2
                onClicked: root.flow.identify()
                contentItem: RowLayout {
                    id: identifyRow
                    spacing: 6
                    MaterialSymbol {
                        Layout.leftMargin: 12
                        text: "tv_signin"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.rightMargin: 12
                        text: Translation.tr("Show names on the screens")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    // The chosen screen
    Reveal {
        order: 3
        visible: root.selectedMonitor !== null
        ColumnLayout {
            id: chosen
            width: parent.width
            spacing: 12
            readonly property var monitor: root.selectedMonitor
            readonly property var spec: monitor ? HyprlandMonitors.spec(monitor) : null
            readonly property string recommended: monitor ? `${root.recommendedScale(monitor, spec?.mode)}` : "1"

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                StyledText {
                    Layout.fillWidth: true
                    text: [chosen.monitor?.make, chosen.monitor?.model].filter(part => part && part.length > 0).join(" ")
                        || (chosen.monitor?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                StyledText {
                    text: Translation.tr("Resolution")
                    color: Appearance.colors.colSubtext
                }
                ChoiceDropdown {
                    id: modes
                    readonly property var monitor: chosen.monitor
                    options: HyprlandMonitors.modes(modes.monitor).map(mode => ({
                        "displayName": Translation.tr("%1 × %2 · %3 Hz").arg(mode.width).arg(mode.height).arg(Math.round(Number(mode.rate))),
                        "value": `${mode.width}x${mode.height}@${mode.rate}`
                    }))
                    currentValue: (() => {
                        const current = HyprlandMonitors.parseMode(chosen.spec?.mode);
                        const match = HyprlandMonitors.modes(modes.monitor).find(mode => mode.width === current?.width && mode.height === current?.height
                            && Math.abs(Number(mode.rate) - Number(current?.rate)) < 1);
                        return match ? `${match.width}x${match.height}@${match.rate}` : undefined;
                    })()
                    onSelected: value => root.change(modes.monitor.name, { "mode": value })
                }
            }
            // Size of everything: whole-pixel scales, the recommended one marked
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: HyprlandMonitors.scalesFor(chosen.spec?.mode)
                    delegate: SelectCard {
                        id: scaleCard
                        required property real modelData
                        width: 92
                        height: 64
                        radius: Appearance.rounding.normal
                        selected: Math.abs(Number(chosen.spec?.scale) - scaleCard.modelData) < 0.01
                        onClicked: root.change(chosen.monitor.name, { "scale": scaleCard.modelData })
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: `${Math.round(scaleCard.modelData * 100)}%`
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: `${scaleCard.modelData}` === chosen.recommended
                                text: Translation.tr("recommended")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
