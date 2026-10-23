//! The XMP packet a photo carries when it is rated or tagged, and the
//! writing of it into a jpeg. The packet is a small XML block that other
//! programs (Lightroom and the rest) read the same way; it rides in an
//! APP1 segment of its own, next to the exif one. Writing goes through a
//! temporary file that replaces the original only once whole, so a crash
//! mid-write cannot take a photograph with it; the file's own date stays,
//! so a rating does not move a picture in a sort by date.

const std = @import("std");
const exif = @import("exif.zig");

/// The signature an APP1 carries before its XMP packet.
const xmp_sig = "http://ns.adobe.com/xap/1.0/\x00";

/// Builds the packet into `buf`, from what the picture should say.
pub fn packet(buf: []u8, m: *const exif.Meta) []const u8 {
    var n: usize = 0;
    put(buf, &n, "<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>", .{});
    put(buf, &n, "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">", .{});
    put(buf, &n, "<rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"", .{});
    if (m.rating >= 0) put(buf, &n, " xmp:Rating=\"{d}\"", .{m.rating});
    if (m.tags_n > 0) {
        put(buf, &n, "><dc:subject><rdf:Bag>", .{});
        for (0..m.tags_n) |i| {
            put(buf, &n, "<rdf:li>{s}</rdf:li>", .{m.tagOf(i)});
        }
        put(buf, &n, "</rdf:Bag></dc:subject>", .{});
    }
    put(buf, &n, "></rdf:Description></rdf:RDF></x:xmpmeta>", .{});
    put(buf, &n, "<?xpacket end=\"w\"?>", .{});
    return buf[0..n];
}

/// Rebuilds a jpeg's first segments with our packet in: the original
/// segments minus any XMP of their own, with ours right after the SOI.
/// Everything from the start of the picture data on is copied as it is.
pub fn rebuild(gpa: std.mem.Allocator, bytes: []const u8, pkt: []const u8) ![]u8 {
    if (bytes.len < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8) return error.NotJpeg;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, bytes[0..2]);

    // Our own segment: its length counts itself.
    const seg_len: u16 = @intCast(2 + xmp_sig.len + pkt.len);
    try out.appendSlice(gpa, &.{ 0xFF, 0xE1, @intCast(seg_len >> 8), @intCast(seg_len & 0xFF) });
    try out.appendSlice(gpa, xmp_sig);
    try out.appendSlice(gpa, pkt);

    var i: usize = 2;
    while (i + 4 <= bytes.len) {
        if (bytes[i] != 0xFF) {
            try out.append(gpa, bytes[i]);
            i += 1;
            continue;
        }
        const marker = bytes[i + 1];
        if (marker == 0x01 or (marker >= 0xD0 and marker <= 0xD9)) {
            try out.appendSlice(gpa, bytes[i .. i + 2]);
            i += 2;
            continue;
        }
        if (marker == 0xDA) {
            // The picture data itself: everything to the end goes as is.
            try out.appendSlice(gpa, bytes[i..]);
            return out.toOwnedSlice(gpa);
        }
        if (marker == 0xFF) {
            i += 1;
            continue;
        }
        const len = std.mem.readInt(u16, bytes[i + 2 ..][0..2], .big);
        if (len < 2) return error.BadJpeg;
        const seg_end = i + 2 + @as(usize, len);
        if (seg_end > bytes.len) return error.BadJpeg;
        // An XMP segment of the file's own is dropped: ours replaces it.
        const is_xmp = marker == 0xE1 and i + 4 + xmp_sig.len <= seg_end and
            std.mem.eql(u8, bytes[i + 4 ..][0..xmp_sig.len], xmp_sig);
        if (!is_xmp) try out.appendSlice(gpa, bytes[i..seg_end]);
        i = seg_end;
    }
    try out.appendSlice(gpa, bytes[i..]);
    return out.toOwnedSlice(gpa);
}

/// Writes the rating and tags into the picture file at `path`: reads it,
/// rebuilds it with a fresh packet, and replaces it in one step. The
/// file's own date is put back, so a rating does not re-date a picture.
pub fn rewriteFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8, m: *const exif.Meta) !void {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024 * 1024));
    defer gpa.free(bytes);
    const was = try scan.statFile(io, path);

    var pkt_buf: [2048]u8 = undefined;
    const pkt = packet(&pkt_buf, m);
    const rebuilt = try rebuild(gpa, bytes, pkt);
    defer gpa.free(rebuilt);

    var dir = try std.Io.Dir.openDirAbsolute(io, model.parentOf(path) orelse return error.NoParent, .{});
    defer dir.close(io);
    {
        var af = try dir.createFileAtomic(io, model.nameOf(path), .{ .replace = true });
        errdefer af.deinit(io);
        var buffer: [64 * 1024]u8 = undefined;
        var writer = af.file.writer(io, &buffer);
        try writer.interface.writeAll(rebuilt);
        try writer.interface.flush();
        try af.replace(io);
        af.deinit(io);
    }

    // The picture keeps its own date.
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_write });
    defer file.close(io);
    try file.setTimestamps(io, .{ .modify_timestamp = .{ .new = was.mtime } });
}

