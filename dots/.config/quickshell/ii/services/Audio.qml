pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: (sink?.ready && sink?.audio) ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node?.nickname || node?.description || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return node?.properties?.["application.name"] || node?.description || node?.name || Translation.tr("Unknown")
    }

    // Lists
    function correctType(node, isSink) {
        return node && (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream && !root.isCleanMic(node)
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream && !root.isCleanMic(node)
        })
    }

    // Noise reduction: the "Clean microphone" is the chosen mic run through PipeWire's WebRTC filter (noise
    // suppression, a high-pass against rumble, gain control). It stays out of the device lists; `micInUse`
    // is the real microphone, whether apps get it directly or cleaned.
    readonly property string cleanMicName: "folis_clean_mic"
    function isCleanMic(node) {
        return (node?.name ?? "").startsWith(root.cleanMicName);
    }
    readonly property bool noiseReduction: Config.options?.audio.noiseReduction.enable ?? false
    readonly property PwNode cleanMicNode: Pipewire.nodes.values.find(node => node.name === root.cleanMicName) ?? null
    // The microphone the filter listens to: the chosen one while it's plugged in, otherwise another
    readonly property string cleanMicTarget: {
        const wanted = Config.options?.audio.noiseReduction.mic ?? "";
        if (root.inputDevices.some(node => node.name === wanted)) return wanted;
        return root.inputDevices[0]?.name ?? "";
    }
    readonly property PwNode micInUse: root.isCleanMic(root.source)
        ? (root.inputDevices.find(node => node.name === root.cleanMicTarget) ?? null) : root.source

    // Picks the microphone apps use; with noise reduction on, the one that gets cleaned
    function selectMic(node) {
        if (!node) return;
        if (root.noiseReduction) Config.options.audio.noiseReduction.mic = node.name;
        else root.setDefaultSource(node);
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)
    // Stays true while a microphone is briefly re-created (a USB mic behind a hub is, on every resume),
    // so mic buttons don't flicker to "unavailable"
    property bool inputAvailable: true
    onInputDevicesChanged: {
        if (root.inputDevices.length > 0) {
            noInputTimer.stop();
            root.inputAvailable = true;
        } else {
            noInputTimer.restart();
        }
    }

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }

    function toggleMicMute() {
        if (source?.audio) source.audio.muted = !source.audio.muted
    }

    function incrementVolume() {
        if (!sink?.audio) return;
        const step = value < 0.1 ? 0.01 : 0.02;
        sink.audio.volume = Math.min(1, sink.audio.volume + step);
    }
    
    function decrementVolume() {
        if (!sink?.audio) return;
        const step = value < 0.1 ? 0.01 : 0.02;
        sink.audio.volume = Math.max(0, sink.audio.volume - step);
    }

    function setDefaultSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Timer {
        id: noInputTimer
        interval: 2000
        onTriggered: root.inputAvailable = root.inputDevices.length > 0
    }

    // ---- Main shell only: the noise reduction filter, as a small pipewire process of its own ----
    readonly property bool cleanMicWanted: root.loaded && root.noiseReduction && root.cleanMicTarget.length > 0
    property string cleanMicRunningTarget: ""
    onCleanMicWantedChanged: root.syncCleanMic()
    onCleanMicTargetChanged: root.syncCleanMic()
    onCleanMicNodeChanged: {
        // The configured default becomes the clean microphone as soon as it exists
        if (root.cleanMicNode && root.cleanMicWanted && !root.isCleanMic(Pipewire.defaultAudioSource))
            Pipewire.preferredDefaultAudioSource = root.cleanMicNode;
    }
    function syncCleanMic() {
        if (!root.cleanMicWanted) {
            if (cleanMicProc.running) {
                // Back to the real microphone before the clean one disappears
                const real = root.inputDevices.find(node => node.name === root.cleanMicRunningTarget);
                if (real) Pipewire.preferredDefaultAudioSource = real;
                cleanMicProc.running = false;
            }
            return;
        }
        if (cleanMicProc.running && root.cleanMicRunningTarget === root.cleanMicTarget) return;
        cleanMicProc.running = false;
        cleanMicConf.setText(root.cleanMicConfig(root.cleanMicTarget));
        root.cleanMicRunningTarget = root.cleanMicTarget;
        cleanMicStartTimer.restart();
    }
    // The echo reference (sink.props) is never linked: the module puts all its nodes in one node.group, so a
    // linked speaker monitor would run the mic and webrtc whenever anything plays. Calling apps cancel echo
    // themselves; here the filter only runs while something records from the clean microphone.
    function cleanMicConfig(target) {
        return `context.properties = { log.level = 0 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.* = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt, flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-echo-cancel
        args = {
            library.name = aec/libspa-aec-webrtc
            monitor.mode = true
            audio.channels = 1
            audio.position = [ MONO ]
            aec.args = {
                webrtc.high_pass_filter = true
                webrtc.noise_suppression = true
                webrtc.gain_control = true
            }
            capture.props = {
                node.name = "${root.cleanMicName}_capture"
                target.object = "${target}"
                node.passive = true
                node.dont-fallback = true
                node.dont-reconnect = true
            }
            sink.props = {
                node.name = "${root.cleanMicName}_reference"
                node.autoconnect = false
            }
            source.props = {
                node.name = "${root.cleanMicName}"
                node.description = "${Translation.tr("Clean microphone")}"
            }
        }
    }
]
`;
    }
    FileView {
        id: cleanMicConf
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/folis-clean-mic.conf`
        printErrors: false // Only written, never read
    }
    Process {
        id: cleanMicProc
        command: ["pipewire", "-c", cleanMicConf.path]
    }
    Timer { // Lets the config file land first
        id: cleanMicStartTimer
        interval: 300
        onTriggered: if (root.cleanMicWanted) cleanMicProc.running = true
    }

    // Apps that were recording lose the microphone without a word when it drops out, so say what happened.
    // Compared once things settle, since a mic that is re-created vanishes and comes back within a second.
    // Only the main shell does this (load()), not the settings app.
    property bool loaded: false
    function load() {
        root.loaded = true;
        root.syncCleanMic();
    }
    QtObject {
        id: micWatch
        property string name: ""
        property int nodeId: -1
        property string label: ""
        property bool recording: false // An app was using the mic when it changed
    }
    onSourceChanged: {
        if (micWatch.name.length > 0 && root.inputAppNodes.length > 0) micWatch.recording = true;
        micSettleTimer.restart();
    }
    Timer {
        id: micSettleTimer
        interval: 2000
        onTriggered: {
            const node = root.source;
            if (!node || !root.loaded) return;
            const previous = micWatch.label;
            const stillThere = root.inputDevices.some(device => device.name === micWatch.name);
            if (micWatch.name.length > 0 && node.name !== micWatch.name && !stillThere) {
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "audio-input-microphone",
                    Translation.tr("Microphone switched to %1").arg(root.friendlyDeviceName(node)),
                    Translation.tr("%1 was disconnected").arg(previous)]);
            } else if (micWatch.name.length > 0 && node.name === micWatch.name && node.id !== micWatch.nodeId && micWatch.recording) {
                Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "audio-input-microphone",
                    Translation.tr("%1 reconnected").arg(root.friendlyDeviceName(node)),
                    Translation.tr("It dropped out for a moment. If an app lost the sound, turn its microphone off and on again.")]);
            }
            micWatch.name = node.name;
            micWatch.nodeId = node.id;
            micWatch.label = root.friendlyDeviceName(node);
            micWatch.recording = false;
        }
    }

    Connections {
        target: root
        function onSinkChanged() {
            volumeProtection.lastReady = false;
            volumeProtection.lastVolume = 0;
        }
    }

    Connections { // Protection against sudden volume changes
        id: volumeProtection
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable || !root.sink?.audio) return;
            const newVolume = root.sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
