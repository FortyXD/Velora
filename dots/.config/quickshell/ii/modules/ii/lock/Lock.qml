pragma ComponentBehavior: Bound
import qs.modules.common.panels.lock

LockScreen {
    id: root

    lockSurface: LockSurface {
        context: root.context
    }
    LockEditorWindow {}
}
