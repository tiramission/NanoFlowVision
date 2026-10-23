//! What a picture says about itself: EXIF, read from the bytes the
//! measurement already holds. A JPEG carries it in an APP1 segment, a
//! TIFF in its own header; the tags this needs live in the first few
//! kilobytes, so the file is never read twice. Strings land in the
//! structure's own fixed buffers -- the bytes they came from are a
//! worker's reused buffer, gone by the next job.

const std = @import("std");

/// The tags the gallery shows. Rationals keep their two halves: they are
/// shown as they were written (1/250 s, f/2.8), not rounded on the way in.
pub const Meta = struct {
    make_len: u8 = 0,
    make: [32]u8 = undefined,
    model_len: u8 = 0,
    model: [64]u8 = undefined,
    /// When the picture was taken: "2024:01:01 10:00:00", as EXIF writes it.
    date_len: u8 = 0,
    date: [20]u8 = undefined,
    exposure_num: u32 = 0,
    exposure_den: u32 = 0,
    aperture_num: u32 = 0,
    aperture_den: u32 = 0,
    iso: u32 = 0,
    focal_num: u32 = 0,
    focal_den: u32 = 0,
    /// How the picture was held: 1 upright, 6 and 8 turned, 3 upside down.
    orientation: u16 = 1,

    pub fn makeOf(m: *const Meta) []const u8 {
        return m.make[0..m.make_len];
    }

    pub fn modelOf(m: *const Meta) []const u8 {
        return m.model[0..m.model_len];
    }

    pub fn dateOf(m: *const Meta) []const u8 {
        return m.date[0..m.date_len];
    }

    /// Whether anything at all was found in this picture.
    pub fn empty(m: *const Meta) bool {
        return m.make_len == 0 and m.model_len == 0 and m.date_len == 0 and
            m.exposure_den == 0 and m.aperture_den == 0 and m.iso == 0 and
            m.focal_den == 0 and m.orientation == 1;
    }
};

/// Reads the EXIF out of a picture's first bytes, if it has any there.
pub fn parse(bytes: []const u8) ?Meta {
    if (bytes.len >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8) return parseJpeg(bytes);
    if (bytes.len >= 8 and (std.mem.eql(u8, bytes[0..4], "II\x2a\x00") or
        std.mem.eql(u8, bytes[0..4], "MM\x00\x2a")))
    {
        return parseTiff(bytes);
    }
    return null;
}

/// Walks a JPEG's markers to its Exif APP1 segment.
fn parseJpeg(bytes: []const u8) ?Meta {
    var i: usize = 2;
    while (i + 4 <= bytes.len) {
        if (bytes[i] != 0xFF) {
            i += 1;
            continue;
        }
        const marker = bytes[i + 1];
        // The markers that stand alone carry no length.
        if (marker == 0x01 or (marker >= 0xD0 and marker <= 0xD9)) {
            i += 2;
            continue;
        }
        if (marker == 0xFF or marker == 0xD8) {
            i += 1;
            continue;
        }
        if (marker == 0xDA) return null; // the picture itself begins: too late
        const len = std.mem.readInt(u16, bytes[i + 2 ..][0..2], .big);
        if (len < 2) return null;
        const seg_end = i + 2 + len;
        if (seg_end > bytes.len) return null;
        // The Exif segment starts with "Exif\0\0"; other APP1s are XMP and
        // the like, and are stepped over.
        if (marker == 0xE1 and i + 10 <= seg_end and
            std.mem.eql(u8, bytes[i + 4 .. i + 10], "Exif\x00\x00"))
        {
            if (parseTiff(bytes[i + 10 .. seg_end])) |meta| return meta;
        }
        i = seg_end;
    }
    return null;
}

const Tag = enum(u16) {
    make = 0x010F,
    model = 0x0110,
    orientation = 0x0112,
    exif_ifd = 0x8769,
    exposure = 0x829A,
    aperture = 0x829D,
    iso = 0x8827,
    date = 0x9003,
    focal = 0x920A,
    _,
};

fn typeSize(typ: u16) u32 {
    return switch (typ) {
        1, 2, 6, 7 => 1, // byte, ascii, sbyte, undefined
        3, 8 => 2, // short
        4, 9, 11 => 4, // long, slong, float
        5, 10, 12 => 8, // rational, srational, double
        else => 0,
    };
}

