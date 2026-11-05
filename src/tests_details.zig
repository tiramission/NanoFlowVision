//! The details that make the shell feel finished: the search a keystroke
//! away and one click to clear, the keyboard's place in the status bar,
//! the way out of an empty folder, and the rail's own row and edge.
//! Assertions are rectangles and state, not merely "the words exist".

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const i18n = @import("i18n.zig");
const fullscreen = @import("fullscreen.zig");
const tests_mod = @import("tests.zig");

test "the search is a keystroke away, and gives the wall back" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // ⌘F puts the caret in the search box: the next word typed is a
    // query, not a rating and not a key.
    _ = t.shortcut(.{ .key = 'f', .ctrl = true });
    t.settle(0.2);
    t.typeText("pic-2");
    t.settle(0.2);
    try std.testing.expectEqualStrings("pic-2", state.search.text());
    try std.testing.expectEqual(@as(usize, 1), state.shown.len);

    // The xmark in the box gives the wall back in one click.
    t.frame();
    const clear = state.search_clear_at;
    try std.testing.expect(clear.w > 0);
    t.click(clear.x + clear.w / 2, clear.y + clear.h / 2);
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.search.text().len);
    try std.testing.expectEqual(@as(usize, 4), state.shown.len);
}

test "the status bar says where the keyboard stands" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The walk starts on the first tile, and moves from there: the bar
    // keeps count of where the keyboard stands.
    t.key(.down);
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 0), state.select.cursor);
    t.key(.down);
    t.settle(0.1);
    try std.testing.expect(state.select.cursor != null);
    const here = state.select.cursor.? + 1;
    try std.testing.expect(t.hasText(i18n.cursorPosition(t.ctx.alloc(), .en, here)));

    state.lang = .zh;
    t.frame();
    try std.testing.expect(t.hasText(std.fmt.allocPrint(t.ctx.alloc(), "第 {d} 张", .{here}) catch ""));
}

test "an empty folder leaves a way out" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "void");

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("void");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.shown.len);

    // Not just the words: both ways out are drawn, at a size a hand can
    // hit, and the formats hint says what would fill the wall.
    try std.testing.expect(t.hasText("No pictures here"));
    try std.testing.expect(t.containsText("JPG"));
    const open = t.findText("Open folder") orelse return error.TextNotFound;
    const rescan = t.findText("Rescan") orelse return error.TextNotFound;
    try std.testing.expect(open.w > 30 and open.h > 8);
    try std.testing.expect(rescan.w > 30 and rescan.h > 8);
    // The rescan asks for a new listing rather than doing anything else.
    t.click(rescan.x + rescan.w / 2, rescan.y + rescan.h / 2);
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.shown.len);
}

test "the rail names the folder it is rooted at, and its edge is a handle" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Even with no subfolders, the rail says where the reader is: the
    // root's own row, and the word below it.
    try std.testing.expect(t.hasText(state.tree.name));
    const root = t.findText(state.tree.name).?;
    const none = t.findText("No subfolders here").?;
    try std.testing.expect(none.y > root.y);
    try std.testing.expectEqual(@as(f32, 240), state.rail_w);

    // The edge drags: the columns take the width the hand gives them,
    // and a double click puts the width back.
    const edge = state.rail_w - 2;
    t.drag(edge, 300, edge + 60, 300);
    t.settle(0.2);
    try std.testing.expect(state.rail_w > 280);
    t.doubleClick(state.rail_w - 2, 300);
    t.settle(0.2);
    try std.testing.expectEqual(@as(f32, 240), state.rail_w);
}

test "space is the quick look, both ways" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // On the wall, Space opens the cursor's picture. The walk starts
    // on the first tile.
    t.key(.down);
    t.settle(0.1);
    t.typeText(" ");
    t.settle(0.2);
    try std.testing.expect(state.large != null);
    try std.testing.expectEqual(@as(?usize, 0), state.select.cursor);

    // And in the large view, Space is the way back, same as Escape.
    t.typeText(" ");
    t.settle(0.2);
    try std.testing.expect(state.large == null);
    try std.testing.expectEqual(@as(?usize, 0), state.select.cursor);
}

