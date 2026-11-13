import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property var paths: []
    property bool removable: false
    property bool previews: false
    signal removed(int index)
    spacing: 6
    Repeater {
        model: root.paths
        delegate: Rectangle {
            id: attachment
            required property string modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: 52
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            RowLayout {
                anchors { fill: parent; margins: 8 }
                spacing: 8
                Loader {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36
                    sourceComponent: root.previews && /\.(png|jpe?g|webp|gif)$/i.test(attachment.modelData) ? previewComponent : iconComponent
                    Component { id: previewComponent; Image { source: "file://" + attachment.modelData; sourceSize.width: 72; sourceSize.height: 72; fillMode: Image.PreserveAspectFit; asynchronous: true } }
                    Component { id: iconComponent; MaterialSymbol { text: "draft"; iconSize: 24 } }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: attachment.modelData.split("/").pop()
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.small
                    HoverHandler { id: fileHover }
                    StyledToolTip { text: attachment.modelData; alternativeVisibleCondition: fileHover.hovered }
                }
                ChatIconButton { visible: root.removable; symbol: "close"; tooltip: Translation.tr("Remove attachment"); onClicked: root.removed(attachment.index) }
            }
        }
    }
}
