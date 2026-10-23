import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * The weather on a card: now, where, and the next hours. Click to refresh.
 */
DesktopWidgetCard {
    id: root
    configEntryName: "weather"

    onClicked: Weather.refresh()

    ColumnLayout {
        anchors.fill: parent
        implicitWidth: Math.max(nowRow.implicitWidth, hours.implicitWidth)
        spacing: 12

        RowLayout {
            id: nowRow
            spacing: 12
            MaterialSymbol {
                text: Weather.hasData ? (Icons.getWeatherIcon(Weather.data.wCode, Weather.data.night) ?? "cloud") : (Weather.status === "error" ? "cloud_off" : "cloud_sync")
                iconSize: 56
                fill: 1
                color: root.colAccent
            }
            ColumnLayout {
                spacing: -2
                StyledText {
                    text: Weather.data.tempShort
                    font.pixelSize: 44
                    font.family: Appearance.font.family.expressive
                    font.weight: Font.Medium
                    color: root.colOnCard
                }
                StyledText {
                    Layout.maximumWidth: 200
                    elide: Text.ElideRight
                    text: Weather.hasData ? [Weather.data.description, Weather.place.name].filter(s => s.length > 0).join(" • ")
                        : Weather.status === "error" ? Weather.error : Translation.tr("Getting the weather…")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.colOnCardVariant
                }
            }
        }

        WeatherHours {
            id: hours
            visible: Weather.hourly.length > 0
            count: 6
            colText: root.colOnCard
            colSubtext: root.colOnCardVariant
        }
    }
}
