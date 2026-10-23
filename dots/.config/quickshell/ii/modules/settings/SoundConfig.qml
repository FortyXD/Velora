import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.sound

ContentPage {
    id: page

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource // What apps record: the clean microphone with noise reduction
    readonly property PwNode mic: Audio.micInUse // The real microphone
    // Built-in sound cards add an analog boost to the microphone above about 35 % (the ALC285 at least)
    readonly property bool sourceBuiltIn: (page.mic?.name ?? "").includes(".pci-")
    // The level meter runs while the window is in front, or while you're hearing yourself
    readonly property bool watching: page.pageShown && ((ApplicationWindow.window?.active ?? false) || micTest.listening)

    PwObjectTracker {
        objects: [page.sink, page.source, page.mic]
    }

    // Mute button, slider and percentage for one device
    component VolumeControl: RowLayout {
        id: control
        property PwNode node
        property bool input: false
        readonly property bool muted: control.node?.audio?.muted ?? false
        Layout.fillWidth: true
        spacing: 10

        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            toggled: control.muted
            colBackground: Appearance.colors.colLayer2
            colBackgroundToggled: Appearance.colors.colErrorContainer
            colBackgroundToggledHover: Appearance.colors.colErrorContainerHover
            onClicked: if (control.node?.audio) control.node.audio.muted = !control.node.audio.muted
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: control.input ? (control.muted ? "mic_off" : "mic") : (control.muted ? "volume_off" : "volume_up")
                iconSize: 22
                color: control.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: control.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }
        StyledSlider {
            Layout.fillWidth: true
            enabled: !!control.node?.audio
            configuration: StyledSlider.Configuration.M
            value: control.node?.audio?.volume ?? 0
            onMoved: if (control.node?.audio) control.node.audio.volume = value
        }
        StyledText {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: `${Math.round((control.node?.audio?.volume ?? 0) * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    component Caption: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Output")
        description: Translation.tr("Where sound plays. Apps follow the device in use unless you move them below.")

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: Audio.outputDevices
                delegate: AudioDeviceTile {
                    required property var modelData
                    node: modelData
                    selected: modelData.id === page.sink?.id
                    onClicked: Audio.setDefaultSink(modelData)
                }
            }
        }
        Caption {
            visible: Audio.outputDevices.length === 0
            text: Translation.tr("No speakers or headphones found")
        }

        VolumeControl {
            node: page.sink
        }

        RowLayout { // Balance, for stereo devices
            id: balanceRow
            readonly property var volumes: page.sink?.audio?.volumes ?? []
            readonly property real loudest: balanceRow.volumes.length === 2 ? Math.max(balanceRow.volumes[0], balanceRow.volumes[1]) : 0
            readonly property real balance: balanceRow.loudest > 0 ? (balanceRow.volumes[1] - balanceRow.volumes[0]) / balanceRow.loudest : 0
            // Snaps to the middle, which also hides the tiny difference PipeWire leaves between equal channels
            function snap(value) {
                return Math.abs(value) < 0.05 ? 0 : value;
            }
            function setBalance(value) {
                if (balanceRow.volumes.length !== 2 || !page.sink?.audio) return;
                const b = balanceRow.snap(value);
                page.sink.audio.volumes = [balanceRow.loudest * (b > 0 ? 1 - b : 1), balanceRow.loudest * (b < 0 ? 1 + b : 1)];
            }
            readonly property bool settingsSearchable: true
            readonly property string searchText: Translation.tr("Balance")
            visible: balanceRow.volumes.length === 2
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 10
            StyledText {
                text: Translation.tr("Balance")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                text: Translation.tr("L")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.S
                from: -1
                to: 1
                stopIndicatorValues: [0]
                usePercentTooltip: false
                tooltipContent: {
                    const b = balanceRow.snap(value);
                    return b === 0 ? "0" : b < 0 ? Translation.tr("%1% left").arg(Math.round(-b * 100)) : Translation.tr("%1% right").arg(Math.round(b * 100));
                }
                value: balanceRow.snap(balanceRow.balance)
                onMoved: balanceRow.setBalance(value)
            }
            StyledText {
                text: Translation.tr("R")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ConfigExpander {
            title: Translation.tr("Ear protection")
            description: Translation.tr("Stops sudden jumps in volume and caps how loud it can get")
            buttonIcon: "hearing"
            ConfigSwitch {
                buttonIcon: "hearing"
                text: Translation.tr("Earbang protection")
                autoToggle: false
                checked: Config.options.audio.protection.enable
                onClicked: Config.options.audio.protection.enable = !Config.options.audio.protection.enable
            }
            ConfigSpinBox {
                enabled: Config.options.audio.protection.enable
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase (%)")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: Config.options.audio.protection.maxAllowedIncrease = value
            }
            ConfigSpinBox {
                enabled: Config.options.audio.protection.enable
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit (%)")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154 // pavucontrol allows up to 153%
                stepSize: 2
                onValueChanged: Config.options.audio.protection.maxAllowed = value
            }
        }
    }

    ContentSection {
        icon: "mic"
        title: Translation.tr("Input")
        description: Translation.tr("The microphone apps use. The one you pick here comes back by itself when it's plugged in again.")

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: Audio.inputDevices
                delegate: AudioDeviceTile {
                    required property var modelData
                    node: modelData
                    selected: modelData.id === page.mic?.id
                    onClicked: Audio.selectMic(modelData)
                }
            }
        }
        Caption {
            visible: Audio.inputDevices.length === 0
            text: Translation.tr("No microphone found")
        }

        VolumeControl {
            node: page.mic
            input: true
        }

        ConfigSwitch {
            buttonIcon: "noise_control_off"
            text: Translation.tr("Noise reduction")
            description: Translation.tr("Removes fan hum, hiss and echo and keeps your voice at a steady level. Apps get a “Clean microphone” made from the one picked above.")
            autoToggle: false
            checked: Audio.noiseReduction
            onClicked: {
                if (!Audio.noiseReduction && page.mic) Config.options.audio.noiseReduction.mic = page.mic.name;
                Config.options.audio.noiseReduction.enable = !Audio.noiseReduction;
            }
        }

        // How loud the microphone hears you, live, only while this page is on screen
        PwNodePeakMonitor {
            id: peakMonitor
            node: page.source
            enabled: page.watching && !!page.source
        }
        RowLayout {
            readonly property bool settingsSearchable: true
            readonly property string searchText: Translation.tr("Input level")
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 10
            StyledText {
                text: Audio.noiseReduction ? Translation.tr("Apps hear") : Translation.tr("Input level")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            Rectangle {
                id: meterTrack
                Layout.fillWidth: true
                implicitHeight: 10
                radius: 5
                color: Appearance.colors.colSecondaryContainer
                // -60 dBFS .. 0 dBFS, the way level meters read
                readonly property real level: peakMonitor.peak > 0 ? Math.max(0, Math.min(1, (20 * Math.log10(peakMonitor.peak) + 60) / 60)) : 0
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(parent.height, parent.width * meterTrack.level)
                    visible: meterTrack.level > 0
                    color: meterTrack.level > 0.92 ? Appearance.colors.colError : Appearance.colors.colPrimary
                    Behavior on width {
                        NumberAnimation { duration: 60 }
                    }
                }
            }
        }
        Caption {
            text: Translation.tr("Speak normally: the bar should reach about two thirds. Red means it's too loud and will crackle.")
        }
        NoticeBox {
            visible: page.sourceBuiltIn && (page.mic?.audio?.volume ?? 0) > 0.4
            Layout.fillWidth: true
            materialIcon: "graphic_eq"
            text: Translation.tr("Above about 35 % the built-in microphone adds analog boost: louder, but muffled, booming and noisy. Turn it down and speak closer instead.")
        }

        RowLayout { // Hear yourself live: the microphone apps get, played straight back
            id: micTest
            property bool listening: false
            property bool restarting: false
            readonly property string target: page.source?.name ?? ""
            readonly property string sinkName: page.sink?.name ?? ""
            readonly property bool onSpeakers: micTest.sinkName.includes(".pci-") && !/hdmi|displayport/i.test(micTest.sinkName)
            readonly property bool settingsSearchable: true
            readonly property string searchText: Translation.tr("Test the microphone")
            Layout.fillWidth: true
            spacing: 10

            // Another microphone (or noise reduction switched) while listening: follow it
            onTargetChanged: if (listenProc.running) {
                micTest.restarting = true;
                restartTimer.restart();
            }

            RippleButton {
                implicitHeight: 40
                leftPadding: 14
                rightPadding: 16
                buttonRadius: Appearance.rounding.full
                enabled: !!page.source
                colBackground: micTest.listening ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary
                colBackgroundHover: micTest.listening ? Appearance.colors.colLayer2Hover : Appearance.colors.colPrimaryHover
                onClicked: micTest.listening = !micTest.listening
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: micTest.listening ? "stop" : "hearing"
                        iconSize: 20
                        color: micTest.listening ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: micTest.listening ? Translation.tr("Stop") : Translation.tr("Test the microphone")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: micTest.listening ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: !micTest.listening ? Translation.tr("Plays the microphone back live, so you hear yourself the way others do")
                    : micTest.onSpeakers ? Translation.tr("Speak: you hear yourself live. On the built-in speakers it may echo or whistle, headphones work best")
                    : Translation.tr("Speak: you hear yourself live")
            }

            Process {
                id: listenProc
                // Stops by itself after 5 minutes, and with the page or the window
                running: micTest.listening && page.pageShown && !micTest.restarting && micTest.target.length > 0
                command: {
                    const props = JSON.stringify(Translation.tr("Microphone test"));
                    return ["timeout", "-s", "INT", "300", "pw-loopback", "--name", "folis_mic_test",
                        "--capture", micTest.target, "--channels", "1", "--channel-map", "[ MONO ]", "--latency", "10",
                        "--capture-props", `{ application.name = ${props} node.dont-fallback = true node.dont-reconnect = true }`,
                        "--playback-props", `{ application.name = ${props} }`];
                }
                onExited: if (!micTest.restarting) micTest.listening = false
            }
            Timer {
                id: restartTimer
                interval: 300
                onTriggered: micTest.restarting = false
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Apps")
        description: Translation.tr("Each app's own volume, and the device it plays on")

        Caption {
            visible: Audio.outputAppNodes.length === 0 && Audio.inputAppNodes.length === 0
            text: Translation.tr("No app is playing or recording sound right now")
        }
        ContentSubsection {
            visible: Audio.outputAppNodes.length > 0
            title: Translation.tr("Playing")
            Repeater {
                model: Audio.outputAppNodes
                delegate: AudioMixerRow {
                    required property var modelData
                    node: modelData
                }
            }
        }
        ContentSubsection {
            visible: Audio.inputAppNodes.length > 0
            title: Translation.tr("Using the microphone")
            Repeater {
                model: Audio.inputAppNodes
                delegate: AudioMixerRow {
                    required property var modelData
                    node: modelData
                }
            }
        }
        ConfigNavRow {
            buttonIcon: "equalizer"
            title: Translation.tr("Advanced mixer")
            description: Translation.tr("Profiles, ports and everything else, in %1").arg(Config.options.apps.volumeMixer)
            onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer])
        }
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("System sounds")

        ConfigSwitch {
            buttonIcon: "battery_android_full"
            text: Translation.tr("Battery")
            description: Translation.tr("When the battery is low or full")
            autoToggle: false
            checked: Config.options.sounds.battery
            onClicked: Config.options.sounds.battery = !Config.options.sounds.battery
        }
        ConfigSwitch {
            buttonIcon: "av_timer"
            text: Translation.tr("Timers")
            description: Translation.tr("When the timer rings, or a focus or break period ends")
            autoToggle: false
            checked: Config.options.sounds.pomodoro
            onClicked: Config.options.sounds.pomodoro = !Config.options.sounds.pomodoro
        }
    }
}
