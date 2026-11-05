//! The window and the platform: its icon (the exe carries one in its
//! resources, but the running window has to be told) and its state
//! (whether it is maximized, which the settings remember).

const std = @import("std");
const builtin = @import("builtin");

const HWND = std.os.windows.HWND;
const HICON = std.os.windows.HICON;
const HINSTANCE = std.os.windows.HINSTANCE;

const WM_SETICON: u32 = 0x0080;
const ICON_SMALL: usize = 0;
const ICON_BIG: usize = 1;
const IMAGE_ICON: u32 = 1;
const LR_DEFAULTSIZE: u32 = 0x0040;
const SM_CXSMICON: i32 = 49;
const SM_CYSMICON: i32 = 50;

extern "user32" fn LoadImageW(hInst: ?HINSTANCE, name: *const anyopaque, type: u32, cx: i32, cy: i32, fuLoad: u32) callconv(.winapi) ?HICON;
extern "user32" fn SendMessageW(hwnd: HWND, msg: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;
extern "user32" fn GetSystemMetrics(index: i32) callconv(.winapi) i32;
extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.winapi) ?HINSTANCE;

/// The ico sits at resource id 1: res/app.rc puts it there.
const icon_id: usize = 1;

/// The resource name as the loader reads it: a small whole number is an
/// id, not a pointer to a string.
fn resourceName() *const anyopaque {
    return @ptrFromInt(icon_id);
}

/// Puts the exe's icon on the window: the big one for the taskbar and
/// Alt-Tab, the small one for the title bar's corner. The handle is the
/// window's own, in whatever shape the framework holds it.
pub fn apply(window_handle: *anyopaque) void {
    if (builtin.os.tag != .windows) return;
    const hwnd: HWND = @ptrCast(window_handle);
    const inst = GetModuleHandleW(null) orelse return;
    const name = resourceName();
    const big = LoadImageW(inst, name, IMAGE_ICON, 0, 0, LR_DEFAULTSIZE) orelse return;
    const small = LoadImageW(
        inst,
        name,
        IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON),
        0,
    ) orelse big;
    _ = SendMessageW(hwnd, WM_SETICON, ICON_BIG, @bitCast(@intFromPtr(big)));
    _ = SendMessageW(hwnd, WM_SETICON, ICON_SMALL, @bitCast(@intFromPtr(small)));
}

extern "user32" fn IsZoomed(hwnd: HWND) callconv(.winapi) i32;

/// Whether the window is maximized -- the state a close should remember,
/// so the next start can do something better than reopen at the full
/// screen's size.
pub fn zoomed(window_handle: *anyopaque) bool {
    if (builtin.os.tag != .windows) return false;
    const hwnd: HWND = @ptrCast(window_handle);
    return IsZoomed(hwnd) != 0;
}

// --- full screen -------------------------------------------------------
//
// The window is a normal overlapped window; going full screen means
// dropping that frame (WS_POPUP over the monitor's whole rectangle) and
// putting it back afterwards. The style and the rectangle before the
// change are kept here -- one window, one full screen. The settings
// never see this: the app saves the frame it remembers instead.

const RECT = extern struct {
    left: i32 = 0,
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
};

const MONITORINFO = extern struct {
    cbSize: u32 = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{},
    rcWork: RECT = .{},
    dwFlags: u32 = 0,
};

const GWL_STYLE: i32 = -16;
const WS_POPUP: u32 = 0x8000_0000;
const WS_VISIBLE: u32 = 0x1000_0000;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOACTIVATE: u32 = 0x0010;
const SWP_FRAMECHANGED: u32 = 0x0020;
const SWP_SHOWWINDOW: u32 = 0x0040;
const MONITOR_DEFAULTTONEAREST: u32 = 2;
const SW_SHOWMAXIMIZED: i32 = 3;

extern "user32" fn GetWindowLongPtrW(hwnd: HWND, index: i32) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrW(hwnd: HWND, index: i32, value: isize) callconv(.winapi) isize;
extern "user32" fn SetWindowPos(hwnd: HWND, after: ?HWND, x: i32, y: i32, cx: i32, cy: i32, flags: u32) callconv(.winapi) i32;
extern "user32" fn GetWindowRect(hwnd: HWND, rect: *RECT) callconv(.winapi) i32;
extern "user32" fn MonitorFromWindow(hwnd: HWND, flags: u32) callconv(.winapi) ?*anyopaque;
extern "user32" fn GetMonitorInfoW(monitor: *anyopaque, info: *MONITORINFO) callconv(.winapi) i32;
extern "user32" fn ShowWindow(hwnd: HWND, cmd: i32) callconv(.winapi) i32;

/// What the window was before it went full screen.
const Before = struct {
    style: isize,
    rect: RECT,
    zoomed: bool,
};
var before: ?Before = null;

/// Takes the window over the monitor it is on (on) or puts its frame
/// back (off). False when Windows gave us nothing to work with.
pub fn setFullscreen(window_handle: *anyopaque, on: bool) bool {
    if (builtin.os.tag != .windows) return false;
    const hwnd: HWND = @ptrCast(window_handle);
    if (on) {
        if (before != null) return true;
        const style = GetWindowLongPtrW(hwnd, GWL_STYLE);
        var rect: RECT = .{};
        if (GetWindowRect(hwnd, &rect) == 0) return false;
        const monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) orelse return false;
        var info: MONITORINFO = .{};
        if (GetMonitorInfoW(monitor, &info) == 0) return false;
        before = .{ .style = style, .rect = rect, .zoomed = IsZoomed(hwnd) != 0 };
        const popup: isize = @intCast(WS_POPUP | WS_VISIBLE);
        _ = SetWindowLongPtrW(hwnd, GWL_STYLE, popup);
        const m = info.rcMonitor;
        _ = SetWindowPos(hwnd, null, m.left, m.top, m.right - m.left, m.bottom - m.top, SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOZORDER | SWP_NOACTIVATE);
        return true;
    }
    const was = before orelse return true;
    before = null;
    _ = SetWindowLongPtrW(hwnd, GWL_STYLE, was.style);
    _ = SetWindowPos(
        hwnd,
        null,
        was.rect.left,
        was.rect.top,
        was.rect.right - was.rect.left,
        was.rect.bottom - was.rect.top,
        SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOZORDER | SWP_NOACTIVATE,
    );
    // A window that was maximized comes back maximized, not at the frame
    // it happened to have when the picture went full screen.
    if (was.zoomed) _ = ShowWindow(hwnd, SW_SHOWMAXIMIZED);
    return true;
}

/// Whether our own full screen is on (the window may have been taken
/// away by the system, e.g. Win+D -- then this says yes and the next
/// frame puts it right).
pub fn fullscreenOn(window_handle: *anyopaque) bool {
    _ = window_handle;
    if (builtin.os.tag != .windows) return false;
    return before != null;
}
