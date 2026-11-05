//! The folders the tests put pictures in: red squares, and a bigger picture
//! for the tests that need room to drag.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// A folder with a red square in it, and where it is.
pub const Sample = struct {
    tmp: std.testing.TmpDir,
    path: []u8,

    pub fn deinit(s: *Sample, gpa: std.mem.Allocator) void {
        gpa.free(s.path);
        s.tmp.cleanup();
    }
};

pub fn makeSample(gpa: std.mem.Allocator) !Sample {
    return makeSampleWith(gpa, 1);
}

/// A folder with `count` red squares in it, and where it is.
pub fn makeSampleWith(gpa: std.mem.Allocator, count: usize) !Sample {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    // Red squares, as PNGs the app can read.
    var red = [_]u8{ 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 2, .height = 2 });
    defer gpa.free(png);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const name = try std.fmt.allocPrint(gpa, "pic-{d}.png", .{i});
        defer gpa.free(name);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = png });
    }

    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    return .{ .tmp = tmp, .path = path };
}

/// A folder of pictures big enough to be worth zooming: 1200x900 each, so
/// 1:1 is larger than the room and a drag has room to move.
pub fn makeBigSample(gpa: std.mem.Allocator, count: usize) !Sample {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    var pixels: [1200 * 900 * 4]u8 = undefined;
    for (0..1200 * 900) |i| {
        const x = i % 1200;
        const y = i / 1200;
        pixels[i * 4 + 0] = @truncate(y);
        pixels[i * 4 + 1] = @truncate(x);
        pixels[i * 4 + 2] = 90;
        pixels[i * 4 + 3] = 255;
    }
    const png = try ui.png.encode(gpa, .{ .bytes = pixels[0..], .width = 1200, .height = 900 });
    defer gpa.free(png);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const name = try std.fmt.allocPrint(gpa, "big-{d}.png", .{i});
        defer gpa.free(name);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = png });
    }

    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    return .{ .tmp = tmp, .path = path };
}
