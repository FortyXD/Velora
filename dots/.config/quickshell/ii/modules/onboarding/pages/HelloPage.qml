pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

/**
 * The greeting, in Velora's own motion: colored light drifts around the middle, the V is drawn in one
 * stroke, then sends out soft rings — the same wave that carries a new look across the screen — while
 * "hello" falls into place letter by letter in one language after another. "Start" grows into the
 * setup's sheet (the host takes its geometry from `startButton`).
 */
Item {
    id: root
    required property var flow
    property alias startButton: start
    signal started()

    readonly property var words: ["Привет", "Hello", "Hola", "Bonjour", "Hallo", "Ciao", "Olá", "Merhaba", "Cześć", "Привіт", "こんにちは", "안녕하세요"]
    property int wordIndex: 0
    property bool intro: true // Until the V is drawn

    // Light: three soft colors circling the middle, slowly
    Item {
        id: light
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: lightIn.start()
        NumberAnimation on opacity { id: lightIn; running: false; to: 1; duration: Motion.ms(1600); easing.type: Easing.OutCubic }
        property real turn: 0
        NumberAnimation on turn {
            running: !Motion.reduced
            from: 0
            to: Math.PI * 2
            duration: 42000
            loops: Animation.Infinite
        }
        Repeater {
            model: [
                { "color": Appearance.colors.colPrimary, "radius": 0.42, "orbit": 0.14, "phase": 0 },
                { "color": Appearance.colors.colTertiary, "radius": 0.34, "orbit": 0.2, "phase": 2.1 },
                { "color": Appearance.colors.colSecondary, "radius": 0.3, "orbit": 0.17, "phase": 4.2 },
            ]
            delegate: Shape {
                id: orb
                required property var modelData
                required property int index
                readonly property real size: Math.min(root.width, root.height) * modelData.radius * 2
                readonly property real angle: light.turn * (index % 2 ? -1 : 1) + modelData.phase
                width: size
                height: size
                x: root.width / 2 - size / 2 + Math.cos(angle) * root.width * modelData.orbit
                y: root.height * 0.42 - size / 2 + Math.sin(angle) * root.height * modelData.orbit
                opacity: 0.38
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: orb.size / 2; centerY: orb.size / 2
                        centerRadius: orb.size / 2
                        focalX: orb.size / 2; focalY: orb.size / 2
                        GradientStop { position: 0; color: orb.modelData.color }
                        GradientStop { position: 0.55; color: ColorUtils.transparentize(orb.modelData.color, 0.7) }
                        GradientStop { position: 1; color: ColorUtils.transparentize(orb.modelData.color, 1) }
                    }
                    PathAngleArc {
                        centerX: orb.size / 2; centerY: orb.size / 2
                        radiusX: orb.size / 2; radiusY: orb.size / 2
                        startAngle: 0; sweepAngle: 360
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        spacing: 26

        Item {
            id: mark
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 120
            implicitHeight: 120

            // Rings going out from the V, like the wave of a new look
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: ring
                    required property int index
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    opacity: 0
                    visible: !Motion.reduced
                    SequentialAnimation {
                        running: !root.intro && !Motion.reduced
                        loops: Animation.Infinite
                        PauseAnimation { duration: ring.index * 900 }
                        ParallelAnimation {
                            NumberAnimation { target: ring; property: "scale"; from: 0.7; to: 3.2; duration: 2700; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring; property: "opacity"; from: 0.5; to: 0; duration: 2700; easing.type: Easing.OutQuad }
                        }
                        PauseAnimation { duration: (2 - ring.index) * 900 }
                    }
                }
            }

            // The V, drawn in one stroke: down the left side, around the point, up the right
            Shape {
                id: v
                anchors.centerIn: parent
                width: 100
                height: 100
                scale: 0.84
                preferredRendererType: Shape.CurveRenderer
                property real drawn: 0
                // 0…0.5 the left stroke, 0.5…1 the right one
                readonly property real leftPart: Math.min(1, drawn / 0.5)
                readonly property real rightPart: Math.max(0, (drawn - 0.5) / 0.5)
                ShapePath {
                    strokeColor: Appearance.colors.colPrimary
                    strokeWidth: 14
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 7
                    startY: 21
                    PathLine { x: 7 + (45 - 7) * v.leftPart; y: 21 + (85.3 - 21) * v.leftPart }
                }
                ShapePath {
                    strokeColor: v.rightPart > 0 ? Appearance.colors.colPrimary : "transparent"
                    strokeWidth: 14
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 45
                    startY: 85.3
                    PathQuad { controlX: 48.3; controlY: 90.9; x: 51.7; y: 85.3 }
                    PathLine { x: 51.7 + (93.3 - 51.7) * v.rightPart; y: 85.3 + (13.1 - 85.3) * v.rightPart }
                }
                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: Motion.ms(250) }
                    NumberAnimation { target: v; property: "drawn"; from: 0; to: 1; duration: Motion.ms(1100); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                    // A small breath once it's whole
                    NumberAnimation { target: v; property: "scale"; to: 0.94; duration: Motion.ms(220); easing.type: Easing.OutCubic }
                    NumberAnimation { target: v; property: "scale"; to: 0.84; duration: Motion.ms(520); easing.type: Easing.OutBack }
                    ScriptAction { script: root.intro = false }
                }
            }
        }

        // "Hello", letter by letter: they drop in with a little bounce and leave upward
        Item {
            id: greeting
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 560
            implicitHeight: 112
            property var letters: Array.from(root.words[root.wordIndex])
            property bool leaving: false

            Row {
                id: letters
                anchors.centerIn: parent
                Repeater {
                    model: greeting.letters
                    delegate: StyledText {
                        id: letter
                        required property string modelData
                        required property int index
                        text: modelData
                        font.family: Appearance.font.family.title
                        font.pixelSize: 88
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        opacity: 0
                        transform: Translate { id: lift; y: Motion.travel(-26) }
                        SequentialAnimation {
                            id: arrive
                            running: !root.intro
                            PauseAnimation { duration: letter.index * Motion.ms(45) }
                            ParallelAnimation {
                                NumberAnimation { target: letter; property: "opacity"; to: 1; duration: Motion.ms(260) }
                                NumberAnimation { target: lift; property: "y"; to: 0; duration: Motion.ms(620); easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            }
                        }
                        Connections {
                            target: greeting
                            function onLeavingChanged() {
                                if (greeting.leaving) depart.start();
                            }
                        }
                        SequentialAnimation {
                            id: depart
                            PauseAnimation { duration: letter.index * Motion.ms(30) }
                            ParallelAnimation {
                                NumberAnimation { target: letter; property: "opacity"; to: 0; duration: Motion.ms(240) }
                                NumberAnimation { target: lift; property: "y"; to: Motion.travel(22); duration: Motion.ms(300); easing.type: Easing.InCubic }
                            }
                        }
                    }
                }
            }
            Timer {
                running: !root.intro
                interval: 2600
                repeat: true
                onTriggered: {
                    greeting.leaving = true;
                    next.restart();
                }
            }
            Timer {
                id: next
                interval: Motion.ms(30 * greeting.letters.length + 320)
                onTriggered: {
                    greeting.leaving = false;
                    root.wordIndex = (root.wordIndex + 1) % root.words.length;
                }
            }
        }

        StyledText {
            id: tagline
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Welcome to Velora. A few choices, and the desktop is yours.")
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
            opacity: 0
            NumberAnimation on opacity { running: !root.intro; to: 0.82; duration: Motion.ms(700) }
        }

        RippleButton {
            id: start
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 14
            implicitWidth: 220
            implicitHeight: 56
            buttonRadius: height / 2
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            focus: true
            opacity: 0
            scale: 0.9
            NumberAnimation on opacity { running: !root.intro; to: 1; duration: Motion.ms(400) }
            NumberAnimation on scale { running: !root.intro; to: 1; duration: Motion.ms(600); easing.type: Easing.OutBack }
            Keys.onReturnPressed: root.started()
            Keys.onEnterPressed: root.started()
            onClicked: root.started()
            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Start")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimary
            }
            // A soft halo that breathes, so it's clear where to go
            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: parent.width + 18
                height: parent.height + 18
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.55)
                visible: !Motion.reduced
                SequentialAnimation on opacity {
                    running: !root.intro && !Motion.reduced
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 36
            implicitWidth: skipText.implicitWidth + 28
            buttonRadius: height / 2
            opacity: root.intro ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: Motion.ms(600) }
            }
            onClicked: root.flow.skip()
            contentItem: StyledText {
                id: skipText
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Skip setup")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
