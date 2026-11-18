import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.sound

SettingsDetailPage {
    id: rootPage
    sectionTitles: ({
        output: Translation.tr("Output"),
        microphone: Translation.tr("Microphone"),
        mixer: Translation.tr("App mixer"),
        alerts: Translation.tr("System sounds")
    })

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource // What apps record: the clean microphone with noise reduction
    readonly property PwNode mic: Audio.micInUse // The real microphone
    // Built-in sound cards add an analog boost to the microphone above about 35 % (the ALC285 at least)
    readonly property bool sourceBuiltIn: (rootPage.mic?.name ?? "").includes(".pci-")
    readonly property var settingsWindow: ApplicationWindow.window
    readonly property bool audioPageVisible: Config.ready && pageShown && !!settingsWindow?.visible
        && settingsWindow.visibility !== Window.Minimized && !GlobalStates.screenLocked
    readonly property bool watching: audioPageVisible && microphoneBranch.shown

    MicrophoneMonitor {
        id: monitor
        active: rootPage.audioPageVisible && Config.options.audio.monitorInSettings
        sourceName: rootPage.source?.name ?? ""
        sinkName: rootPage.sink?.name ?? ""
    }

    PwObjectTracker {
        objects: [rootPage.sink, rootPage.source, rootPage.mic]
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
            enabled: !!control.node?.audio
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
            defaultValue: Audio.defaultVolume(control.node)
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

    component DevicePicker: ChoiceDropdown {
        id: picker
        property bool input: false
        readonly property var devices: input ? Audio.inputDevices : Audio.outputDevices
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.margins: 8
        Accessible.name: input ? Translation.tr("Microphone") : Translation.tr("Output")
        options: devices.map(node => ({ displayName: Audio.friendlyDeviceName(node), value: node.id, icon: input ? "mic" : "speaker" }))
        currentValue: input ? rootPage.mic?.id : rootPage.sink?.id
        placeholderText: input ? Translation.tr("No microphone found") : Translation.tr("No speakers or headphones found")
        enabled: devices.length > 0
        onSelected: id => {
            const node = devices.find(device => device.id === id);
            if (node) { if (input) Audio.selectMic(node); else Audio.setDefaultSink(node); }
        }
    }
    component MonitorControl: ConfigSwitch {
        buttonIcon: "hearing"
        text: Translation.tr("Hear my microphone")
        description: monitor.failed ? Translation.tr("Couldn’t start monitoring. Toggle to retry.")
            : monitor.listening ? Translation.tr("Playing through %1").arg(Audio.friendlyDeviceName(rootPage.sink))
            : Translation.tr("Listen while Sound settings are open")
        checked: Config.options.audio.monitorInSettings
        autoToggle: false
        onClicked: Config.options.audio.monitorInSettings = !checked
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overviewBranch
            key: "overview"
            page: rootPage

            GridLayout {
                id: devicesGrid
                Layout.fillWidth: true
                columns: width >= 590 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 14
                rowSpacing: 14
                ContentSection {
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Output")
                    DevicePicker {}
                    VolumeControl { node: rootPage.sink; Layout.margins: 10 }
                    ConfigSwitch {
                        id: protectionRow
                        Layout.preferredHeight: devicesGrid.columns === 2 ? Math.max(implicitHeight, monitorRow.implicitHeight) : implicitHeight
                        buttonIcon: "health_and_safety"
                        text: Translation.tr("Ear protection")
                        description: Translation.tr("Limit sudden volume changes")
                        checked: Config.options.audio.protection.enable
                        autoToggle: false
                        onClicked: Config.options.audio.protection.enable = !checked
                    }
                    SettingsBranchLink {
                        id: outputLink
                        Layout.preferredHeight: devicesGrid.columns === 2 ? Math.max(implicitHeight, microphoneLink.implicitHeight) : implicitHeight
                        branch: outputBranch
                        buttonIcon: "tune"
                        title: Translation.tr("Output settings")
                        detail: Translation.tr("Balance and hearing protection")
                    }
                }
                ContentSection {
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Microphone")
                    DevicePicker { input: true }
                    VolumeControl { node: rootPage.mic; input: true; Layout.margins: 10 }
                    MonitorControl {
                        id: monitorRow
                        Layout.preferredHeight: devicesGrid.columns === 2 ? Math.max(implicitHeight, protectionRow.implicitHeight) : implicitHeight
                    }
                    SettingsBranchLink {
                        id: microphoneLink
                        Layout.preferredHeight: devicesGrid.columns === 2 ? Math.max(implicitHeight, outputLink.implicitHeight) : implicitHeight
                        branch: microphoneBranch
                        buttonIcon: "mic"
                        title: Translation.tr("Microphone settings")
                        detail: Translation.tr("Input level, noise reduction and testing")
                    }
                }
            }
            ContentSection {
                title: Translation.tr("Output level")
                OutputLevelMeter {
                    node: rootPage.sink
                    active: rootPage.audioPageVisible && overviewBranch.shown
                    sampling: monitor.listening || Audio.outputAppNodes.length > 0
                }
            }
            ContentSection {
                title: Translation.tr("Apps")
                Repeater {
                    model: overviewBranch.shown && rootPage.pageShown ? Audio.outputAppNodes.slice(0, 2) : []
                    delegate: AudioMixerRow { required property var modelData; node: modelData }
                }
                SettingsBranchLink {
                    branch: mixerBranch
                    buttonIcon: "tune"
                    summary: {
                        const count = Audio.outputAppNodes.length + Audio.inputAppNodes.length;
                        return count === 1 ? Translation.tr("1 active stream") : Translation.tr("%1 active streams").arg(count);
                    }
                }
                SettingsBranchLink {
                    branch: alertsBranch
                    buttonIcon: "notifications_active"
                    summary: [Config.options.sounds.battery ? Translation.tr("Battery") : "", Config.options.sounds.pomodoro ? Translation.tr("Timers") : ""].filter(Boolean).join(" · ") || Translation.tr("Off")
                }
            }
        }

        SettingsBranch {
            id: outputBranch
            key: "output"
            page: rootPage

            ContentSection {
                icon: "volume_up"
                title: Translation.tr("Output")
                description: Translation.tr("Apps follow the selected output unless you choose another in the app mixer.")

                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: Audio.outputDevices
                        delegate: AudioDeviceTile {
                            required property var modelData
                            node: modelData
                            selected: modelData.id === rootPage.sink?.id
                            onClicked: Audio.setDefaultSink(modelData)
                        }
                    }
                }
                Caption {
                    visible: Audio.outputDevices.length === 0
                    text: Translation.tr("No speakers or headphones found")
                }

                VolumeControl {
                    node: rootPage.sink
                }

                RowLayout { // Balance, for stereo devices
                    id: balanceRow
                    readonly property var volumes: rootPage.sink?.audio?.volumes ?? []
                    readonly property real loudest: balanceRow.volumes.length === 2 ? Math.max(balanceRow.volumes[0], balanceRow.volumes[1]) : 0
                    readonly property real balance: balanceRow.loudest > 0 ? (balanceRow.volumes[1] - balanceRow.volumes[0]) / balanceRow.loudest : 0
                    // Snaps to the middle, which also hides the tiny difference PipeWire leaves between equal channels
                    function snap(value) {
                        return Math.abs(value) < 0.05 ? 0 : value;
                    }
                    function setBalance(value) {
                        if (balanceRow.volumes.length !== 2 || !rootPage.sink?.audio) return;
                        const b = balanceRow.snap(value);
                        rootPage.sink.audio.volumes = [balanceRow.loudest * (b > 0 ? 1 - b : 1), balanceRow.loudest * (b < 0 ? 1 + b : 1)];
                    }
                    readonly property bool settingsSearchable: true
                    readonly property string title: Translation.tr("Balance")
                    readonly property string searchText: title
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
                        defaultValue: 0
                        defaultValueText: Translation.tr("Center")
                        stopIndicatorValues: []
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
        }

        SettingsBranch {
            id: microphoneBranch
            key: "microphone"
            page: rootPage

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
                            selected: modelData.id === rootPage.mic?.id
                            onClicked: Audio.selectMic(modelData)
                        }
                    }
                }
                Caption {
                    visible: Audio.inputDevices.length === 0
                    text: Translation.tr("No microphone found")
                }

                VolumeControl {
                    node: rootPage.mic
                    input: true
                }

                ConfigSwitch {
                    buttonIcon: "noise_control_off"
                    text: Translation.tr("Noise reduction")
                    description: Translation.tr("Removes fan hum, hiss and echo and keeps your voice at a steady level. Apps get a “Clean microphone” made from the one picked above.")
                    autoToggle: false
                    checked: Audio.noiseReduction
                    onClicked: {
                        if (!Audio.noiseReduction && rootPage.mic) Config.options.audio.noiseReduction.mic = rootPage.mic.name;
                        Config.options.audio.noiseReduction.enable = !Audio.noiseReduction;
                    }
                }

                // How loud the microphone hears you, live, only while this page is on screen
                PwNodePeakMonitor {
                    id: peakMonitor
                    node: rootPage.source
                    enabled: rootPage.watching && !!rootPage.source
                }
                RowLayout {
                    readonly property bool settingsSearchable: true
                    readonly property string title: Translation.tr("Input level")
                    readonly property string searchText: title
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
                    visible: rootPage.sourceBuiltIn && (rootPage.mic?.audio?.volume ?? 0) > 0.4
                    Layout.fillWidth: true
                    materialIcon: "graphic_eq"
                    text: Translation.tr("Above about 35 % the built-in microphone adds analog boost: louder, but muffled, booming and noisy. Turn it down and speak closer instead.")
                }

                ContentSubsection {
                    title: Translation.tr("Test the microphone")
                    MonitorControl {}
                }
            }
        }

        SettingsBranch {
            id: mixerBranch
            key: "mixer"
            page: rootPage

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
        }

        SettingsBranch {
            id: alertsBranch
            key: "alerts"
            page: rootPage

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
    }
}