/// Reads one IFD: its entries, and where the Exif IFD sits if it says.
fn walkIfd(bytes: []const u8, endian: std.builtin.Endian, at: u32, meta: *Meta, exif_at: *?u32) void {
    if (at + 2 > bytes.len) return;
    const count = std.mem.readInt(u16, bytes[at..][0..2], endian);
    var i: usize = at + 2;
    var seen: usize = 0;
    while (seen < count and i + 12 <= bytes.len) : (seen += 1) {
        const tag: Tag = @fromBackingInt(@intCast(std.mem.readInt(u16, bytes[i..][0..2], endian)));
        const typ = std.mem.readInt(u16, bytes[i + 2 ..][0..2], endian);
        const value_len = typeSize(typ) * std.mem.readInt(u32, bytes[i + 4 ..][0..4], endian);
        // Four bytes or fewer sit in the entry itself; the rest are a
        // pointer to somewhere else in the block.
        const value_at: usize = if (value_len <= 4) i + 8 else blk: {
            const off = std.mem.readInt(u32, bytes[i + 8 ..][0..4], endian);
            if (off >= bytes.len) {
                i += 12;
                continue;
            }
            break :blk off;
        };
        switch (tag) {
            .make => copyAscii(meta.make[0..], &meta.make_len, bytes, value_at, value_len),
            .model => copyAscii(meta.model[0..], &meta.model_len, bytes, value_at, value_len),
            .orientation => {
                if (typ == 3 and value_at + 2 <= bytes.len)
                    meta.orientation = std.mem.readInt(u16, bytes[value_at..][0..2], endian);
            },
            .exif_ifd => {
                if (typ == 4 and value_at + 4 <= bytes.len)
                    exif_at.* = std.mem.readInt(u32, bytes[value_at..][0..4], endian);
            },
            .exposure => readRational(bytes, endian, value_at, typ, &meta.exposure_num, &meta.exposure_den),
            .aperture => readRational(bytes, endian, value_at, typ, &meta.aperture_num, &meta.aperture_den),
            .iso => {
                if (typ == 3 and value_at + 2 <= bytes.len)
                    meta.iso = std.mem.readInt(u16, bytes[value_at..][0..2], endian);
                if (typ == 4 and value_at + 4 <= bytes.len)
                    meta.iso = std.mem.readInt(u32, bytes[value_at..][0..4], endian);
            },
            .date => copyAscii(meta.date[0..], &meta.date_len, bytes, value_at, value_len),
            .focal => readRational(bytes, endian, value_at, typ, &meta.focal_num, &meta.focal_den),
            _ => {},
        }
        i += 12;
    }
}

fn readRational(bytes: []const u8, endian: std.builtin.Endian, at: usize, typ: u16, num: *u32, den: *u32) void {
    if (typ != 5 or at + 8 > bytes.len) return;
    num.* = std.mem.readInt(u32, bytes[at..][0..4], endian);
    den.* = std.mem.readInt(u32, bytes[at + 4 ..][0..4], endian);
}

fn copyAscii(buf: []u8, len: *u8, bytes: []const u8, at: usize, value_len: u32) void {
    if (value_len == 0) return;
    var n: usize = 0;
    while (n < value_len and at + n < bytes.len and n < buf.len) : (n += 1) {
        const ch = bytes[at + n];
        if (ch == 0) break;
        buf[n] = ch;
    }
    // EXIF strings are padded with spaces up to their count.
    while (n > 0 and buf[n - 1] == ' ') n -= 1;
    if (n > std.math.maxInt(u8)) n = std.math.maxInt(u8);
    len.* = @intCast(n);
}

/// Reads the EXIF out of a TIFF block: the header says which way the
/// numbers go, and where the first directory sits.
fn parseTiff(bytes: []const u8) ?Meta {
    var meta: Meta = .{};
    if (bytes.len < 8) return null;
    const endian: std.builtin.Endian = if (std.mem.eql(u8, bytes[0..2], "II"))
        .little
    else if (std.mem.eql(u8, bytes[0..2], "MM"))
        .big
    else
        return null;
    if (std.mem.readInt(u16, bytes[2..4], endian) != 42) return null;
    const ifd0 = std.mem.readInt(u32, bytes[4..8], endian);

    var exif_at: ?u32 = null;
    walkIfd(bytes, endian, ifd0, &meta, &exif_at);
    if (exif_at) |at| walkIfd(bytes, endian, at, &meta, &exif_at);
    if (meta.empty()) return null;
    return meta;
}

