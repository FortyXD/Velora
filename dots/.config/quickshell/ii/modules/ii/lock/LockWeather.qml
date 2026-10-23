import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The weather now on a card, with the next hours when the layout item says `hours`.
 * Data from Weather (in the settings app it reads what the shell saved).
 */
Rectangle {
    id: root
    property bool showHours: false
    readonly property bool hasContent: Weather.hasData

    implicitWidth: column.implicitWidth + 40
    implicitHeight: column.implicitHeight + 32
    radius: Appearance.rounding.verylarge
    color: Appearance.m3colors.m3surfaceContainer

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: 10

        RowLayout {
            spacing: 12
            MaterialSymbol {
                text: Weather.hasData ? (Icons.getWeatherIcon(Weather.data.wCode, Weather.data.night) ?? "cloud") : "cloud_sync"
                iconSize: 44
                fill: 1
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                spacing: -2
                StyledText {
                    text: Weather.data.tempShort
                    font.pixelSize: 34
                    font.family: Appearance.font.family.expressive
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.maximumWidth: 220
                    elide: Text.ElideRight
                    text: Weather.hasData ? [Weather.data.description, Weather.place.name].filter(s => s.length > 0).join(" • ") : Translation.tr("Weather")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
        WeatherHours {
            visible: root.showHours && Weather.hourly.length > 0
            count: 5
            colText: Appearance.colors.colOnSurface
            colSubtext: Appearance.colors.colOnSurfaceVariant
        }
    }
}
