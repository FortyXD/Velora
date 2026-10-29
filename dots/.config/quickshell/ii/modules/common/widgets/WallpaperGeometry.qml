import QtQml

// All dimensions are logical pixels, except for the image's intrinsic size.
// Keep cover scaling reactive to hotplug, output mode and fractional scale changes.
QtObject {
    property real viewportWidth: 1
    property real viewportHeight: 1
    property real imageWidth: 0
    property real imageHeight: 0
    property real zoom: 1

    readonly property bool hasImageSize: isFinite(imageWidth) && imageWidth > 0
        && isFinite(imageHeight) && imageHeight > 0
    readonly property real sourceWidth: hasImageSize ? imageWidth : Math.max(1, viewportWidth)
    readonly property real sourceHeight: hasImageSize ? imageHeight : Math.max(1, viewportHeight)
    readonly property real coverScale: Math.max(Math.max(1, viewportWidth) / sourceWidth,
        Math.max(1, viewportHeight) / sourceHeight)
    // Even malformed settings must not expose empty edges.
    readonly property real effectiveScale: coverScale * (isFinite(zoom) ? Math.max(1, zoom) : 1)
    readonly property real scaledWidth: sourceWidth * effectiveScale
    readonly property real scaledHeight: sourceHeight * effectiveScale
}
