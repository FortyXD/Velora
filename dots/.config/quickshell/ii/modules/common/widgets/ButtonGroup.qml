import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A container that supports GroupButton children for bounciness.
 * See https://m3.material.io/components/button-groups/overview
 */
Rectangle {
    id: root
    default property alias groupData: rowLayout.data
    property alias uniformCellSizes: rowLayout.uniformCellSizes
    property real spacing: 5
    property real padding: 0
    property alias clickIndex: rowLayout.clickIndex
    property alias childrenCount: rowLayout.childrenCount

    readonly property var visibleChildren: rowLayout.children.filter(child =>
        child.visible && (child.baseWidth ?? child.implicitWidth ?? child.width) > 0)
    property real contentWidth: {
        let total = 0;
        for (const child of visibleChildren)
            total += child.baseWidth ?? child.implicitWidth ?? child.width;
        return total + rowLayout.spacing * Math.max(0, visibleChildren.length - 1);
    }

    topLeftRadius: visibleChildren.length > 0 ? ((visibleChildren[0].radius ?? Appearance.rounding.small) + padding) :
        Appearance?.rounding?.small
    bottomLeftRadius: topLeftRadius
    topRightRadius: visibleChildren.length > 0 ? ((visibleChildren[visibleChildren.length - 1].radius ?? Appearance.rounding.small) + padding) :
        Appearance?.rounding?.small
    bottomRightRadius: topRightRadius

    color: "transparent"
    width: root.contentWidth + padding * 2
    implicitHeight: rowLayout.implicitHeight + padding * 2
    implicitWidth: root.contentWidth + padding * 2
    
    children: [RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
        property int clickIndex: -1
        property int childrenCount: children.length
    }]
}
