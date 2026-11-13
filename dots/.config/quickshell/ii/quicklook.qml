//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import Quickshell
import Quickshell.Io

ApplicationWindow {
    id: root
    component PreviewButton: Button {
        id: control
        padding: 10
        leftPadding: 16; rightPadding: 16
        background: Rectangle {
            radius: 20
            color: control.down ? "#8c5b43" : control.hovered ? "#6b4533" : "#54362a"
            opacity: control.enabled ? 1 : 0.4
            border.width: control.activeFocus ? 1 : 0
            border.color: "#ffb692"
        }
    }
    visible: true
    width: 900; height: 680
    minimumWidth: 440; minimumHeight: 320
    color: "#261812"
    palette.windowText: "#f7ddd2"
    palette.text: "#f7ddd2"
    palette.button: "#54362a"
    palette.buttonText: "#f7ddd2"
    title: "Velora Quick Look — " + (info.name ?? "")
    property var paths: JSON.parse(Quickshell.env("VELORA_PREVIEW_PATHS") || "[]")
    property int current: 0
    property int page: 1
    property int requestId: 0
    property var info: ({})
    property bool busy: false
    readonly property bool typing: activeFocusItem && activeFocusItem.cursorPosition !== undefined && !activeFocusItem.readOnly
    readonly property string currentPath: paths[current] ?? ""
    function load() {
        requestId++;
        player.stop(); player.source = "";
        decoder.running = false;
        info = ({}); busy = true;
        reload.restart();
    }
    function step(delta) {
        if (paths.length < 2) return;
        current = (current + delta + paths.length) % paths.length;
        page = 1; load();
    }
    function openFile() {
        if (info.url) Qt.openUrlExternally(info.url);
        root.close();
    }
    Component.onCompleted: load()
    onClosing: { player.stop(); decoder.running = false; Qt.quit(); }
    Timer { id: reload; interval: 30; onTriggered: decoder.running = true }
    Process {
        id: decoder
        command: ["python3", "-I", Quickshell.shellPath("scripts/quicklook.py"), "--directory", Quickshell.env("VELORA_PREVIEW_DIR"), "--page", String(root.page), "--request-id", String(root.requestId), "--", root.currentPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                try {
                    const result = JSON.parse(text);
                    if (result.requestId !== root.requestId) return;
                    root.info = result;
                    if (root.info.kind === "video" || root.info.kind === "audio") {
                        sound.muted = root.info.kind === "video";
                        player.source = root.info.url;
                        if (root.info.kind === "video") player.play();
                    }
                } catch (e) { root.info = {error: String(e)}; }
                root.busy = false;
            }
        }
    }
    MediaPlayer { id: player; audioOutput: AudioOutput { id: sound } videoOutput: video }
    Shortcut { sequence: "Escape"; onActivated: root.close() }
    Shortcut { sequence: "Space"; enabled: !root.typing; onActivated: root.close() }
    Shortcut { sequence: "Left"; enabled: !root.typing; onActivated: root.step(-1) }
    Shortcut { sequence: "Right"; enabled: !root.typing; onActivated: root.step(1) }
    Shortcut { sequences: ["Return", "Enter"]; enabled: !root.typing; onActivated: root.openFile() }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Label { text: root.info.name ?? qsTr("Quick Look"); font.pixelSize: 18; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Label { text: (root.current + 1) + " / " + root.paths.length; visible: root.paths.length > 1 }
            PreviewButton { text: qsTr("Open"); onClicked: root.openFile() }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            Image {
                anchors.fill: parent
                visible: ["image", "pdf"].includes(root.info.kind)
                source: visible ? (root.info.preview ?? root.info.url) : ""
                sourceSize: Qt.size(1800, 1400)
                fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                Label { anchors.centerIn: parent; visible: parent.status === Image.Error; text: qsTr("Cannot display this image") }
            }
            AnimatedImage {
                anchors.fill: parent; visible: root.info.kind === "gif"
                source: visible ? root.info.url : ""; playing: visible; cache: false
                fillMode: Image.PreserveAspectFit
            }
            VideoOutput { id: video; anchors.fill: parent; visible: root.info.kind === "video"; fillMode: VideoOutput.PreserveAspectFit }
            ScrollView {
                anchors.fill: parent; visible: root.info.kind === "text"
                TextArea { text: root.info.text ?? ""; readOnly: true; textFormat: TextEdit.PlainText; selectByMouse: true; wrapMode: TextEdit.NoWrap; font.family: "monospace"; background: null }
            }
            ColumnLayout {
                anchors.centerIn: parent; width: Math.min(parent.width, 480)
                visible: !root.busy && ["other", "audio"].includes(root.info.kind)
                Label { text: root.info.kind === "audio" ? "♪" : "◇"; font.pixelSize: 72; Layout.alignment: Qt.AlignHCenter }
                Label { text: root.info.mime ?? ""; Layout.alignment: Qt.AlignHCenter }
                Label { text: root.info.error ?? (root.info.kind === "audio" ? qsTr("Press Play to listen") : qsTr("Open this file in its application")); wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            }
            BusyIndicator { anchors.centerIn: parent; running: root.busy }
        }
        RowLayout {
            Layout.fillWidth: true
            PreviewButton { text: "←"; implicitWidth: 44; enabled: root.paths.length > 1; onClicked: root.step(-1) }
            PreviewButton { text: "→"; implicitWidth: 44; enabled: root.paths.length > 1; onClicked: root.step(1) }
            Label { text: root.info.size === undefined ? "" : (root.info.size / 1024).toFixed(1) + " KiB" }
            Label { text: qsTr("Preview truncated"); visible: root.info.truncated ?? false }
            Item { Layout.fillWidth: true }
            RowLayout {
                visible: root.info.kind === "pdf"
                PreviewButton { text: "−"; enabled: root.page > 1; onClicked: { root.page--; root.load(); } }
                Label { text: root.page + " / " + (root.info.pages ?? "…") }
                PreviewButton { text: "+"; enabled: root.page < (root.info.pages ?? 1); onClicked: { root.page++; root.load(); } }
            }
            RowLayout {
                visible: ["audio", "video"].includes(root.info.kind)
                PreviewButton { text: player.playbackState === MediaPlayer.PlayingState ? qsTr("Pause") : qsTr("Play"); onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
                PreviewButton { text: sound.muted ? qsTr("Unmute") : qsTr("Mute"); onClicked: sound.muted = !sound.muted }
                Label { text: player.error !== MediaPlayer.NoError ? player.errorString : Math.floor(player.position / 1000) + " / " + Math.floor(player.duration / 1000) + " s"; elide: Text.ElideRight; Layout.maximumWidth: 150 }
            }
        }
    }
}
