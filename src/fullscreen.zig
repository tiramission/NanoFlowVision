//! Full screen: taking the window over for one photograph, giving it
//! back, and the quiet that follows in that room. The state lives in
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
        s.chrome_hidden = false;
        if (on) s.last_activity = c.time;
        c.changed = true;
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
        s.last_activity = c.time;
        s.chrome_hidden = false;
        s.chrome_idle = false;
        scheduleChromeHide(s);
        c.changed = true;
    } else {
        _ = screen.set(w, false);
        s.fullscreen = false;
        s.frame_before = null;
        s.chrome_hidden = false;
        s.chrome_idle = false;
        c.changed = true;
    }
    if (w.surface) |surface| surface.requestFrame();
}

/// The frame the settings should keep: the window as it was before full
/// screen, never the full-screen rectangle itself.
pub fn frameForSettings(s: *app.State) ?WindowRect {
    if (s.fullscreen) return s.frame_before;
    const w = s.window orelse return null;
    const f = w.frame();
    return .{ .x = f.x, .y = f.y, .width = f.width, .height = f.height };
}

/// The timer that says the idle moment arrived; the view compares it
/// with the clock, so an early timer hides nothing.
fn chromeHideTimer(ctx: ?*anyopaque) callconv(.c) void {
    const s: *app.State = @ptrCast(@alignCast(ctx.?));
    s.chrome_timer_pending = false;
    s.chrome_idle = true;
    if (s.window) |w| w.redraw();
}

fn scheduleChromeHide(s: *app.State) void {
    if (s.window == null or s.chrome_timer_pending) return;
    s.chrome_timer_pending = true;
    nanoui.App.after(2500, s, chromeHideTimer);
}

/// Called by the large view with this frame's input. In full screen, a
/// movement or a key brings the chrome back and restarts the quiet
/// timer; after a couple of seconds it stands back and the picture has
/// the whole room.
pub fn noteInput(s: *app.State, c: *ui.Context) void {
    if (!s.fullscreen) {
        s.chrome_hidden = false;
        return;
    }
    const moved = c.input.mouse.x != s.idle_mouse_x or c.input.mouse.y != s.idle_mouse_y;
    s.idle_mouse_x = c.input.mouse.x;
    s.idle_mouse_y = c.input.mouse.y;
    const active = moved or c.input.key != null or c.input.chars.len > 0 or
        c.input.scroll.y != 0 or c.input.pressed or c.input.released;
    if (active) {
        s.last_activity = c.time;
        s.chrome_idle = false;
        if (s.chrome_hidden) {
            s.chrome_hidden = false;
            c.changed = true;
        }
        scheduleChromeHide(s);
    } else if (s.chrome_idle) {
        if (c.time - s.last_activity >= 2.4) {
            s.chrome_idle = false;
            if (!s.chrome_hidden) {
                s.chrome_hidden = true;
                c.changed = true;
            }
        } else {
            // A timer from before the last movement: too early, so it is
            // started again from here.
            s.chrome_idle = false;
            scheduleChromeHide(s);
        }
    }
}
