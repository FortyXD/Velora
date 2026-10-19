import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Current download and upload speed
Item {
    id: root

    property var host: null
    readonly property bool showDownload: host?.options?.showDownload ?? true
    readonly property bool showUpload: host?.options?.showUpload ?? true
    readonly property color textColor: host?.inPill ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer0

    Component.onCompleted: NetworkSpeed.users += 1
    Component.onDestruction: NetworkSpeed.users -= 1

    implicitWidth: row.implicitWidth + 8
    implicitHeight: Appearance.sizes.baseBarHeight

    component Rate: RowLayout {
        required property string icon
        required property real rate
        spacing: 1
        MaterialSymbol {
            text: parent.icon
            iconSize: Appearance.font.pixelSize.normal
            color: root.textColor
        }
        StyledText {
            // Fixed width so the bar doesn't jitter as the numbers change
            Layout.preferredWidth: rateMetrics.width
            text: NetworkSpeed.format(parent.rate)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.features: { "tnum": 1 }
            color: root.textColor
        }
    }

    TextMetrics {
        id: rateMetrics
        font.pixelSize: Appearance.font.pixelSize.smaller
        text: "000 KB/s"
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rate {
            visible: root.showDownload
            icon: "arrow_downward"
            rate: NetworkSpeed.downloadRate
        }
        Rate {
            visible: root.showUpload
            icon: "arrow_upward"
            rate: NetworkSpeed.uploadRate
        }
    }
}
