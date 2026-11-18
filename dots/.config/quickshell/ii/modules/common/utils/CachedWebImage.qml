pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common.functions

Instantiator {
    id: root
    required property string sourceUrl
    required property string cacheDirectory
    property int maxBytes: 32 * 1024 * 1024
    readonly property url fileUrl: object?.ready && object.sourceUrl === sourceUrl ? Qt.resolvedUrl(object.filePath) : ""

    model: StringUtils.parseWebUrl(sourceUrl) ? [sourceUrl] : []
    delegate: ImageDownloaderProcess {
        required property string modelData
        property bool ready: false
        sourceUrl: modelData
        filePath: root.cacheDirectory + "/" + Qt.md5(modelData)
        maxBytes: root.maxBytes
        onExited: (code, status) => ready = code === 0 && status === 0
    }
}
