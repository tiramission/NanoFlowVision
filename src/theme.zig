//! The gallery's look: two neutral rooms, graphite and paper, with no
//! colour of their own -- so the photographs are the only thing in the
//! window that has any. Hover brightens, selection inverts, the keyboard
//! cursor strokes an edge: state is said with light and shape, never with
//! a hue. docs/redesign/03-visual.md is the spec; this file holds its
//! values, and the test at the foot keeps them over the contrast lines so
//! a later tweak cannot quietly break them.

const std = @import("std");
const nanoui = @import("nanoui");

const white: nanoui.ui.Color = .{ .r = 1, .g = 1, .b = 1 };
const black: nanoui.ui.Color = .{};

/// The colors the views paint with, beyond nanoui's Theme slots. The
/// names are materials, not ranks: `page` is what the window is, `well`
/// is where a photograph waits, `ink` is the words.
pub const Colors = struct {
    /// The navigation column.
    sidebar: nanoui.ui.Color,
    /// What is chosen, and the ink on it. Both are the inverted pair, so
    /// the same tokens read as "the loud thing" in either room.
    picked: nanoui.ui.Color,
    on_picked: nanoui.ui.Color,
    /// The window's ground.
    page: nanoui.ui.Color,
    /// Menus, dialogs, toasts, the settings panel.
    card: nanoui.ui.Color,
    /// 1px strokes and separators.
    border: nanoui.ui.Color,
    /// The stronger stroke: a hovered edge, a control's own border.
    line2: nanoui.ui.Color,
    /// A tile's ground before its photograph arrives, and the place a
    /// file that cannot be read stays empty in.
    tile: nanoui.ui.Color,
    /// The well a photograph waits in: skeletons and empty room.
    well: nanoui.ui.Color,
    text: nanoui.ui.Color,
    secondary: nanoui.ui.Color,
    tertiary: nanoui.ui.Color,
    /// The inverted emphasis: a white ring on graphite, an ink ring on
    /// paper. Selection, primary buttons, sliders and progress all speak
    /// through it, and neither theme has to be told what it means.
    accent: nanoui.ui.Color,
    hover: nanoui.ui.Color,
    control: nanoui.ui.Color,
    control_on: nanoui.ui.Color,
    /// The star -- the one content colour the interface owns.
    grade: nanoui.ui.Color,
    green: nanoui.ui.Color,
    red: nanoui.ui.Color,
};

pub fn colors(dark: bool) Colors {
    if (dark) {
        return .{
            .sidebar = nanoui.ui.Color.hex(0x111316),
            .picked = nanoui.ui.Color.hex(0xedeef0),
            .on_picked = nanoui.ui.Color.hex(0x0e0f11),
            .page = nanoui.ui.Color.hex(0x0e0f11),
            .card = nanoui.ui.Color.hex(0x15171a),
            .border = nanoui.ui.Color.hex(0x23262a),
            .line2 = nanoui.ui.Color.hex(0x33373d),
            .tile = nanoui.ui.Color.hex(0x15171a),
            .well = nanoui.ui.Color.hex(0x16181b),
            .text = nanoui.ui.Color.hex(0xedeef0),
            .secondary = nanoui.ui.Color.hex(0xa2a5ab),
            .tertiary = nanoui.ui.Color.hex(0x787c83),
            .accent = nanoui.ui.Color.hex(0xedeef0),
            .hover = white.alpha(0.05),
            .control = nanoui.ui.Color.hex(0x1a1d21),
            .control_on = nanoui.ui.Color.hex(0x262a2f),
            .grade = nanoui.ui.Color.hex(0xe8b93b),
            .green = nanoui.ui.Color.hex(0x7fbf6a),
            .red = nanoui.ui.Color.hex(0xe86f5e),
        };
    }
    return .{
        .sidebar = nanoui.ui.Color.hex(0xf1f1ee),
        .picked = nanoui.ui.Color.hex(0x17181a),
        .on_picked = nanoui.ui.Color.hex(0xf7f7f4),
        .page = nanoui.ui.Color.hex(0xf7f7f4),
        .card = nanoui.ui.Color.hex(0xffffff),
        .border = nanoui.ui.Color.hex(0xe4e4df),
        .line2 = nanoui.ui.Color.hex(0xd2d2cc),
        .tile = nanoui.ui.Color.hex(0xedeDE9),
        .well = nanoui.ui.Color.hex(0xefefea),
        .text = nanoui.ui.Color.hex(0x17181a),
        .secondary = nanoui.ui.Color.hex(0x5a5c60),
        .tertiary = nanoui.ui.Color.hex(0x7c7e84),
        .accent = nanoui.ui.Color.hex(0x17181a),
        .hover = black.alpha(0.04),
        .control = nanoui.ui.Color.hex(0xe9e9e4),
        .control_on = nanoui.ui.Color.hex(0xffffff),
        .grade = nanoui.ui.Color.hex(0x8a6a10),
        .green = nanoui.ui.Color.hex(0x4b7a32),
        .red = nanoui.ui.Color.hex(0xa33227),
    };
}

