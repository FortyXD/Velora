pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

SettingsDetailPage {
    id: root
    sectionTitles: ({
        sources: Translation.tr("Wallpaper sources"),
        safety: Translation.tr("Work safety"),
        translation: Translation.tr("Translation")
    })
    readonly property string configPath: FileUtils.trimFileProtocol(Config.filePath)
    readonly property string configDir: FileUtils.parentDirectory(configPath)
    readonly property int overrideCount: Object.keys(HyprlandSettings.overrides).length

    component FileSection: ContentSection {
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        minimumCardHeight: fileGrid.columns === 2 ? Math.max(shellFiles.naturalCardHeight, hyprFiles.naturalCardHeight) : 0
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overview
            page: root
            key: "overview"

            GridLayout {
                id: fileGrid
                objectName: "advancedFileGrid"
                Layout.fillWidth: true
                columns: width >= 610 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 14
                rowSpacing: 12

                FileSection {
                    id: shellFiles
                    title: Translation.tr("Shell config file")
                    icon: "code"
                    ConfigNavRow {
                        buttonIcon: "data_object"
                        tileColor: ColorUtils.mix(Appearance.colors.colPrimary, "#47435e", 0.32)
                        title: "config.json"
                        description: root.configPath
                        trailingIcon: "open_in_new"
                        searchText: [title, description, Translation.tr("Open file")].join(" ")
                        Accessible.name: Translation.tr("Open file") + " " + title
                        StyledToolTip {
                            text: Translation.tr("Every option, including those without a switch here, is stored in this file. Changes apply instantly.")
                        }
                        onClicked: Qt.openUrlExternally(`file://${root.configPath}`)
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        spacing: 6
                        SettingsToolButton {
                            horizontalPadding: 6
                            materialIcon: "folder_open"
                            mainText: Translation.tr("Open folder")
                            onClicked: Qt.openUrlExternally(`file://${root.configDir}`)
                        }
                        SettingsToolButton {
                            id: copyButton
                            property bool justCopied: false
                            horizontalPadding: 6
                            materialIcon: justCopied ? "check" : "content_copy"
                            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
                            onClicked: {
                                Quickshell.clipboardText = root.configPath;
                                justCopied = true;
                                copiedTimer.restart();
                            }
                            Timer { id: copiedTimer; interval: 1500; onTriggered: copyButton.justCopied = false }
                        }
                    }
                    ConfigNavRow {
                        id: restartButton
                        property bool armed: false
                        buttonIcon: armed ? "warning" : "restart_alt"
                        title: armed ? Translation.tr("Click again to restart") : Translation.tr("Restart shell")
                        trailingIcon: ""
                        onClicked: {
                            if (armed) {
                                armed = false;
                                Quickshell.execDetached([Quickshell.shellPath("scripts/shell-session"), "--restart", "ii"]);
                            } else {
                                armed = true;
                                disarmTimer.restart();
                            }
                        }
                        StyledToolTip {
                            text: Translation.tr("Restarts the bar, sidebars and widgets. Usually not needed: they reload by themselves.")
                        }
                        Timer { id: disarmTimer; interval: 3000; onTriggered: restartButton.armed = false }
                    }
                }
                FileSection {
                    id: hyprFiles
                    title: Translation.tr("Window manager files")
                    icon: "account_tree"
                    ConfigNavRow {
                        buttonIcon: "edit_document"
                        title: "general.lua"
                        description: Translation.tr("Your Hyprland tweaks")
                        trailingIcon: "open_in_new"
                        onClicked: Qt.openUrlExternally(`file://${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/general.lua`)
                    }
                    ConfigNavRow {
                        buttonIcon: "subdirectory_arrow_right"
                        title: "shell_settings.lua"
                        description: Translation.tr("Loaded after general.lua · %1 changed").arg(root.overrideCount)
                        trailingIcon: "open_in_new"
                        onClicked: Qt.openUrlExternally(`file://${HyprlandSettings.luaPath}`)
                    }
                    ConfigNavRow {
                        id: resetHyprRow
                        property bool armed: false
                        enabled: root.overrideCount > 0
                        buttonIcon: armed ? "warning" : "settings_backup_restore"
                        title: armed ? Translation.tr("Click again to reset") : Translation.tr("Reset overrides")
                        searchText: title + " " + Translation.tr("Reset window manager options")
                        trailingIcon: ""
                        onClicked: {
                            if (armed) {
                                armed = false;
                                HyprlandSettings.reset(Object.keys(HyprlandSettings.overrides));
                            } else {
                                armed = true;
                                resetTimer.restart();
                            }
                        }
                        StyledToolTip { text: Translation.tr("Forget every change made here and go back to the config files") }
                        Timer { id: resetTimer; interval: 3000; onTriggered: resetHyprRow.armed = false }
                    }
                }
            }

            ContentSection {
                title: Translation.tr("Shell options")
                SettingsBranchLink {
                    branch: wallpaperSources
                    buttonIcon: "photo_library"
                    detail: Translation.tr("File picker, daily wallpaper and online sources")
                    summary: Config.options.background.daily.enable ? Translation.tr("Wallpaper of the day") : ""
                }
                SettingsBranchLink {
                    branch: safetyBranch
                    buttonIcon: "shield"
                    summary: [Config.options.workSafety.enable.wallpaper ? Translation.tr("Wallpaper") : "",
                        Config.options.workSafety.enable.clipboard ? Translation.tr("Clipboard") : ""].filter(Boolean).join(" · ") || Translation.tr("Off")
                }
                SettingsBranchLink {
                    branch: translationBranch
                    buttonIcon: "translate"
                    summary: Translation.languageName(localeInput.value)
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
        WallpaperSourcesBranch { id: wallpaperSources; page: root }
        SettingsBranch {
            id: safetyBranch
            page: root
            key: "safety"
            ContentSection {
                title: Translation.tr("Work safety")
                description: Translation.tr("Only kicks in on public networks (names with words like cafe, school, university, guest) and only for files or links with anime or NSFW keywords. The keyword lists are in the config file under workSafety.")

                ConfigSwitch {
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Hide such wallpapers")
                    description: Translation.tr("Shows a plain background instead")
                    autoToggle: false
                    checked: Config.options.workSafety.enable.wallpaper
                    onClicked: Config.options.workSafety.enable.wallpaper = !checked
                }
                ConfigSwitch {
                    buttonIcon: "content_paste_off"
                    text: Translation.tr("Hide such images in the clipboard history")
                    autoToggle: false
                    checked: Config.options.workSafety.enable.clipboard
                    onClicked: Config.options.workSafety.enable.clipboard = !checked
                }
            }
        }
        SettingsBranch {
            id: translationBranch
            page: root
            key: "translation"
            ContentSection {
                title: Translation.tr("Translation")
                description: Translation.tr("Missing your language? Gemini can translate the shell into it. Set the Gemini API key first: type /key in the left sidebar chat.")

                Process {
                    id: translationProc
                    property string locale: ""
                    command: [Directories.aiTranslationScriptPath, translationProc.locale]
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 480 ? 2 : 1
                    rowSpacing: 6
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
        }
    }
}
