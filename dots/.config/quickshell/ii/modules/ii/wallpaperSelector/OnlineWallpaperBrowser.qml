import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * The Online part of the wallpaper selector: pick a source, search, then set or save a wallpaper.
 */
ColumnLayout {
    id: root

    property int columns: 4
    spacing: 6

    readonly property var provider: OnlineWallpapers.provider
    readonly property var optionNames: ({
        "relevance": Translation.tr("Relevance"), "relevant": Translation.tr("Relevance"),
        "toplist": Translation.tr("Top"), "popular": Translation.tr("Popular"), "random": Translation.tr("Random"),
        "date_added": Translation.tr("Newest"), "latest": Translation.tr("Newest"), "views": Translation.tr("Most viewed"),
        "favorites": Translation.tr("Most liked"), "week": Translation.tr("This week"), "month": Translation.tr("This month"),
        "year": Translation.tr("This year"), "all": Translation.tr("All"), "general": Translation.tr("General"),
        "anime": Translation.tr("Anime"), "people": Translation.tr("People"), "backgrounds": Translation.tr("Backgrounds"),
        "nature": Translation.tr("Nature"), "places": Translation.tr("Places"), "science": Translation.tr("Science"),
        "travel": Translation.tr("Travel"), "buildings": Translation.tr("Buildings"),
    })

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    function runSearch() {
        OnlineWallpapers.search(searchField.text);
    }

    Component.onCompleted: {
        if (OnlineWallpapers.results.length === 0 && !OnlineWallpapers.loading) root.runSearch();
    }

    RowLayout { // Source and search
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.margins: 4
        spacing: 6

        ChoiceDropdown {
            maximumWidth: 210
            minimumWidth: 170
            currentValue: OnlineWallpapers.providerId
            options: OnlineWallpapers.enabledProviders.map(provider => ({
                "value": provider.id, "displayName": provider.name, "icon": provider.icon,
                "description": provider.needsKey && !OnlineWallpapers.hasKey(provider.id) ? Translation.tr("Needs an API key") : ""
            }))
            onSelected: value => {
                OnlineWallpapers.setProvider(value);
                root.runSearch();
            }
        }

        ToolbarTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: false // ToolbarTextField fills by default, which would take the grid's room
            implicitHeight: 36
            enabled: root.provider?.supportsQuery ?? false
            placeholderText: enabled ? Translation.tr("Search %1").arg(root.provider?.name ?? "") : Translation.tr("This source has no search")
            font.pixelSize: Appearance.font.pixelSize.small
            text: OnlineWallpapers.query
            onAccepted: root.runSearch()
            Keys.onEscapePressed: event => event.accepted = false
        }

        ChoiceDropdown {
            visible: (root.provider?.sortings ?? []).length > 0
            maximumWidth: 170
            minimumWidth: 130
            currentValue: OnlineWallpapers.sorting.length > 0 ? OnlineWallpapers.sorting : (root.provider?.sortings?.[0] ?? "")
            options: (root.provider?.sortings ?? []).map(value => ({ "value": value, "displayName": root.optionNames[value] ?? value }))
            onSelected: value => {
                OnlineWallpapers.sorting = value;
                root.runSearch();
            }
        }

        ChoiceDropdown {
            visible: (root.provider?.categories ?? []).length > 0
            maximumWidth: 160
            minimumWidth: 120
            currentValue: OnlineWallpapers.category.length > 0 ? OnlineWallpapers.category : (root.provider?.categories?.[0] ?? "")
            options: (root.provider?.categories ?? []).map(value => ({ "value": value, "displayName": root.optionNames[value] ?? value }))
            onSelected: value => {
                OnlineWallpapers.category = value;
                root.runSearch();
            }
        }

        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            toggled: Config.options.background.online.fitScreen
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive
            onClicked: {
                Config.options.background.online.fitScreen = !Config.options.background.online.fitScreen;
                root.runSearch();
            }
            contentItem: MaterialSymbol {
                text: "fit_screen"
                iconSize: 20
                horizontalAlignment: Text.AlignHCenter
                color: parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                text: Translation.tr("Only wallpapers that fit this screen (%1×%2), where the source can tell").arg(OnlineWallpapers.screenWidth).arg(OnlineWallpapers.screenHeight)
            }
        }

        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.runSearch()
            contentItem: MaterialSymbol {
                text: "search"
                iconSize: 20
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        StyledIndeterminateProgressBar {
            visible: OnlineWallpapers.loading
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 4
                rightMargin: 4
            }
        }

        GridView {
            id: grid
            anchors.fill: parent
            cellWidth: width / root.columns
            cellHeight: cellWidth * 0.66
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: StyledScrollBar {}
            model: OnlineWallpapers.results
            onAtYEndChanged: if (atYEnd && count > 0) OnlineWallpapers.loadMore()

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: frame
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.wallpaperSelectorItemMargins
                    }
                    radius: Appearance.rounding.normal
                    color: hover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                    clip: true

                    OnlineThumbnail {
                        anchors {
                            fill: parent
                            margins: Appearance.sizes.wallpaperSelectorItemPadding
                        }
                        url: cell.modelData.thumb ?? ""
                    }

                    Rectangle { // Size, author and actions
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: Appearance.sizes.wallpaperSelectorItemPadding
                        }
                        implicitHeight: info.implicitHeight + 8
                        radius: Appearance.rounding.small
                        color: ColorUtils.transparentize(Appearance.colors.colLayer0, hover.hovered ? 0.1 : 0.35)

                        RowLayout {
                            id: info
                            anchors {
                                fill: parent
                                margins: 4
                                leftMargin: 8
                            }
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: [cell.modelData.width > 0 ? `${cell.modelData.width}×${cell.modelData.height}` : "",
                                    cell.modelData.lowRes ? Translation.tr("low resolution") : "", cell.modelData.author ?? ""]
                                    .filter(part => part.length > 0).join(" · ")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer0
                            }
                            Repeater {
                                model: hover.hovered ? [
                                    { "icon": "download", "tip": Translation.tr("Save to the library"), "act": () => OnlineWallpapers.download(cell.modelData, false) },
                                    { "icon": "open_in_new", "tip": Translation.tr("Open the source page"), "act": () => Qt.openUrlExternally(cell.modelData.pageUrl) },
                                    { "icon": "link", "tip": Translation.tr("Copy the image link"), "act": () => Quickshell.clipboardText = cell.modelData.full },
                                ] : []
                                delegate: RippleButton {
                                    required property var modelData
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    buttonRadius: Appearance.rounding.full
                                    onClicked: modelData.act()
                                    contentItem: MaterialSymbol {
                                        text: parent.modelData.icon
                                        iconSize: 16
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    StyledToolTip {
                                        text: parent.modelData.tip
                                    }
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: hover
                    }
                    TapHandler { // Click sets the wallpaper
                        onTapped: {
                            OnlineWallpapers.download(cell.modelData, true);
                            GlobalStates.wallpaperSelectorOpen = false;
                        }
                    }
                    StyledToolTip {
                        extraVisibleCondition: hover.hovered && (cell.modelData.title ?? "").length > 0
                        text: cell.modelData.title ?? ""
                    }
                }
            }
        }

        ColumnLayout { // Nothing to show
            anchors.centerIn: parent
            visible: OnlineWallpapers.results.length === 0 && !OnlineWallpapers.loading
            width: Math.min(parent.width - 40, 520)
            spacing: 8
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: OnlineWallpapers.error.length > 0 ? "cloud_off" : (root.provider?.icon ?? "public")
                iconSize: 48
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: OnlineWallpapers.error.length > 0 ? OnlineWallpapers.error : Translation.tr(root.provider?.description ?? "")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
