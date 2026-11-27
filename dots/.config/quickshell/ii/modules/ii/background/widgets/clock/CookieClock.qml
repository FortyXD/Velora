pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io

import qs.modules.ii.background.widgets.clock.dateIndicator
import qs.modules.ii.background.widgets.clock.minuteMarks

Item {
    id: root

    property var options: Config.options.background.widgets.clock.cookie
    property var colors: Appearance.colors
    property bool preview: false

    property real implicitSize: 230

    property color colShadow: root.colors.colShadow
    property color colBackground: root.colors.colPrimaryContainer
    property color colOnBackground: ColorUtils.mix(root.colors.colSecondary, root.colBackground, 0.15)
    property color colBackgroundInfo: ColorUtils.mix(root.colors.colPrimary, root.colBackground, 0.55)
    property color colHourHand: root.colors.colPrimary
    property color colMinuteHand: root.colors.colTertiary
    property color colSecondHand: root.colors.colPrimary

    readonly property list<string> clockNumbers: DateTime.time.split(/[: ]/)
    readonly property int clockHour: parseInt(clockNumbers[0]) % 12
    readonly property int clockMinute: DateTime.clock.minutes
    readonly property int clockSecond: DateTime.clock.seconds

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    function applyStyle(sides, dialStyle, hourHandStyle, minuteHandStyle, secondHandStyle, dateStyle) {
        root.options.sides = sides
        root.options.dialNumberStyle = dialStyle
        root.options.hourHandStyle = hourHandStyle
        root.options.minuteHandStyle = minuteHandStyle
        root.options.secondHandStyle = secondHandStyle
        root.options.dateStyle = dateStyle
    }

    function setClockPreset(category) {
        if (root.preview || !root.options.aiStyling) return;
        if (category === "") return;
        print("[Cookie clock] Setting clock preset for category: " + category)
        // "abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"
        if (category == "abstract") {
            applyStyle(9, "none", "fill", "medium", "dot", "bubble")
        } else if (category == "anime") {
            applyStyle(7, "none", "fill", "bold", "dot", "bubble")
        } else if (category == "city" || category == "space") {
            applyStyle(23, "full", "hollow", "thin", "classic", "bubble")
        } else if (category == "minimalist") {
            applyStyle(6, "none", "fill", "bold", "dot", "hide")
        } else if (category == "landscape") {
            applyStyle(14, "full", "hollow", "medium", "classic", "bubble")
        } else if (category == "plants") {
            applyStyle(9, "dots", "fill", "bold", "dot", "border")
        } else if (category == "person") {
            applyStyle(14, "full", "classic", "classic", "classic", "rect")
        }
    }

    FileView {
        id: categoryFileView
        path: !root.preview && Config.ready ? Directories.generatedWallpaperCategoryPath : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.setClockPreset(categoryFileView.text().trim())
        }
    }

    property bool useSineCookie: root.options.useSineCookie
    StyledDropShadow {
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        target: root.useSineCookie ? sineCookieLoader : roundedPolygonCookieLoader

        RotationAnimation on rotation {
            running: !root.preview && root.options.constantlyRotate && !PowerSaving.cutAnimations
            duration: 30000
            easing.type: Easing.Linear
            loops: Animation.Infinite
            from: 360
            to: 0
        }
    }
    Loader {
        id: sineCookieLoader
        z: 0
        visible: GraphicsInfo.api === GraphicsInfo.Software
        active: root.useSineCookie
        sourceComponent: SineCookie {
            implicitSize: root.implicitSize
            sides: root.options.sides
            color: root.colBackground
        }
    }
    Loader {
        id: roundedPolygonCookieLoader
        z: 0
        visible: GraphicsInfo.api === GraphicsInfo.Software
        active: !root.useSineCookie
        sourceComponent: MaterialCookie {
            implicitSize: root.implicitSize
            sides: root.options.sides
            color: root.colBackground
        }
    }

    // Hour/minutes numbers/dots/lines
    MinuteMarks {
        style: root.options.dialNumberStyle
        dateStyle: root.options.dateStyle
        anchors.fill: parent
        color: root.colOnBackground
    }

    // Stupid extra hour marks in the middle
    FadeLoader {
        id: hourMarksLoader
        anchors.centerIn: parent
        shown: root.options.hourMarks
        sourceComponent: HourMarks {
            implicitSize: 135 * (1.75 - 0.75 * hourMarksLoader.opacity)
            color: root.colOnBackground
            colOnBackground: ColorUtils.mix(root.colBackgroundInfo, root.colOnBackground, 0.5)
        }
    }

    // Number column in the middle
    FadeLoader {
        id: timeColumnLoader
        anchors.centerIn: parent
        shown: root.options.timeIndicators
        scale: 1.4 - 0.4 * timeColumnLoader.shown
        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        sourceComponent: TimeColumn {
            isEnabled: root.options.timeIndicators
            hourMarksEnabled: root.options.hourMarks
            color: root.colBackgroundInfo
        }
    }

    // Minute hand
    FadeLoader {
        anchors.fill: parent
        z: 1
        shown: root.options.minuteHandStyle !== "hide"
        sourceComponent: MinuteHand {
            anchors.fill: parent
            clockMinute: root.clockMinute
            style: root.options.minuteHandStyle
            color: root.colMinuteHand
        }
    }

    // Hour hand
    FadeLoader {
        anchors.fill: parent
        z: item?.style === "hollow" ? 0 : 2
        shown: root.options.hourHandStyle !== "hide"
        sourceComponent: HourHand {
            clockHour: root.clockHour
            clockMinute: root.clockMinute
            style: root.options.hourHandStyle
            color: root.colHourHand
        }
    }

    // Second hand
    FadeLoader {
        id: secondHandLoader
        z: (root.options.secondHandStyle === "line") ? 2 : 3
        shown: Config.options.time.secondPrecision && root.options.secondHandStyle !== "hide"
        anchors.fill: parent
        sourceComponent: SecondHand {
            id: secondHand
            clockSecond: root.clockSecond
            style: root.options.secondHandStyle
            color: root.colSecondHand
        }
    }

    // Center dot
    FadeLoader {
        z: 4
        anchors.centerIn: parent
        shown: root.options.minuteHandStyle !== "bold"
        sourceComponent: Rectangle {
            color: root.options.minuteHandStyle === "medium" ? root.colBackground : root.colMinuteHand
            implicitWidth: 6
            implicitHeight: implicitWidth
            radius: width / 2
        }
    }

    // Date
    FadeLoader {
        anchors.fill: parent
        shown: root.options.dateStyle !== "hide"

        sourceComponent: DateIndicator {
            colors: root.colors
            color: root.colBackgroundInfo
            style: root.options.dateStyle
        }
    }
}
