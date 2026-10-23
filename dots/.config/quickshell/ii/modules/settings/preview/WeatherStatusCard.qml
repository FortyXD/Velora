import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What the shell knows about the weather right now: the conditions, the place and how it was found,
 * when and from where it came, or what went wrong. "Refresh" asks the shell to fetch again.
 */
Rectangle {
    id: root
    Layout.fillWidth: true
    Layout.leftMargin: 6
    Layout.rightMargin: 6
    implicitHeight: content.implicitHeight + 32
    radius: Appearance.rounding.normal
    color: Weather.status === "error" && !Weather.hasData ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
    readonly property color colOn: Weather.status === "error" && !Weather.hasData ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer

    readonly property bool settingsSearchable: true
    property string searchText: Translation.tr("Weather now Refresh")

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: 16
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            MaterialSymbol {
                text: Weather.hasData ? (Icons.getWeatherIcon(Weather.data.wCode, Weather.data.night) ?? "cloud") : (Weather.status === "error" ? "cloud_off" : "cloud_sync")
                iconSize: 52
                fill: 1
                color: root.colOn
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    spacing: 10
                    StyledText {
                        text: Weather.data.tempShort
                        font.pixelSize: 36
                        font.family: Appearance.font.family.expressive
                        font.weight: Font.Medium
                        color: root.colOn
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 6
                        visible: Weather.hasData
                        text: `${Weather.data.description} • ${Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike)}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.colOn
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: {
                        if (!Weather.hasData) return Weather.status === "error" ? Weather.error : Translation.tr("Getting the weather…");
                        const where = [Weather.place.name || Translation.tr("Unknown place"), Weather.sourceText].filter(s => s.length > 0).join(" • ");
                        return where;
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.colOn
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: Weather.hasData
                    wrapMode: Text.Wrap
                    text: Translation.tr("Updated %1 from %2").arg(Qt.locale().toString(new Date(Weather.updatedAt), `${Config.options.time.format}, d MMM`)).arg(Weather.provider)
                        + (Weather.status === "error" ? ` • ${Translation.tr("last try failed: %1").arg(Weather.error)}` : "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colOn
                    opacity: 0.8
                }
            }
            RippleButton {
                Layout.alignment: Qt.AlignTop
                implicitHeight: 36
                leftPadding: 12
                rightPadding: 14
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: Weather.refresh()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Refresh")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        WeatherHours {
            Layout.alignment: Qt.AlignHCenter
            visible: Weather.hourly.length > 0
            count: 8
            cellWidth: 52
            colText: root.colOn
            colSubtext: root.colOn
        }

        StyledText {
            Layout.fillWidth: true
            visible: Weather.place.source === "ip"
            wrapMode: Text.Wrap
            text: Translation.tr("The place was guessed from your IP address. With a VPN or proxy that can be another city: type yours below.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colOn
        }
    }
}
