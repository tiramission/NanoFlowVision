//! The gallery's look: nanomon's palettes, on warm charcoal or cream, with
//! amber for what is chosen. The colors are Harness's Codegraff sets, the
//! same ones nanomon (justrach/nanomon, MIT) uses; the words are set in
//! Geist and the figures in JetBrains Mono where they are installed, and
//! they fall back where they are not. This file is the single place that
//! says what the interface's colors mean; docs/design.md documents it.

const std = @import("std");
const nanoui = @import("nanoui");

const white: nanoui.ui.Color = .{ .r = 1, .g = 1, .b = 1 };
const black: nanoui.ui.Color = .{};

/// The colors the views paint with, beyond nanoui's Theme slots.
pub const Colors = struct {
    sidebar: nanoui.ui.Color,
    /// The selected item, and the ink on it.
    picked: nanoui.ui.Color,
    on_picked: nanoui.ui.Color,
    page: nanoui.ui.Color,
    card: nanoui.ui.Color,
    border: nanoui.ui.Color,
    /// The well a photograph waits in before it is decoded.
    well: nanoui.ui.Color,
    text: nanoui.ui.Color,
    secondary: nanoui.ui.Color,
    tertiary: nanoui.ui.Color,
    accent: nanoui.ui.Color,
    hover: nanoui.ui.Color,
    control: nanoui.ui.Color,
    control_on: nanoui.ui.Color,
    green: nanoui.ui.Color,
    red: nanoui.ui.Color,
};

pub fn colors(dark: bool) Colors {
    if (dark) {
        const bg = nanoui.ui.Color.hex(0x16140f);
        const amber = nanoui.ui.Color.hex(0xe8a33d);
        return .{
            .sidebar = nanoui.ui.Color.hex(0x1b1914),
            .picked = amber,
            .on_picked = bg,
            .page = bg,
            .card = nanoui.ui.Color.hex(0x1f1c16),
            .border = bg.mix(white, 0.09),
            .well = nanoui.ui.Color.hex(0x191712),
            .text = nanoui.ui.Color.hex(0xedeae2),
            .secondary = nanoui.ui.Color.hex(0x9a9384),
            .tertiary = nanoui.ui.Color.hex(0x5c564b),
            .accent = amber,
            .hover = white.alpha(0.05),
            .control = nanoui.ui.Color.hex(0x221f19),
            .control_on = nanoui.ui.Color.hex(0x37322a),
            .green = nanoui.ui.Color.hex(0x7fa86b),
            .red = nanoui.ui.Color.hex(0xd2674f),
        };
    }
    const bg = nanoui.ui.Color.hex(0xfaf8f3);
    const amber = nanoui.ui.Color.hex(0xc77d20);
    return .{
        .sidebar = nanoui.ui.Color.hex(0xf3efe6),
        .picked = amber,
        .on_picked = nanoui.ui.Color.hex(0xfffdf8),
        .page = bg,
        .card = nanoui.ui.Color.hex(0xf0ece3),
        .border = bg.mix(black, 0.09),
        .well = nanoui.ui.Color.hex(0xe9e3d6),
        .text = nanoui.ui.Color.hex(0x1a1813),
        .secondary = nanoui.ui.Color.hex(0x6b6557),
        .tertiary = nanoui.ui.Color.hex(0xa8a090),
        .accent = amber,
        .hover = black.alpha(0.04),
        .control = nanoui.ui.Color.hex(0xebe5d9),
        .control_on = nanoui.ui.Color.hex(0xfffdf8),
        .green = nanoui.ui.Color.hex(0x5c7e47),
        .red = nanoui.ui.Color.hex(0xb14228),
    };
}

/// nanoui's Theme slots, filled the way nanomon fills them: the page is
/// the background, the chrome sits on `sidebar` and `card`, amber picks.
pub fn ui(dark: bool) nanoui.ui.Theme {
    const k = colors(dark);
    var t = if (dark) nanoui.ui.Theme.dark_theme else nanoui.ui.Theme.light;
    t.background = k.page;
    t.surface = k.control_on;
    t.surface_hover = k.control;
    t.text = k.text;
    t.muted = k.secondary;
    t.border = k.border;
    t.accent = k.accent;
    t.accent_hover = k.accent.mix(if (dark) white else black, 0.14);
    t.accent_text = k.on_picked;
    t.track = k.control;
    t.danger = k.red;
    t.success = k.green;
    t.font = "Geist";
    t.mono_font = "JetBrains Mono";
    return t;
}

pub fn forDark(want_dark: bool) nanoui.ui.Theme {
    return ui(want_dark);
}
