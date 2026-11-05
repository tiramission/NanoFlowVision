//! The details that make the shell feel finished: the search a keystroke
//! away and one click to clear, the keyboard's place in the status bar,
//! the way out of an empty folder, and the rail's own row and edge.
//! Assertions are rectangles and state, not merely "the words exist".

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const i18n = @import("i18n.zig");
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
