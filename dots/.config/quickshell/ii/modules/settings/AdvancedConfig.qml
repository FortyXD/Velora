import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    readonly property string configPath: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`)
    readonly property string configDir: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse`)

    component ActionButton: RippleButton {
        id: actionButton
        property string buttonIcon
        property string label
        property bool danger: false
        implicitHeight: 40
        leftPadding: 14
        rightPadding: 16
        buttonRadius: Appearance.rounding.full
        colBackground: actionButton.danger ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
        colBackgroundHover: actionButton.danger ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
        colRipple: actionButton.danger ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSecondaryContainerActive
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                text: actionButton.buttonIcon
                iconSize: 20
                color: actionButton.danger ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: actionButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: actionButton.danger ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shell config file")
        description: Translation.tr("Every option, including those without a switch here, is stored in this file. Changes apply instantly.")

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 12
            ConfigIconTile {
                icon: "description"
                active: true
            }
            StyledText {
                Layout.fillWidth: true
                text: root.configPath
                elide: Text.ElideMiddle
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.bottomMargin: 10
            spacing: 6

            ActionButton {
                buttonIcon: "edit_document"
                label: Translation.tr("Open file")
                onClicked: Qt.openUrlExternally(`file://${root.configPath}`)
            }
            ActionButton {
                buttonIcon: "folder_open"
                label: Translation.tr("Open folder")
                onClicked: Qt.openUrlExternally(`file://${root.configDir}`)
            }
            ActionButton {
                id: copyButton
                property bool justCopied: false
                buttonIcon: justCopied ? "check" : "content_copy"
                label: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
                onClicked: {
                    Quickshell.clipboardText = root.configPath;
                    copyButton.justCopied = true;
                    copiedTimer.restart();
                }
                Timer {
                    id: copiedTimer
                    interval: 1500
                    onTriggered: copyButton.justCopied = false
                }
            }
            ActionButton {
                id: restartButton
                property bool armed: false
                danger: armed
                buttonIcon: armed ? "warning" : "restart_alt"
                label: armed ? Translation.tr("Click again to restart") : Translation.tr("Restart shell")
                onClicked: {
                    if (!armed) {
                        armed = true;
                        disarmTimer.restart();
                        return;
                    }
                    armed = false;
                    Quickshell.execDetached(["bash", "-c", "qs kill -c ii; qs -d -c ii"]);
                }
                Timer {
                    id: disarmTimer
                    interval: 3000
                    onTriggered: restartButton.armed = false
                }
                StyledToolTip {
                    text: Translation.tr("Restarts the bar, sidebars and widgets. Usually not needed: they reload by themselves.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Window manager files")
        description: Translation.tr("Options you change in these settings are saved to shell_settings.lua, which is loaded after your own custom config")

        ConfigNavRow {
            buttonIcon: "edit_document"
            title: Translation.tr("Your Hyprland tweaks")
            description: "custom/general.lua"
            trailingIcon: "open_in_new"
            onClicked: Qt.openUrlExternally(`file://${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/general.lua`)
        }
        ConfigNavRow {
            buttonIcon: "settings_suggest"
            title: Translation.tr("Saved from these settings")
            description: "custom/shell_settings.lua"
            valueText: Translation.tr("%1 changed").arg(Object.keys(HyprlandSettings.overrides).length)
            trailingIcon: "open_in_new"
            onClicked: Qt.openUrlExternally(`file://${HyprlandSettings.luaPath}`)
        }
        ConfigNavRow {
            id: resetHyprRow
            property bool armed: false
            enabled: Object.keys(HyprlandSettings.overrides).length > 0
            buttonIcon: "restart_alt"
            title: armed ? Translation.tr("Click again to reset") : Translation.tr("Reset window manager options")
            description: Translation.tr("Forget every change made here and go back to the config files")
            trailingIcon: ""
            onClicked: {
                if (!armed) {
                    armed = true;
                    resetDisarmTimer.restart();
                    return;
                }
                armed = false;
                HyprlandSettings.reset(Object.keys(HyprlandSettings.overrides));
            }
            Timer {
                id: resetDisarmTimer
                interval: 3000
                onTriggered: resetHyprRow.armed = false
            }
        }
    }

    ContentSection {
        title: Translation.tr("Work safety")
        description: Translation.tr("Only kicks in on public networks (names with words like cafe, school, university, guest) and only for files or links with anime or NSFW keywords. The keyword lists are in the config file under workSafety.")

        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide such wallpapers")
            description: Translation.tr("Shows a plain background instead")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "content_paste_off"
            text: Translation.tr("Hide such images in the clipboard history")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Translation")
        description: Translation.tr("Missing your language? Gemini can translate the shell into it. Set the Gemini API key first: type /key in the left sidebar chat.")

        Process {
            id: translationProc
            property string locale: ""
            command: [Directories.aiTranslationScriptPath, translationProc.locale]
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            ConfigComboRow {
                id: localeInput
                // The language to translate into: one from the list, or any other locale code
                property string value: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                readonly property bool known: Translation.languageNames[localeInput.value] !== undefined
                icon: "translate"
                text: Translation.tr("Language")
                maximumWidth: 260
                currentValue: localeInput.value
                customLabel: Translation.tr("Other locale code…")
                customPlaceholder: "fr_FR"
                customActive: !localeInput.known
                customValue: localeInput.known ? "" : localeInput.value
                onSelected: value => localeInput.value = value
                onCustomEntered: text => localeInput.value = text
                options: Object.keys(Translation.languageNames)
                    .map(code => ({ displayName: Translation.languageName(code), value: code }))
                    .sort((a, b) => a.displayName.localeCompare(b.displayName))
            }
            RippleButtonWithIcon {
                id: generateTranslationBtn
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                materialIcon: "auto_awesome"
                enabled: !translationProc.running || (translationProc.locale !== localeInput.value.trim())
                mainText: enabled ? Translation.tr("Generate") : Translation.tr("Generating...")
                onClicked: {
                    translationProc.locale = localeInput.value.trim();
                    translationProc.running = false;
                    translationProc.running = true;
                }
                StyledToolTip {
                    text: generateTranslationBtn.enabled ? Translation.tr("Typically takes 2 minutes") : Translation.tr("Don't close this window!")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Networking")

        ConfigComboRow {
            readonly property var agents: [
                { displayName: Translation.tr("Firefox on Linux"), value: "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" },
                { displayName: Translation.tr("Firefox on Windows"), value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0" }
            ]
            readonly property bool known: agents.some(agent => agent.value === Config.options.networking.userAgent)
            icon: "badge"
            text: Translation.tr("User agent")
            description: Translation.tr("How the shell introduces itself to websites it downloads from")
            options: agents.map(agent => Object.assign({ description: agent.value }, agent))
            currentValue: Config.options.networking.userAgent
            customLabel: Translation.tr("Custom…")
            customPlaceholder: "Mozilla/5.0 …"
            customActive: !known
            customValue: known ? "" : Config.options.networking.userAgent
            onSelected: value => Config.options.networking.userAgent = value
            onCustomEntered: text => Config.options.networking.userAgent = text
        }
    }

    ContentSection {
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            description: Translation.tr("How often CPU and memory usage is read, also for the system monitor widget")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }
}
