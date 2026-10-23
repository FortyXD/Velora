import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather"

    implicitHeight: backgroundShape.implicitHeight
    implicitWidth: backgroundShape.implicitWidth

    onClicked: Weather.refresh()

    StyledDropShadow {
        target: backgroundShape
    }

    MaterialShape {
        id: backgroundShape
        anchors.fill: parent
        shape: MaterialShape.Shape.Pill
        color: Appearance.colors.colPrimaryContainer
        implicitSize: 200

        StyledText {
            font {
                pixelSize: 80
                family: Appearance.font.family.expressive
                weight: Font.Medium
            }
            color: Appearance.colors.colPrimary
            text: Weather.data.tempShort
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: 16
                topMargin: 20
            }
        }

        MaterialSymbol {
            iconSize: 80
            color: Appearance.colors.colOnPrimaryContainer
            text: Weather.hasData ? (Icons.getWeatherIcon(Weather.data.wCode, Weather.data.night) ?? "cloud") : (Weather.status === "error" ? "cloud_off" : "cloud_sync")
            anchors {
                left: parent.left
                bottom: parent.bottom

                leftMargin: 16
                bottomMargin: 20
            }
        }
    }
}