/// A hand-built TIFF block, in either byte order, with one of each kind
/// of tag the parser reads. Also the tests up in tests.zig build their
/// jpeg on top of it.
pub const Fixture = struct {
    bytes: [256]u8 = @splat(0),

    fn put16(self: *Fixture, at: usize, v: u16, e: std.builtin.Endian) void {
        std.mem.writeInt(u16, self.bytes[at..][0..2], v, e);
    }

    fn put32(self: *Fixture, at: usize, v: u32, e: std.builtin.Endian) void {
        std.mem.writeInt(u32, self.bytes[at..][0..4], v, e);
    }

    fn entry(self: *Fixture, at: usize, tag: u16, typ: u16, count: u32, value: [4]u8, e: std.builtin.Endian) void {
        self.put16(at, tag, e);
        self.put16(at + 2, typ, e);
        self.put32(at + 4, count, e);
        @memcpy(self.bytes[at + 8 ..][0..4], &value);
    }

    fn value16(v: u16, e: std.builtin.Endian) [4]u8 {
        var b: [4]u8 = @splat(0);
        std.mem.writeInt(u16, b[0..2], v, e);
        return b;
    }

    fn value32(v: u32, e: std.builtin.Endian) [4]u8 {
        var b: [4]u8 = @splat(0);
        std.mem.writeInt(u32, b[0..4], v, e);
        return b;
    }

    /// The block: IFD0 with Make, Model, Orientation and the Exif pointer;
    /// the Exif IFD with a date, a shutter, an aperture, an ISO and a focal
    /// length. Strings and rationals sit behind their entries.
    pub fn build(e: std.builtin.Endian) Fixture {
        var f: Fixture = .{};
        f.bytes[0..2].* = if (e == .little) "II".* else "MM".*;
        f.put16(2, 42, e);
        f.put32(4, 8, e);

        f.put16(8, 4, e); // IFD0: four entries
        f.entry(10, 0x010F, 2, 6, value32(62, e), e); // Make
        f.entry(22, 0x0110, 2, 13, value32(68, e), e); // Model
        f.entry(34, 0x0112, 3, 1, value16(6, e), e); // Orientation
        f.entry(46, 0x8769, 4, 1, value32(81, e), e); // Exif IFD
        f.put32(58, 0, e); // no IFD1

        @memcpy(f.bytes[62..68], "Canon\x00");
        @memcpy(f.bytes[68..81], "Canon EOS R5\x00");

        f.put16(81, 5, e); // Exif IFD: five entries
        f.entry(83, 0x9003, 2, 20, value32(147, e), e); // date
        f.entry(95, 0x829A, 5, 1, value32(167, e), e); // exposure
        f.entry(107, 0x829D, 5, 1, value32(175, e), e); // aperture
        f.entry(119, 0x8827, 3, 1, value16(200, e), e); // ISO
        f.entry(131, 0x920A, 5, 1, value32(183, e), e); // focal
        f.put32(143, 0, e);

        @memcpy(f.bytes[147..167], "2024:01:02 03:04:05\x00");
        f.put32(167, 1, e); // 1/250 s
        f.put32(171, 250, e);
        f.put32(175, 28, e); // f/2.8
        f.put32(179, 10, e);
        f.put32(183, 240, e); // 24 mm
        f.put32(187, 10, e);
        return f;
    }
};

