// SPDX-License-Identifier: GPL-3.0-only
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Config from 'resource:///org/gnome/shell/misc/config.js';
import {LoginDialog} from 'resource:///org/gnome/shell/gdm/loginDialog.js';

function allocate(actor, x, y, width, height) {
    actor.allocate(new Clutter.ActorBox({x1: Math.round(x), y1: Math.round(y),
        x2: Math.round(x + width), y2: Math.round(y + height)}));
}

export default class VeloraGreeter extends Extension {
    enable() {
        if (Main.sessionMode.currentMode !== 'gdm' || Config.PACKAGE_VERSION !== '51.1')
            return;
        this._dialogs = new Map();
        try {
            this._wallpaperMonitor = Gio.File.new_for_path('/var/lib/velora-greeter').monitor_directory(Gio.FileMonitorFlags.NONE, null);
        } catch (_) { /* The bundled theme also works without the sync service. */ }
        this._wallpaperMonitor?.connect('changed', () => {
            if (this._wallpaperTimer) GLib.source_remove(this._wallpaperTimer);
            this._wallpaperTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => {
                this._wallpaperTimer = 0;
                for (const view of this._dialogs.values())
                    view.background.set_style(this._backgroundStyle());
                return GLib.SOURCE_REMOVE;
            });
        });
        this._injections = new InjectionManager();
        const extension = this;
        this._injections.overrideMethod(LoginDialog.prototype, '_init', original => function (...args) {
            original.call(this, ...args);
            try { extension._attach(this); } catch (error) { console.error(error); extension.disable(); }
        });
        this._injections.overrideMethod(LoginDialog.prototype, 'vfunc_allocate', original => function (box) {
            original.call(this, box);
            const view = extension._dialogs.get(this);
            if (view) {
                try { extension._layout(this, view, box); } catch (error) { console.error(error); extension.disable(); }
            }
        });
        if (Main.screenShield._dialog instanceof LoginDialog)
            this._attach(Main.screenShield._dialog);
        this._tick = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._updateClock();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _attach(dialog) {
        if (this._dialogs.has(dialog))
            return;
        // If the native structure changes, leave that dialog entirely to GNOME.
        if (!dialog._authPrompt || !dialog._userSelectionBox)
            return;
        const background = new St.Widget({reactive: false, style: this._backgroundStyle()});
        const clock = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, reactive: false});
        const time = new St.Label({style_class: 'velora-clock'});
        const date = new St.Label({style_class: 'velora-date'});
        clock.add_child(time);
        clock.add_child(date);
        const brand = new St.BoxLayout({style_class: 'velora-brand', reactive: false});
        brand.add_child(new St.Icon({gicon: Gio.icon_new_for_string(`${this.path}/logo.svg`), icon_size: 26}));
        brand.add_child(new St.Label({text: 'Velora', y_align: Clutter.ActorAlign.CENTER}));
        const power = new St.Button({style_class: 'velora-power', can_focus: true,
            accessible_name: 'Power', child: new St.Icon({icon_name: 'system-shutdown-symbolic', icon_size: 22})});
        power.connect('clicked', () => Main.panel.statusArea.quickSettings?.menu.toggle());
        dialog.insert_child_at_index(background, 0);
        for (const actor of [clock, brand, power])
            dialog.add_child(actor);
        dialog.add_style_class_name('velora-greeter');
        const logoOpacity = dialog._logoBin?.opacity;
        if (dialog._logoBin) dialog._logoBin.opacity = 0;
        const destroyed = dialog.connect('destroy', () => this._dialogs.delete(dialog));
        this._dialogs.set(dialog, {background, clock, time, date, brand, power, destroyed, logoOpacity});
        this._updateClock();
        dialog.queue_relayout();
    }

    _backgroundStyle() {
        let path = `${this.path}/autumn.jpg`;
        try {
            const manifest = Gio.File.new_for_path('/var/lib/velora-greeter/current.json');
            if (manifest.query_info('standard::size', Gio.FileQueryInfoFlags.NONE, null).get_size() < 4096) {
                const [ok, contents] = manifest.load_contents(null);
                const name = ok ? JSON.parse(new TextDecoder().decode(contents)).image : '';
                if (typeof name === 'string' && /^wallpaper-[a-f0-9]{64}\.jpg$/.test(name)) {
                    const candidate = `/var/lib/velora-greeter/${name}`;
                    const info = Gio.File.new_for_path(candidate).query_info('standard::type,standard::size', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                    if (info.get_file_type() === Gio.FileType.REGULAR && info.get_size() < 16 * 1024 * 1024)
                        path = candidate;
                }
            }
        } catch (_) { /* An unavailable bridge always leaves the bundled wallpaper. */ }
        return `background-image: url("${path}"); background-size: cover; background-color: #261812;`;
    }

    _updateClock() {
        const now = GLib.DateTime.new_now_local();
        for (const view of this._dialogs.values()) {
            view.time.text = now.format('%H:%M');
            view.date.text = now.format('%A, %e %B');
        }
    }

    _layout(dialog, view, box) {
        const width = box.get_width();
        const height = box.get_height();
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        allocate(view.background, 0, 0, width, height);
        // Compact screens retain GNOME's native allocation for accessible authentication.
        const spacious = height / scale >= 720;
        view.clock.visible = spacious;
        if (spacious) {
            const [, clockHeight] = view.clock.get_preferred_height(width);
            allocate(view.clock, 0, height * 0.27, width, clockHeight);
            for (const actor of [dialog._authPrompt, dialog._userSelectionBox]) {
                if (!actor.visible)
                    continue;
                const [, naturalWidth] = actor.get_preferred_width(-1);
                const actorWidth = Math.min(Math.max(300 * scale, naturalWidth), width - 80 * scale);
                const [, naturalHeight] = actor.get_preferred_height(actorWidth);
                const actorHeight = naturalHeight;
                allocate(actor, (width - actorWidth) / 2, Math.max(height * 0.48, height - actorHeight - 64 * scale), actorWidth, actorHeight);
            }
        }
        allocate(view.brand, 32 * scale, 32 * scale, 160 * scale, 32 * scale);
        let powerY = height - 80 * scale;
        if (dialog._authPrompt.visible && dialog._authPrompt._inputWell) {
            const [, inputY] = dialog._authPrompt._inputWell.get_transformed_position();
            const [, dialogY] = dialog.get_transformed_position();
            powerY = inputY - dialogY;
        }
        allocate(view.power, width / 2 + 190 * scale, powerY, 48 * scale, 48 * scale);
    }

    disable() {
        this._wallpaperMonitor?.cancel();
        this._wallpaperMonitor = null;
        if (this._wallpaperTimer) GLib.source_remove(this._wallpaperTimer);
        this._wallpaperTimer = 0;
        if (this._tick)
            GLib.source_remove(this._tick);
        this._tick = 0;
        this._injections?.clear();
        for (const [dialog, view] of this._dialogs ?? []) {
            dialog.disconnect(view.destroyed);
            dialog.remove_style_class_name('velora-greeter');
            if (dialog._logoBin && view.logoOpacity !== undefined) dialog._logoBin.opacity = view.logoOpacity;
            for (const actor of [view.background, view.clock, view.brand, view.power])
                actor.destroy();
            dialog.queue_relayout();
        }
        this._dialogs?.clear();
    }
}
