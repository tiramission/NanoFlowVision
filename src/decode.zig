//! Pictures, as the pixels nanoui draws: BGRA, premultiplied.
//!
//! Two ways in: `probeSize` reads a picture's own size from its header
//! alone, so a gallery can be laid out before a single pixel is decoded;
//! `decode` turns a whole file into the pixels the renderer samples.

const std = @import("std");
const builtin = @import("builtin");
const zigimg = @import("zigimg");

pub const Size = struct {
    w: u32,
    h: u32,

    /// Width over height; 1 for a picture that cannot be measured.
    pub fn aspect(s: Size) f32 {
        if (s.h == 0) return 1;
        return @as(f32, @floatFromInt(s.w)) / @as(f32, @floatFromInt(s.h));
    }
};

pub const Pixels = struct {
    w: u32,
    h: u32,
    /// Premultiplied BGRA, four bytes a pixel.
    bgra: []u8,

    pub fn deinit(self: Pixels, gpa: std.mem.Allocator) void {
        gpa.free(self.bgra);
    }
};

/// The picture's own size, from its header alone: no pixels decoded.
pub fn probeSize(bytes: []const u8) ?Size {
    if (bytes.len >= 24 and std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n")) {
        return .{
            .w = std.mem.readInt(u32, bytes[16..20], .big),
            .h = std.mem.readInt(u32, bytes[20..24], .big),
        };
    }
    if (bytes.len >= 10 and std.mem.startsWith(u8, bytes, "GIF8")) {
        return .{
            .w = std.mem.readInt(u16, bytes[6..8], .little),
            .h = std.mem.readInt(u16, bytes[8..10], .little),
        };
    }
    if (bytes.len >= 26 and bytes[0] == 'B' and bytes[1] == 'M') {
        const w = std.mem.readInt(i32, bytes[18..22], .little);
        const h = std.mem.readInt(i32, bytes[22..26], .little);
        return .{ .w = @intCast(@abs(w)), .h = @intCast(@abs(h)) };
    }
    if (bytes.len >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8) return jpegSize(bytes);
    return null;
}

/// A JPEG's size, from its frame header: walk the markers to it.
fn jpegSize(bytes: []const u8) ?Size {
    var i: usize = 2;
    while (i + 9 <= bytes.len) {
        if (bytes[i] != 0xFF) {
            i += 1;
            continue;
        }
        const marker = bytes[i + 1];
        if (marker == 0xFF) {
            i += 1;
            continue;
        }
        // The frame headers, SOF0 to SOF15, minus the three that are not.
        const is_sof = marker >= 0xC0 and marker <= 0xCF and
            marker != 0xC4 and marker != 0xC8 and marker != 0xCC;
        if (is_sof) {
            return .{
                .h = std.mem.readInt(u16, bytes[i + 5 ..][0..2], .big),
                .w = std.mem.readInt(u16, bytes[i + 7 ..][0..2], .big),
            };
        }
        // The markers that stand alone carry no length.
        if (marker == 0x01 or (marker >= 0xD0 and marker <= 0xD9)) {
            i += 2;
            continue;
        }
        const len = std.mem.readInt(u16, bytes[i + 2 ..][0..2], .big);
        if (len < 2) return null;
        i += 2 + len;
    }
    return null;
}

