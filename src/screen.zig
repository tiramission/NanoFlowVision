//! The window's screen: full screen where the platform gives it to us,
//! a maximized window where it does not. The large view asks this file
//! to take the window over and give it back; the interface itself only
//! keeps a flag. With no window (tests, snapshots) nothing is touched:
//! the call says it worked, and the state machine is what is tested.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const win = @import("win.zig");

/// True when this platform has no real full screen and the window is
/// only maximized (nanoui has no X11/Wayland full screen).
pub fn fallback() bool {
    return builtin.os.tag != .windows and builtin.os.tag != .macos;
}

/// Takes the window full screen (on) or gives it back. False when the
/// platform refused, in which case the caller keeps its old state.
pub fn set(window: ?*nanoui.Window, on: bool) bool {
    const w = window orelse return true;
    if (builtin.os.tag == .windows) {
        const hwnd = w.hwnd orelse return false;
        return win.setFullscreen(@ptrCast(hwnd), on);
    }
    if (comptime builtin.os.tag == .macos) return macSet(w, on);
    // Linux, and any other platform without a full screen: maximize is
    // the next best thing. `zoom` toggles, so it is called on the change.
    if (on != fallback_on) {
        w.zoom();
        fallback_on = on;
    }
    return true;
}

/// Whether the window is full screen right now.
pub fn isOn(window: ?*nanoui.Window) bool {
    const w = window orelse return false;
    if (builtin.os.tag == .windows) {
        const hwnd = w.hwnd orelse return false;
        return win.fullscreenOn(@ptrCast(hwnd));
    }
    if (comptime builtin.os.tag == .macos) return macOn(w);
    return fallback_on;
}

var fallback_on = false;

// macOS: the window's own full screen, its own Space and animation. The
// style mask's full screen bit is the answer; it changes a few frames
// after the request, which is why the app waits before listening to it.
const mac = if (builtin.os.tag == .macos) struct {
    const objc = nanoui.objc;
    const full_screen_bit: objc.NSUInteger = 1 << 14;

    fn set(w: *nanoui.Window, want: bool) bool {
        if (want == on(w)) return true;
        objc.msg(void, w.nswindow, "toggleFullScreen:", .{@as(?objc.Object, null)});
        return true;
    }

    fn on(w: *nanoui.Window) bool {
        const mask = objc.msg(objc.NSUInteger, w.nswindow, "styleMask", .{});
        return (mask & full_screen_bit) != 0;
    }
} else struct {
    fn set(w: *nanoui.Window, want: bool) bool {
        _ = w;
        _ = want;
        return false;
    }
    fn on(w: *nanoui.Window) bool {
        _ = w;
        return false;
    }
};

fn macSet(w: *nanoui.Window, on: bool) bool {
    return mac.set(w, on);
}

fn macOn(w: *nanoui.Window) bool {
    return mac.on(w);
}

test "the fallback is not the Windows or Mac path" {
    try std.testing.expectEqual(
        builtin.os.tag != .windows and builtin.os.tag != .macos,
        fallback(),
    );
    // With no window, the call is a no-op that reports success: tests
    // never touch a handle.
    try std.testing.expect(set(null, true));
    try std.testing.expect(!isOn(null));
}