test "Ctrl+O asks the system for a folder" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 1);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The dialog itself opens outside the frame (AGENTS.md); the key's
    // job is to ask for it.
    _ = t.shortcut(.{ .key = 'o', .ctrl = true });
    t.frame();
    try std.testing.expect(state.dialog_pending);
}

test "the keyboard's map is a table, not a wall of text" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album");

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1000, .height = 800 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    _ = t.shortcut(.{ .key = '/', .ctrl = true });
    t.settle(0.4);
    try std.testing.expect(state.keys_open);

    // Four groups, each with its rows, and the key column stands to the
    // left of what the key does -- a table, not one string.
    try std.testing.expect(t.hasText("Everywhere"));
    try std.testing.expect(t.hasText("Grid"));
    try std.testing.expect(t.hasText("Large view"));
    try std.testing.expect(t.hasText("Sidebar"));
    const key = t.findText("Ctrl+O") orelse return error.TextNotFound;
    const what = t.findText("Open a folder") orelse return error.TextNotFound;
    try std.testing.expect(what.x > key.x + key.w);

    // The Chinese map is a table too, and it is its own words.
    state.lang = .zh;
    t.frame();
    t.frame();
    try std.testing.expect(t.hasText("全局"));
    try std.testing.expect(t.hasText("打开目录"));
    try std.testing.expect(!t.hasText("Open a folder"));
}

test "the large view is a dark room, whatever the theme" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 2);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 900, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);
    t.frame();

    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.4);
    try std.testing.expect(state.large != null);

    // A pixel in the room beside the picture: dark in a light interface
    // too. (Premultiplied BGRA.)
    const pixels = try t.render(gpa);
    defer pixels.deinit(gpa);
    const at = (400 * pixels.width + 10) * 4;
    const b = pixels.bytes[at];
    const g = pixels.bytes[at + 1];
    const r = pixels.bytes[at + 2];
    try std.testing.expect(@as(u32, r) + g + b < 160);
}

test "F11 takes the screen, and gives it back in the right order" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1000, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // From the wall: the cursor's picture goes large, then the window.
    t.key(.down);
    t.settle(0.1);
    t.key(.f11);
    t.settle(0.2);
    try std.testing.expect(state.large != null);
    try std.testing.expect(state.fullscreen);

    // F11 again: the window comes back, the picture stays large.
    t.key(.f11);
    t.settle(0.2);
    try std.testing.expect(!state.fullscreen);
    try std.testing.expect(state.large != null);

    // And the Esc order inside full screen: window first, picture second.
    t.key(.f11);
    t.settle(0.2);
    try std.testing.expect(state.fullscreen);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expect(!state.fullscreen);
    try std.testing.expect(state.large != null);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expect(state.large == null);
}

test "an empty folder has nothing to go full screen with" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "void");

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 900, 600);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("void");
    t.settle(0.2);
    t.key(.f11);
    t.settle(0.2);
    try std.testing.expect(state.large == null);
    try std.testing.expect(!state.fullscreen);
}

test "the chrome stands back in full screen, and comes back on a move" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1000, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);

    t.key(.down);
    t.settle(0.1);
    t.key(.f11);
    t.settle(0.3);
    try std.testing.expect(state.fullscreen);
    try std.testing.expect(!state.chrome_hidden);
    try std.testing.expectEqual(@as(f32, 1), fullscreen.chromeOpacity(state));
    try std.testing.expect(t.hasText("1 / 4"));

    // The pointer stays still: no timer, just the clock the view already
    // reads. After the quiet the bars go, and the fit takes the room.
    const before = t.findText("1 / 4").?;
    t.advance(3.0);
    try std.testing.expect(state.chrome_hidden);
    try std.testing.expectEqual(@as(f32, 0), fullscreen.chromeOpacity(state));
    try std.testing.expect(!t.hasText("1 / 4"));
    try std.testing.expect(!fullscreen.chromeLive(state));

    // The picture grew into the space the bars left.
    const after = state.first_picture;
    _ = after;

    // A movement: the bars come back, and the picture gives the room back.
    t.moveTo(30, 30);
    t.settle(0.3);
    try std.testing.expect(!state.chrome_hidden);
    try std.testing.expectEqual(@as(f32, 1), fullscreen.chromeOpacity(state));
    try std.testing.expect(t.hasText("1 / 4"));
    const again = t.findText("1 / 4").?;
    try std.testing.expectEqual(before.y, again.y);

    // A key is a movement too, and a held wheel notch as well.
    t.advance(3.0);
    try std.testing.expect(state.chrome_hidden);
    t.typeText("i");
    t.settle(0.3);
    try std.testing.expect(!state.chrome_hidden);
}

