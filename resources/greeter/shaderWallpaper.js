// SPDX-License-Identifier: GPL-3.0-only
import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

const presets = ['aurora', 'liquid', 'grid', 'dunes'];

function source(directory, name) {
    const [, bytes] = Gio.File.new_for_path(directory + '/' + name + '.glsl').load_contents(null);
    return new TextDecoder().decode(bytes);
}

const Wallpaper = GObject.registerClass({
    Implements: [Clutter.Content],
}, class VeloraShaderWallpaper extends GObject.Object {
    configure(context, directory, settings) {
        const declarations = 'uniform float time; uniform vec2 resolution; uniform vec4 color1, color2, color3, color4;\n'
            + source(directory, 'wallpaper-noise') + source(directory, settings.name);
        const snippet = Cogl.Snippet.new(Cogl.SnippetHook.TEXTURE_LOOKUP, declarations, null);
        snippet.set_replace('cogl_texel = wallpaper(cogl_tex_coord.st) * vec4(.54, .54, .54, 1.);');
        this.pipeline = Cogl.Pipeline.new(context);
        this.pipeline.set_layer_null_texture(0);
        this.pipeline.add_layer_snippet(0, snippet);
        this.sizeUniform = this.pipeline.get_uniform_location('resolution');
        this.timeUniform = this.pipeline.get_uniform_location('time');
        settings.colors.forEach((hex, i) => {
            const rgb = hex.match(/../g).map(channel => parseInt(channel, 16) / 255);
            this.pipeline.set_uniform_float(this.pipeline.get_uniform_location('color' + (i + 1)), 4, 1, [...rgb, 1]);
        });
        this.time = 40;
    }

    vfunc_paint_content(actor, root) {
        const box = actor.get_content_box();
        this.pipeline.set_uniform_float(this.sizeUniform, 2, 1, [box.get_width(), box.get_height()]);
        this.pipeline.set_uniform_1f(this.timeUniform, this.time);
        const node = Clutter.PipelineNode.new(this.pipeline);
        node.add_texture_rectangle(box, 0, 0, 1, 1);
        root.add_child(node);
    }
});

export function createWallpaper(stage, directory, settings) {
    if (!settings || !presets.includes(settings.name) || !Array.isArray(settings.colors) ||
        settings.colors.length !== 4 || !settings.colors.every(hex => typeof hex === 'string' && /^[0-9a-f]{6}$/.test(hex)) ||
        !Number.isFinite(settings.speed) || settings.speed < .25 || settings.speed > 3 ||
        !Number.isInteger(settings.fps) || settings.fps < 5 || settings.fps > 60)
        return null;
    const content = new Wallpaper();
    content.configure(stage.context.get_backend().get_cogl_context(), directory, settings);
    const actor = new Clutter.Actor({content, x_expand: true, y_expand: true, reactive: false});
    St.Settings.get().bind_property('enable-animations', actor, 'visible', GObject.BindingFlags.SYNC_CREATE);
    const interval = Math.ceil(1000 / settings.fps);
    let timer = 0;
    function sync() {
        if (actor.mapped && !timer) {
            let previous = GLib.get_monotonic_time();
            timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, interval, () => {
                const now = GLib.get_monotonic_time();
                content.time += (now - previous) * settings.speed / 1e6;
                previous = now;
                content.invalidate();
                return GLib.SOURCE_CONTINUE;
            });
        } else if (!actor.mapped && timer) {
            GLib.source_remove(timer);
            timer = 0;
        }
    }
    actor.connect('notify::mapped', sync);
    actor.connect('destroy', () => {
        if (timer) GLib.source_remove(timer);
        timer = 0;
    });
    sync();
    return actor;
}
