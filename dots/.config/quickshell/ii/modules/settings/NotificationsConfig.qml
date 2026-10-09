import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        title: Translation.tr("Notification popups")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout duration (ms)")
            description: Translation.tr("Used when the notification doesn't set its own")
            value: Config.options.notifications.timeout
            from: 1000
            to: 60000
            stepSize: 1000
            onValueChanged: {
                Config.options.notifications.timeout = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Show unread count in the bar")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("On-screen display")
        description: Translation.tr("Volume and brightness indicators")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout (ms)")
            value: Config.options.osd.timeout
            from: 100
            to: 3000
            stepSize: 100
            onValueChanged: {
                Config.options.osd.timeout = value;
            }
        }
    }
}