fn put(buf: []u8, n: *usize, comptime fmt: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(buf[n.*..], fmt, args) catch return;
    n.* += written.len;
}

const model = @import("model.zig");
const scan = @import("scan.zig");

test "a packet carries the rating and the tags, and reads back" {
    var m: exif.Meta = .{};
    m.rating = 4;
    m.addTag("family");
    m.addTag("sea");

    var buf: [2048]u8 = undefined;
    const pkt = packet(&buf, &m);
    var back: exif.Meta = .{};
    exif.readXmpPacket(pkt, &back);
    try std.testing.expectEqual(@as(i8, 4), back.rating);
    try std.testing.expectEqual(@as(usize, 2), back.tags_n);
    try std.testing.expectEqualStrings("family", back.tagOf(0));
    try std.testing.expectEqualStrings("sea", back.tagOf(1));
}

test "a packet with no rating reads back as none" {
    var buf: [2048]u8 = undefined;
    const pkt = packet(&buf, &.{});
    var back: exif.Meta = .{};
    exif.readXmpPacket(pkt, &back);
    try std.testing.expectEqual(@as(i8, -1), back.rating);
    try std.testing.expectEqual(@as(usize, 0), back.tags_n);
}

test "rebuilding a jpeg puts the packet in and keeps the picture" {
    const gpa = std.testing.allocator;
    // SOI, a sizeless minimal frame header and the end: enough structure
    // for the walk to keep everything but the packet.
    const original = [_]u8{
        0xFF, 0xD8,
        0xFF, 0xC0,
        0x00, 0x0B,
        0x08, 0x00,
        0x08, 0x00,
        0x10, 0x01,
        0x01, 0x11,
        0x00, 0xFF,
        0xDA, 0x00,
        0x02, 12,
        34,   56,
        0xFF, 0xD9,
    };
    var m: exif.Meta = .{};
    m.rating = 3;
    var buf: [2048]u8 = undefined;
    const rebuilt = try rebuild(gpa, original[0..], packet(&buf, &m));
    defer gpa.free(rebuilt);

    // Longer by exactly one segment; it starts with SOI + APP1 + signature.
    try std.testing.expect(rebuilt.len > original.len);
    try std.testing.expectEqual(@as(u8, 0xFF), rebuilt[0]);
    try std.testing.expectEqual(@as(u8, 0xD8), rebuilt[1]);
    try std.testing.expectEqual(@as(u8, 0xFF), rebuilt[2]);
    try std.testing.expectEqual(@as(u8, 0xE1), rebuilt[3]);
    try std.testing.expect(std.mem.indexOf(u8, rebuilt, "xmp:Rating=\"3\"") != null);

    // And a second write replaces the first, adding no second packet.
    const twice = try rebuild(gpa, rebuilt, packet(&buf, &m));
    defer gpa.free(twice);
    var packets: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, twice, i, "http://ns.adobe.com/xap/1.0/\x00")) |at| {
        packets += 1;
        i = at + 1;
    }
    try std.testing.expectEqual(@as(usize, 1), packets);
    // The picture data survived, to the last byte.
    try std.testing.expect(std.mem.indexOf(u8, twice, &.{ 0xFF, 0xDA, 0x00, 0x02, 12, 34, 56, 0xFF, 0xD9 }) != null);
}
