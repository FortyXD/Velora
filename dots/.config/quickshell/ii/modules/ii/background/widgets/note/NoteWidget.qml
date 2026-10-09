import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * Sticky note. The pencil button edits it in place: Ctrl+Enter or the check button saves, Esc cancels.
 * While editing, the background layer asks for keyboard focus (GlobalStates.desktopWidgetEditing).
 */
DesktopWidgetCard {
    id: root
    configEntryName: "note"

    readonly property var options: Config.options.background.widgets.note
    property bool editing: false

    hoverEnabled: true
    draggable: root.placementStrategy === "free" && !root.editing

    function startEditing() {
        noteField.text = root.options.text;
        root.editing = true;
        focusTimer.restart();
    }
    function save() {
        root.options.text = noteField.text;
        root.editing = false;
    }
    function cancel() {
        root.editing = false;
    }

    onEditingChanged: GlobalStates.desktopWidgetEditing = root.editing
    Component.onDestruction: if (root.editing) GlobalStates.desktopWidgetEditing = false

    Timer { // The layer gets keyboard focus a moment after asking for it
        id: focusTimer
        interval: 60
        onTriggered: {
            noteField.forceActiveFocus();
            noteField.cursorPosition = noteField.text.length;
        }
    }

    component NoteButton: RippleButton {
        id: noteButton
        property string buttonIcon
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: root.colLayer
        colBackgroundHover: ColorUtils.mix(root.colLayer, root.colOnCard, 0.85)
        colRipple: ColorUtils.mix(root.colLayer, root.colOnCard, 0.7)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: noteButton.buttonIcon
            iconSize: 18
            color: root.colOnCard
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item { // Width of the note
            implicitWidth: 260
            implicitHeight: 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol {
                text: "sticky_note_2"
                iconSize: 20
                fill: 1
                color: root.colAccent
            }
            StyledText {
                Layout.fillWidth: true
                text: root.options.title.length > 0 ? root.options.title : Translation.tr("Note")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.colOnCard
            }
            NoteButton {
                visible: root.editing
                buttonIcon: "close"
                onClicked: root.cancel()
                StyledToolTip {
                    text: Translation.tr("Cancel") + " (Esc)"
                }
            }
            NoteButton {
                opacity: (root.editing || root.containsMouse) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                buttonIcon: root.editing ? "check" : "edit"
                onClicked: root.editing ? root.save() : root.startEditing()
                StyledToolTip {
                    text: root.editing ? Translation.tr("Save") + " (Ctrl+Enter)" : Translation.tr("Edit")
                }
            }
        }

        StyledText { // Reading
            visible: !root.editing
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            text: root.options.text.length > 0 ? root.options.text : Translation.tr("Empty note. Hover and press the pencil to write something.")
            wrapMode: Text.Wrap
            font.family: Appearance.font.family.reading
            font.pixelSize: Appearance.font.pixelSize.normal
            lineHeight: 1.15
            color: root.options.text.length > 0 ? root.colOnCard : root.colOnCardVariant
        }

        StyledTextArea { // Writing
            id: noteField
            visible: root.editing
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            Layout.minimumHeight: 100
            wrapMode: TextEdit.Wrap
            padding: 10
            color: root.colOnCard
            placeholderText: Translation.tr("Write something to remember...")
            font.family: Appearance.font.family.reading
            font.pixelSize: Appearance.font.pixelSize.normal
            background: Rectangle {
                radius: Appearance.rounding.small
                color: root.colLayer
                border.width: noteField.activeFocus ? 2 : 0
                border.color: root.colAccent
            }
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                    root.save();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                }
            }
        }
    }
}
