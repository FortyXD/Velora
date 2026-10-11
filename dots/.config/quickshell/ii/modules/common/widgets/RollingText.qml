import qs.modules.common
import QtQuick

/**
 * Text whose characters roll vertically when they change, like a mechanical counter.
 * Only the characters that changed move; digits use tabular figures so the width stays put.
 */
Row {
    id: root
    property string text
    property color color: Appearance.colors.colOnLayer1
    property real pixelSize: Appearance.font.pixelSize.small
    property string family: Appearance.font.family.numbers
    property int weight: Font.Normal
    property bool animate: true
    property bool reverse: false // Roll downwards, which reads better for countdowns
    property int duration: 260

    Repeater {
        model: root.text.length

        delegate: Item {
            id: slot
            required property int index
            readonly property string character: root.text.charAt(index)
            property string shown: character
            property string previous: ""

            implicitWidth: currentText.implicitWidth
            implicitHeight: currentText.implicitHeight
            clip: rollAnimation.running

            onCharacterChanged: {
                if (!root.animate || !root.visible) {
                    shown = character;
                    return;
                }
                previous = shown;
                shown = character;
                rollAnimation.restart();
            }

            component SlotText: Text {
                renderType: Text.NativeRendering
                color: root.color
                font {
                    family: root.family
                    pixelSize: root.pixelSize
                    weight: root.weight
                    hintingPreference: Font.PreferDefaultHinting
                    features: ({ "tnum": 1 })
                }
            }

            SlotText {
                id: outgoingText
                visible: rollAnimation.running
                text: slot.previous
            }
            SlotText {
                id: currentText
                text: slot.shown
            }

            ParallelAnimation {
                id: rollAnimation
                readonly property real distance: slot.height * (root.reverse ? -1 : 1)
                NumberAnimation {
                    target: currentText
                    property: "y"
                    from: rollAnimation.distance
                    to: 0
                    duration: root.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                NumberAnimation {
                    target: outgoingText
                    property: "y"
                    from: 0
                    to: -rollAnimation.distance
                    duration: root.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                NumberAnimation {
                    target: outgoingText
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: root.duration
                }
            }
        }
    }
}
