import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.weather

/**
 * The weather now, then the next hours, the coming days and the details, as chosen
 * (options: showHours, showDays, showDetails). A click on the top refreshes it.
 */
Rectangle {
    id: root
    property Item host: null
    readonly property var options: root.host?.options ?? {}

    implicitHeight: column.implicitHeight + 24
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 10

        RippleButton { // Now
            Layout.fillWidth: true
            implicitHeight: nowRow.implicitHeight + 8
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            onClicked: Weather.refresh()
            contentItem: RowLayout {
                id: nowRow
                spacing: 12
                MaterialSymbol {
                    text: Weather.hasData ? (Icons.getWeatherIcon(Weather.data.wCode, Weather.data.night) ?? "cloud") : (Weather.status === "error" ? "cloud_off" : "cloud_sync")
                    iconSize: 40
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Weather.hasData ? Weather.data.temp : "--"
                        font {
                            family: Appearance.font.family.numbers
                            variableAxes: Appearance.font.variableAxes.numbers
                            pixelSize: Appearance.font.pixelSize.huge
                        }
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Weather.hasData ? `${Weather.data.description} • ${Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike)}`
                            : Weather.status === "error" ? Weather.error : Translation.tr("Getting the weather…")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                ColumnLayout {
                    spacing: 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignRight
                        text: Weather.busy ? "sync" : "location_on"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        Layout.maximumWidth: 120
                        elide: Text.ElideRight
                        text: Weather.place.name || Weather.data.city || ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        WeatherHours {
            Layout.alignment: Qt.AlignHCenter
            visible: (root.options.showHours ?? true) && Weather.hourly.length > 0
            count: Math.max(3, Math.min(8, Math.floor(column.width / 52)))
            cellWidth: 48
        }

        ColumnLayout { // The coming days
            Layout.fillWidth: true
            visible: (root.options.showDays ?? false) && Weather.daily.length > 0
            spacing: 2
            Repeater {
                model: Weather.daily
                delegate: Rectangle {
                    id: dayRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: dayRowLayout.implicitHeight + 8
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        id: dayRowLayout
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 10
                        StyledText {
                            Layout.preferredWidth: 64
                            text: dayRow.modelData.day
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                        MaterialSymbol {
                            text: Icons.getWeatherIcon(dayRow.modelData.code) ?? "cloud"
                            iconSize: Appearance.font.pixelSize.larger
                            fill: 1
                            color: Appearance.colors.colOnLayer2
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: `${dayRow.modelData.high} / ${dayRow.modelData.low}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        GridLayout { // Details
            Layout.fillWidth: true
            visible: (root.options.showDetails ?? false) && Weather.hasData
            columns: 2
            rowSpacing: 5
            columnSpacing: 5
            uniformCellWidths: true
            WeatherCard {
                title: Translation.tr("Wind")
                symbol: "air"
                value: `(${Weather.data.windDir}) ${Weather.data.wind}`
            }
            WeatherCard {
                title: Translation.tr("Humidity")
                symbol: "humidity_low"
                value: Weather.data.humidity
            }
            WeatherCard {
                title: Translation.tr("Precipitation")
                symbol: "rainy_light"
                value: Weather.data.precip
            }
            WeatherCard {
                title: Translation.tr("UV Index")
                symbol: "wb_sunny"
                value: Weather.data.uv
            }
            WeatherCard {
                title: Translation.tr("Sunrise")
                symbol: "wb_twilight"
                value: Weather.data.sunrise
            }
            WeatherCard {
                title: Translation.tr("Sunset")
                symbol: "bedtime"
                value: Weather.data.sunset
            }
        }
    }
}
