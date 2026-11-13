import QtQuick

/**
 * MouseArea.containsMouse is press-scoped when hoverEnabled is false. Remember
 * that accepted press, but measure the actual pointer separately so releasing
 * in place does not dismiss a click-opened popup. Never take the owner's clicks.
 * Synthetic anchors (workspace previews) and ordinary hover targets are unchanged.
 */
Item {
    id: root

    property Item target
    readonly property bool clickToShow: target?.hoverEnabled === false
    property bool clickArmed: false
    readonly property bool containsMouse: enabled && !!target && target.enabled && (clickToShow
        ? clickArmed && (target.pressed ? !!target.containsMouse : pointer.hovered)
        : !!target.containsMouse)

    onTargetChanged: clickArmed = false
    onClickToShowChanged: clickArmed = false
    onEnabledChanged: clickArmed = false

    HoverHandler {
        id: pointer
        parent: root.target
        enabled: root.enabled && !!root.target && root.target.enabled && root.clickToShow
        blocking: false
        onHoveredChanged: {
            if (!hovered) root.clickArmed = false;
        }
    }

    Connections {
        target: root.target
        ignoreUnknownSignals: true // Synthetic anchors are Items, not MouseAreas
        function onEnabledChanged() {
            if (!root.target.enabled) root.clickArmed = false;
        }
        function onCanceled() { root.clickArmed = false; }
        function onContainsMouseChanged() {
            // During a grab HoverHandler can stay hovered outside the MouseArea.
            if (root.clickToShow && root.target.pressed && !root.target.containsMouse)
                root.clickArmed = false;
        }
        function onPressedChanged() {
            if (!root.enabled || !root.clickToShow) return;
            if (root.target.pressed) root.clickArmed = true;
            else if (!pointer.hovered) root.clickArmed = false;
        }
    }
}
