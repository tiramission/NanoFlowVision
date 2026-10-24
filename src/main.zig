//! NanoFlowVision: a picture browser, drawn by nanoui.
//!
//! The folder to show is the one on the command line, the user's pictures,
//! or the folder the app was started in. The way the window sat and the
//! way the gallery was set come back as they were.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const app = @import("app.zig");
const config = @import("config.zig");
const i18n = @import("i18n.zig");
const theme = @import("theme.zig");
const win = @import("win.zig");

const app_name = "NanoFlowVision";

pub fn main(init: std.process.Init) !void {
    const nanoui_app = try nanoui.App.create(init, .{ .name = app_name });
    return runApp(nanoui_app, init);
}

fn runApp(nanoui_app: *nanoui.App, init: std.process.Init) !void {
    const gpa = init.gpa;
    const settings = loadSettings(gpa, init.io);
    defer if (settings.dir_path) |d| gpa.free(d);

    const root = try rootFolder(init);
    defer init.gpa.free(root);

    const state = try app.State.create(gpa, init.io, root);
    // The state is torn down after the app: the app's own destroy closes
    // the window, and the window's on_close still reads the state. Defers
    // run backwards, so the state's comes first.
    defer state.deinit();
    defer nanoui_app.destroy();
    state.dark = settings.dark or nanoui_app.flags.dark;
    state.recursive = settings.recursive;
    state.lang = settings.lang;
    state.settings_dir = settings.dir_path;
    // A snapshot or a script run opens a figment of a window: the way it
    // sat is not how the app sits, and is not worth remembering.
    state.snapshot_run = nanoui_app.flags.snapshot != null;

    const window = try nanoui_app.newWindow(.{
        .title = app_name,
        .width = settings.width,
        .height = settings.height,
        .x = settings.x,
        .y = settings.y,
        .theme = theme.forDark(state.dark),
        .content = .{ .view = .init(state, app.State.view) },
        .on_close = .{ .ctx = state, .func = saveFromWindow },
    });
    state.window = window;
    state.pool.window = window;
    // The exe's icon rides in its resources; the running window is told
    // of it here, for the title bar's corner and the taskbar.
    if (builtin.os.tag == .windows) {
        if (window.hwnd) |hwnd| win.apply(@ptrCast(hwnd));
    }
    try nanoui_app.run();
}

/// The settings, and the folder they live in (owned, when there is one).
/// A window that closed maximized is not restored at the screen's size:
/// it opens at the app's own size, as if it had never been dragged out.
fn loadSettings(gpa: std.mem.Allocator, io: std.Io) struct { dir_path: ?[]u8, dark: bool, recursive: bool, lang: i18n.Lang, x: ?f64, y: ?f64, width: f64, height: f64 } {
    const dir_path: ?[]u8 = nanoui.path(gpa, .data, app_name) catch null;
    if (dir_path) |d| {
        std.Io.Dir.createDirAbsolute(io, d, .default_file) catch {};
        const s = config.load(gpa, io, d);
        if (s.maximized) {
            return .{ .dir_path = d, .dark = s.dark, .recursive = s.recursive, .lang = s.lang, .x = null, .y = null, .width = 1100, .height = 720 };
        }
        return .{ .dir_path = d, .dark = s.dark, .recursive = s.recursive, .lang = s.lang, .x = s.x, .y = s.y, .width = s.width, .height = s.height };
    }
    return .{ .dir_path = null, .dark = false, .recursive = false, .lang = .zh, .x = null, .y = null, .width = 1100, .height = 720 };
}

/// The window is closing: the way it sat is remembered, unless the window
/// was a figment -- a snapshot or a script run -- whose size and place
/// would only be remembered wrongly.
fn saveFromWindow(ctx: *anyopaque, window: *nanoui.Window) void {
    _ = window;
    const state: *app.State = @ptrCast(@alignCast(ctx));
    if (state.snapshot_run) return;
    state.saveSettings();
}

/// The folder to show.
fn rootFolder(init: std.process.Init) ![]u8 {
    const gpa = init.gpa;
    var args = try std.process.Args.iterateAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next(); // the app's own name
    if (args.next()) |arg| {
        if (arg.len > 0) return gpa.dupe(u8, arg);
    }

    const home = if (builtin.os.tag == .windows)
        init.environ_map.get("USERPROFILE")
    else
        init.environ_map.get("HOME");
    if (home) |h| {
        const pictures = try std.fmt.allocPrint(gpa, "{s}/Pictures", .{h});
        if (isFolder(init.io, pictures)) return pictures;
        gpa.free(pictures);
    }

    const cwd = try std.process.currentPathAlloc(init.io, gpa);
    defer gpa.free(cwd);
    return gpa.dupe(u8, cwd);
}

fn isFolder(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}