test "the bars never eat a click they are not showing for" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 4);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 1000, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);

    t.key(.down);
    t.settle(0.1);
    t.key(.f11);
    t.settle(0.3);
    t.advance(3.0);
    try std.testing.expect(state.chrome_hidden);

    // A click where the zoom chip used to be goes to the picture, not to
    // a bar that is gone: the click closes the large view.
    const where = t.findText("1 / 4");
    try std.testing.expect(where == null);
    t.click(1000 - 60, 800 - 76 - 40);
    t.settle(0.3);
    try std.testing.expect(state.large == null);
    try std.testing.expect(!state.fullscreen);
}

test "the settings keep the window as it was before full screen" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    // Without a window there is nothing to keep -- and with a full
    // screen standing, the remembered frame is what is written, never
    // the full-screen rectangle.
    try std.testing.expect(fullscreen.frameForSettings(state) == null);
    state.frame_before = .{ .x = 10, .y = 20, .width = 900, .height = 640 };
    state.fullscreen = true;
    const kept = fullscreen.frameForSettings(state).?;
    try std.testing.expectEqual(@as(f64, 900), kept.width);
    try std.testing.expectEqual(@as(f64, 10), kept.x);
}

test "the wheel zooms about the pointer, and keeps that point still" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 2);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 900, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);

    t.key(.down);
    t.settle(0.1);
    t.typeText(" ");
    t.settle(0.2);
    try std.testing.expect(state.large != null);
    // The big pixels, so the picture has a rectangle to hold points in.
    const key = try @import("thumbs.zig").largeKey(gpa, state.large.?.path);
    defer gpa.free(key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(key)) |known| {
            if (known.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    t.settle(0.2);
    t.frame();

    // First, make the picture overflow the room: while it is smaller than
    // the room it stays centred, and there is nothing to hold still.
    const fit_rect = state.large_at;
    t.scroll(fit_rect.x + fit_rect.w / 2, fit_rect.y + fit_rect.h / 2, 1200);
    t.settle(0.6);
    t.frame();
    const big = state.large_at;
    try std.testing.expect(big.w > 900 and big.h > 800);

    // Now the point under the pointer, three tenths across and six
    // tenths down: one notch, and it must not move -- not when the
    // easing arrives, and not on any frame on the way there.
    const px = big.x + big.w * 0.3;
    const py = big.y + big.h * 0.6;
    const fx = 0.3;
    const fy = 0.6;
    t.scroll(px, py, 120);
    var frame: usize = 0;
    while (frame < 40) : (frame += 1) {
        t.frame();
        const now = state.large_at;
        try std.testing.expect(@abs((px - now.x) / now.w - fx) < 0.005);
        try std.testing.expect(@abs((py - now.y) / now.h - fy) < 0.005);
    }
    t.settle(0.6);
    try std.testing.expect(state.zoom_target != null);

    // Two notches in quick succession: the second lands while the first
    // is still easing, and the point must still not move.
    t.scroll(px, py, 120);
    t.advance(0.03);
    t.scroll(px, py, 120);
    t.settle(0.6);
    t.frame();
    const after = state.large_at;
    try std.testing.expect(@abs((px - after.x) / after.w - fx) < 0.005);
    try std.testing.expect(@abs((py - after.y) / after.h - fy) < 0.005);

    // And back to the fit: the picture is the room again, in the middle.
    t.scroll(px, py, -2000);
    t.settle(0.6);
    try std.testing.expect(state.zoom_target == null);
    t.frame();
    try std.testing.expectEqual(@as(f32, 0), state.pan_tx);
    try std.testing.expectEqual(@as(f32, 0), state.pan_ty);
}
