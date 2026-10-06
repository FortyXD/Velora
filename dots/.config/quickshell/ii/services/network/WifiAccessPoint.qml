import QtQuick

QtObject {
    required property var lastIpcObject
    readonly property string ssid: lastIpcObject.ssid
    readonly property string bssid: lastIpcObject.bssid
    readonly property int strength: lastIpcObject.strength
    readonly property int frequency: lastIpcObject.frequency
    readonly property bool active: lastIpcObject.active
    readonly property string security: lastIpcObject.security
    readonly property bool isSecure: security.length > 0
    readonly property string savedUuid: lastIpcObject.savedUuid ?? ""
    readonly property bool savedCredentials: lastIpcObject.savedCredentials ?? false

    property bool askingPassword: false
    property string errorText: ""
}
