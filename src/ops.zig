//! The file operations the menu offers: open and reveal in the system's
//! shell, the bin, the clipboard as files, and a rename. Where nanoui has
//! the primitive (the shell everywhere, the bin and file clipboard on the
//! Mac) it is used; the rest this does itself, against the system's own
//! interfaces.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const model = @import("model.zig");

/// Opens the file in its default app.
pub fn open(path: []const u8) bool {
    return nanoui.shell.openPath(path);
}

/// Shows the file in the system's file manager.
pub fn reveal(path: []const u8) void {
    nanoui.shell.showInFolder(path);
}

/// Moves the file to the bin -- the recycle bin on Windows -- so it can
/// be taken back.
pub fn trash(path: []const u8) bool {
    if (comptime builtin.os.tag == .windows) return trashWindows(path);
    return nanoui.shell.trash(path);
}

/// Copies a file onto the clipboard, as files: a paste in the file
/// manager takes it, and so does the app itself.
pub fn copyFileToClipboard(gpa: std.mem.Allocator, path: []const u8) void {
    if (comptime builtin.os.tag == .windows) {
        copyFilesWindows(gpa, &.{path});
        return;
    }
    // TODO(mac): the file clipboard.
}

/// The files on the clipboard, as files, or null. The caller frees the
/// paths and the slice.
pub fn clipboardFiles(gpa: std.mem.Allocator) ?[][]u8 {
    if (comptime builtin.os.tag == .windows) return readFilesWindows(gpa);
    return nanoui.clipboard.readFiles(gpa) catch null;
}

/// Renames the file at `old_path` to `new_name`, in its own folder, and
/// hands back its new path. A name that is taken is refused.
pub fn renameFile(gpa: std.mem.Allocator, io: std.Io, old_path: []const u8, new_name: []const u8) ![]u8 {
    const parent = model.parentOf(old_path) orelse return error.NoParent;
    const new_path = try model.join(gpa, parent, new_name);
    errdefer gpa.free(new_path);
    if (std.mem.eql(u8, old_path, new_path)) return error.SameName;
    if (exists(io, new_path)) return error.NameExists;
    try std.Io.Dir.renameAbsolute(old_path, new_path, io);
    return new_path;
}

/// Copies the file at `path` into the folder `dest_dir_path`, under a
/// name that does not collide: the first copy is " - Copy", the next
/// " - Copy (2)", and so on. Hands back the new path, or null when the
/// file could not be read. The caller frees it.
pub fn pasteInto(gpa: std.mem.Allocator, io: std.Io, path: []const u8, dest_dir_path: []const u8) !?[]u8 {
    const name = model.nameOf(path);
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const base = if (dot) |d| name[0..d] else name;
    const ext = if (dot) |d| name[d..] else "";

    var serial: usize = 0;
    while (serial < 1000) : (serial += 1) {
        const bare = if (serial == 0)
            try std.fmt.allocPrint(gpa, "{s} - Copy{s}", .{ base, ext })
        else
            try std.fmt.allocPrint(gpa, "{s} - Copy ({d}){s}", .{ base, serial, ext });
        defer gpa.free(bare);
        const dest = try model.join(gpa, dest_dir_path, bare);
        errdefer gpa.free(dest);
        if (exists(io, dest)) {
            gpa.free(dest);
            continue;
        }
        try std.Io.Dir.copyFileAbsolute(path, dest, io, .{});
        return dest;
    }
    return null;
}

pub fn exists(io: std.Io, path: []const u8) bool {
    var f = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
    f.close(io);
    return true;
}

// -- Windows: the bin and the file clipboard, against the system's own
// -- interfaces. Declared here so nothing else in the app touches them.

const FO_DELETE: u32 = 3;
const FOF_ALLOWUNDO: u16 = 0x40;
const FOF_NOCONFIRMATION: u16 = 0x10;
const FOF_SILENT: u16 = 0x04;
const FOF_NOERRORUI: u16 = 0x400;
const CF_HDROP: u32 = 15;
const GMEM_MOVEABLE: u32 = 0x0002;

const SHFILEOPSTRUCTW = extern struct {
    hwnd: ?*anyopaque,
    wFunc: u32,
    pFrom: [*:0]const u16,
    pTo: ?[*:0]const u16,
    fFlags: u16,
    fAnyOperationsAborted: i32,
    hNameMappings: ?*anyopaque,
    lpszProgressTitle: ?[*:0]const u16,
};

