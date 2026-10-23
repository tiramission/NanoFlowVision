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
    return makeSampleWith(gpa, 1);
}

/// A folder with `count` red squares in it, and where it is.
fn makeSampleWith(gpa: std.mem.Allocator, count: usize) !Sample {
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

/// Waits until the workers have measured every picture, and the gallery is
/// laid out.
fn waitForLayout(t: *ui.Tester, state: *app.State) !void {
    var tries: usize = 0;
    while (tries < 400) : (tries += 1) {
        const current = state.current orelse return error.NoFolder;
        if (state.shared.measuredCount() >= current.pictures.len) {
            t.frame();
            return;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
        t.frame();
    }
    return error.TooSlow;
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

test "a file on disk is decoded by the platform's own decoder" {
    const gpa = std.testing.allocator;
    var sample = try makeSample(gpa);
    defer sample.deinit(gpa);

    // The file at rest, decoded the way the workers do it: the platform's
    // decoder where there is one, zigimg where there is not.
    const file = try std.fmt.allocPrint(gpa, "{s}/pic-0.png", .{sample.path});
    defer gpa.free(file);
    var pixels = try decode.decodeFile(gpa, std.testing.io, file, 256);
    defer pixels.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 2), pixels.w);
    try std.testing.expectEqual(@as(u32, 2), pixels.h);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixels.bgra[0..4]);
}

test "a picture larger than a thumbnail is scaled while it is decoded" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A 600 by 400 red picture: wider than a thumbnail's longest side.
    const w: u32 = 600;
    const h: u32 = 400;
    const red = try gpa.alloc(u8, @as(usize, w) * h * 4);
    defer gpa.free(red);
    var i: usize = 0;
    while (i + 3 < red.len) : (i += 4) {
        red[i] = 0;
        red[i + 1] = 0;
        red[i + 2] = 255;
        red[i + 3] = 255;
    }
    const png = try ui.png.encode(gpa, .{ .bytes = red, .width = w, .height = h });
    defer gpa.free(png);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "big.png", .data = png });

    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}/big.png", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    var pixels = try decode.decodeFile(gpa, std.testing.io, path, 256);
    defer pixels.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 256), pixels.w);
    try std.testing.expectEqual(@as(u32, 170), pixels.h);
    // A flat colour, scaled, is itself: premultiplied BGRA, blue first.
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixels.bgra[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, pixels.bgra[pixels.bgra.len - 4 ..]);
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
    const picture_path = state.current.?.pictures[0].path;
    var decoded = false;
    for (0..400) |_| {
        t.frame();
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
    const picture_path = state.current.?.pictures[0].path;
    const key = try thumbs.largeKey(gpa, picture_path);
    defer gpa.free(key);
    var decoded = false;
    for (0..400) |_| {
        t.frame();
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

test "the gallery waits for the sizes, then its layout is made once" {
    const gpa = std.testing.allocator;
    var sample = try makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();

    // Until the sizes are known, there is no layout to speak of.
    t.frame();
    if (state.shared.measuredCount() < 12) {
        try std.testing.expect(t.hasText("measuring"));
        try std.testing.expect(state.layout.placements.len == 0);
    }

    // Once they are known, the layout is made.
    try waitForLayout(&t, state);
    try std.testing.expectEqual(@as(usize, 12), state.layout.placements.len);
    try std.testing.expect(state.layout.height > 0);

    // And it is the same in the frames after: the gallery does not move.
    const height = state.layout.height;
    const columns = state.layout.columns;
    const first_y = state.layout.placements[0].y;
    t.frame();
    t.frame();
    try std.testing.expectEqual(height, state.layout.height);
    try std.testing.expectEqual(columns, state.layout.columns);
    try std.testing.expectEqual(first_y, state.layout.placements[0].y);

    // Another width makes it again.
    t.resize(600, 600);
    t.frame();
    try std.testing.expect(state.layout.width != 0);
    try std.testing.expect(state.layout.height != height or state.layout.columns != columns);
}

test "the thumbnails are asked for beyond the window, not only in it" {
    const gpa = std.testing.allocator;
    var sample = try makeSampleWith(gpa, 150);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try waitForLayout(&t, state);

    const current = state.current.?;
    // The pictures that are in the window, and those that are not.
    try std.testing.expect(state.built > 0);
    try std.testing.expect(state.built < current.pictures.len);

    // Every picture in the window is asked for, and so are the ones just
    // below it: they are on their way before they come into view.
    var asked: usize = 0;
    for (current.pictures) |*pic| {
        const known = state.shared.get(pic.path) orelse continue;
        if (known.decoding or known.thumb != null) asked += 1;
    }
    try std.testing.expect(asked > state.built);
    try std.testing.expect(asked < current.pictures.len);
}

test "the cache gives up the thumbnails that are not wanted" {
    const gpa = std.testing.allocator;
    var sample = try makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();

    // Wait for the thumbnails themselves.
    const current = state.current.?;
    var tries: usize = 0;
    while (tries < 400) : (tries += 1) {
        var ready = true;
        for (current.pictures) |*pic| {
            const known = state.shared.get(pic.path) orelse continue;
            if (known.thumb == null) ready = false;
        }
        if (ready) break;
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
        t.frame();
    }
    const first = current.pictures[0].path;
    try std.testing.expect(state.shared.get(first).?.thumb != null);

    // Nothing is wanted: the cache gives the thumbnails up.
    state.shared.trim(0, &.{});
    try std.testing.expect(state.shared.get(first).?.thumb == null);
}

test "scrolling moves the gallery, and the layout stays where it was" {
    const gpa = std.testing.allocator;
    var sample = try makeSampleWith(gpa, 150);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try waitForLayout(&t, state);

    // Where the pictures are, and how tall the whole gallery is.
    const height = state.layout.height;
    const first_y = state.layout.placements[0].y;
    const last = state.layout.placements.len - 1;
    const last_y = state.layout.placements[last].y;

    // Scroll down, over the gallery.
    t.scroll(500, 300, -400);
    t.frame();
    t.frame();

    // The gallery is longer than the window, so the view moved.
    try std.testing.expect(state.layout.height > 600);
    try std.testing.expect(state.last_offset > 0);

    // And the pictures did not move: the layout is the same one.
    try std.testing.expectEqual(height, state.layout.height);
    try std.testing.expectEqual(first_y, state.layout.placements[0].y);
    try std.testing.expectEqual(last_y, state.layout.placements[last].y);

    // The picture that is now at the top was asked for before it came into
    // view: it is on its way, or already there.
    const current = state.current.?;
    const top = state.first_picture.?;
    var found = false;
    for (current.pictures) |*pic| {
        if (top.y < 0) continue;
        const known = state.shared.get(pic.path) orelse continue;
        if (known.thumb != null or known.decoding) found = true;
    }
    try std.testing.expect(state.built > 0);
    try std.testing.expect(found);
}
