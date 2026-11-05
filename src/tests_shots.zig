//! The design's own snapshots: the screens the redesign's plan names,
//! drawn offscreen and written to docs/redesign/shots/ for a reader's
//! eye. Each one stages the state it documents -- the empty wall, the
//! unreadable folder, the failed tile beside one still waiting -- so
//! the picture and the plan can be held side by side.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const thumbs = @import("thumbs.zig");
const xmp = @import("xmp.zig");
const tests_mod = @import("tests.zig");

/// The shots' home, made once by the first test that needs it.
fn ensureDir() !void {
    std.Io.Dir.cwd().createDirPath(std.testing.io, "docs/redesign/shots") catch {};
}

test "snapshot: the grid, lit and chosen" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // Three chosen, the keyboard on the second, the pointer on a
    // corner chip: what a culling afternoon looks like.
    const p1 = state.layout.placements[1];
    t.click(state.grid_x + p1.x + p1.w / 2, state.grid_y + p1.y - state.grid_offset + p1.h / 2);
    t.ctx.input.ctrl = true;
    const p2 = state.layout.placements[2];
    t.click(state.grid_x + p2.x + p2.w / 2, state.grid_y + p2.y - state.grid_offset + p2.h / 2);
    const p3 = state.layout.placements[3];
    t.click(state.grid_x + p3.x + p3.w / 2, state.grid_y + p3.y - state.grid_offset + p3.h / 2);
    t.ctx.input.ctrl = false;
    t.key(.down);
    const p5 = state.layout.placements[5];
    t.moveTo(state.grid_x + p5.x + p5.w - 10, state.grid_y + p5.y - state.grid_offset + 10);
    t.frame();
    try t.screenshot("docs/redesign/shots/grid-light.png");
}

test "snapshot: the grid in the dark" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    state.dark = true;
    state.appearance = .dark;
    // The tester's theme is told at init: the room is dark from the
    // first frame.
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    try std.testing.expect(state.dark);
    try t.screenshot("docs/redesign/shots/grid-dark.png");
}

test "snapshot: the narrow window keeps its way" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album");
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/two.png", .data = png });
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("album");
    t.settle(0.3);
    try tests_mod.waitForLayout(&t, state);
    t.resize(760, 800);
    t.settle(0.3);
    try t.screenshot("docs/redesign/shots/grid-narrow.png");
}

test "snapshot: the large view, with its strip and folded facts" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);
    const key = try thumbs.largeKey(gpa, state.large.?.path);
    defer gpa.free(key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(key)) |known| {
            if (known.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    try tests_mod.waitForThumbs(&t, state);
    t.frame();
    t.frame();
    t.typeText("i"); // the facts folded to a line
    t.settle(0.1);
    try t.screenshot("docs/redesign/shots/lightbox.png");
}

test "snapshot: the large view, zoomed, facts open" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // A photograph with a photograph's size, so 240% fills the window,
    // and with the exif the folded panel opens to.
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);
    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);
    const key = try thumbs.largeKey(gpa, state.large.?.path);
    defer gpa.free(key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(key)) |known| {
            if (known.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    // About 240%: the target set, then the easing given its frames. The
    // facts stand open -- the exif gives them something to say.
    state.zoom = 2.4;
    state.zoom_target = 2.4;
    try std.testing.expect(state.info_open);
    t.settle(0.6);
    try t.screenshot("docs/redesign/shots/lightbox-zoom.png");
}

test "snapshot: the settings sheet over its scrim" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("Settings");
    t.settle(0.6);
    try std.testing.expect(state.settings_open);
    try t.screenshot("docs/redesign/shots/settings.png");
}

test "snapshot: the empty folder" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "void");
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("void");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.current.?.pictures.len);
    try t.screenshot("docs/redesign/shots/empty.png");
}

test "snapshot: the search that matches nothing" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("Search…");
    t.typeText("zzz");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.shown.len);
    try t.screenshot("docs/redesign/shots/no-match.png");
}

test "snapshot: a tile that failed beside one still waiting" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 1);
    defer sample.deinit(gpa);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "broken.png", .data = "this is not a picture" });
    // A big second picture: its decode outlasts the broken one's
    // failure, so the two states stand together.
    const w: u32 = 1400;
    const h: u32 = 1000;
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
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "big.png", .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();

    // The moment the broken one has failed and the big one is still on
    // its way: the two answers, one wall.
    var tries: usize = 0;
    while (tries < 400) : (tries += 1) {
        t.frame();
        const broken = state.shared.get(state.current.?.pictures[0].path);
        const big = state.shared.get(state.current.?.pictures[1].path);
        if (broken != null and broken.?.failed) {
            if (big == null or big.?.thumb == null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    t.frame();
    try t.screenshot("docs/redesign/shots/failed.png");
}

test "snapshot: the rail folded away" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    _ = t.shortcut(.{ .key = 'b', .ctrl = true });
    t.settle(0.1);
    try std.testing.expect(!state.rail_visible);
    try t.screenshot("docs/redesign/shots/rail-collapsed.png");
}

test "snapshot: the measuring under way" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    // The wall before its sizes are known: the answers go out of the
    // cache, and one frame later the page is measuring again.
    state.shared.clear();
    t.frame();
    try std.testing.expect(state.shared.measuredCount() < state.current.?.pictures.len);
    try t.screenshot("docs/redesign/shots/measuring.png");
}

test "snapshot: the folder that cannot be read" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}/nowhere", .{ cwd, tmp.sub_path });
    defer gpa.free(path);
    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    t.frame();
    t.frame();
    try std.testing.expect(state.folder_broken);
    t.settle(0.5);
    try t.screenshot("docs/redesign/shots/unreadable.png");
}

test "snapshot: the choice the filter took off the wall" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    const stars = [_]i8{ 5, 3, 1 };
    const names = [_][]const u8{ "a.jpg", "b.jpg", "c.jpg" };
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const dir_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(dir_path);
    for (names, 0..) |name, i| {
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = jpeg[0..] });
        var m: exif.Meta = .{};
        m.rating = stars[i];
        const fp = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_path, name });
        defer gpa.free(fp);
        try xmp.rewriteFile(gpa, std.testing.io, fp, &m);
    }
    const path = dir_path;
    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // All three chosen, then the filter keeps only the five-star one:
    // the other two are still chosen, and the bar says where they went.
    _ = t.shortcut(.{ .key = 'a', .ctrl = true });
    t.settle(0.1);
    t.frame();
    const btn = state.filter_at;
    t.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
    t.settle(0.2);
    try t.clickText("★★★★★");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 1), state.shown.len);
    try std.testing.expect(t.containsText("hidden by the filter"));
    try t.screenshot("docs/redesign/shots/hidden.png");
}
