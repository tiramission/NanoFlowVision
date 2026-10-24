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
