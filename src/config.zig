//! The app's own small settings, kept in the data directory: where the
//! window sat, how it was coloured, what the gallery takes in. A few
//! lines of "key = value" -- nothing here is worth a format of its own.

const std = @import("std");
const i18n = @import("i18n.zig");

pub const Settings = struct {
    /// Where the window sat. Null when it was centred by the system.
    x: ?f64 = null,
    y: ?f64 = null,
    width: f64 = 1280,
    height: f64 = 800,
    /// Whether the gallery is drawn dark.
    dark: bool = false,
    /// Whether the gallery takes the subfolders' pictures in.
    recursive: bool = false,
    /// The language the interface speaks.
    lang: i18n.Lang = .en,
};

/// Reads the settings from `dir/settings.txt`, or the defaults when there
/// is nothing to read.
pub fn load(gpa: std.mem.Allocator, io: std.Io, dir_path: []const u8) Settings {
    var out: Settings = .{};
    const bytes = read(gpa, io, dir_path) catch return out;
    defer gpa.free(bytes);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " ");
        const value = std.mem.trim(u8, line[eq + 1 ..], " ");
        if (std.mem.eql(u8, key, "x")) {
            out.x = number(value);
        } else if (std.mem.eql(u8, key, "y")) {
            out.y = number(value);
        } else if (std.mem.eql(u8, key, "width")) {
            if (number(value)) |v| out.width = v;
        } else if (std.mem.eql(u8, key, "height")) {
            if (number(value)) |v| out.height = v;
        } else if (std.mem.eql(u8, key, "dark")) {
            out.dark = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "recursive")) {
            out.recursive = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "lang")) {
            out.lang = if (std.mem.eql(u8, value, "zh")) .zh else .en;
        }
    }
    if (out.width < 200) out.width = 200;
    if (out.height < 150) out.height = 150;
    return out;
}

/// Writes the settings into `dir/settings.txt`: a temporary file first,
/// swapped in only when whole.
pub fn save(io: std.Io, dir_path: []const u8, s: Settings) void {
    const where = path(dir_path);
    defer std.heap.smp_allocator.free(where);
    var file = std.Io.Dir.createFileAbsolute(io, where, .{ .truncate = true }) catch return;
    defer file.close(io);
    var buf: [512]u8 = undefined;
    var w = file.writer(io, &buf);
    w.interface.print(
        "x = {d}\ny = {d}\nwidth = {d:.0}\nheight = {d:.0}\ndark = {d}\nrecursive = {d}\nlang = {s}\n",
        .{ s.x orelse -1, s.y orelse -1, s.width, s.height, @intFromBool(s.dark), @intFromBool(s.recursive), @tagName(s.lang) },
    ) catch return;
    w.interface.flush() catch return;
}

fn number(value: []const u8) ?f64 {
    if (value.len == 0) return null;
    return std.fmt.parseFloat(f64, value) catch null;
}

/// Where the settings file sits.
pub fn path(dir_path: []const u8) []const u8 {
    return std.fmt.allocPrint(std.heap.smp_allocator, "{s}/settings.txt", .{dir_path}) catch unreachable;
}

fn read(gpa: std.mem.Allocator, io: std.Io, dir_path: []const u8) ![]u8 {
    var file = try std.Io.Dir.openFileAbsolute(io, path(dir_path), .{});
    defer file.close(io);
    var buffer: [4 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(gpa, .limited(64 * 1024));
}

test "settings round-trip" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const dir_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(dir_path);

    const s: Settings = .{ .x = 12.5, .y = -3, .width = 900, .height = 600, .dark = true, .recursive = true };
    save(std.testing.io, dir_path, s);
    const back = load(gpa, std.testing.io, dir_path);
    try std.testing.expectEqual(@as(f64, 12.5), back.x.?);
    try std.testing.expectEqual(@as(f64, -3), back.y.?);
    try std.testing.expectEqual(@as(f64, 900), back.width);
    try std.testing.expectEqual(@as(f64, 600), back.height);
    try std.testing.expect(back.dark and back.recursive);

    // Nothing to read: the defaults.
    const fresh = load(gpa, std.testing.io, "C:/definitely/not/here");
    try std.testing.expect(!fresh.dark and fresh.x == null);
}
