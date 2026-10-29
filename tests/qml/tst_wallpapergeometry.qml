import QtQuick
import QtTest

TestCase {
    name: "WallpaperGeometry"
    WallpaperGeometry { id: geometry }

    function init() {
        geometry.viewportWidth = 1920;
        geometry.viewportHeight = 1080;
        geometry.imageWidth = 3840;
        geometry.imageHeight = 2160;
        geometry.zoom = 1;
    }

    function coversViewport() {
        verify(isFinite(geometry.scaledWidth));
        verify(isFinite(geometry.scaledHeight));
        verify(geometry.scaledWidth + 0.001 >= geometry.viewportWidth);
        verify(geometry.scaledHeight + 0.001 >= geometry.viewportHeight);
        if (geometry.hasImageSize)
            fuzzyCompare(geometry.scaledWidth / geometry.scaledHeight,
                geometry.imageWidth / geometry.imageHeight, 0.000001);
    }

    function test_ultrawide_hotplug_and_mode_changes() {
        compare(geometry.scaledWidth, 1920);
        geometry.viewportWidth = 3440;
        geometry.viewportHeight = 1440;
        fuzzyCompare(geometry.scaledWidth, 3440, 0.001);
        fuzzyCompare(geometry.scaledHeight, 1935, 0.001);
        coversViewport();
        // Fractional scaling changes the logical size without changing the image.
        geometry.viewportWidth = 1512;
        geometry.viewportHeight = 1008;
        fuzzyCompare(geometry.scaledWidth, 1792, 0.001);
        fuzzyCompare(geometry.scaledHeight, 1008, 0.001);
        coversViewport();
        geometry.viewportWidth = 1080;
        geometry.viewportHeight = 1920;
        coversViewport();
    }

    function test_small_and_portrait_images() {
        geometry.imageWidth = 640;
        geometry.imageHeight = 480;
        coversViewport();
        geometry.imageWidth = 1080;
        geometry.imageHeight = 1920;
        coversViewport();
    }

    function test_pending_and_invalid_metadata_data() {
        return [
            {tag: "pending", w: 0, h: 0},
            {tag: "missing-height", w: 3840, h: 0},
            {tag: "negative", w: -1, h: 2160},
            {tag: "not-a-number", w: NaN, h: NaN},
            {tag: "infinite", w: Infinity, h: 2160}
        ];
    }
    function test_pending_and_invalid_metadata(data) {
        geometry.imageWidth = data.w;
        geometry.imageHeight = data.h;
        compare(geometry.hasImageSize, false);
        coversViewport();
        geometry.viewportWidth = 3440;
        geometry.viewportHeight = 1440;
        coversViewport();
        geometry.imageWidth = 3840;
        geometry.imageHeight = 2160;
        compare(geometry.hasImageSize, true);
        coversViewport();
    }

    function test_zoom_and_invalid_settings() {
        geometry.zoom = 1.07;
        fuzzyCompare(geometry.scaledWidth, 2054.4, 0.001);
        fuzzyCompare(geometry.scaledHeight, 1155.6, 0.001);
        coversViewport();
        for (const zoom of [0, -1, 0.5, NaN, Infinity]) {
            geometry.zoom = zoom;
            coversViewport();
        }
    }

    function test_independent_outputs() {
        const other = Qt.createQmlObject('import QtQml; WallpaperGeometry { viewportWidth: 3440; viewportHeight: 1440; imageWidth: 3840; imageHeight: 2160 }', this);
        geometry.viewportWidth = 1512;
        geometry.viewportHeight = 1008;
        fuzzyCompare(other.scaledWidth, 3440, 0.001);
        fuzzyCompare(geometry.scaledWidth, 1792, 0.001);
        other.destroy();
    }
}
