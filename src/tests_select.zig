//! The choice's tests: what a click, a key and the hand's box make of
//! the grid, and what the bulk's commands do to the files themselves.
//! Everything here asserts a state a reader could see -- a count in the
//! status bar, a file on the disk, a box still up -- not merely that the
//! code took a branch.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const ops = @import("ops.zig");
const menu_mod = @import("menu.zig");
const xmp = @import("xmp.zig");
const tests_mod = @import("tests.zig");

/// Where the middle of tile `i` stands on the screen right now.
fn tileCenter(s: *app.State, i: usize) ui.Point {
    const p = s.layout.placements[i];
    return .{
        .x = s.grid_x + p.x + p.w / 2,
        .y = s.grid_y + p.y - s.grid_offset + p.h / 2,
    };
}

test "a click chooses, the adding key adds, escape lets go" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // A plain click: one chosen, and the status bar says so.
    const first = tileCenter(state, 1);
    t.click(first.x, first.y);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 1), state.select.count());
    try std.testing.expect(t.hasText("1 of 12 selected"));

    // The adding key joins one more, and takes it back off. A click with
    // Control is a context-menu press now (nanoui v0.9 reads it so), so
    // the adding key is held with `setMods`, not left to the click.
    t.setMods(.{ .ctrl = true });
    const third = tileCenter(state, 3);
    t.click(third.x, third.y);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 2), state.select.count());
    try std.testing.expect(t.hasText("2 of 12 selected"));
    t.click(third.x, third.y);
    t.settle(0.1);
    t.setMods(.{});
    try std.testing.expectEqual(@as(usize, 1), state.select.count());
    // Everything at once, and the escape that lets all of it go.
    _ = t.shortcut(.{ .key = 'a', .ctrl = true });
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 12), state.select.count());
    try std.testing.expect(t.hasText("12 of 12 selected"));
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 0), state.select.count());
    try std.testing.expect(t.hasText("12 pictures"));
}

test "the shift-click grows the choice from the anchor, either way" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    const a = tileCenter(state, 1);
    t.click(a.x, a.y);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 1), state.select.count());
    t.ctx.input.shift = true;
    const b = tileCenter(state, 4);
    t.click(b.x, b.y);
    t.ctx.input.shift = false;
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 4), state.select.count());
    try std.testing.expect(t.hasText("4 of 12 selected"));

    // Back the other way: the anchor holds where the plain click was.
    const c = tileCenter(state, 0);
    t.ctx.input.shift = true;
    t.click(c.x, c.y);
    t.ctx.input.shift = false;
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 2), state.select.count());
    try std.testing.expect(state.select.has(state.shown[0].path));
    try std.testing.expect(state.select.has(state.shown[1].path));
    try std.testing.expect(!state.select.has(state.shown[2].path));
}

test "the box the hand draws gathers what it holds" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // From the ground before the first tile, across the first two: the
    // box holds what it touches, and the count says how many.
    const p0 = state.layout.placements[0];
    const p1 = state.layout.placements[1];
    const x0 = state.grid_x + p0.x - 6;
    const y0 = state.grid_y + p0.y - state.grid_offset - 6;
    const x1 = state.grid_x + p1.x + p1.w / 2;
    const y1 = state.grid_y + p1.y - state.grid_offset + p1.h / 2;
    t.drag(x0, y0, x1, y1);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 2), state.select.count());
    try std.testing.expect(state.select.has(state.shown[0].path));
    try std.testing.expect(state.select.has(state.shown[1].path));

    // The ground again: a click on nothing, and the choice is gone.
    t.click(x0, y0);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 0), state.select.count());
}

test "one picture goes to the bin on a key; a handful asks first" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // One chosen, the key: gone, and said so.
    const first = tileCenter(state, 0);
    t.click(first.x, first.y);
    t.key(.delete);
    t.settle(0.3);
    try std.testing.expect(state.current.?.pictures.len == 11);
    try std.testing.expect(t.hasText("Moved to Recycle Bin"));

    // A handful: the word comes before the deed, and Cancel keeps them.
    _ = t.shortcut(.{ .key = 'a', .ctrl = true });
    t.settle(0.1);
    t.key(.delete);
    t.settle(0.3);
    try std.testing.expect(t.hasText("Delete 11 pictures?"));
    try std.testing.expect(state.confirming_trash.items.len == 11);
    try t.clickText("Cancel");
    t.settle(0.2);
    try std.testing.expect(state.confirming_trash.items.len == 0);
    try std.testing.expect(state.current.?.pictures.len == 11);

    // And the same dialog, confirmed: the bin takes them all.
    t.key(.delete);
    t.settle(0.2);
    try t.clickText("Move to Recycle Bin");
    t.settle(0.4);
    try std.testing.expect(state.current.?.pictures.len == 0);
}

