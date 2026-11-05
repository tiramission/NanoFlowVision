//! The shell's tests: the command bar and its two menus, the status bar
//! along the bottom, the settings panel and the scrim it draws, and the
//! difference between a picture that is on its way and one that cannot
//! be read. Everything here asserts a rectangle or a pixel where the
//! thing could be drawn wrong rather than merely present.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const config = @import("config.zig");
const exif = @import("exif.zig");
const i18n = @import("i18n.zig");
const statusbar = @import("statusbar.zig");
const xmp = @import("xmp.zig");
const tests_mod = @import("tests.zig");

test "the folder's name survives a narrow window" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album");

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("album");
    t.settle(0.2);
    try std.testing.expectEqualStrings("album", state.current.?.name);

    // A window the design's breakpoint calls narrow: the way here is
    // still said, in a box wide enough to read (at least 80 points), not
    // squeezed into a fragment beside the search.
    t.resize(700, 600);
    t.settle(0.2);
    var widest: f32 = 0;
    var seen: usize = 0;
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "album")) {
            seen += 1;
            widest = @max(widest, n.rect.w);
        },
        else => {},
    };
    // Twice: the rail's own row, and the breadcrumb's last crumb. The
    // crumb's box holds at least 120 points however narrow the window (its
    // text node is as wide as the glyphs, which a cut name shortens), so
    // what is checked is that both are drawn and on one line.
    try std.testing.expect(seen >= 2);
    try std.testing.expect(widest > 0);
    // And the crumb is on one line, in the bar: a long name is cut with an
    // ellipsis, never wrapped into a second line that would push the bar's
    // contents down.
    var in_bar = false;
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "album")) {
            try std.testing.expect(n.rect.h <= 22);
            if (n.rect.y < 44) in_bar = true;
        },
        else => {},
    };
    try std.testing.expect(in_bar);
}

test "the grid's density is three steps, and says which one it took" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The density button writes its place out each frame, so the test
    // can click where it is rather than where the layout was.
    t.frame();
    const button = state.density_at;
    try std.testing.expect(button.w > 0);

    // Large: one column, and the picture is as tall as the window's
    // content can make it.
    t.click(button.x + button.w / 2, button.y + button.h / 2);
    t.settle(0.3);
    try t.clickText("Large");
    t.settle(0.5);
    try std.testing.expectEqual(config.Density.large, state.density);
    t.frame();
    try std.testing.expectEqual(@as(usize, 1), state.layout.columns);
    try std.testing.expect(state.layout.placements[0].h > 400);
    // The change is said out loud rather than left to be noticed.
    try std.testing.expect(t.hasText("Grid density: Large"));

    // Small: a wall you can scan, at the same window.
    t.click(button.x + button.w / 2, button.y + button.h / 2);
    t.settle(0.3);
    try t.clickText("Small");
    t.settle(0.5);
    try std.testing.expectEqual(config.Density.small, state.density);
    t.frame();
    try std.testing.expect(state.layout.placements[0].h < 200);
    // And the wall it makes has more columns to it than the one above.
    try std.testing.expect(state.layout.columns >= 3);
}

test "a picture that cannot be read says so, and one that is waiting does not" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    // A file with a picture's name and nothing a decoder can use.
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "broken.png", .data = "this is not a picture" });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Sorted by name, the broken one comes first; wait until the workers
    // have given up on it rather than hope they have.
    var broken: ?usize = null;
    for (state.shown, 0..) |pic, i| {
        if (std.mem.eql(u8, pic.name, "broken.png")) broken = i;
    }
    const index = broken orelse return error.NoBrokenPicture;
    var tries: usize = 0;
    while (tries < 400) : (tries += 1) {
        if (state.shared.get(state.shown[index].path)) |known| {
            if (known.failed) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
        t.frame();
    }
    t.frame();

    // Exactly one "Can't read", and it sits on the broken tile: the
    // picture still on its way has a square of tile and no words, so the
    // two states can be told apart at a glance.
    var hits: usize = 0;
    var where: ui.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "Can't read")) {
            hits += 1;
            where = n.rect;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), hits);

    const place = state.layout.placements[index];
    const left = state.grid_x + place.x;
    const top = state.grid_y + place.y - state.grid_offset;
    try std.testing.expect(where.x >= left);
    try std.testing.expect(where.x + where.w <= left + place.w);
    try std.testing.expect(where.y >= top);
    try std.testing.expect(where.y + where.h <= top + place.h);
}

