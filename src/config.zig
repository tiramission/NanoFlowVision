//! The app's own small settings, kept in the data directory: where the
//! window sat, how it was coloured, what the gallery takes in. A few
//! lines of "key = value" -- nothing here is worth a format of its own.

const std = @import("std");
const i18n = @import("i18n.zig");

/// How the room is lit: with the system, or held at either end.
pub const Appearance = enum { auto, light, dark };

/// How big the pictures are in the grid -- a target row height, not a
/// column count, so the grid is the same density whatever the window is.
/// Three steps only: the thumbnail cache is sized by the side it decodes
/// at (192 MB), and five steps would cost more hit rate than the extra
/// choice is worth.
pub const Density = enum {
    small,
    medium,
    large,

    /// The column width a step aims at: 128, 256 or 512 points.
    pub fn row(self: Density) f32 {
        return switch (self) {
            .small => 128,
            .medium => 256,
            .large => 512,
        };
    }

    /// The longest side a thumbnail is decoded to for this step.
    pub fn side(self: Density) u32 {
        return switch (self) {
            .small => 128,
            .medium => 256,
            .large => 512,
        };
    }

    pub fn fromName(name: []const u8) ?Density {
        if (std.mem.eql(u8, name, "small")) return .small;
        if (std.mem.eql(u8, name, "medium")) return .medium;
        if (std.mem.eql(u8, name, "large")) return .large;
        return null;
    }

    /// The word the menu shows for it.
    pub fn label(self: Density, lang: i18n.Lang) []const u8 {
        const tr = i18n.strings(lang);
        return switch (self) {
            .small => tr.density_small,
            .medium => tr.density_medium,
            .large => tr.density_large,
        };
    }
};

/// What a held left button does in the large view.
pub const Hold = enum {
    /// 1:1 about the pointer, and the drag inside it.
    look,
    /// Only the drag: the size stays what the wheel left it.
    drag,

    pub fn nameOf(h: Hold) []const u8 {
        return switch (h) {
            .look => "look",
            .drag => "drag",
        };
    }

    pub fn fromName(name: []const u8) ?Hold {
        if (std.mem.eql(u8, name, "look")) return .look;
        if (std.mem.eql(u8, name, "drag")) return .drag;
        return null;
    }
};

pub const Settings = struct {
    /// Where the window sat. Null when it was centred by the system.
    x: ?f64 = null,
    y: ?f64 = null,
    width: f64 = 1100,
    height: f64 = 720,
    /// Whether the gallery is drawn dark. Kept for files written before
    /// `appearance` existed; `appearance` says the same thing better.
    dark: bool = false,
    /// How the room is lit. Follows the system unless said otherwise.
    appearance: Appearance = .auto,
    /// How big the pictures are in the grid.
    density: Density = .medium,
    /// Whether the interface skips its fades and slides.
    reduce_motion: bool = false,
    /// Whether the tiles the reader has not chosen are dimmed while a
    /// choice stands: the culling way of seeing.
    dim_unselected: bool = true,
    /// How wide the navigation column is, 200 to 360.
    rail_w: f32 = 240,
    /// Whether the gallery takes the subfolders' pictures in.
    recursive: bool = false,
    /// What a held left button does on the large view: a look at 1:1, or
    /// the hand that moves the picture. Both are useful and they disagree,
    /// so the reader says which the button is for.
    hold: Hold = .look,
    /// The folder the tree was rooted at, opened again next time. Empty
    /// for the app's own choice of a starting folder.
    root: []const u8 = "",
    /// The language the interface speaks.
    lang: i18n.Lang = .zh,
    /// The window was maximized when it last closed. A maximized window
    /// is the screen's size, and reopening at the screen's size is not
    /// what anyone meant: the next start opens at its own size instead.
    maximized: bool = false,
};

/// Reads the settings from `dir/settings.txt`, or the defaults when there
/// is nothing to read.
pub fn load(gpa: std.mem.Allocator, io: std.Io, dir_path: []const u8) Settings {
    var out: Settings = .{};
    const bytes = read(gpa, io, dir_path) catch return out;
    defer gpa.free(bytes);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var saw_appearance = false;
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
        } else if (std.mem.eql(u8, key, "appearance")) {
            out.appearance = if (std.mem.eql(u8, value, "auto"))
                .auto
            else if (std.mem.eql(u8, value, "dark"))
                .dark
            else
                .light;
            saw_appearance = true;
        } else if (std.mem.eql(u8, key, "density")) {
            if (Density.fromName(value)) |d| out.density = d;
        } else if (std.mem.eql(u8, key, "reduce_motion")) {
            out.reduce_motion = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "dim_unselected")) {
            out.dim_unselected = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "rail_w")) {
            if (number(value)) |v| out.rail_w = @floatCast(v);
        } else if (std.mem.eql(u8, key, "recursive")) {
            out.recursive = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "hold")) {
            if (Hold.fromName(value)) |h| out.hold = h;
        } else if (std.mem.eql(u8, key, "maximized")) {
            out.maximized = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "root")) {
            // The value is a slice of the file's own bytes, which go out
            // with the read: the root keeps a copy of its own.
            out.root = gpa.dupe(u8, value) catch "";
        } else if (std.mem.eql(u8, key, "lang")) {
            out.lang = if (std.mem.eql(u8, value, "zh")) .zh else .en;
        }
    }
    // A window too small to see or too large for any screen is a saved
    // accident, not a wish: hold both ends.
    out.width = std.math.clamp(out.width, 480, 1920);
    out.height = std.math.clamp(out.height, 320, 1200);
    out.rail_w = std.math.clamp(out.rail_w, 200, 360);
    // A file written before appearances were a choice still says which
    // way it was drawn; take that as the answer until it says more.
    if (!saw_appearance) out.appearance = if (out.dark) .dark else .light;
    return out;
}

