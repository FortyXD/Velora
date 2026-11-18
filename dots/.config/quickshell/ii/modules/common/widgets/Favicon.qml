import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell.Widgets

IconImage {
    id: root
    property string url
    property string displayText

    property real size: 32
    readonly property string domainName: {
        const host = StringUtils.parseWebUrl(root.url)?.hostname ?? "";
        if (host === "vertexaisearch.cloud.google.com")
            return (StringUtils.parseWebUrl(root.displayText) ?? StringUtils.parseWebUrl("https://" + root.displayText))?.hostname ?? "";
        return host;
    }

    CachedWebImage {
        id: favicon
        sourceUrl: root.domainName ? "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(root.domainName) + "&sz=32" : ""
        cacheDirectory: Directories.favicons
        maxBytes: 256 * 1024
    }
    source: favicon.fileUrl
    implicitSize: root.size

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.implicitSize
            height: root.implicitSize
            radius: Appearance.rounding.full
        }
    }
}
