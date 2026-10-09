import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        title: Translation.tr("Right sidebar")
        description: Translation.tr("Quick toggles, sliders, notifications, calendar and to-do")

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr('Keep right sidebar loaded')
            description: Translation.tr("Opens faster at the cost of around 15MB of RAM")
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: {
                Config.options.sidebar.keepRightSidebarLoaded = checked;
            }
        }
        ContentSubsection {
            title: Translation.tr("Quick toggles")
            ConfigSelectionArray {
                currentValue: Config.options.sidebar.quickToggles.style
                onSelected: newValue => {
                    Config.options.sidebar.quickToggles.style = newValue;
                }
                options: [
                    { displayName: Translation.tr("Classic"), icon: "password_2", value: "classic" },
                    { displayName: Translation.tr("Android"), icon: "action_key", value: "android" }
                ]
            }
            ConfigSpinBox {
                enabled: Config.options.sidebar.quickToggles.style === "android"
                icon: "splitscreen_left"
                text: Translation.tr("Columns")
                value: Config.options.sidebar.quickToggles.android.columns
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.quickToggles.android.columns = value;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Sliders")
        description: Translation.tr("Shown above the quick toggles")

        ConfigSwitch {
            buttonIcon: "tune"
            text: Translation.tr("Show sliders")
            checked: Config.options.sidebar.quickSliders.enable
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.enable = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "brightness_6"
            text: Translation.tr("Brightness")
            checked: Config.options.sidebar.quickSliders.showBrightness
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showBrightness = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "volume_up"
            text: Translation.tr("Volume")
            checked: Config.options.sidebar.quickSliders.showVolume
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showVolume = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.sidebar.quickSliders.enable
            buttonIcon: "mic"
            text: Translation.tr("Microphone")
            checked: Config.options.sidebar.quickSliders.showMic
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showMic = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Left sidebar")
        description: Translation.tr("AI chat, translator and image browser")

        ConfigSwitch {
            buttonIcon: "translate"
            text: Translation.tr('Translator')
            autoToggle: false
            checked: Config.options.sidebar.translator.enable
            onClicked: Config.options.sidebar.translator.enable = !Config.options.sidebar.translator.enable
        }
        ContentSubsection {
            title: Translation.tr("Anime image browser")
            description: Translation.tr("A Wallhaven and booru image browser in the left sidebar, plus random anime wallpaper buttons. Hidden keeps the page (swipe to it) but removes its tab.")
            ConfigSelectionArray {
                currentValue: Config.options.policies.weeb
                onSelected: newValue => {
                    Config.options.policies.weeb = newValue;
                }
                options: [
                    { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                    { displayName: Translation.tr("On"), icon: "check", value: 1 },
                    { displayName: Translation.tr("Hidden"), icon: "visibility_off", value: 2 }
                ]
            }
        }
        ConfigNavRow {
            buttonIcon: "neurology"
            title: Translation.tr("Assistant")
            description: Translation.tr("AI features and the system prompt")
            onClicked: ApplicationWindow.window?.openPage("search", Translation.tr("Assistant"))
        }
    }

    ContentSection {
        title: Translation.tr("Opening")

        ConfigNavRow {
            buttonIcon: "south_east"
            title: Translation.tr("Hot corners")
            description: Translation.tr("Open sidebars from the corners of the screen")
            onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Hot corners"))
        }
    }
}
