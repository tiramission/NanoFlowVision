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

// ---- the folder picker ----
//
// The system's own folder dialog: IFileOpenDialog in folder mode, which
// the framework's dialog does not do on Windows -- its file dialog only
// opens files, and a folder chosen there can never be confirmed.

const GUID = std.os.windows.GUID;

const clsid_file_open_dialog = GUID{
    .Data1 = 0xDC1C5A9C,
    .Data2 = 0xE88A,
    .Data3 = 0x4DDE,
    .Data4 = .{ 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 },
};
const iid_file_open_dialog = GUID{
    .Data1 = 0xD57C7288,
    .Data2 = 0xD4AD,
    .Data3 = 0x4768,
    .Data4 = .{ 0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60 },
};
const iid_shell_item = GUID{
    .Data1 = 0x43826D1E,
    .Data2 = 0xE718,
    .Data3 = 0x42EE,
    .Data4 = .{ 0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE },
};

const FOS_PICKFOLDERS: u32 = 0x20;
const FOS_FORCEFILESYSTEM: u32 = 0x40;
const SIGDN_FILESYSPATH: u32 = 0x80058000;
const COINIT_APARTMENTTHREADED: u32 = 0x2;
const CLSCTX_INPROC_SERVER: u32 = 1;

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, model: u32) callconv(.winapi) i32;
extern "ole32" fn CoCreateInstance(clsid: *const GUID, outer: ?*anyopaque, ctx: u32, iid: *const GUID, out: *?*anyopaque) callconv(.winapi) i32;
extern "ole32" fn CoTaskMemFree(p: ?*anyopaque) callconv(.winapi) void;
extern "shell32" fn SHCreateItemFromParsingName(path: [*:0]const u16, bc: ?*anyopaque, iid: *const GUID, out: *?*anyopaque) callconv(.winapi) i32;

/// A shell item: a folder, to the dialog. Its vtable, with the slots
/// that are of no use to us left anonymous but counted.
const ShellItem = extern struct {
    vtbl: *const ShellItemVTable,
};
const ShellItemVTable = extern struct {
    query_interface: *const anyopaque,
    add_ref: *const anyopaque,
    release: *const fn (*ShellItem) callconv(.winapi) u32,
    bind_to_handler: *const anyopaque,
    get_parent: *const anyopaque,
    get_display_name: *const fn (*ShellItem, u32, *[*:0]u16) callconv(.winapi) i32,
    get_attributes: *const anyopaque,
    compare: *const anyopaque,
};

/// The open dialog itself: IModalWindow's four, then IFileDialog's
/// twenty-one, then IFileOpenDialog's own two -- the anonymous slots are
/// there for the count, which is all the vtable is.
const FileDialog = extern struct {
    vtbl: *const FileDialogVTable,
};
const FileDialogVTable = extern struct {
    query_interface: *const anyopaque,
    add_ref: *const anyopaque,
    release: *const fn (*FileDialog) callconv(.winapi) u32,
    show: *const fn (*FileDialog, ?HWND) callconv(.winapi) i32,
    set_file_types: *const anyopaque,
    set_file_type_index: *const anyopaque,
    get_file_type_index: *const anyopaque,
    advise: *const anyopaque,
    unadvise: *const anyopaque,
    set_options: *const fn (*FileDialog, u32) callconv(.winapi) i32,
    get_options: *const anyopaque,
    set_default_folder: *const fn (*FileDialog, *ShellItem) callconv(.winapi) i32,
    set_folder: *const anyopaque,
    get_current_selection: *const anyopaque,
    set_file_name: *const anyopaque,
    set_title: *const fn (*FileDialog, [*:0]const u16) callconv(.winapi) i32,
    set_ok_button_label: *const anyopaque,
    set_file_name_label: *const anyopaque,
    get_result: *const fn (*FileDialog, *?*ShellItem) callconv(.winapi) i32,
    add_place: *const anyopaque,
    set_default_extension: *const anyopaque,
    close: *const anyopaque,
    set_client_guid: *const anyopaque,
    clear_client_data: *const anyopaque,
    set_filter: *const anyopaque,
    get_results: *const anyopaque,
    get_selected_items: *const anyopaque,
};

/// UTF-8 into a UTF-16 buffer, ended with zero. The buffer holds the
/// text plus its end; the result is the text as the system reads it.
fn wide(buf: []u16, s: []const u8) ?[*:0]const u16 {
    const n = std.unicode.utf8ToUtf16Le(buf[0 .. buf.len - 1], s) catch return null;
    buf[n] = 0;
    return @ptrCast(buf.ptr);
}

/// Opens the folder dialog. The window it belongs to is its owner; the
/// dialog starts at `start`. The chosen folder, UTF-8, is the caller's
/// to free; null means the reader backed out.
pub fn pickFolder(gpa: std.mem.Allocator, parent: *anyopaque, start: []const u8, title: []const u8) ?[]u8 {
    if (builtin.os.tag != .windows) return null;
    const hr_init = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    if (hr_init != 0 and hr_init != 1) return null;

    var dialog: ?*FileDialog = null;
    if (CoCreateInstance(&clsid_file_open_dialog, null, CLSCTX_INPROC_SERVER, &iid_file_open_dialog, @ptrCast(&dialog)) != 0) return null;
    const d = dialog.?;
    defer _ = d.vtbl.release(d);

    if (d.vtbl.set_options(d, FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM) != 0) return null;

    var title_buf: [256]u16 = undefined;
    if (title.len > 0) {
        if (wide(&title_buf, title)) |t| {
            if (d.vtbl.set_title(d, t) != 0) return null;
        }
    }

    // The dialog opens where the reader already is.
    var start_buf: [1024]u16 = undefined;
    if (start.len > 0) {
        if (wide(&start_buf, start)) |s16| {
            var item: ?*ShellItem = null;
            if (SHCreateItemFromParsingName(s16, null, &iid_shell_item, @ptrCast(&item)) == 0) {
                defer _ = item.?.vtbl.release(item.?);
                _ = d.vtbl.set_default_folder(d, item.?);
            }
        }
    }

    const hwnd: HWND = @ptrCast(parent);
    if (d.vtbl.show(d, hwnd) != 0) return null;

    var result: ?*ShellItem = null;
    if (d.vtbl.get_result(d, &result) != 0) return null;
    const item = result.?;
    defer _ = item.vtbl.release(item);
    var name: [*:0]u16 = undefined;
    if (item.vtbl.get_display_name(item, SIGDN_FILESYSPATH, &name) != 0) return null;
    defer CoTaskMemFree(name);
    return std.unicode.utf16LeToUtf8Alloc(gpa, std.mem.sliceTo(name, 0)) catch null;
}
