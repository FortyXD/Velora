import QtQuick
import QtQml.Models
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

QtObject {
    id: root
    property var theme
    property var barStyle
    readonly property var base: Appearance.colors
    readonly property var overrides: theme?.config?.appearance?.palette?.roleOverrides ?? {}
    readonly property var roles: Object.assign({}, paletteJobs.object?.result ?? {}, theme?.previewPalette ?? {}, overrides)
    readonly property bool dark: (theme?.mode ?? (Appearance.m3colors.darkmode ? "dark" : "light")) === "dark"
    readonly property string accent: theme?.accent || theme?.config?.appearance?.palette?.accentColor || ""
    readonly property bool monochrome: theme?.config?.appearance?.palette?.type === "scheme-monochrome"
    // Older saved themes may carry only a seed. Ask the shell's generator for its colors
    // only while that theme is open. A dry run has no templates or desktop side effects.
    readonly property Instantiator paletteJobs: Instantiator {
        model: root.theme && !root.theme.previewPalette?.secondary_container && /^#[0-9a-f]{6}$/i.test(root.accent)
            ? [JSON.stringify([root.accent, root.theme.config?.appearance?.palette?.type, root.dark])] : []
        delegate: Process {
            id: job
            required property string modelData
            readonly property var args: JSON.parse(modelData)
            property var result: ({})
            command: ["matugen", "--dry-run", "--json", "hex", "-q", "--mode", args[2] ? "dark" : "light",
                "--type", args[1] && args[1] !== "auto" ? args[1] : "scheme-tonal-spot", "color", "hex", args[0]]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const generated = JSON.parse(text).colors;
                        job.result = Object.fromEntries(Object.entries(generated).map(([name, value]) => [name, value.default.color]));
                    } catch (error) { job.result = ({}); }
                }
            }
        }
    }
    readonly property color colPrimary: roles.primary ?? (monochrome ? (dark ? "white" : "black") : /^#[0-9a-f]{6}$/i.test(accent) ? accent : base.colPrimary)
    readonly property color colOnPrimary: overrides.primary
        ? Appearance.m3colors.contrastingInk(colPrimary, roles.on_primary ?? base.colOnPrimary) : roles.on_primary ?? base.colOnPrimary
    readonly property color colPrimaryContainer: roles.primary_container ?? base.colPrimaryContainer
    readonly property color colOnPrimaryContainer: roles.on_primary_container ?? base.colOnPrimaryContainer
    readonly property color colSecondary: roles.secondary ?? base.colSecondary
    readonly property color colTertiary: roles.tertiary ?? base.colTertiary
    readonly property color colSecondaryContainer: roles.secondary_container ?? base.colSecondaryContainer
    readonly property color colOnSecondaryContainer: roles.on_secondary_container ?? base.colOnSecondaryContainer
    readonly property color colSecondaryContainerHover: ColorUtils.mix(colSecondaryContainer, colOnSecondaryContainer, 0.9)
    readonly property color colTertiaryContainer: roles.tertiary_container ?? base.colTertiaryContainer
    readonly property color colOnTertiaryContainer: roles.on_tertiary_container ?? base.colOnTertiaryContainer
    readonly property color colLayer0: overrides.surface_container ?? roles.surface_container_low ?? (theme && dark !== Appearance.m3colors.darkmode ? (dark ? "#1a191c" : "#f5f3f6") : base.colLayer0)
    readonly property color colLayer2Base: roles.surface_container ?? base.colLayer2Base
    readonly property color colLayer4Base: roles.surface_container_highest ?? base.colLayer4Base
    readonly property color colLayer1: roles.surface_container_high ?? base.colLayer1
    readonly property color colOnSurface: roles.on_surface ?? (theme && dark !== Appearance.m3colors.darkmode ? (dark ? "#ede9ed" : "#1c191c") : base.colOnSurface)
    readonly property color colOnSurfaceVariant: roles.on_surface_variant ?? base.colOnSurfaceVariant
    readonly property color colOnLayer0: colOnSurface
    readonly property color colOnLayer1: colOnSurfaceVariant
    readonly property color colSubtext: roles.outline ?? base.colSubtext
    readonly property color colError: roles.error ?? base.colError
    readonly property color colOutlineVariant: roles.outline_variant ?? base.colOutlineVariant
    readonly property color colLayer0Border: theme ? ColorUtils.mix(colOutlineVariant, colLayer0, 0.4) : base.colLayer0Border
    readonly property color colShadow: base.colShadow
    readonly property real barOpacity: barStyle.backgroundOpacity >= 0 ? barStyle.backgroundOpacity
        : (barStyle.glass ? Math.min(0.6, 1 - Appearance.backgroundTransparency) : 1 - Appearance.backgroundTransparency)
    readonly property color colBarBackground: ColorUtils.applyAlpha(colLayer0, barOpacity)
}
