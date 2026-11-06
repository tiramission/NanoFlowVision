//! The look: a button held down shows the picture at 1:1, or fitted to the
//! window, without changing anything the reader has chosen. Which press is
//! a look, and what part of the frame the press must stay out of.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");

/// How far the pointer may travel while a press is still a look. One
/// point, the smallest movement a hand makes on purpose: a click that
/// wobbles is a look, a press that is meant to drag leaves it at once.
pub const slop: f32 = 1.0;

/// The button held down for a look, as the mode it shows: the left one
/// at 1:1, the right one fitting the picture to the room. Null when
/// neither is held, and when the press belongs to something drawn over the
/// photograph -- the top bar's stars, the filmstrip, the facts, the chip.
///
/// The press does not have to land on a pixel: the room around a fitted
/// picture is part of the view, and a reader who has just zoomed with the
/// wheel often has the pointer beside the photograph rather than on it.
/// Asking for a pixel made the look fail exactly there -- a picture at
/// 3x fills the room and takes a press anywhere, while one at 120% sits
/// under a pointer that is a few points past its edge.
pub fn mode(s: *app.State, c: *ui.Context, chrome: Chrome) ?app.ZoomMode {
    // A look already begun keeps itself, wherever the picture moved to:
    // the pointer was on the photograph when the press started, and asking
    // again would end it the moment a 1:1 picture shrank from under the
    // hand.
    if (s.peek) |held| {
        // A look lasts until the button is let go, a drag included: at 1:1
        // the picture is bigger than the room in most cases, and moving it
        // under the hand is what the held button is for.
        return switch (held.mode) {
            .actual => if (c.input.down and !c.input.secondary_down) .actual else null,
            .fit => if (c.input.secondary_down) .fit else null,
            else => null,
        };
    }
    const m = c.input.mouse;
    // The bars and the facts are their own controls; a press on them is
    // not a press on the view. The chip is a button too.
    if (chrome.bars and (m.y < chrome.top or m.y >= c.size.h - chrome.bottom)) return null;
    if (m.x >= c.size.w - 122 and m.y >= c.size.h - chrome.bottom - 32) return null;
    if (chrome.facts and m.x < 16 + 360 and m.y > c.size.h - chrome.bottom - 16 - 200) return null;
    if (c.input.secondary_down) return .fit;
    // The left button looks from the moment it goes down. A hand that then
    // moves drags the 1:1 picture, and the look lasts until the button is
    // let go -- the look is what the button is for.
    // The reader may have said the left button is the drag's alone: then
    // holding it changes nothing, and the size stays where the wheel left
    // it.
    if (s.hold == .drag) return null;
    if (c.input.down and !c.input.secondary_down) return .actual;
    return null;
}

/// What the chrome takes off the room this frame, for the press that has
/// to stay out of it.
pub const Chrome = struct {
    /// The bars are drawn and take clicks.
    bars: bool,
    top: f32,
    bottom: f32,
    /// The facts card stands.
    facts: bool,
};
