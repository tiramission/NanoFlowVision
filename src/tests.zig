//! The app's tests: the view, drawn offscreen, and the pictures it decodes.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const decode = @import("decode.zig");
const thumbs = @import("thumbs.zig");

/// A folder with a red square in it, and where it is.
const Sample = struct {
    tmp: std.testing.TmpDir,
    path: []u8,

    fn deinit(s: *Sample, gpa: std.mem.Allocator) void {
        gpa.free(s.path);
        s.tmp.cleanup();
    }
};

fn makeSample(gpa: std.mem.Allocator) !Sample {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    // A red square, as a PNG the app can read.
    var red = [_]u8{ 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 2, .height = 2 });
    defer gpa.free(png);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "red.png", .data = png });

    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    return .{ .tmp = tmp, .path = path };
}

test "a picture is decoded into the pixels the renderer draws" {
    const gpa = std.testing.allocator;
    var red = [_]u8{ 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 2, .height = 2 });
    defer gpa.free(png);

    // Its size comes from the header alone.
    const size = decode.probeSize(png).?;
    try std.testing.expectEqual(@as(u32, 2), size.w);
    try std.testing.expectEqual(@as(u32, 2), size.h);

    // And the pixels come out as premultiplied BGRA: blue first, red last.
    var pixels = try decode.decode(gpa, png, 256);
    defer pixels.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 2), pixels.w);
    try std.testing.expectEqual(@as(u32, 2), pixels.h);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixels.bgra[0..4]);
}

test "the gallery shows a folder's pictures, decoded in the background" {
    const gpa = std.testing.allocator;
    var sample = try makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    t.frame();

    // The tree, the toolbar and the count of pictures.
    try std.testing.expect(t.hasText("NanoFlowVision"));
    try std.testing.expect(t.hasText("1 pictures"));

    // The workers decode the picture in the background.
    const picture_path = try std.fmt.allocPrint(gpa, "{s}/red.png", .{sample.path});
    defer gpa.free(picture_path);
    var decoded = false;
    for (0..200) |_| {
        if (state.shared.get(picture_path)) |cached| {
            if (cached.thumb != null) {
                decoded = true;
                break;
            }
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    try std.testing.expect(decoded);

    // The picture's size was measured too, so the layout knows its shape.
    try std.testing.expect(state.shared.get(picture_path).?.measured);

    // And the red square is on the screen.
    t.frame();
    const rendered = try t.render(gpa);
    defer rendered.deinit(gpa);
    var reds: usize = 0;
    var i: usize = 0;
    while (i + 3 < rendered.bytes.len) : (i += 4) {
        const r = rendered.bytes[i + 2];
        const g = rendered.bytes[i + 1];
        const b = rendered.bytes[i];
        if (r > 200 and g < 60 and b < 60) reds += 1;
    }
    try std.testing.expect(reds > 0);
}

test "the tree opens a folder when its row is clicked" {
    const gpa = std.testing.allocator;
    var sample = try makeSample(gpa);
    defer sample.deinit(gpa);

    // A folder inside the sample, and one inside that.
    try sample.tmp.dir.createDirPath(std.testing.io, "album");
    try sample.tmp.dir.createDirPath(std.testing.io, "album/2024");
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/two.png", .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    t.frame();

    // The album is in the tree, and the root's picture is counted.
    try std.testing.expect(t.hasText("album"));
    try std.testing.expect(t.hasText("1 pictures"));

    try t.clickText("album");
    t.settle(0.2);
    // The gallery shows the album now, and the album's own picture.
    try std.testing.expectEqualStrings("album", state.current.?.name);
    try std.testing.expectEqual(@as(usize, 1), state.current.?.pictures.len);
    // And the folder inside the album shows in the tree.
    try std.testing.expect(t.hasText("2024"));
}

test "a double click shows the picture large" {
    const gpa = std.testing.allocator;
    var sample = try makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    t.frame();
    t.frame(); // the first frame only knows where the picture was

    const where = state.first_picture orelse return error.NoPictureOnScreen;
    try std.testing.expect(where.w > 0 and where.h > 0);

    // A double click on it opens it large.
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);
    try std.testing.expect(state.large != null);

    // The large picture is decoded in the background too.
    const picture_path = try std.fmt.allocPrint(gpa, "{s}/red.png", .{sample.path});
    defer gpa.free(picture_path);
    const key = try thumbs.largeKey(gpa, picture_path);
    defer gpa.free(key);
    var decoded = false;
    for (0..200) |_| {
        if (state.shared.get(key)) |cached| {
            if (cached.thumb != null) {
                decoded = true;
                break;
            }
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    try std.testing.expect(decoded);

    // And it is drawn, much bigger than the thumbnail was.
    t.frame();
    const rendered = try t.render(gpa);
    defer rendered.deinit(gpa);
    var reds: usize = 0;
    var i: usize = 0;
    while (i + 3 < rendered.bytes.len) : (i += 4) {
        const r = rendered.bytes[i + 2];
        const g = rendered.bytes[i + 1];
        const b = rendered.bytes[i];
        if (r > 200 and g < 60 and b < 60) reds += 1;
    }
    try std.testing.expect(reds > 400);

    // Escape closes it again.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expect(state.large == null);
}
