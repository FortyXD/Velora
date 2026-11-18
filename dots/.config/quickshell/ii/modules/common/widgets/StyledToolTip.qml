import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false

    readonly property bool internalVisibleCondition: !!parent && ((extraVisibleCondition && (parent.hovered === undefined || parent.hovered)) || alternativeVisibleCondition)
    readonly property var paneBounds: visible ? parent?.Window.window?.popupBoundsFor?.(parent) : null
    leftMargin: margins + (paneBounds?.left ?? 0)
    rightMargin: margins + (paneBounds?.right ?? 0)
    topMargin: margins + (paneBounds?.top ?? 0)
    bottomMargin: margins + (paneBounds?.bottom ?? 0)
    verticalPadding: 6
    horizontalPadding: 10
    background: null
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.popup.captionSize ?? 12
        hintingPreference: Font.PreferNoHinting // Prevent shaky text
    }

    delay: 0
    visible: internalVisibleCondition
    
    contentItem: StyledToolTipContent {
        id: contentItem
        font: root.font
        text: root.text
        shown: root.internalVisibleCondition
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
        maximumWidth: root.paneBounds ? Math.max(0, root.paneBounds.width - 2 * root.margins - root.leftPadding - root.rightPadding) : Infinity
    }
}
