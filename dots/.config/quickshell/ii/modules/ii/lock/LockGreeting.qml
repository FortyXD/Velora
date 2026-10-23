import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * "Good evening, Name" with the user's picture (~/.face or the AccountsService icon), or their initial.
 */
RowLayout {
    id: root
    readonly property bool hasContent: true
    readonly property string name: {
        const user = SystemInfo.username;
        return user.length > 0 ? user.charAt(0).toUpperCase() + user.slice(1) : "";
    }
    readonly property string greeting: {
        const hour = DateTime.clock.hours;
        if (hour < 5) return Translation.tr("Good night");
        if (hour < 12) return Translation.tr("Good morning");
        if (hour < 18) return Translation.tr("Good afternoon");
        return Translation.tr("Good evening");
    }
    // The first picture that exists: ~/.face, ~/.face.icon or the AccountsService icon
    property string picture: ""
    Process {
        running: true
        command: ["bash", "-c", `for f in ~/.face ~/.face.icon /var/lib/AccountsService/icons/"$USER"; do [ -r "$f" ] && echo "$f" && break; done`]
        stdout: StdioCollector {
            onStreamFinished: root.picture = text.trim()
        }
    }

    spacing: 16

    Item {
        implicitWidth: 64
        implicitHeight: 64
        MaterialShape {
            anchors.fill: parent
            visible: avatar.status !== Image.Ready
            shape: MaterialShape.Shape.Cookie9Sided
            implicitSize: 64
            color: Appearance.colors.colPrimaryContainer
            StyledText {
                anchors.centerIn: parent
                text: root.name.charAt(0)
                font.pixelSize: 28
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
        Image {
            id: avatar
            anchors.fill: parent
            visible: false
            source: root.picture.length > 0 ? `file://${root.picture}` : ""
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        OpacityMask {
            anchors.fill: parent
            visible: avatar.status === Image.Ready
            source: avatar
            maskSource: Rectangle {
                width: 64
                height: 64
                radius: 32
            }
        }
    }

    ColumnLayout {
        spacing: -2
        StyledText {
            text: `${root.greeting},`
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer0
            style: Text.Raised
            styleColor: ColorUtils.transparentize(Appearance.colors.colShadow, 0.5)
        }
        StyledText {
            text: root.name
            font.pixelSize: 34
            font.family: Appearance.font.family.title
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
            style: Text.Raised
            styleColor: ColorUtils.transparentize(Appearance.colors.colShadow, 0.5)
        }
    }
}
