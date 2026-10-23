//! NanoFlowVision: a picture browser, drawn by nanoui.
//!
//! The folder to show is the one on the command line, the user's pictures,
//! or the folder the app was started in.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const app = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    const nanoui_app = try nanoui.App.create(init, .{ .name = "NanoFlowVision" });
    defer nanoui_app.destroy();

    const root = try rootFolder(init);
    defer init.gpa.free(root);

    const state = try app.State.create(init.gpa, init.io, root);
    defer state.deinit();

    const window = try nanoui_app.newWindow(.{
        .title = "NanoFlowVision",
        .width = 1280,
        .height = 800,
        .content = .{ .view = .init(state, app.State.view) },
    });
    state.window = window;
    state.pool.window = window;
    try nanoui_app.run();
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
