import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar

StyledPopup {
    id: root

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 8

        // Header
        ColumnLayout {
            id: header
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                MaterialSymbol {
                    fill: 0
                    font.weight: Font.DemiBold
                    text: "location_on"
                    iconSize: Appearance.popup.iconSize
                    color: Appearance.popup.colText
                }

                StyledText {
                    text: Weather.place.name || Weather.data.city || Translation.tr("Unknown place")
                    font {
                        weight: Font.DemiBold
                        pixelSize: Appearance.popup.titleSize
                    }
                    color: Appearance.popup.colText
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.popup.captionSize
                color: Appearance.popup.colSubtext
                text: Weather.hasData ? `${Weather.data.temp} • ${Weather.data.description} • ${Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike)}`
                    : Weather.status === "error" ? Weather.error : Translation.tr("Getting the weather…")
            }
        }

        // The next hours
        WeatherHours {
            Layout.alignment: Qt.AlignHCenter
            visible: Weather.hourly.length > 0
            count: 6
            cellWidth: 48
            colText: Appearance.colors.colOnSurfaceVariant
            colSubtext: Appearance.colors.colSubtext
        }

        // The next days
        ColumnLayout {
            Layout.fillWidth: true
            visible: Weather.daily.length > 0
            spacing: 2
            Repeater {
                model: Weather.daily
                delegate: Rectangle {
                    id: dayRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: dayRowLayout.implicitHeight + 8
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh
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
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        MaterialSymbol {
                            text: Icons.getWeatherIcon(dayRow.modelData.code) ?? "cloud"
                            iconSize: Appearance.font.pixelSize.larger
                            fill: 1
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: `${dayRow.modelData.high} / ${dayRow.modelData.low}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }

        // Metrics grid
        GridLayout {
            id: gridLayout
            columns: 2
            rowSpacing: 5
            columnSpacing: 5
            uniformCellWidths: true

            WeatherCard {
                title: Translation.tr("UV Index")
                symbol: "wb_sunny"
                value: Weather.data.uv
            }
            WeatherCard {
                title: Translation.tr("Wind")
                symbol: "air"
                value: `(${Weather.data.windDir}) ${Weather.data.wind}`
            }
            WeatherCard {
                title: Translation.tr("Precipitation")
                symbol: "rainy_light"
                value: Weather.data.precip
            }
            WeatherCard {
                title: Translation.tr("Humidity")
                symbol: "humidity_low"
                value: Weather.data.humidity
            }
            WeatherCard {
                visible: Weather.data.visib.length > 0
                title: Translation.tr("Visibility")
                symbol: "visibility"
                value: Weather.data.visib
            }
            WeatherCard {
                title: Translation.tr("Pressure")
                symbol: "readiness_score"
                value: Weather.data.press
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

        // Footer: when, from where, how the place was found
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Weather.hasData
            text: [Translation.tr("Updated %1").arg(Qt.locale().toString(new Date(Weather.updatedAt), Config.options.time.format)), Weather.provider, Weather.sourceText]
                .filter(s => s.length > 0).join(" • ")
            font {
                weight: Font.Medium
                pixelSize: Appearance.font.pixelSize.smaller
            }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