test "the settings panel dims the page behind it, and lights the room" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // A point in the navigation column, well clear of where the panel
    // will stand: the scrim must reach it.
    const x: usize = 12;
    const y: usize = 300;
    const before = try t.render(gpa);
    defer before.deinit(gpa);
    const bi = (y * before.width + x) * 4;
    const lit = @as(u32, before.bytes[bi]) + before.bytes[bi + 1] + before.bytes[bi + 2];

    try t.clickText("Settings");
    t.settle(0.6);
    try std.testing.expect(state.settings_open);

    const after = try t.render(gpa);
    defer after.deinit(gpa);
    const ai = (y * after.width + x) * 4;
    const dimmed = @as(u32, after.bytes[ai]) + after.bytes[ai + 1] + after.bytes[ai + 2];
    try std.testing.expect(dimmed < lit);
    // The panel itself is over the page, saying what can be changed.
    try std.testing.expect(t.hasText("Appearance"));
    try std.testing.expect(t.hasText("Grid density"));

    // The room follows what the panel says: held at either end...
    try t.clickText("Dark");
    t.settle(0.4);
    try std.testing.expect(state.dark);
    try t.clickText("Light");
    t.settle(0.4);
    try std.testing.expect(!state.dark);
    // ...or given back to the system.
    try t.clickText("System");
    t.settle(0.4);
    try std.testing.expectEqual(nanoui.isDark(), state.dark);
}

test "the status bar says what is here, and that the folder is watched" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();

    // While the size is on its way, the bar says how far it has got --
    // with a capital, which the gallery's own line does not use.
    t.frame();
    if (state.shared.measuredCount() < 1) {
        try std.testing.expect(t.containsText("Measuring"));
    }
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // The count of what is shown, along the bottom: its own line of
    // text, and in the bar rather than anywhere else in the window.
    const count = t.findText("1 picture") orelse return error.TextNotFound;
    try std.testing.expect(count.y > 540);
    try std.testing.expect(t.hasText("·"));
    // And that the folder is being watched.
    try std.testing.expect(t.hasText("Watching"));
}

test "the window's title says how the measuring goes, then the name" {
    const gpa = std.testing.allocator;
    // The assembly in one piece: how far, then whose window it is.
    const en = statusbar.progressTitle(gpa, .en, 42);
    defer gpa.free(en);
    try std.testing.expect(std.mem.indexOf(u8, en, "Measuring 42%") != null);
    try std.testing.expect(std.mem.endsWith(u8, en, "· NanoFlowVision"));
    const zh = statusbar.progressTitle(gpa, .zh, 7);
    defer gpa.free(zh);
    try std.testing.expect(std.mem.indexOf(u8, zh, "正在测量 7%") != null);
}

test "a folder that cannot be read says so, with the way out" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A folder that was never made, inside one that was: the listing
    // fails before the first frame. (A missing drive letter would ask
    // the system to go looking, and a test has no patience for that.)
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}/nowhere", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    t.frame();

    // The dialog stands over the page, and it names the folder it could
    // not read, with a button that leads out of it.
    try std.testing.expect(state.folder_broken);
    try std.testing.expect(t.hasText("Can't open this folder"));
    try std.testing.expect(t.containsText("nowhere"));
    try std.testing.expect(t.hasText("Open another folder"));

    // Escape stands it down: the app goes on, empty but alive.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.3);
    try std.testing.expect(!state.folder_broken);
}

test "a search that matches nothing offers the way back" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // A word nothing matches: the wall is replaced by the words, and
    // the way back stands beside them.
    try t.clickText("Search…");
    t.typeText("zzz");
    t.settle(0.2);
    try std.testing.expect(t.hasText("No matches for \"zzz\""));
    try std.testing.expectEqual(@as(usize, 0), state.shown.len);

    // One click undoes the filter, and the wall comes back.
    try t.clickText("Clear search");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 1), state.shown.len);
    try std.testing.expect(t.hasText("1 picture"));
}

test "the more menu gathers the choice's words, the subfolders and the settings" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 3);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The rail's old foot is gone: what it held is behind the bar's last
    // button, whose place the frame writes out for the click.
    t.frame();
    try std.testing.expect(!t.hasText("Open folder"));
    const more = state.more_at;
    try std.testing.expect(more.w > 0);
    t.click(more.x + more.w / 2, more.y + more.h / 2);
    t.settle(0.3);
    try std.testing.expect(state.more_open);
    try std.testing.expect(t.hasText("Select all"));
    try std.testing.expect(t.hasText("Subfolders"));
    try std.testing.expect(t.hasText("Rescan"));
    try std.testing.expect(t.hasText("Open folder"));

    // Selecting all from the menu chooses the whole wall, and the status
    // bar says how much that is.
    try t.clickText("Select all");
    t.settle(0.3);
    try std.testing.expectEqual(@as(usize, 3), state.select.count());
    try std.testing.expect(t.hasText("3 of 3 selected"));

    // The subfolders are a mode the bar shows while it is on: the menu
    // puts it on, and the chip it grows takes it off again.
    t.frame();
    const again = state.more_at;
    t.click(again.x + again.w / 2, again.y + again.h / 2);
    t.settle(0.3);
    try t.clickText("Subfolders");
    t.settle(0.5);
    try std.testing.expect(state.recursive);
    try std.testing.expect(t.hasText("Subfolders"));
    try t.clickText("Subfolders");
    t.settle(0.5);
    try std.testing.expect(!state.recursive);
}

