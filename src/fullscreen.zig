//! Full screen: taking the window over for one photograph, giving it
//! back, and the chrome standing back in that room. The state lives in
//! `app.State`; the window is touched only here, through `screen.zig`,
//! and only at the top of a frame -- never in the middle of a build.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const large = @import("large.zig");
const model = @import("model.zig");
const screen = @import("screen.zig");
const win = @import("win.zig");

/// How long the chrome waits for a movement before standing back, and
/// how long it takes to leave or come back. The fade is short enough to
/// feel like the room is changing rather than like a menu.
pub const quiet: f64 = 2.2;
pub const fade: f32 = 0.14;

/// A window's rectangle in points: the frame the settings keep while a
/// full screen stands.
pub const WindowRect = struct { x: f64, y: f64, width: f64, height: f64 };

/// Full screen on, or off. From the wall it opens the cursor's picture
/// (or the first) large first: a full screen of nothing is not the
/// point.
pub fn toggle(s: *app.State, c: *ui.Context) void {
    // The Mac's full screen is animated and asynchronous; a second
    // request while it is moving would fight the first.
    if (builtin.os.tag == .macos and s.window != null and c.time - s.fullscreen_at < 0.8) return;
    s.fullscreen_at = c.time;
    if (!s.fullscreen and s.large == null) {
        const pic = cursorOrFirst(s) orelse return;
        large.show(s, pic);
    }
    s.fullscreen_pending = !s.fullscreen;
    c.changed = true;
}

/// The picture the keyboard is on, or the first one.
fn cursorOrFirst(s: *app.State) ?*model.Picture {
    if (s.select.cursor) |i| if (i < s.shown.len) return s.shown[i];
    if (s.shown.len > 0) return s.shown[0];
    return null;
}

/// Takes the window over (or gives it back). The frame it had is kept
/// for the settings, which must never write a full-screen rectangle.
pub fn apply(s: *app.State, c: *ui.Context, on: bool) void {
    const w = s.window orelse {
        s.fullscreen = on;
        quietDown(s, c);
        return;
    };
    if (on) {
        const f = w.frame();
        s.frame_before = .{ .x = f.x, .y = f.y, .width = f.width, .height = f.height };
        if (builtin.os.tag == .windows) {
            if (w.hwnd) |hwnd| s.maximized_before = win.zoomed(@ptrCast(hwnd));
        }
        if (!screen.set(w, true)) return;
        s.fullscreen = true;
        s.fullscreen_since = c.time;
        quietDown(s, c);
    } else {
        _ = screen.set(w, false);
        s.fullscreen = false;
        s.frame_before = null;
        quietDown(s, c);
    }
    if (w.surface) |surface| surface.requestFrame();
}

/// The chrome is up, and the clock starts again: the room has just been
/// changed, and a bar that vanished in the same breath would be a flash.
fn quietDown(s: *app.State, c: *ui.Context) void {
    s.chrome_shown_at = c.time;
    s.chrome_hidden = false;
    c.changed = true;
}

/// The frame the settings should keep: the window as it was before full
/// screen, never the full-screen rectangle itself.
pub fn frameForSettings(s: *app.State) ?WindowRect {
    if (s.fullscreen) return s.frame_before;
    const w = s.window orelse return null;
    const f = w.frame();
    return .{ .x = f.x, .y = f.y, .width = f.width, .height = f.height };
}

/// Called by the large view with this frame's input, and it is the only
/// place the quiet is judged: no timer, no second clock. `c.time` moves
/// with every frame the framework draws, so a pointer at rest, a key
/// being held, and a wheel turning all read the same way.
pub fn noteInput(s: *app.State, c: *ui.Context) void {
    if (!s.fullscreen) {
        s.chrome_hidden = false;
        s.chrome_fade = 1;
        return;
    }
    // Anything that is not "still" brings the chrome back and starts the
    // wait again. A key held down keeps sending frames; each one counts.
    const busy = c.input.pressed or c.input.released or c.input.scroll.y != 0 or
        c.input.key != null or c.input.chars.len > 0 or c.input.shortcut != null or
        c.input.mouse.x != s.idle_mouse_x or c.input.mouse.y != s.idle_mouse_y;
    s.idle_mouse_x = c.input.mouse.x;
    s.idle_mouse_y = c.input.mouse.y;
    if (busy) {
        s.chrome_shown_at = c.time;
        s.chrome_hidden = false;
    } else if (!s.chrome_hidden and c.time - s.chrome_shown_at >= quiet) {
        s.chrome_hidden = true;
    }

    // The fade is driven here too, so it runs with the frames the quiet
    // already asks for: one value the whole chrome reads.
    const target: f32 = if (s.chrome_hidden) 0 else 1;
    const step = if (c.reduced_motion) 1.0 else fade;
    if (@abs(s.chrome_fade - target) > 0.001) {
        if (step >= 1.0) {
            s.chrome_fade = target;
        } else {
            s.chrome_fade += (target - s.chrome_fade) * @min(1.0, step);
            if (@abs(s.chrome_fade - target) < 0.02) s.chrome_fade = target;
        }
        c.animationFrame();
        c.changed = true;
    }
}

/// The bars' opacity this frame: 1 while they stand, 0 once they are
/// gone. The bars draw at it, and stop answering clicks at the bottom
/// end -- an invisible bar that still eats a click is worse than one
/// that never hid.
pub fn chromeOpacity(s: *app.State) f32 {
    if (!s.fullscreen) return 1;
    return s.chrome_fade;
}

/// Whether the bars take clicks: they do until they are all but gone.
pub fn chromeLive(s: *app.State) bool {
    return chromeOpacity(s) > 0.35;
}

/// Whether the bars are still painted at all: they fade to nothing and
/// then leave the tree, so no invisible rectangle is left behind.
pub fn chromeDrawn(s: *app.State) bool {
    return chromeOpacity(s) > 0.02;
}

/// The room the picture has: the bars' height while they stand, a margin
/// once they are gone -- and it moves with the fade, so the fit grows
/// smoothly with them instead of jumping when the timer fires.
pub fn topRoom(s: *app.State, bar_h: f32, margin: f32) f32 {
    const t = chromeOpacity(s);
    return margin + (bar_h + margin - margin) * t;
}
