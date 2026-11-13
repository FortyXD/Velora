import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.settings.preview

Item {
    id: root

    property string mode: "all"
    readonly property var modes: [
        {
            value: "all",
            displayName: Translation.tr("Everything"),
            icon: "search",
            example: ""
        },
        {
            value: "app",
            displayName: Translation.tr("Apps"),
            icon: "apps",
            example: ""
        },
        {
            value: "math",
            displayName: Translation.tr("Math"),
            icon: "calculate",
            example: "24 * 7"
        },
        {
            value: "webSearch",
            displayName: Translation.tr("Web search"),
            icon: "public",
            example: "Velora"
        },
        {
            value: "emojis",
            displayName: Translation.tr("Emojis"),
            icon: "mood",
            example: "smile"
        },
        {
            value: "clipboard",
            displayName: Translation.tr("Clipboard"),
            icon: "content_paste",
            example: ""
        },
        {
            value: "action",
            displayName: Translation.tr("Action"),
            icon: "bolt",
            example: "wallpaper"
        },
        {
            value: "shellCommand",
            displayName: Translation.tr("Shell command"),
            icon: "terminal",
            example: "pwd"
        }
    ]
    readonly property real radius: Appearance.rounding.normal

    signal modeSelected(string mode)

    function tryExample(value) {
        if (value === "app")
            input.text = Config.options.search.prefix.app + (DesktopEntries.applications.values.find(app =>
            !app.noDisplay)?.name ?? "Velora");
        else if (value === "file")
            input.text = Translation.tr("project");
        else
            root.tryMode("math");
        input.forceActiveFocus();
        input.cursorPosition = input.text.length;
    }
    function tryMode(value) {
        const spec = root.modes.find(item => item.value === value);
        input.text = (value === "all" ? "" : Config.options.search.prefix[value]) + (spec?.example ?? "");
        input.forceActiveFocus();
        input.cursorPosition = input.text.length;
    }
    function updateQuery() {
        LauncherSearch.query = input.text;
    }

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 44

    Component.onDestruction: {
        LauncherSearch.query = "";
        Lens.cancelSearch();
    }

    MiniScreen {
        anchors.fill: parent
        crop: "top"
        scrim: 0.28
    }

    Rectangle {
        anchors.fill: parent
        opacity: 0.6
        radius: root.radius

        gradient: Gradient {
            GradientStop {
                color: Appearance.colors.colSecondaryContainer
                position: 0
            }

            GradientStop {
                color: Appearance.colors.colLayer1
                position: 1
            }
        }
    }

    ColumnLayout {
        id: body

        spacing: 16

        anchors {
            left: parent.left
            margins: 22
            right: parent.right
            top: parent.top
        }

        RowLayout {
            Layout.fillWidth: true

            MaterialSymbol {
                color: Appearance.colors.colOnLayer1
                iconSize: 22
                text: "search"
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                text: Translation.tr("Your search")
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Live preview")
            }
        }

        Rectangle {
            Layout.fillWidth: true
            border.color: Appearance.colors.colOutlineVariant
            color: Appearance.colors.colLayer0Base
            implicitHeight: launcher.implicitHeight + 20
            radius: Appearance.rounding.normal

            ColumnLayout {
                id: launcher

                spacing: 8

                anchors {
                    left: parent.left
                    margins: 10
                    right: parent.right
                    top: parent.top
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ChoiceDropdown {
                        Accessible.name: Translation.tr("Search mode")
                        currentValue: root.mode
                        displayText: root.width < 600 ? "" : (currentOption?.displayName ?? "")
                        maximumWidth: root.width < 600 ? 80 : 200
                        minimumWidth: root.width < 600 ? 80 : 120
                        objectName: "settingsSearchModes"
                        options: root.modes

                        onSelected: value => root.tryMode(value)
                    }

                    ToolbarTextField {
                        id: input

                        Layout.fillWidth: true
                        implicitHeight: 44
                        objectName: "settingsSearchPreviewInput"
                        placeholderText: Translation.tr("Search apps, files or calculate…")

                        onAccepted: {
                            debounce.stop();
                            root.updateQuery();
                        }
                        onTextChanged: {
                            const matches = root.modes.filter(item => item.value !== "all"
                                                                      && Config.options.search.prefix[item.value]
                                                                      ?.length && input.text.startsWith(
                                                                          Config.options.search.prefix[item.value]));
                            matches.sort((a, b) => Config.options.search.prefix[b.value].length
                                                   - Config.options.search.prefix[a.value].length);
                            root.mode = matches[0]?.value ?? "all";
                            root.modeSelected(root.mode);
                            debounce.restart();
                        }
                    }

                    RippleButton {
                        Accessible.name: Translation.tr("Clear")
                        implicitHeight: 36
                        implicitWidth: 36
                        visible: input.text.length > 0

                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 20
                            text: "close"
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            input.clear();
                            input.forceActiveFocus();
                        }

                        StyledToolTip {
                            text: Translation.tr("Clear")
                        }
                    }
                }

                Timer {
                    id: debounce

                    interval: 180

                    onTriggered: root.updateQuery()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    visible: input.text.trim().length > 0

                    Repeater {
                        model: input.text.trim() ? LauncherSearch.results.slice(0, 4) : []

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            color: Appearance.colors.colLayer1
                            implicitHeight: resultBody.implicitHeight + 20
                            radius: Appearance.rounding.small

                            RowLayout {
                                id: resultBody

                                spacing: 12

                                anchors {
                                    left: parent.left
                                    margins: 10
                                    right: parent.right
                                    top: parent.top
                                }

                                IconImage {
                                    implicitSize: 28
                                    source: visible ? Quickshell.iconPath(modelData.iconName,
                                                                          "application-x-executable") : ""
                                    visible: modelData.iconType === LauncherSearchResult.IconType.System
                                }

                                StyledText {
                                    font.pixelSize: 22
                                    text: visible ? modelData.iconName : ""
                                    visible: modelData.iconType === LauncherSearchResult.IconType.Text
                                }

                                MaterialSymbol {
                                    color: Appearance.colors.colPrimary
                                    iconSize: 24
                                    text: modelData.iconName || "search"
                                    visible: modelData.iconType !== LauncherSearchResult.IconType.System
                                             && modelData.iconType !== LauncherSearchResult.IconType.Text
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: modelData.name
                                        textFormat: Text.PlainText
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideMiddle
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        text: modelData.lensPath || modelData.type || ""
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.margins: 10
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr(
                                  "No results yet. Try another query or check your search folders.")
                        visible: !LauncherSearch.results.length
                        wrapMode: Text.Wrap
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !input.text.length

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Application")
                        materialIcon: "apps"
                        objectName: "searchExampleApp"

                        onClicked: root.tryExample("app")
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("File")
                        materialIcon: "description"
                        objectName: "searchExampleFile"

                        onClicked: root.tryExample("file")
                    }

                    RippleButtonWithIcon {
                        mainText: "24 × 7"
                        materialIcon: "calculate"
                        objectName: "searchExampleMath"

                        onClicked: root.tryExample("math")
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            text: input.text.length ? Translation.tr(
                                          "Preview only. Open results and run actions from the launcher.") :
                                      Translation.tr("Try an app name, a document or a calculation.")
            wrapMode: Text.Wrap
        }
    }
}
