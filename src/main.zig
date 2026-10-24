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

const app_name = "NanoFlowVision";

pub fn main(init: std.process.Init) !void {
    const nanoui_app = try nanoui.App.create(init, .{ .name = app_name });
    defer nanoui_app.destroy();

    const gpa = init.gpa;
    const settings = loadSettings(gpa, init.io);
    defer if (settings.dir_path) |d| gpa.free(d);

    const root = try rootFolder(init);
    defer init.gpa.free(root);

    const state = try app.State.create(gpa, init.io, root);
    defer state.deinit();
    state.dark = settings.dark;
    state.recursive = settings.recursive;
    state.settings_dir = settings.dir_path;

    const window = try nanoui_app.newWindow(.{
        .title = app_name,
        .width = settings.width,
        .height = settings.height,
        .x = settings.x,
        .y = settings.y,
        .theme = if (settings.dark) nanoui.ui.Theme.dark_theme else null,
        .content = .{ .view = .init(state, app.State.view) },
        .on_close = .{ .ctx = state, .func = saveFromWindow },
    });
    state.window = window;
    state.pool.window = window;
    try nanoui_app.run();
}

/// The settings, and the folder they live in (owned, when there is one).
fn loadSettings(gpa: std.mem.Allocator, io: std.Io) struct { dir_path: ?[]u8, dark: bool, recursive: bool, x: ?f64, y: ?f64, width: f64, height: f64 } {
    const dir_path: ?[]u8 = nanoui.path(gpa, .data, app_name) catch null;
    if (dir_path) |d| {
        std.Io.Dir.createDirAbsolute(io, d, .default_file) catch {};
        const s = config.load(gpa, io, d);
        return .{ .dir_path = d, .dark = s.dark, .recursive = s.recursive, .x = s.x, .y = s.y, .width = s.width, .height = s.height };
    }
    return .{ .dir_path = null, .dark = false, .recursive = false, .x = null, .y = null, .width = 1280, .height = 800 };
}

/// The window is closing: the way it sat is remembered.
fn saveFromWindow(ctx: *anyopaque, window: *nanoui.Window) void {
    const state: *app.State = @ptrCast(@alignCast(ctx));
    const dir_path = state.settings_dir orelse return;
    const f = window.frame();
    state.window = null;
    config.save(state.io, dir_path, .{
        .x = f.x,
        .y = f.y,
        .width = f.width,
        .height = f.height,
        .dark = state.dark,
        .recursive = state.recursive,
    });
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