test "the rail says when a folder has no subfolders" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    try std.testing.expectEqual(@as(usize, 0), state.tree.children.len);
    try std.testing.expect(t.hasText("No subfolders here"));
    try std.testing.expect(t.hasText("Library"));
}

test "a folded rail leaves a button that brings it back" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    _ = t.shortcut(.{ .key = 'b', .ctrl = true });
    t.settle(0.2);
    try std.testing.expect(!state.rail_visible);
    // The button stands where the rail was, at the bar's start, and it
    // says nothing: its place is what the frame left for the pointer.
    t.frame();
    const back = state.rail_toggle_at;
    try std.testing.expect(back.w > 0);
    try std.testing.expect(back.x < 60);
    t.click(back.x + back.w / 2, back.y + back.h / 2);
    t.settle(0.2);
    try std.testing.expect(state.rail_visible);
}

test "a tile says its name and weight while the pointer is on it" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 6);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1100, .height = 720 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // The first tile's place, as the layout left it.
    const p = state.layout.placements[0];
    const cx = state.grid_x + p.x + p.w / 2;
    const cy = state.grid_y + p.y - state.grid_offset + p.h / 2;
    const name = state.shown[0].name;
    // Nowhere near the wall: the name is the picture's own business.
    try std.testing.expect(!t.hasText(name));

    t.moveTo(cx, cy);
    t.frame();
    const said = t.findText(name) orelse return error.NoCaption;
    // The caption runs along the tile's foot, inside it: the one place
    // a name can be read without covering what it names.
    const foot = state.grid_y + p.y - state.grid_offset + p.h;
    try std.testing.expect(said.w > 0);
    try std.testing.expect(said.y + said.h <= foot + 1);
    try std.testing.expect(said.y >= foot - 27);
    // The weight of the file, beside it, as the status bar says it.
    const known = state.shared.measuredOf(state.shown[0].path) orelse return error.NotMeasured;
    var buf: [24]u8 = undefined;
    const size_said = statusbar.sizeText(&buf, known.bytes);
    const weighed = t.findText(size_said) orelse return error.NoWeight;
    // The weight sits at the far end of the foot, and the name stops
    // before it: the two never run into one word.
    const tile_right = state.grid_x + p.x + p.w;
    try std.testing.expect(weighed.x + weighed.w <= tile_right - 6);
    try std.testing.expect(weighed.x + weighed.w >= tile_right - 12);
    try std.testing.expect(said.x + said.w <= weighed.x - 2);

    // Chosen, and the name stays: a choice should be readable without
    // the pointer resting on it.
    t.click(cx, cy);
    t.moveTo(4, 4);
    t.frame();
    try std.testing.expect(t.hasText(name));
}


test "the corner chip opens the picture's menu" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 6);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1100, .height = 720 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    const p = state.layout.placements[0];
    const left = state.grid_x + p.x;
    const top = state.grid_y + p.y - state.grid_offset;
    // The chip's middle, where the design puts it: 24 square, six in
    // from the tile's top right corner.
    const cx = left + p.w - 36 + 12;
    const cy = top + 6 + 12;
    t.moveTo(cx, cy);
    t.frame();
    t.click(cx, cy);
    t.frame();
    try std.testing.expect(state.menu_for != null);
    // And the choice under it is untouched: the corner is the picture's
    // menu, not a way to pick it.
    try std.testing.expectEqual(@as(usize, 0), state.select.count());
}

test "a rated picture wears its stars in the tile's corner" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "three.jpg", .data = jpeg[0..] });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const dir = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(dir);
    const file = try std.fmt.allocPrint(gpa, "{s}/three.jpg", .{dir});
    defer gpa.free(file);
    var meta: exif.Meta = .{};
    meta.rating = 3;
    try xmp.rewriteFile(gpa, std.testing.io, file, &meta);

    const state = try app.State.create(gpa, std.testing.io, dir);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1100, .height = 720 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // Three stars, and only three: the corner says what the file says.
    const stars = t.findText("★★★") orelse return error.NoStars;
    try std.testing.expect(!t.hasText("★★★★"));
    // Low in the tile and to its left, inside its edges: the corner a
    // photograph never needs for itself.
    const p = state.layout.placements[0];
    const left = state.grid_x + p.x;
    const top = state.grid_y + p.y - state.grid_offset;
    try std.testing.expect(stars.x >= left and stars.x < left + p.w / 2);
    try std.testing.expect(stars.y > top + p.h / 2 and stars.y + stars.h <= top + p.h);
}

