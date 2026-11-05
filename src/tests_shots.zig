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
const fullscreen = @import("fullscreen.zig");
const thumbs = @import("thumbs.zig");
const xmp = @import("xmp.zig");
const shots = @import("shots.zig");
const tests_mod = @import("tests.zig");

/// The shots' home, made once by the first test that needs it.
fn ensureDir() !void {
    std.Io.Dir.cwd().createDirPath(std.testing.io, "docs/redesign/shots") catch {};
}

test "snapshot: the grid, lit and chosen" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "grid-light", 12);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // Three chosen, the keyboard on the second, the pointer on a corner
    // chip: what a culling afternoon looks like. The state is set rather
    // than clicked tile by tile -- a click also moves the cursor, and the
    // view follows the cursor, so a click-driven setup can scroll the wall
    // away from the row it means to show.
    state.select.only(state.shown[1], 1);
    state.select.toggle(state.shown[2], 2);
    state.select.toggle(state.shown[3], 3);
    state.select.cursor = 1;
    state.scroll_to_top = true;
    t.settle(0.2);
    // The pointer on a corner chip, in the first row.
    const p3 = state.layout.placements[3];
    t.moveTo(state.grid_x + p3.x + p3.w - 10, state.grid_y + p3.y - state.grid_offset + 10);
    t.frame();
    try shots.shot(&t, "docs/redesign/shots/grid-light.png");
}

test "snapshot: the grid in the dark" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "grid-dark", 12);
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
    try shots.shot(&t, "docs/redesign/shots/grid-dark.png");
}

test "snapshot: the narrow window keeps its way" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "grid-narrow", 4);
    defer sample.deinit(gpa);
    const album = try std.fmt.allocPrint(gpa, "{s}/album", .{sample.path});
    defer gpa.free(album);
    std.Io.Dir.createDirAbsolute(std.testing.io, album, .default_file) catch {};
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    const two = try std.fmt.allocPrint(gpa, "{s}/album/two.png", .{sample.path});
    defer gpa.free(two);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = two, .data = png });
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
    try shots.shot(&t, "docs/redesign/shots/grid-narrow.png");
}

test "snapshot: the large view, with its strip and folded facts" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "lightbox", 12);
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
    try shots.shot(&t, "docs/redesign/shots/lightbox.png");
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
    // About 240%: the target set, the anchor in the middle, and the
    // easing given its frames. The facts stand open -- the exif gives
    // them something to say.
    state.zoom_mode = .free;
    state.zoom_target = 2.4;
    state.anchor = .{ .x = 0.5, .y = 0.5 };
    state.anchor_mouse = .{ .x = 640, .y = 400 };
    try std.testing.expect(state.info_open);
    t.settle(0.6);
    try shots.shot(&t, "docs/redesign/shots/lightbox-zoom.png");
}

test "snapshot: the settings sheet over its scrim" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "settings", 12);
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
    try shots.shot(&t, "docs/redesign/shots/settings.png");
}

test "snapshot: the empty folder" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "empty", 4);
    defer sample.deinit(gpa);
    const void_dir = try std.fmt.allocPrint(gpa, "{s}/void", .{sample.path});
    defer gpa.free(void_dir);
    std.Io.Dir.createDirAbsolute(std.testing.io, void_dir, .default_file) catch {};
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("void");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.current.?.pictures.len);
    try shots.shot(&t, "docs/redesign/shots/empty.png");
}

test "snapshot: the search that matches nothing" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "no-match", 4);
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
    try shots.shot(&t, "docs/redesign/shots/no-match.png");
}

test "snapshot: a tile that failed beside one still waiting" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "failed", 1);
    defer sample.deinit(gpa);
    const broken_path = try std.fmt.allocPrint(gpa, "{s}/broken.png", .{sample.path});
    defer gpa.free(broken_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = broken_path, .data = "this is not a picture" });
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
    const big_path = try std.fmt.allocPrint(gpa, "{s}/big.png", .{sample.path});
    defer gpa.free(big_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = big_path, .data = png });

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
    try shots.shot(&t, "docs/redesign/shots/failed.png");
}

test "snapshot: the rail folded away" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "rail-collapsed", 12);
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
    try shots.shot(&t, "docs/redesign/shots/rail-collapsed.png");
}

test "snapshot: the measuring under way" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "measuring", 12);
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
    try shots.shot(&t, "docs/redesign/shots/measuring.png");
}