/// The picture as pixels, no longer than `max_side` on its longest side.
/// The pixels each one covers are averaged, so a thumbnail does not alias.
pub fn decode(gpa: std.mem.Allocator, bytes: []const u8, max_side: u32) !Pixels {
    var img = try zigimg.Image.fromMemory(gpa, bytes);
    defer img.deinit(gpa);
    if (img.width == 0 or img.height == 0) return error.BadPicture;
    try img.convert(gpa, .rgba32);

    const src = img.pixels.rgba32;
    const sw: u32 = @intCast(img.width);
    const sh: u32 = @intCast(img.height);
    const longest = @max(sw, sh);
    var dw = sw;
    var dh = sh;
    if (longest > max_side) {
        dw = @max(1, sw * max_side / longest);
        dh = @max(1, sh * max_side / longest);
    }

    const out = try gpa.alloc(u8, @as(usize, dw) * dh * 4);
    errdefer gpa.free(out);
    for (0..dh) |y| {
        const sy0 = y * sh / dh;
        const sy1 = @max(sy0 + 1, (y + 1) * sh / dh);
        for (0..dw) |x| {
            const sx0 = x * sw / dw;
            const sx1 = @max(sx0 + 1, (x + 1) * sw / dw);
            // The colours the new pixel covers, and the same colours with
            // their alpha already in them.
            var sum = [4]u64{ 0, 0, 0, 0 };
            var over = [3]u64{ 0, 0, 0 };
            for (sy0..sy1) |sy| {
                for (sx0..sx1) |sx| {
                    const p = src[@as(usize, sy) * sw + sx];
                    sum[0] += p.r;
                    sum[1] += p.g;
                    sum[2] += p.b;
                    sum[3] += p.a;
                    over[0] += @as(u64, p.r) * p.a;
                    over[1] += @as(u64, p.g) * p.a;
                    over[2] += @as(u64, p.b) * p.a;
                }
            }
            const n: u64 = @intCast((sy1 - sy0) * (sx1 - sx0));
            const o = (@as(usize, y) * dw + x) * 4;
            // Premultiplied BGRA, as the renderers draw it.
            out[o + 0] = @intCast(over[2] / (n * 255));
            out[o + 1] = @intCast(over[1] / (n * 255));
            out[o + 2] = @intCast(over[0] / (n * 255));
            out[o + 3] = @intCast(sum[3] / n);
        }
    }
    return .{ .w = dw, .h = dh, .bgra = out };
}

/// The most bytes of a file the pure-Zig way will read to decode it.
pub const max_file: usize = 256 * 1024 * 1024;

/// The picture at `path` as pixels, no longer than `max_side` on its longest
/// side. Where the platform has a system decoder -- Windows' WIC, macOS'
/// ImageIO -- the picture is scaled while it is decoded, and the file is
/// never whole in memory; elsewhere, and wherever the system decoder cannot
/// read a picture, the whole file is read and zigimg makes the thumbnail.
pub fn decodeFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8, max_side: u32) !Pixels {
    if (builtin.os.tag == .windows) {
        const wic = @import("wic.zig");
        if (wic.decodeFile(gpa, path, max_side)) |pixels| return pixels else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {}, // the system decoder does not know this picture
        }
    }
    if (builtin.os.tag == .macos) {
        const imageio = @import("imageio.zig");
        if (imageio.decodeFile(gpa, path, max_side)) |pixels| return pixels else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {},
        }
    }
    const bytes = try @import("scan.zig").readAll(gpa, io, path, .limited(max_file));
    defer gpa.free(bytes);
    return decode(gpa, bytes, max_side);
}

test "a JPEG's size comes from its header" {
    // A minimal JPEG header: SOI, then a frame header saying 16 by 8.
    const bytes = [_]u8{
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, 0x00, 0x11, // SOF0, length 17
        0x08, // precision
        0x00, 0x08, // height 8
        0x00, 0x10, // width 16
        0x03, // components
    };
    const s = probeSize(&bytes).?;
    try std.testing.expectEqual(@as(u32, 16), s.w);
    try std.testing.expectEqual(@as(u32, 8), s.h);
    try std.testing.expectEqual(@as(f32, 2.0), s.aspect());
}

test "a PNG's size comes from its header" {
    const bytes = [_]u8{
        0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A,
        0,    0,   0,   13,  'I',  'H',  'D',  'R',
        0, 0, 0, 4, // width 4
        0, 0, 0, 2, // height 2
        8, 6, 0, 0,
        0,
    };
    const s = probeSize(&bytes).?;
    try std.testing.expectEqual(@as(u32, 4), s.w);
    try std.testing.expectEqual(@as(u32, 2), s.h);
}

test "a picture too small to measure has no size" {
    try std.testing.expect(probeSize("not an image at all") == null);
}
