import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One navigation path for top-level pages, registered subpages and editors inside a page.
RowLayout {
    id: root

    property var entries: []
    property bool initialized: false
    property int previousDepth: 0

    signal activated(var entry)

    implicitHeight: 36
    spacing: 2

    transform: Translate {
        id: pathShift
    }

    Component.onCompleted: {
        previousDepth = entries.length;
        initialized = true;
    }
    onEntriesChanged: {
        if (!initialized)
            return;
        entrance.stop();
        pathShift.x = entries.length < previousDepth ? -8 : 8;
        opacity = 0;
        previousDepth = entries.length;
        entrance.start();
    }

    ParallelAnimation {
        id: entrance

        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
            property: "opacity"
            target: root
            to: 1
        }

        NumberAnimation {
            duration: Appearance.scaledDuration(220)
            easing.type: Easing.OutCubic
            property: "x"
            target: pathShift
            to: 0
        }
    }

    Repeater {
        model: root.entries

        delegate: Item {
            id: crumb

            required property int index
            readonly property bool last: index === root.entries.length - 1
            required property var modelData

            Layout.fillWidth: last
            Layout.maximumWidth: last ? Infinity : Math.max(60, Math.min(200, root.width
                                                                         / root.entries.length))

            Layout.minimumWidth: 0
            implicitWidth: titleButton.implicitWidth + (separator.visible ? separator.width + 2 : 0)
            implicitHeight: 36

            MaterialSymbol {
                id: separator

                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colSubtext
                iconSize: 18
                text: "chevron_right"
                visible: crumb.index > 0
                width: 18
            }

            RippleButton {
                id: titleButton

                Accessible.name: crumb.modelData.title
                x: separator.visible ? separator.width + 2 : 0
                width: Math.min(implicitWidth, Math.max(0, crumb.width - x))
                buttonRadius: Appearance.rounding.small
                hoverEnabled: true
                implicitHeight: 36
                leftPadding: 8
                objectName: "settingsBreadcrumb-" + crumb.index
                rightPadding: 8

                contentItem: StyledText {
                    color: crumb.last ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: crumb.last ? Font.DemiBold : Font.Normal
                    text: crumb.modelData.title
                }

                onClicked: root.activated(crumb.modelData)

                StyledToolTip {
                    text: crumb.modelData.title
                }
            }

        }
    }
}
