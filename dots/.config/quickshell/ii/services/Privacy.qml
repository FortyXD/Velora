pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

/**
 * Microphone, camera and screen capture activity, read from PipeWire links.
 * Apps that open a camera directly through V4L2 bypass PipeWire and can't be seen here.
 */
Singleton {
    id: root

    // EasyEffects and the noise reduction filter (Audio.qml) read the microphone to process it; apps
    // recording their output still count
    function isEffectsNode(node) {
        return /easyeffects|^folis_clean_mic/i.test(node?.name ?? "");
    }
    function isCameraNode(node) {
        return /^(v4l2|libcamera)/.test(node?.name ?? "");
    }
    // Each app once, even when it has several links (stereo channels, several streams)
    function uniqueTargets(groups) {
        const seen = new Set();
        return groups.map(group => group.target).filter(node => {
            if (!node || seen.has(node.id)) return false;
            seen.add(node.id);
            return true;
        });
    }

    readonly property var micClients: uniqueTargets(Pipewire.linkGroups.values.filter(group =>
        group.source?.type === PwNodeType.AudioSource
        && group.target?.type === PwNodeType.AudioInStream
        && !isEffectsNode(group.target)))
    readonly property var videoGroups: Pipewire.linkGroups.values.filter(group => group.source?.type === PwNodeType.VideoSource)
    readonly property var cameraClients: uniqueTargets(videoGroups.filter(group => isCameraNode(group.source)))
    readonly property var screenClients: uniqueTargets(videoGroups.filter(group => !isCameraNode(group.source)))

    readonly property bool micActive: micClients.length > 0
    readonly property bool cameraActive: cameraClients.length > 0
    readonly property bool screenSharing: screenClients.length > 0
    readonly property bool anyActive: micActive || cameraActive || screenSharing

    // Needs the node to be tracked (PwObjectTracker) for the full properties
    function appName(node) {
        const props = node?.properties ?? {};
        return props["application.name"] || props["node.description"] || node?.description || node?.name || "";
    }
}