/// nanoui's Theme slots, filled from the same palette the views read, so
/// kit's menus, sheets and toasts are dressed in the room they open in.
pub fn ui(dark: bool) nanoui.ui.Theme {
    const k = colors(dark);
    var t = if (dark) nanoui.ui.Theme.dark_theme else nanoui.ui.Theme.light;
    t.dark = dark;
    t.background = k.page;
    t.surface = k.card;
    // What a row or a menu item turns when the pointer is on it: the
    // panel's own ground, nudged, opaque, so text keeps its contrast.
    t.surface_hover = k.card.mix(if (dark) white else black, 0.06);
    t.text = k.text;
    t.muted = k.secondary;
    t.border = k.border;
    t.accent = k.accent;
    t.accent_hover = k.accent.mix(if (dark) white else black, 0.14);
    t.accent_text = k.on_picked;
    t.track = k.control;
    t.knob = k.accent;
    t.danger = k.red;
    t.success = k.green;
    t.font = "Geist";
    t.mono_font = "JetBrains Mono";
    return t;
}

pub fn forDark(want_dark: bool) nanoui.ui.Theme {
    return ui(want_dark);
}

// --- contrast, as WCAG 2.1 counts it -------------------------------------

/// One channel, from sRGB to the linear value the luminance wants.
fn linear(v: f32) f64 {
    const x: f64 = v;
    return if (x <= 0.04045) x / 12.92 else std.math.pow(f64, (x + 0.055) / 1.055, 2.4);
}

/// A color's relative luminance, 0 (black) to 1 (white).
pub fn luminance(c: nanoui.ui.Color) f64 {
    return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
}

/// How far apart two colors are in light: 1 is the same color, 21 is
/// black against white. WCAG's ratio, for text on a background.
pub fn contrast(fg: nanoui.ui.Color, bg: nanoui.ui.Color) f64 {
    const a = luminance(fg);
    const b = luminance(bg);
    const hi = @max(a, b);
    const lo = @min(a, b);
    return (hi + 0.05) / (lo + 0.05);
}

// What the interface writes on `page`, and the line each must clear:
// body text 4.5; the tertiary ink only ever carries a group label, a
// chevron or a disabled word, so the spec exempts it at 3 in both rooms.
test "every text token is over the contrast line" {
    for ([_]bool{ true, false }) |dark| {
        const k = colors(dark);
        const on = [_]struct { name: []const u8, fg: nanoui.ui.Color, min: f64 }{
            .{ .name = "ink", .fg = k.text, .min = 4.5 },
            .{ .name = "ink2", .fg = k.secondary, .min = 4.5 },
            .{ .name = "grade", .fg = k.grade, .min = 4.5 },
            .{ .name = "danger", .fg = k.red, .min = 4.5 },
            .{ .name = "ok", .fg = k.green, .min = 4.5 },
            // Icons and group labels only: 3, in both rooms.
            .{ .name = "ink3", .fg = k.tertiary, .min = 3 },
        };
        for (on) |pair| {
            const ratio = contrast(pair.fg, k.page);
            if (ratio < pair.min) {
                std.debug.print("\n{s}: {s} on page is {d:.2}:1, under {d}\n", .{
                    if (dark) "dark" else "light", pair.name, ratio, pair.min,
                });
                return error.ContrastTooLow;
            }
        }
        // The inverted pair carries its own ink: a primary button's label,
        // white on graphite and ink on paper.
        try std.testing.expect(contrast(k.on_picked, k.accent) >= 4.5);
        // And the tertiary never lands on the rail's slightly other ground
        // without clearing the same 3.
        try std.testing.expect(contrast(k.tertiary, k.sidebar) >= 3);
    }
}
