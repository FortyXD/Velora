# Control alignment

Material Symbols remain text items: ordinary text baselines, icon rotations and
intentional asymmetry (for example `play_arrow`) must not be normalized by moving
every glyph. Centered symbols disable Qt's integer anchor rounding instead.
An odd line height otherwise introduces a half-logical-pixel bias, magnified by
the output scale. This applies to shared settings tiles, status glyphs, bar,
sidebar and overlay controls without changing their hitboxes or text fonts.

Do not add `descent / 2` to each icon: rendered comparisons show that this can
push already-centered icons down. Native font rasterization and fractional
surface dimensions can still differ by one physical pixel.

Controls resize their `contentItem` to the available area. A centered action's
icon/label Row therefore lives **inside** a content Item and keeps its natural
size. Stretching the Row itself leaves its children at the leading edge. This
is different from settings/list rows whose labels intentionally fill the space
between a leading icon and a trailing switch/action.

The fixes cover:

- Shared MaterialSymbol center anchors (including existing StatusIcon and
  ConfigIconTile consumers); no global translation or font replacement.
- Toolbar icon/label and tab buttons, expanded/collapsed FABs, selection pills.
- Real implicit heights for optional icons and icon/label buttons; uniform,
  compact selection-pill heights with and without icons.
- Collapsed navigation-rail icon/highlight/caption groups inside their hitbox.

Waffle's FluentIcon uses SVGs, not this icon font. Asset padding, intentional
leading-edge list layouts and text baselines are not changed indiscriminately.
This is not a claim that every screen/state/theme has been visually inspected.

## Regression checks

```sh
python -m unittest discover -s tests -p test_ui_alignment.py -v
```

The geometry test loads production controls/layouts with isolated theme values
and no desktop services, in Basic and Fusion styles. It covers stretching,
icon-only/label-only/combined states, RTL selection content, selected/disabled
states, collapsed/expanded controls, implicit height and baseline alignment.

Optional pixel coverage requires Qt 6 Quick development libraries, `g++`,
`pkg-config`, fontconfig, Pillow and the installed Material Symbols Rounded
font. It renders 192 combinations: six icon sizes, four symmetric glyphs, two
fill states and real device pixel ratios 1, 1.25, 1.666667 and 2. Rendering uses
an isolated offscreen QQuickWindow, not recordings or clipboard captures of the
user's desktop. Missing optional prerequisites skip that test, not the geometry
checks when Qt Quick Test is available.
