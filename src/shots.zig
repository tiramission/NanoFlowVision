//! The snapshots' own PNG writer. nanoui's writer stores deflate blocks
//! uncompressed -- good enough for a test's one-off, but the shots in
//! docs/ are read by people and rendered by GitHub, and a 1280x800 frame
//! at 2x is 16 MB that way. These rows go through std's flate instead,
//! so the same picture is a few hundred kilobytes.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

fn crc(parts: []const []const u8) u32 {
    var c = std.hash.Crc32.init();
    for (parts) |p| c.update(p);
    return c.final();
}

fn chunk(out: *std.ArrayList(u8), gpa: std.mem.Allocator, kind: *const [4]u8, data: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(data.len), .big);
    try out.appendSlice(gpa, &len);
    try out.appendSlice(gpa, kind);
    try out.appendSlice(gpa, data);
    var sum: [4]u8 = undefined;
    std.mem.writeInt(u32, &sum, crc(&.{ kind, data }), .big);
    try out.appendSlice(gpa, &sum);
}

/// Writes a tester's frame -- premultiplied BGRA -- as a straight RGBA
/// PNG, deflated.
pub fn write(gpa: std.mem.Allocator, io: std.Io, path: []const u8, pixels: anytype) !void {
    const bytes = try encode(gpa, pixels);
    defer gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

/// The PNG's own bytes.
pub fn encode(gpa: std.mem.Allocator, pixels: anytype) ![]u8 {
    // Rows, each led by filter type 0, un-premultiplied as PNG wants.
    const row_len = pixels.width * 4 + 1;
    const raw = try gpa.alloc(u8, row_len * pixels.height);
    defer gpa.free(raw);
    for (0..pixels.height) |y| {
        raw[y * row_len] = 0;
        for (0..pixels.width) |x| {
            const s = pixels.bytes[(y * pixels.width + x) * 4 ..][0..4];
            const d = raw[y * row_len + 1 + x * 4 ..][0..4];
            const a = s[3];
            const un = struct {
                fn f(v: u8, al: u8) u8 {
                    if (al == 0) return 0;
                    return @intCast(@min(255, (@as(u32, v) * 255 + al / 2) / al));
                }
            }.f;
            d.* = .{ un(s[2], a), un(s[1], a), un(s[0], a), a };
        }
    }

    const window = try gpa.alloc(u8, std.compress.flate.max_window_len);
    defer gpa.free(window);
    var out: std.Io.Writer.Allocating = try .initCapacity(gpa, 1 << 14);
    defer out.deinit();
    var deflate = try std.compress.flate.Compress.init(&out.writer, window, .zlib, .default);
    try deflate.writer.writeAll(raw);
    try deflate.finish();
    const z = out.written();

    var png: std.ArrayList(u8) = .empty;
    errdefer png.deinit(gpa);
    try png.appendSlice(gpa, "\x89PNG\r\n\x1a\n");
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(pixels.width), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(pixels.height), .big);
    ihdr[8..13].* = .{ 8, 6, 0, 0, 0 }; // 8 bits, RGBA
    try chunk(&png, gpa, "IHDR", &ihdr);
    try chunk(&png, gpa, "IDAT", z);
    try chunk(&png, gpa, "IEND", "");
    return png.toOwnedSlice(gpa);
}

/// Writes what a tester last drew.
pub fn shot(t: *ui.Tester, path: []const u8) !void {
    const pixels = try t.render(t.gpa);
    defer pixels.deinit(t.gpa);
    try write(t.gpa, std.testing.io, path, pixels);
}

test "a shot is a compressed PNG" {
    const gpa = std.testing.allocator;
    // A flat red frame, as a tester renders one.
    var frame: [64 * 64 * 4]u8 = undefined;
    for (0..64 * 64) |i| frame[i * 4 ..][0..4].* = .{ 0, 0, 255, 255 };
    const bytes = try encode(gpa, .{ .bytes = &frame, .width = 64, .height = 64 });
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("\x89PNG", bytes[0..4]);
    try std.testing.expectEqualStrings("IHDR", bytes[12..16]);
    // The zlib header inside IDAT is deflate's, not a stored block's: the
    // whole point of this file.
    try std.testing.expectEqual(@as(u8, 0x78), bytes[41]);
    try std.testing.expect(bytes.len < 1024);
}
