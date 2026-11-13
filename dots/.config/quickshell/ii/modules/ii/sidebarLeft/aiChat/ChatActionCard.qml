import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var entry
    readonly property var message: entry ?? ({role:"",text:"",model:"",status:"done",attachments:[],steps:[],error:"",source:null,hasActions:false})
    property bool live: false
    property bool expanded: false
    property bool confirmingDelete: false
    readonly property bool approval: live && Assistant.approval !== null
    readonly property bool legacyApproval: entry?.source?.functionPending ?? false
    readonly property bool remoteApproval: legacyApproval && entry?.source?.functionCall?.name === "remote_context"
    readonly property bool checkpointDeletable: !!entry?.transactionId && ["committed", "rolled_back", "failed"].includes(entry?.transactionState)
    spacing: 8
    RippleButtonWithIcon {
        visible: (root.entry?.steps?.length ?? 0) > 0
        Layout.fillWidth: true
        materialIcon: root.expanded ? "expand_less" : "check_circle"
        mainText: Translation.tr("Completed steps: %1").arg((root.entry?.steps?.length ?? 0))
        onClicked: root.expanded = !root.expanded
    }
    Repeater {
        model: root.expanded ? (root.entry?.steps ?? []) : []
        delegate: ChatTextBlock {
            required property var modelData
            Layout.fillWidth: true
            markdown: false
            content: "✓ " + modelData.label + (modelData.path ? "\n" + modelData.path : "")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
    StyledText {
        visible: root.live && Assistant.busy && !!Assistant.currentAction && !root.approval
        Layout.fillWidth: true
        text: Assistant.currentAction
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }
    Rectangle {
        visible: root.approval || root.legacyApproval
        Layout.fillWidth: true
        implicitHeight: approvalLayout.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSecondaryContainer
        ColumnLayout {
            id: approvalLayout
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8
            StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; font.bold: true; text: Translation.tr("Your confirmation is needed") }
            ScrollView {
                id: approvalScroll
                objectName: "chatApprovalScroll"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(320, approvalDetails.implicitHeight)
                contentWidth: availableWidth
                clip: true
                ChatTextBlock {
                    id: approvalDetails
                    objectName: "chatApprovalText"
                    width: approvalScroll.availableWidth; markdown: false
                    content: {
                        if (root.approval) return Assistant.actionLabel(Assistant.approval?.tool ?? "") + "\n" + Assistant.approvalDescription();
                        if (root.remoteApproval) {
                            const args = root.entry.source.functionCall.args;
                            return Translation.tr("Send conversation context to %1?").arg(args.endpoint) + "\n"
                                + Translation.tr("Messages: %1").arg(args.messageCount) + (args.attachment ? "\n" + args.attachment : "");
                        }
                        return Translation.tr("Review this command in the protected agent before running it?");
                    }
                }
            }
            Image {
                visible: root.approval && !!Assistant.approval?.details?.preview
                Layout.fillWidth: true; Layout.preferredHeight: visible ? 160 : 0
                source: visible ? "data:image/png;base64," + Assistant.approval.details.preview : ""
                fillMode: Image.PreserveAspectFit
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "check"; mainText: root.remoteApproval ? Translation.tr("Allow sending context") : Translation.tr("Allow this action")
                    enabled: !root.approval || Assistant.approvalReviewComplete
                    onClicked: { if (root.approval) Assistant.decide(true); else Ai.approveCommand(root.message.source); }
                }
                RippleButtonWithIcon {
                    materialIcon: "close"; mainText: Translation.tr("Cancel")
                    onClicked: { if (root.approval) Assistant.decide(false); else Ai.rejectCommand(root.message.source); }
                }
            }
        }
    }
    Repeater {
        model: root.live ? Assistant.choices : []
        delegate: RippleButtonWithIcon {
            required property var modelData
            Layout.fillWidth: true
            mainText: modelData.label || modelData.value
            materialIcon: "arrow_forward"
            enabled: !SidebarChat.busy
            onClicked: Assistant.submitChoice(modelData.value, modelData.label, "sidebar")
        }
    }
    ChatTextBlock {
        visible: !!root.entry?.transactionState
        Layout.fillWidth: true; markdown: false
        content: {
            const labels = {preparing:"Preparing a checkpoint",running:"Task in progress",committed:"Changes saved",rolled_back:"Changes rolled back",rollback_conflict:"Rollback paused: files changed since this task",failed:"Task failed",checkpoint_deleted:"Checkpoint removed"};
            return Translation.tr(labels[root.entry?.transactionState] ?? root.entry?.transactionState ?? "");
        }
        color: root.entry?.transactionState === "rollback_conflict" ? Appearance.colors.colError : Appearance.colors.colSubtext
    }
    ChatTextBlock {
        visible: (root.entry?.conflicts?.length ?? 0) > 0
        Layout.fillWidth: true; markdown: false
        content: Translation.tr("These files were preserved. Review their newer changes before retrying rollback:") + "\n" + (root.entry?.conflicts ?? []).join("\n")
        color: Appearance.colors.colError
    }
    Flow {
        visible: (root.entry?.rollbackAvailable ?? false) || root.checkpointDeletable
        Layout.fillWidth: true; spacing: 8
        RippleButtonWithIcon {
            objectName: "chatRollback"
            visible: root.entry?.rollbackAvailable ?? false
            materialIcon: "undo"; mainText: Translation.tr("Roll back changes")
            enabled: !SidebarChat.busy
            onClicked: SidebarChat.rollback(root.entry)
        }
        RippleButtonWithIcon {
            materialIcon: "delete_history"; mainText: Translation.tr("Remove checkpoint")
            visible: root.checkpointDeletable
            enabled: !SidebarChat.busy
            onClicked: root.confirmingDelete = !root.confirmingDelete
        }
    }
    ColumnLayout {
        visible: root.confirmingDelete && root.checkpointDeletable
        Layout.fillWidth: true
        ChatTextBlock { Layout.fillWidth: true; markdown: false; content: Translation.tr("Remove this checkpoint permanently? These changes will no longer be reversible from this chat.") }
        RowLayout {
            RippleButtonWithIcon { materialIcon: "delete"; mainText: Translation.tr("Remove checkpoint"); enabled: !SidebarChat.busy; onClicked: { if (SidebarChat.deleteCheckpoint(root.entry)) root.confirmingDelete = false; } }
            RippleButtonWithIcon { materialIcon: "close"; mainText: Translation.tr("Keep checkpoint"); onClicked: root.confirmingDelete = false }
        }
    }
    ChatTextBlock { visible: !!(root.entry?.error ?? ""); Layout.fillWidth: true; content: (root.entry?.error ?? ""); markdown: false; color: Appearance.colors.colError }
}
