//! Tests for what goes into the picture files: the stars and the tags of
//! xmp.zig, from the bytes a camera would have written (src/exif.zig's
//! fixture) to the file on disk and back.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const xmp = @import("xmp.zig");
const theme = @import("theme.zig");
const tests_mod = @import("tests.zig");

/// The bytes of a jpeg that carries the fixture's exif: enough of one for
/// the size to be measured and the exif to be read, and no more.
fn exifJpeg(f: *const exif.Fixture) [218]u8 {
    var jpeg: [218]u8 = @splat(0);
    jpeg[0] = 0xFF;
    jpeg[1] = 0xD8;
    jpeg[2] = 0xFF;
    jpeg[3] = 0xE1;
    const seg: u16 = @intCast(2 + 6 + 191);
    jpeg[4] = @intCast(seg >> 8);
    jpeg[5] = @intCast(seg & 0xFF);
    @memcpy(jpeg[6..12], "Exif\x00\x00");
    @memcpy(jpeg[12..][0..191], f.bytes[0..191]);
    var n: usize = 12 + 191;
    jpeg[n] = 0xFF;
    jpeg[n + 1] = 0xC0;
    const sof = [_]u8{ 0x00, 0x0B, 0x08, 0x00, 0x08, 0x00, 0x10, 0x01, 0x01, 0x11, 0x00 };
    @memcpy(jpeg[n + 2 ..][0..sof.len], &sof);
    n = n + 2 + sof.len;
    jpeg[n] = 0xFF;
    jpeg[n + 1] = 0xD9;
    return jpeg;
}

test "stars go into the picture file, and the gallery sorts by them" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = exifJpeg(&f);
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const dir_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(dir_path);

    const names = [_][]const u8{ "a.jpg", "b.jpg", "c.jpg" };
    for (names, 0..) |name, i| {
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = jpeg[0..] });
        var m: exif.Meta = .{};
        m.rating = @intCast(1 + i * 2);
        const file_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_path, name });
        defer gpa.free(file_path);
        try xmp.rewriteFile(gpa, std.testing.io, file_path, &m);
    }

    const state = try app.State.create(gpa, std.testing.io, dir_path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // By stars: the most first.
    try t.clickText("Stars");
    t.settle(0.2);
    try std.testing.expectEqualStrings("c.jpg", state.shown[0].name);
    try std.testing.expectEqualStrings("a.jpg", state.shown[2].name);

    // The other way: the least first.
    try t.clickText("↓");
    t.settle(0.2);
    try std.testing.expectEqualStrings("a.jpg", state.shown[0].name);
    try std.testing.expectEqualStrings("c.jpg", state.shown[2].name);
}

test "the number keys rate a picture, and t tags it, into the file" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = exifJpeg(&f);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg[0..] });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);

    // Four stars: the cache knows, and the file on disk says the same.
    t.typeText("4");
    t.settle(0.2);
    const pic_path = state.current.?.pictures[0].path;
    try std.testing.expectEqual(@as(i8, 4), state.shared.metaOf(pic_path).?.rating);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(bytes);
    try std.testing.expectEqual(@as(i8, 4), exif.parse(bytes).?.rating);

    // A tag: t opens the typing, the field takes the word, enter sets it.
    t.typeText("t");
    t.settle(0.1);
    try t.clickText("Add a tag…");
    t.typeText("family");
    t.key(.enter);
    t.settle(0.2);
    const meta = state.shared.metaOf(pic_path).?;
    try std.testing.expectEqual(@as(usize, 1), meta.tags_n);
    try std.testing.expectEqualStrings("family", meta.tagOf(0));
    const tagged = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(tagged);
    const on_disk = exif.parse(tagged).?;
    try std.testing.expectEqual(@as(usize, 1), on_disk.tags_n);
    try std.testing.expectEqualStrings("family", on_disk.tagOf(0));

    // Zero takes the stars off; the tags stay.
    t.typeText("0");
    t.settle(0.2);
    const cleared = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(cleared);
    const out = exif.parse(cleared).?;
    try std.testing.expectEqual(@as(i8, -1), out.rating);
    try std.testing.expectEqual(@as(usize, 1), out.tags_n);
}

test "snapshot: the exif panel with stars and tags" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = exif.Fixture.build(.little);
    const jpeg = exifJpeg(&f);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg[0..] });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    var m: exif.Meta = .{};
    m.rating = 4;
    m.addTag("family");
    m.addTag("sea");
    const file_path = try std.fmt.allocPrint(gpa, "{s}/pic.jpg", .{path});
    defer gpa.free(file_path);
    try xmp.rewriteFile(gpa, std.testing.io, file_path, &m);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1280, .height = 800, .theme = theme.forDark(true) });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.3);
    t.screenshot("docs/app-rating.png") catch {};
}
