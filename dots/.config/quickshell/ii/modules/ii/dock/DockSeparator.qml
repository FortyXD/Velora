import QtQuick

DockTile {
    id: root
    separator: true
    onRightClicked: root.dock.dockMenuRequested(root)
}
