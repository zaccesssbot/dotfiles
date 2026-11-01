# Accessibility

> Part of [btop](README.md). What the btop themes in this folder change on screen.

## Contrast

Every text colour in a btop theme here is the theme's own foreground, its muted text or one of its
terminal colours, all taken from `palette/zacess.json`. The generator holds each of them to at
least 4.5:1 against the theme's background and stops if one falls short. The lowest text contrast
across the eight themes is 5.99:1 (Zacess Light) and the selected row keeps at least 7.48:1.

| What | Colour slot | Floor |
| --- | --- | --- |
| Main text, titles and graph labels | Foreground | 7:1 |
| Inactive text | Muted text | 4.5:1 |
| Hotkey letters and process details | Cyan terminal colour | 7:1 (4.5:1 in a theme that marks it dim) |
| Selected process row | Selection text on the selection background | 4.5:1 |

## Colour is never the only signal

The CPU, memory, network and process boxes each keep their own colour (green, yellow, magenta and
blue) and their own title, so a box is found by its name as well as its colour. Meters and graphs
show their values as numbers beside them.

## Background

`zt` sets `theme_background = True`, so btop draws on the terminal's own background and matches the
terminal's light or dark Zacess theme rather than painting a block of its own.

## Motion

btop redraws its graphs on a timer (`update_ms` in `btop.conf`, two seconds by default). It has no
pause key: `q` quits and `Esc` opens its menu, where the update time can be raised. The built-in
`TTY` theme, under Options, Color theme, stays available as a fallback that uses only the
terminal's sixteen colours.