/// Writes the settings into `dir/settings.txt`: a temporary file first,
/// swapped in only when whole.
pub fn save(io: std.Io, dir_path: []const u8, s: Settings) void {
    const where = path(dir_path);
    defer std.heap.smp_allocator.free(where);
    var file = std.Io.Dir.createFileAbsolute(io, where, .{ .truncate = true }) catch return;
    defer file.close(io);
    var buf: [1024]u8 = undefined;
    var w = file.writer(io, &buf);
    w.interface.print(
        "x = {d}\ny = {d}\nwidth = {d:.0}\nheight = {d:.0}\nappearance = {s}\ndensity = {s}\nreduce_motion = {d}\ndim_unselected = {d}\nrail_w = {d:.0}\nrecursive = {d}\nhold = {s}\nmaximized = {d}\nroot = {s}\nlang = {s}\n",
        .{ s.x orelse -1, s.y orelse -1, s.width, s.height, @tagName(s.appearance), @tagName(s.density), @intFromBool(s.reduce_motion), @intFromBool(s.dim_unselected), s.rail_w, @intFromBool(s.recursive), @tagName(s.hold), @intFromBool(s.maximized), s.root, @tagName(s.lang) },
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

    const s: Settings = .{
        .x = 12.5,
        .y = -3,
        .width = 900,
        .height = 600,
        .appearance = .dark,
        .density = .large,
        .reduce_motion = true,
        .dim_unselected = false,
        .rail_w = 300,
        .recursive = true,
    };
    save(std.testing.io, dir_path, s);
    const back = load(gpa, std.testing.io, dir_path);
    try std.testing.expectEqual(@as(f64, 12.5), back.x.?);
    try std.testing.expectEqual(@as(f64, -3), back.y.?);
    try std.testing.expectEqual(@as(f64, 900), back.width);
    try std.testing.expectEqual(@as(f64, 600), back.height);
    try std.testing.expect(back.recursive);
    // The look, the density, the motion and the rail all come back.
    try std.testing.expectEqual(Appearance.dark, back.appearance);
    try std.testing.expectEqual(Density.large, back.density);
    try std.testing.expect(back.reduce_motion);
    try std.testing.expect(!back.dim_unselected);
    try std.testing.expectEqual(@as(f32, 300), back.rail_w);

    // A file from before those keys: its own `dark` line still says which
    // way the room was lit.
    const old = try std.fmt.allocPrint(gpa, "{s}/settings.txt", .{dir_path});
    defer gpa.free(old);
    {
        var f = try std.Io.Dir.createFileAbsolute(std.testing.io, old, .{ .truncate = true });
        defer f.close(std.testing.io);
        var buf: [128]u8 = undefined;
        var w = f.writer(std.testing.io, &buf);
        try w.interface.writeAll("dark = 1\nrecursive = 1\n");
        try w.interface.flush();
    }
    const from_before = load(gpa, std.testing.io, dir_path);
    try std.testing.expectEqual(Appearance.dark, from_before.appearance);
    try std.testing.expectEqual(Density.medium, from_before.density);
    try std.testing.expectEqual(@as(f32, 240), from_before.rail_w);

    // Nothing to read: the defaults.
    const fresh = load(gpa, std.testing.io, "C:/definitely/not/here");
    try std.testing.expect(!fresh.dark and fresh.x == null);
    try std.testing.expectEqual(@as(f64, 1100), fresh.width);
    try std.testing.expectEqual(@as(f64, 720), fresh.height);

    // A size no one meant: held to what a window can be.
    var odd: Settings = .{};
    odd.width = 5000;
    odd.height = 100;
    save(std.testing.io, dir_path, odd);
    const held = load(gpa, std.testing.io, dir_path);
    try std.testing.expectEqual(@as(f64, 1920), held.width);
    try std.testing.expectEqual(@as(f64, 320), held.height);

    // A rail dragged past either end is held to what the design allows.
    var wide: Settings = .{};
    wide.rail_w = 900;
    save(std.testing.io, dir_path, wide);
    try std.testing.expectEqual(@as(f32, 360), load(gpa, std.testing.io, dir_path).rail_w);
    var thin: Settings = .{};
    thin.rail_w = 20;
    save(std.testing.io, dir_path, thin);
    try std.testing.expectEqual(@as(f32, 200), load(gpa, std.testing.io, dir_path).rail_w);

    // A maximized window is remembered as such, and nothing else of its
    // frame is worth keeping.
    var big: Settings = .{};
    big.x = -7;
    big.y = -7;
    big.width = 1673;
    big.height = 975;
    big.maximized = true;
    save(std.testing.io, dir_path, big);
    const was_big = load(gpa, std.testing.io, dir_path);
    defer if (was_big.root.len > 0) gpa.free(was_big.root);
    try std.testing.expect(was_big.maximized);

    // The root comes back as it went in.
    var rooted: Settings = .{};
    rooted.root = "C:/Users/a/Pictures/2024";
    save(std.testing.io, dir_path, rooted);
    const came_back = load(gpa, std.testing.io, dir_path);
    defer if (came_back.root.len > 0) gpa.free(came_back.root);
    try std.testing.expectEqualStrings("C:/Users/a/Pictures/2024", came_back.root);
}
