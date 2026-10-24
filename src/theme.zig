//! The gallery's look, as two complete themes: paper and ink in the light,
//! stepped charcoal in the dark. The pictures carry the colour, so the
//! chrome stays a near-monochrome around them and one accent speaks --
//! the amber of a darkroom lamp. Every pair below keeps its contrast:
//! body text 4.5:1 or better on the surfaces it sits on, in both themes.
//!
//! The tokens are nanoui's own (background, surface, text, accent, ...);
//! this file is the single place that says what they mean here.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// The accent, and the ink that sits on it: dark text on amber, both ways.
const accent_amber = ui.Color.hex(0xd97706);
const accent_amber_hover = ui.Color.hex(0xb45309);
const accent_amber_dark = ui.Color.hex(0xf59e0b);
const accent_amber_dark_hover = ui.Color.hex(0xfbbf24);
const ink = ui.Color.hex(0x1a1a1e);

pub const light: ui.Theme = .{
    .dark = false,
    // The gallery recesses one step below the chrome, so the thumbnails
    // sit on paper and the panels read as cards.
    .background = ui.Color.hex(0xf4f4f6),
    .surface = ui.Color.white,
    .surface_hover = ui.Color.hex(0xececef),
    .text = ink,
    .muted = ui.Color.hex(0x71717a),
    .border = ui.Color.hex(0xdddde0),
    .accent = accent_amber,
    .accent_hover = accent_amber_hover,
    .accent_text = ink,
    .track = ui.Color.hex(0xe9e9ec),
    .knob = ui.Color.white,
    .danger = ui.Color.hex(0xdc2626),
    .success = ui.Color.hex(0x16a34a),
    .shadow = .{ .a = 0.10 },
};

pub const dark: ui.Theme = .{
    .dark = true,
    // The chrome is charcoal, the gallery the deepest step: photographs
    // glow against near-black, the way a darkroom shows them.
    .background = ui.Color.hex(0x141416),
    .surface = ui.Color.hex(0x1e1e21),
    .surface_hover = ui.Color.hex(0x2a2a2e),
    .text = ui.Color.hex(0xededf0),
    .muted = ui.Color.hex(0x9d9da6),
    .border = ui.Color.hex(0x35353a),
    .accent = accent_amber_dark,
    .accent_hover = accent_amber_dark_hover,
    .accent_text = ink,
    .track = ui.Color.hex(0x2f2f34),
    .knob = ui.Color.hex(0xededf0),
    .danger = ui.Color.hex(0xf87171),
    .success = ui.Color.hex(0x4ade80),
    .shadow = .{ .a = 0.5 },
};

/// The theme for `dark`, or the light one.
pub fn forDark(want_dark: bool) ui.Theme {
    return if (want_dark) dark else light;
}
