pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    objectName: "bannerPositionPicker"
    property bool shown: false
    readonly property color accent: ColorUtils.mix("#dab184", Appearance.colors.colPrimary, 0.5)
    readonly property int duration: Config.options.notifications.timeout
    readonly property string position: NotificationPreferences.corner
    property real remaining: 1
    function replay() {
        countdown.stop();
        remaining = 1;
        if (shown && Appearance.animationSpeed > 0) countdown.start();
    }
    onShownChanged: replay()
    onDurationChanged: replay()
    onPositionChanged: replay()
    Connections { target: Appearance; function onAnimationSpeedChanged() { root.replay(); } }
    NumberAnimation { id: countdown; target: root; property: "remaining"; from: 1; to: 0; duration: Math.max(1, root.duration) }
    readonly property string title: Translation.tr("Banner position")
    readonly property bool settingsSearchable: true
    readonly property string searchText: title
    readonly property var corners: [
        { key: "topLeft", label: Translation.tr("Top left") }, { key: "topRight", label: Translation.tr("Top right") },
        { key: "bottomLeft", label: Translation.tr("Bottom left") }, { key: "bottomRight", label: Translation.tr("Bottom right") }
    ]
    Layout.fillWidth: true
    implicitHeight: width >= 500 ? 184 : 156

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }
    Item {
        id: desktopStage
        anchors.fill: parent
        anchors.margins: 5
        clip: true
        readonly property string wallpaper: Config.options.background.wallpaperPath
        readonly property string still: FileUtils.isVideoPath(wallpaper) ? Config.options.background.thumbnailPath : wallpaper
        Image {
            anchors.fill: parent
            source: root.shown ? (desktopStage.still || Directories.defaultWallpaper) : ""
            sourceSize: Qt.size(820, 0)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.06, 0.05, 0.08, 0.26) }

        // The sample uses the same sender, title and message as the desktop preview.
        Item {
            id: banner
            objectName: "exampleBanner"
            width: Math.min(288, desktopStage.width * 0.65)
            height: content.implicitHeight + 22
            x: NotificationPreferences.right ? desktopStage.width - width - 16 : 16
            y: NotificationPreferences.top ? 14 : desktopStage.height - height - 14
            Behavior on x { enabled: root.shown; animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Behavior on y { enabled: root.shown; animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            Rectangle {
                x: 7; y: 6; width: parent.width - 14; height: parent.height
                radius: 14; color: ColorUtils.applyAlpha(Appearance.colors.colLayer2Base, 0.72)
            }
            Rectangle {
                anchors.fill: parent; radius: 14
                color: Appearance.colors.colLayer2Base; border.color: ColorUtils.mix(root.accent, color, 0.4)
            }
            RowLayout {
                id: content
                x: 12; y: 10; width: parent.width - 24; spacing: 10
                Rectangle {
                    implicitWidth: 31; implicitHeight: 31; radius: 10
                    color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2Base, 0.25)
                    MaterialSymbol { anchors.centerIn: parent; text: "notifications_active"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Notification preview"); elide: Text.ElideRight; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest }
                        StyledText { text: Translation.tr("Now"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest }
                    }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Test banner"); elide: Text.ElideRight; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Your notifications will appear here."); wrapMode: Text.Wrap; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.smaller }
                }
            }
            Rectangle { x: 13; y: parent.height - 3; width: (parent.width - 26) * root.remaining; height: 2; radius: 1; color: root.accent }
        }

        Repeater {
            model: root.corners
            delegate: RippleButton {
                id: cornerButton
                required property var modelData
                readonly property bool rightCorner: modelData.key.endsWith("Right")
                readonly property bool topCorner: modelData.key.startsWith("top")
                readonly property bool selected: NotificationPreferences.corner === modelData.key
                width: desktopStage.width / 2; height: desktopStage.height / 2
                x: rightCorner ? width : 0; y: topCorner ? 0 : height
                Accessible.name: modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                buttonRadius: 8
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.09)
                onClicked: Config.options.notifications.popupPosition = modelData.key
                contentItem: Item {
                    Rectangle {
                        visible: !cornerButton.selected
                        width: 23; height: 14; radius: 4
                        x: cornerButton.rightCorner ? parent.width - width - 16 : 16
                        y: cornerButton.topCorner ? 17 : parent.height - height - 17
                        color: Qt.rgba(0, 0, 0, 0.34); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.82)
                    }
                }
                StyledToolTip { text: cornerButton.modelData.label }
            }
        }
    }
}