extern "shell32" fn SHFileOperationW(op: *SHFILEOPSTRUCTW) i32;
extern "shell32" fn DragQueryFileW(drop: *anyopaque, i: u32, name: ?[*]u16, len: u32) u32;
extern "user32" fn OpenClipboard(hwnd: ?*anyopaque) i32;
extern "user32" fn CloseClipboard() i32;
extern "user32" fn EmptyClipboard() i32;
extern "user32" fn SetClipboardData(format: u32, handle: ?*anyopaque) ?*anyopaque;
extern "user32" fn GetClipboardData(format: u32) ?*anyopaque;
extern "kernel32" fn GlobalAlloc(flags: u32, bytes: usize) ?*anyopaque;
extern "kernel32" fn GlobalLock(handle: ?*anyopaque) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(handle: ?*anyopaque) i32;
extern "kernel32" fn GlobalFree(handle: ?*anyopaque) ?*anyopaque;

const DROPFILES = extern struct {
    pFiles: u32,
    pt: Point,
    fNC: i32,
    fWide: i32,
    const Point = extern struct { x: i32, y: i32 };
};

fn trashWindows(path: []const u8) bool {
    const heap = std.heap.smp_allocator;
    const wide = std.unicode.utf8ToUtf16LeAllocZ(heap, path) catch return false;
    defer heap.free(wide);
    // The list of files is double-null terminated.
    const from = heap.alloc(u16, wide.len + 2) catch return false;
    defer heap.free(from);
    // The shell wants its separators the Windows way.
    for (wide, 0..) |ch, i| from[i] = if (ch == '/') '\\' else ch;
    from[wide.len] = 0;
    from[wide.len + 1] = 0;

    const from_z: [*:0]const u16 = @ptrCast(from.ptr);
    var op = SHFILEOPSTRUCTW{
        .hwnd = null,
        .wFunc = FO_DELETE,
        .pFrom = from_z,
        .pTo = null,
        .fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI,
        .fAnyOperationsAborted = 0,
        .hNameMappings = null,
        .lpszProgressTitle = null,
    };
    return SHFileOperationW(&op) == 0;
}

fn copyFilesWindows(gpa: std.mem.Allocator, paths: []const []const u8) void {
    // A DROPFILES header, then the wide paths, each null-terminated, with
    // one more null after the last.
    var wide_len: usize = 0;
    for (paths) |p| {
        const wide = std.unicode.utf8ToUtf16LeAllocZ(gpa, p) catch return;
        defer gpa.free(wide);
        wide_len += wide.len + 1;
    }
    const total = @sizeOf(DROPFILES) + (wide_len + 1) * 2;
    const handle = GlobalAlloc(GMEM_MOVEABLE, total) orelse return;
    const at = GlobalLock(handle) orelse {
        _ = GlobalFree(handle);
        return;
    };
    const df: *DROPFILES = @ptrCast(@alignCast(at));
    df.* = .{ .pFiles = @sizeOf(DROPFILES), .pt = .{ .x = 0, .y = 0 }, .fNC = 0, .fWide = 1 };
    var w: [*]u16 = @ptrFromInt(@intFromPtr(at) + @sizeOf(DROPFILES));
    for (paths) |p| {
        const wide = std.unicode.utf8ToUtf16LeAllocZ(gpa, p) catch break;
        @memcpy(w[0..wide.len], wide);
        w[wide.len] = 0;
        w += wide.len + 1;
        gpa.free(wide);
    }
    w[0] = 0;
    _ = GlobalUnlock(handle);
    if (OpenClipboard(null) != 0) {
        _ = EmptyClipboard();
        if (SetClipboardData(CF_HDROP, handle) == null) _ = GlobalFree(handle);
        _ = CloseClipboard();
    } else {
        _ = GlobalFree(handle);
    }
}

fn readFilesWindows(gpa: std.mem.Allocator) ?[][]u8 {
    if (OpenClipboard(null) == 0) return null;
    defer _ = CloseClipboard();
    const handle = GetClipboardData(CF_HDROP) orelse return null;
    const at = GlobalLock(handle) orelse return null;
    defer _ = GlobalUnlock(handle);
    const drop: *anyopaque = @ptrCast(at);
    const count = DragQueryFileW(drop, 0xFFFFFFFF, null, 0);
    var out: std.ArrayList([]u8) = .empty;
    for (0..count) |i| {
        const len = DragQueryFileW(drop, @intCast(i), null, 0);
        const wide = gpa.alloc(u16, len + 1) catch break;
        defer gpa.free(wide);
        _ = DragQueryFileW(drop, @intCast(i), wide.ptr, @intCast(len + 1));
        const name = std.unicode.utf16LeToUtf8Alloc(gpa, wide[0..len]) catch continue;
        out.append(gpa, name) catch break;
    }
    return out.toOwnedSlice(gpa) catch null;
}