test "the number keys rate the choice, into the files" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two photographs the decoders can read, with exif to overwrite.
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "a.jpg", .data = jpeg[0..] });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b.jpg", .data = jpeg[0..] });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Both chosen, four typed once: both files carry it.
    const first = tileCenter(state, 0);
    t.click(first.x, first.y);
    t.ctx.input.ctrl = true;
    const second = tileCenter(state, 1);
    t.click(second.x, second.y);
    t.ctx.input.ctrl = false;
    t.typeText("4");
    t.settle(0.3);

    for (state.current.?.pictures) |*pic| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic.path, gpa, .limited(1 << 20));
        defer gpa.free(bytes);
        try std.testing.expectEqual(@as(i8, 4), exif.parse(bytes).?.rating);
    }
}

test "a name that is taken keeps the box up, and a rename follows the choice" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 2);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The chosen picture's F2: the box, with the name in the field.
    const first = tileCenter(state, 0);
    t.click(first.x, first.y);
    t.key(.f2);
    t.settle(0.2);
    try std.testing.expect(state.rename_open);

    // A name another file has: the box stays, and says so. The field is
    // given the name, and the box told to take it: the field draws its
    // text as leaves of its own, so a click by name would be guessing.
    state.rename_field.set("pic-1.png");
    menu_mod.tryRename(state);
    t.settle(0.2);
    try std.testing.expect(state.rename_open);
    try std.testing.expect(state.rename_error);
    try std.testing.expect(t.hasText("That name is taken"));

    // A name that is free: the file follows, and the choice with it.
    state.rename_field.set("renamed.png");
    menu_mod.tryRename(state);
    t.settle(0.3);
    try std.testing.expect(!state.rename_open);
    const old = try std.fmt.allocPrint(gpa, "{s}/pic-0.png", .{sample.path});
    defer gpa.free(old);
    try std.testing.expect(!ops.exists(std.testing.io, old));
    try std.testing.expect(state.select.has(state.current.?.pictures[0].path));
}

test "the keyboard walks the wall: along the column and across it" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Down: the walk starts at the first picture, then moves along its
    // column -- the tile below, not the one beside it.
    t.key(.down);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 0), state.select.cursor.?);
    t.key(.down);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 2), state.select.cursor.?);
    const col_x = state.layout.placements[2].x;
    t.key(.down);
    t.settle(0.1);
    try std.testing.expectEqual(col_x, state.layout.placements[state.select.cursor.?].x);

    // Right: another column, and its x is the one that moves.
    t.key(.right);
    t.settle(0.1);
    try std.testing.expect(state.layout.placements[state.select.cursor.?].x > col_x);

    // Home and End: the first and the last of the wall.
    t.key(.home);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 0), state.select.cursor.?);
    t.key(.end);
    t.settle(0.1);
    try std.testing.expectEqual(@as(usize, 11), state.select.cursor.?);
}

test "the star filter keeps the rated and says how to let go" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Three photographs with their stars already in the files.
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
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Four stars and up: one stands, and the chip says the filter's name.
    t.frame();
    const btn = state.filter_at;
    t.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
    t.settle(0.2);
    try t.clickText("★★★★");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 1), state.shown.len);
    try std.testing.expect(t.hasText("1 of 3 pictures"));

    // Two stars: one more comes back.
    t.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
    t.settle(0.2);
    try t.clickText("★★");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 2), state.shown.len);

    // The top step: one picture carries five stars, and the chip says
    // what the wall keeps.
    t.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
    t.settle(0.2);
    try t.clickText("★★★★★");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 1), state.shown.len);

    // And the way back, from the same menu.
    t.click(btn.x + btn.w / 2, btn.y + btn.h / 2);
    t.settle(0.2);
    try t.clickText("Clear filter");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 3), state.shown.len);
}

test "the way back walks the folders just left" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album");
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/two.png", .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Into the album, and back with the key: the root again.
    try t.clickText("album");
    t.settle(0.2);
    try std.testing.expectEqualStrings("album", state.current.?.name);
    _ = t.shortcut(.{ .key = ui.Shortcut.left, .alt = true });
    t.settle(0.2);
    try std.testing.expectEqualStrings(sample.path, state.tree.path);
    // And forward again, the same way.
    _ = t.shortcut(.{ .key = ui.Shortcut.right, .alt = true });
    t.settle(0.2);
    try std.testing.expectEqualStrings("album", state.current.?.name);
}

test "the keyboard's map stands over the page, and goes" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    _ = t.shortcut(.{ .key = '/', .ctrl = true });
    t.settle(0.2);
    try std.testing.expect(state.keys_open);
    try std.testing.expect(t.hasText("Keys"));
    try std.testing.expect(t.containsText("Ctrl+O"));
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expect(!state.keys_open);
}