test "snapshot: the folder that cannot be read" {
    try ensureDir();
    const gpa = std.testing.allocator;
    // A fixed path: the dialog names the folder it could not read, and
    // one named at random would differ in the picture on every run. The
    // home is set so the path is drawn from the home down, which keeps
    // this machine's own directories out of a picture that ships with the
    // docs.
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/shots/unreadable/nowhere", .{cwd});
    defer gpa.free(path);
    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    // The home is where the shot's own path starts, so the dialog writes
    // it from there down and this machine's directories stay out of the
    // picture.
    try state.setHome(cwd);
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    t.frame();
    t.frame();
    try std.testing.expect(state.folder_broken);
    t.settle(0.5);
    try shots.shot(&t, "docs/redesign/shots/unreadable.png");
}

test "snapshot: the choice the filter took off the wall" {
    try ensureDir();
    const gpa = std.testing.allocator;
    // A fixed folder: the window's title is the folder's name, and one
    // named at random would differ in the picture on every run.
    const folder = try tests_mod.makeShotFolder(gpa, "hidden", 0);
    defer folder.deinit(gpa);
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    const stars = [_]i8{ 5, 3, 1 };
    const names = [_][]const u8{ "a.jpg", "b.jpg", "c.jpg" };
    for (names, 0..) |name, i| {
        const fp = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ folder.path, name });
        defer gpa.free(fp);
        const rel = try std.fmt.allocPrint(gpa, ".zig-cache/shots/hidden/{s}", .{name});
        defer gpa.free(rel);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = rel, .data = jpeg[0..] });
        var m: exif.Meta = .{};
        m.rating = stars[i];
        try xmp.rewriteFile(gpa, std.testing.io, fp, &m);
    }
    const path = folder.path;
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
    try shots.shot(&t, "docs/redesign/shots/hidden.png");
}

test "snapshot: the keys table" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "keys", 4);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1100, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    _ = t.shortcut(.{ .key = '/', .ctrl = true });
    t.settle(0.5);
    try std.testing.expect(state.keys_open);
    try shots.shot(&t, "docs/redesign/shots/keys.png");
}

test "snapshot: full screen, the chrome at rest" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "fullscreen", 6);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.3);
    // The picture has the whole screen: the bars have stood back after
    // the quiet, the way the app does it.
    t.key(.f11);
    t.settle(0.2);
    t.advance(3.0);
    t.settle(0.4);
    try std.testing.expect(state.chrome_hidden);
    try std.testing.expectEqual(@as(f32, 0), fullscreen.chromeOpacity(state));
    try shots.shot(&t, "docs/redesign/shots/fullscreen.png");
}

test "snapshot: full screen, dark, with the facts" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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
    state.dark = true;
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.3);
    // The big pixels come from the worker: wait for them before the shot.
    const key = try thumbs.largeKey(gpa, state.large.?.path);
    defer gpa.free(key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(key)) |known| {
            if (known.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    t.key(.f11);
    t.settle(0.2);
    t.advance(3.0);
    t.settle(0.4);
    try std.testing.expect(state.chrome_hidden);
    try std.testing.expectEqual(@as(f32, 0), fullscreen.chromeOpacity(state));
    try shots.shot(&t, "docs/redesign/shots/fullscreen-dark.png");
}

test "snapshot: filled, the picture covers the room" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // A photograph, not a square: filling crops its sides, and that is
    // what the picture should show.
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
    try tests_mod.waitForThumbs(&t, state);
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.3);
    const key = try thumbs.largeKey(gpa, state.large.?.path);
    defer gpa.free(key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(key)) |known| {
            if (known.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    t.typeText("f");
    t.settle(0.8);
    try std.testing.expectEqual(app.ZoomMode.fill, state.zoom_mode);
    const at = state.large_at;
    try std.testing.expect(at.w >= 1280 - 60 or at.h >= 800 - 60);
    try shots.shot(&t, "docs/redesign/shots/lightbox-fill.png");
}

test "snapshot: the look at 1:1 under the pointer" {
    try ensureDir();
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeShotFolder(gpa, "peek", 1);
    defer sample.deinit(gpa);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".zig-cache/shots/peek/a.jpg", .data = jpeg });
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1280, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);

    t.key(.down);
    t.settle(0.1);
    t.typeText(" ");
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
    t.settle(0.3);
    t.frame();
    // Hold the left button on the photograph, away from its middle.
    const at = state.large_at;
    t.moveTo(at.x + at.w * 0.3, at.y + at.h * 0.7);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    // A still press for a moment: that is what asks for the look.
    t.advance(0.3);
    t.settle(1.2);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    try shots.shot(&t, "docs/redesign/shots/peek.png");
}
