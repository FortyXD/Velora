import qs.modules.common
import QtQuick;

/**
 * A booru response.
 */
QtObject {
    property string provider
    property var tags
    property var page
    property var images
    property string message
    property bool pending: false // Request still running
    property bool failed: false // Network/HTTP failure: offer retry
    property bool nsfw: false
    property int limit: 20
}
