import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** The fixed routes of the profile being edited: destination, prefix length, gateway and metric. */
ColumnLayout {
    id: root
    required property string fieldKey
    readonly property var routes: ProfileEditor.value(root.fieldKey, []) ?? []

    function update(index, name, value): void {
        const next = root.routes.map(route => Object.assign({}, route));
        next[index][name] = value;
        ProfileEditor.set(root.fieldKey, next);
    }

    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 6

    StyledText {
        text: Translation.tr("Routes")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer2
    }

    Repeater {
        model: root.routes.length
        delegate: RowLayout {
            id: routeRow
            required property int index
            readonly property var route: root.routes[routeRow.index] ?? ({})
            Layout.fillWidth: true
            spacing: 6
            RouteField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Destination")
                text: routeRow.route.dest ?? ""
                onTextEdited: root.update(routeRow.index, "dest", text)
            }
            RouteField {
                Layout.preferredWidth: 70
                placeholderText: Translation.tr("Prefix")
                text: `${routeRow.route.prefix ?? ""}`
                onTextEdited: root.update(routeRow.index, "prefix", parseInt(text) || 0)
            }
            RouteField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Gateway")
                text: routeRow.route["next-hop"] ?? ""
                onTextEdited: root.update(routeRow.index, "next-hop", text)
            }
            RouteField {
                Layout.preferredWidth: 70
                placeholderText: Translation.tr("Metric")
                text: routeRow.route.metric === null || routeRow.route.metric === undefined ? "" : `${routeRow.route.metric}`
                onTextEdited: root.update(routeRow.index, "metric", text.length > 0 ? (parseInt(text) || 0) : null)
            }
            DialogButton {
                buttonText: Translation.tr("Remove")
                onClicked: ProfileEditor.set(root.fieldKey, root.routes.filter((route, index) => index !== routeRow.index))
            }
        }
    }

    DialogButton {
        buttonText: Translation.tr("Add a route")
        onClicked: ProfileEditor.set(root.fieldKey, [...root.routes, { dest: "", prefix: 24, "next-hop": "", metric: null }])
    }
}
