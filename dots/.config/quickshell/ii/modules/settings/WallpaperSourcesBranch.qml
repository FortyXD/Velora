pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

SettingsBranch {
    id: root
    key: "sources"
    readonly property bool readingSources: page.pageShown && shown
    onReadingSourcesChanged: if (readingSources) KeyringStorage.fetchKeyringData()

    ContentSection {
        title: Translation.tr("Choosing wallpapers")

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr("Use system file picker")
            description: Translation.tr("For the wallpaper selector instead of the built-in grid")
            autoToggle: false
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onClicked: Config.options.wallpaperSelector.useSystemFileDialog = !checked
        }
        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Hide wallpaper and widgets behind fullscreen windows")
            autoToggle: false
            checked: Config.options.background.hideWhenFullscreen
            onClicked: Config.options.background.hideWhenFullscreen = !checked
        }
    }

    ContentSection {
        icon: "today"
        title: Translation.tr("Wallpaper of the day")
        description: Translation.tr("A new picture every morning, with colors made from it")

        ConfigSwitch {
            buttonIcon: "event_repeat"
            text: Translation.tr("Change the wallpaper every day")
            description: Translation.tr("Saved to ~/Pictures/Wallpapers/Daily")
            autoToggle: false
            checked: Config.options.background.daily.enable
            onClicked: Config.options.background.daily.enable = !Config.options.background.daily.enable
        }
        ContentSubsection {
            title: Translation.tr("Source")
            ConfigSelectionArray {
                currentValue: Config.options.background.daily.source
                onSelected: newValue => Config.options.background.daily.source = newValue
                options: [
                    { displayName: "Bing", icon: "today", value: "bing" },
                    { displayName: "NASA", icon: "rocket_launch", value: "nasa" },
                    { displayName: "Wikimedia", icon: "account_balance", value: "wikimedia" }
                ]
            }
        }
        ConfigSpinBox {
            icon: "auto_delete"
            text: Translation.tr("Keep pictures for (days)")
            from: 1
            to: 365
            stepSize: 1
            value: Config.options.background.daily.keepDays
            onValueChanged: if (value !== Config.options.background.daily.keepDays) Config.options.background.daily.keepDays = value
        }
        DialogButton {
            buttonText: Translation.tr("Get today's picture now")
            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperOfTheDay", "run"])
        }
    }

    ContentSection {
        icon: "public"
        title: Translation.tr("Online sources")
        description: Translation.tr("Where the Online part of the wallpaper selector searches. Keys are kept in your keyring.")

        ConfigSwitch {
            buttonIcon: "fit_screen"
            text: Translation.tr("Only wallpapers that fit the screen")
            description: Translation.tr("Size and shape of the focused screen, where the source can filter by them")
            autoToggle: false
            checked: Config.options.background.online.fitScreen
            onClicked: Config.options.background.online.fitScreen = !Config.options.background.online.fitScreen
        }

        Repeater {
            model: OnlineWallpapers.providerList
            delegate: ColumnLayout {
                id: providerBlock
                required property var modelData
                readonly property bool enabledSource: !(Config.options.background.online.disabledProviders ?? []).includes(modelData.id)
                Layout.fillWidth: true
                spacing: 2

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: providerBlock.modelData.icon
                    text: providerBlock.modelData.name
                    description: Translation.tr(providerBlock.modelData.description)
                    autoToggle: false
                    checked: providerBlock.enabledSource
                    onClicked: {
                        const disabled = Config.options.background.online.disabledProviders ?? [];
                        Config.options.background.online.disabledProviders = providerBlock.enabledSource
                            ? [...disabled, providerBlock.modelData.id] : disabled.filter(id => id !== providerBlock.modelData.id);
                    }
                }
                ConfigTextRow {
                    Layout.fillWidth: true
                    visible: providerBlock.enabledSource && (providerBlock.modelData.needsKey || providerBlock.modelData.keyOptional)
                    enabled: KeyringStorage.loaded
                    icon: "key"
                    label: providerBlock.modelData.needsKey ? Translation.tr("API key") : Translation.tr("API key (optional)")
                    description: Translation.tr("Get one at %1").arg(providerBlock.modelData.homepage)
                    // The saved key is never shown; typing a new one replaces it
                    placeholderText: OnlineWallpapers.hasKey(providerBlock.modelData.id) ? Translation.tr("Saved. Paste a new key to replace it") : Translation.tr("Paste the key here")
                    value: ""
                    onEditingFinished: {
                        if (value.trim().length === 0) return;
                        KeyringStorage.setNestedField(["wallpaperKeys", providerBlock.modelData.id], value.trim());
                        value = "";
                    }
                }
                DialogButton {
                    visible: providerBlock.enabledSource && OnlineWallpapers.hasKey(providerBlock.modelData.id)
                    Layout.leftMargin: 12
                    buttonText: Translation.tr("Remove the key")
                    onClicked: KeyringStorage.setNestedField(["wallpaperKeys", providerBlock.modelData.id], "")
                }
                ConfigTextRow {
                    Layout.fillWidth: true
                    visible: providerBlock.enabledSource && providerBlock.modelData.id === "reddit"
                    icon: "forum"
                    label: Translation.tr("Subreddits")
                    placeholderText: "wallpaper+wallpapers+EarthPorn"
                    value: Config.options.background.online.subreddits
                    onEditingFinished: Config.options.background.online.subreddits = value.trim()
                }
            }
        }

        ConfigTextRow {
            icon: "folder"
            label: Translation.tr("Save downloads to")
            placeholderText: `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers/Online`
            value: Config.options.background.online.downloadDir
            onEditingFinished: Config.options.background.online.downloadDir = value.trim()
        }
    }
}
