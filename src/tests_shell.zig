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
const statusbar = @import("statusbar.zig");
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
    // Twice: the rail's own row, and the breadcrumb's last crumb.
    try std.testing.expect(seen >= 2);
    try std.testing.expect(widest >= 80);
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
    const count = t.findText("1 pictures") orelse return error.TextNotFound;
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
    try std.testing.expect(t.hasText("nowhere"));
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
    try std.testing.expect(t.hasText("1 pictures"));
}