test "exif comes out of a tiff block, little endian" {
    const f = Fixture.build(.little);
    const meta = parse(f.bytes[0..191]).?;
    try std.testing.expectEqualStrings("Canon", meta.makeOf());
    try std.testing.expectEqualStrings("Canon EOS R5", meta.modelOf());
    try std.testing.expectEqual(@as(u16, 6), meta.orientation);
    try std.testing.expectEqualStrings("2024:01:02 03:04:05", meta.dateOf());
    try std.testing.expectEqual(@as(u32, 1), meta.exposure_num);
    try std.testing.expectEqual(@as(u32, 250), meta.exposure_den);
    try std.testing.expectEqual(@as(u32, 28), meta.aperture_num);
    try std.testing.expectEqual(@as(u32, 10), meta.aperture_den);
    try std.testing.expectEqual(@as(u32, 200), meta.iso);
    try std.testing.expectEqual(@as(u32, 240), meta.focal_num);
    try std.testing.expectEqual(@as(u32, 10), meta.focal_den);
    try std.testing.expect(!meta.empty());
}

test "exif comes out of a tiff block, big endian" {
    const f = Fixture.build(.big);
    const meta = parse(f.bytes[0..191]).?;
    try std.testing.expectEqualStrings("Canon", meta.makeOf());
    try std.testing.expectEqualStrings("Canon EOS R5", meta.modelOf());
    try std.testing.expectEqual(@as(u16, 6), meta.orientation);
    try std.testing.expectEqual(@as(u32, 200), meta.iso);
    try std.testing.expectEqual(@as(u32, 28), meta.aperture_num);
}

test "exif comes out of a jpeg's app1 segment" {
    const f = Fixture.build(.little);
    var jpeg: [2 + 4 + 6 + 191 + 2]u8 = undefined;
    var n: usize = 0;
    jpeg[0] = 0xFF;
    jpeg[1] = 0xD8; // SOI
    jpeg[2] = 0xFF;
    jpeg[3] = 0xE1; // APP1
    const seg: u16 = @intCast(2 + 6 + 191); // the length counts itself
    jpeg[4] = @intCast(seg >> 8);
    jpeg[5] = @intCast(seg & 0xFF);
    @memcpy(jpeg[6..12], "Exif\x00\x00");
    @memcpy(jpeg[12..][0..191], f.bytes[0..191]);
    n = 12 + 191;
    jpeg[n] = 0xFF;
    jpeg[n + 1] = 0xD9; // EOI

    const meta = parse(jpeg[0 .. n + 2]).?;
    try std.testing.expectEqualStrings("Canon", meta.makeOf());
    try std.testing.expectEqual(@as(u32, 200), meta.iso);
}

test "exif steps over an xmp segment and takes the one it knows" {
    const f = Fixture.build(.little);
    var jpeg: [512]u8 = undefined;
    var n: usize = 0;
    jpeg[0] = 0xFF;
    jpeg[1] = 0xD8;
    // An APP1 that is not Exif: XMP, say.
    jpeg[2] = 0xFF;
    jpeg[3] = 0xE1;
    const xmp: u16 = @intCast(2 + "http://ns.adobe.com/xap/1.0/\x00".len);
    jpeg[4] = @intCast(xmp >> 8);
    jpeg[5] = @intCast(xmp & 0xFF);
    const xmp_len = xmp - 2;
    @memcpy(jpeg[6..][0..xmp_len], "http://ns.adobe.com/xap/1.0/\x00");
    n = 6 + xmp_len;
    // Then the Exif one.
    jpeg[n] = 0xFF;
    jpeg[n + 1] = 0xE1;
    const seg: u16 = @intCast(2 + 6 + 191);
    jpeg[n + 2] = @intCast(seg >> 8);
    jpeg[n + 3] = @intCast(seg & 0xFF);
    @memcpy(jpeg[n + 4 ..][0..6], "Exif\x00\x00");
    @memcpy(jpeg[n + 10 ..][0..191], f.bytes[0..191]);
    n = n + 10 + 191;

    const meta = parse(jpeg[0..n]).?;
    try std.testing.expectEqualStrings("Canon", meta.makeOf());
}

test "exif takes nothing from nonsense" {
    try std.testing.expect(parse(&.{}) == null);
    try std.testing.expect(parse("not a picture at all") == null);
    try std.testing.expect(parse(&.{ 0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08 }) == null);
    try std.testing.expect(parse(&.{ 'I', 'I', 42, 0, 0xFF, 0xFF, 0xFF, 0x7F }) == null);
    // A TIFF whose IFD sits past its end: read, but finds nothing.
    try std.testing.expect(parse(&.{ 'I', 'I', 42, 0, 0xFF, 0x00, 0x00, 0x00 }) == null);
}
