pragma Singleton

import Quickshell

/**
 * The tray slots to show: one per item, not one per registration.
 *
 * An app registers its StatusNotifierItem under a D-Bus name, and re-registers it under
 * a fresh name whenever the tray watcher or host changes - a shell reload, or a second
 * watcher taking over. Quickshell keys its items by that name and keeps registrations
 * whose name has since vanished, so Telegram can occupy nine slots after eight reloads,
 * eight of them frozen at the icon they were registered with. Collapse by the identity
 * the app reports and let the newest registration win: the shell already treats that
 * identity as the item - pinning, tooltips and menus address it by id, so two apps
 * sharing one could not be told apart here either.
 */
Singleton {
    function of(items) {
        var unique = [];
        for (var item of items) {
            var key = identity(item);
            var previous = key.length > 0 ? unique.findIndex(other => identity(other) === key) : -1;
            if (previous >= 0)
                unique.splice(previous, 1);
            unique.push(item);
        }
        return unique;
    }

    /// What the app calls itself. Unknown identity is never collapsed.
    function identity(item) {
        if (item.id.length > 0)
            return item.id;
        return item.title.length > 0 ? item.title : '';
    }
}
