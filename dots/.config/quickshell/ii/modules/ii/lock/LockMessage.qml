import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// The user's own text on the lock screen (lock.message)
StyledText {
    id: root
    property bool placeholder: false // In editors, so an empty message can still be placed
    readonly property bool hasContent: Config.options.lock.message.length > 0

    width: Math.min(implicitWidth, 640)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.hasContent ? Config.options.lock.message : Translation.tr("Your message")
    opacity: root.hasContent ? 1 : 0.6
    font.pixelSize: Appearance.font.pixelSize.normal
    color: Appearance.colors.colOnLayer0
    style: Text.Raised
    styleColor: ColorUtils.transparentize(Appearance.colors.colShadow, 0.4)
}
