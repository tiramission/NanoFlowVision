//! The large view's zoom and the wall's prefetch: the wheel that holds the
//! point under the pointer, the modes' trades, a double click's zoom being
//! draggable, a long folder name on one line, and the pictures asked for
//! nearest the window first. Split from tests_details.zig, which was over
//! the 600-line rule.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const model = @import("model.zig");
const thumbs = @import("thumbs.zig");
const tests_mod = @import("tests.zig");

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
    // (To within a point: the pan is derived from the zoom that is drawn,
    // which arrives at the fit asymptotically, and the clamp then pins it
    // to zero once the picture no longer overflows.)
    t.scroll(px, py, -2000);
    t.settle(0.6);
    try std.testing.expect(state.zoom_target == null);
    t.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 0), state.pan_tx, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), state.pan_ty, 1);
}

test "F fills the screen, and trades places with 1:1" {
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
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);

    // `f` from the fit: the picture covers the room, edges cropped.
    t.typeText("f");
    t.settle(0.6);
    try std.testing.expectEqual(app.ZoomMode.fill, state.zoom_mode);
    const covered = state.large_at;
    try std.testing.expect(covered.w >= 900 - 60);
    try std.testing.expect(covered.h >= 800 - 60);
    try std.testing.expect(t.hasText("Fill"));

    // `f` again: 1:1, the other half of the pair. The zoom eases
    // from the fill to the pixels, so give it its frames.
    t.typeText("f");
    t.settle(2.0);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    try std.testing.expect(@abs(state.zoom - 1.0) < 0.01);
    try std.testing.expect(t.hasText("100%"));

    // And `f` once more: back to filling.
    t.typeText("f");
    t.settle(0.6);
    try std.testing.expectEqual(app.ZoomMode.fill, state.zoom_mode);

    // `z` still trades fit with 1:1, from wherever it stands.
    t.typeText("z");
    t.settle(0.6);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    t.typeText("z");
    t.settle(0.6);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    try std.testing.expect(t.hasText("Fit"));

    // A wheel zoom becomes nobody's mode, and says its percentage; the
    // wheel back to the fit returns to the fit.
    t.scroll(450, 400, 120);
    t.settle(0.4);
    try std.testing.expectEqual(app.ZoomMode.free, state.zoom_mode);
    t.scroll(450, 400, -1200);
    t.settle(0.5);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
}

test "a picture zoomed by a double click can be dragged" {
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
    // The big pixels: the picture needs a rectangle to be dragged in.
    const key = try thumbs.largeKey(gpa, state.large.?.path);
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

    // A double click takes it to 1:1. The test picture is 2x2 pixels, so its
    // 1:1 is smaller than the room -- "fill" is the mode that is always
    // bigger than the room, and the one a drag needs.
    t.typeText("f");
    t.settle(1.2);
    t.frame();
    const big = state.large_at;
    try std.testing.expect(big.w >= 900 - 60 and big.h >= 800 - 60);

    // Drag from the middle by a known distance: the picture must follow,
    // and stay where it was let go.
    const cx = big.x + big.w / 2;
    const cy = big.y + big.h / 2;
    t.drag(cx, cy, cx + 60, cy + 40);
    t.settle(0.3);
    t.frame();
    const moved = state.large_at;
    try std.testing.expect(moved.x > big.x + 20 or moved.y > big.y + 10);

    // And a frame later it is still there: nothing zeroes the pan behind
    // the reader's back.
    t.frame();
    t.frame();
    const later = state.large_at;
    try std.testing.expectApproxEqAbs(moved.x, later.x, 1);
    try std.testing.expectApproxEqAbs(moved.y, later.y, 1);
}

test "a long folder name stays on one line, cut in the middle" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    // A folder whose name is longer than the whole command bar.
    const long = "a-folder-name-that-is-far-longer-than-any-command-bar-would-ever-be";
    const dir = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ sample.path, long });
    defer gpa.free(dir);
    std.Io.Dir.createDirAbsolute(std.testing.io, dir, .default_file) catch {};
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    const file = try std.fmt.allocPrint(gpa, "{s}/two.png", .{dir});
    defer gpa.free(file);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = file, .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 900, 600);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    // Into the folder with the long name, so it is the current one: at a
    // narrow width the bar shows only the current folder's crumb. The rail's
    // row is narrow, so the name there is cut -- the state is what moves.
    var found_folder: ?*@import("model.zig").Folder = null;
    for (state.tree.children) |*ch| {
        if (std.mem.eql(u8, ch.name, long)) found_folder = ch;
    }
    const folder = found_folder orelse return error.NoFolder;
    state.open(folder);
    t.settle(0.3);
    try std.testing.expectEqualStrings(long, state.current.?.name);
    t.resize(700, 600);
    t.settle(0.3);

    // The crumb's text is cut through its middle -- "a-folder-…-ever-be" --
    // on one line, inside the 44-point bar. A wrapped crumb would be two
    // lines and push the bar's contents down. (The rail shows the same name
    // cut too, which is why the bar's crumb is found by its place.)
    var cut = false;
    var in_bar = false;
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| {
            if (!std.mem.startsWith(u8, tx.str, "a-folder")) continue;
            try std.testing.expect(n.rect.h <= 22);
            if (std.mem.indexOf(u8, tx.str, "…") != null) cut = true;
            if (n.rect.y < 44) in_bar = true;
        },
        else => {},
    };
    try std.testing.expect(cut);
    try std.testing.expect(in_bar);
}

test "the wall asks for the pictures nearest the window first" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 60);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tests_mod.initTester(&t, gpa, state, 900, 800);
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();

    // Every picture in the prefetch room has been asked for: the room is
    // taller than the window on both sides, so it holds more than what is
    // on screen -- that is what keeps the wall from arriving blank.
    var asked: usize = 0;
    const view_h = 800.0;
    for (state.shown, 0..) |pic, i| {
        const place = state.layout.placements[i];
        const top = place.y - state.grid_offset;
        if (place.y + place.h - state.grid_offset < -3 * view_h) continue;
        if (top > view_h + 10 * view_h) continue;
        asked += 1;
        try std.testing.expect(state.shared.get(pic.path) != null);
    }
    try std.testing.expect(asked > 12);

    // The nearest ones are already decoded, or on their way: the first
    // screenful is not left blank while the far ones are read.
    var ready: usize = 0;
    for (state.shown[0..@min(12, state.shown.len)]) |pic| {
        if (state.shared.get(pic.path)) |known| {
            if (known.thumb != null) ready += 1;
        }
    }
    var tries: usize = 0;
    while (ready < @min(12, state.shown.len) and tries < 400) : (tries += 1) {
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
        t.frame();
        ready = 0;
        for (state.shown[0..@min(12, state.shown.len)]) |pic| {
            if (state.shared.get(pic.path)) |known| {
                if (known.thumb != null) ready += 1;
            }
        }
    }
    try std.testing.expect(ready == @min(12, state.shown.len));
}

test "holding the left button looks at 1:1, and letting go puts it back" {
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
    const key = try thumbs.largeKey(gpa, state.large.?.path);
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
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);

    // Hold the left button on the picture: 1:1, and the point under the
    // pointer stays under it.
    const at = state.large_at;
    const px = at.x + at.w * 0.3;
    const py = at.y + at.h * 0.7;
    t.moveTo(px, py);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    try std.testing.expect(state.peek != null);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expect(state.zoom_target != null);
    // The picture is at 1:1: one of its pixels is one point. (The test
    // picture is 2x2, so 1:1 is smaller than the fit -- the zoom value is
    // what says which mode it is in.)
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), state.zoom, 0.02);

    // Let go: the fit comes back, and the mode with it.
    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();
    try std.testing.expect(state.peek == null);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), state.zoom_target);
}

test "holding the right button fills the room, and letting go puts it back" {
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
    const key = try thumbs.largeKey(gpa, state.large.?.path);
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

    // The right button held: the room is covered.
    const at = state.large_at;
    t.moveTo(at.x + at.w / 2, at.y + at.h / 2);
    t.ctx.input.button = .right;
    t.ctx.secondaryDown();
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.fill, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    const filled = state.large_at;
    try std.testing.expect(filled.w >= 900 - 60 or filled.h >= 800 - 60);

    // Let go: back where it was.
    t.ctx.pointerUp();
    t.ctx.input.button = .right;
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), state.zoom_target);
}

test "the look at 1:1 can be dragged under the held button" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeBigSample(gpa, 2);
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
    const key = try thumbs.largeKey(gpa, state.large.?.path);
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

    // Hold the left button, then move the pointer: the picture must follow
    // it, and the look must survive the movement.
    const at = state.large_at;
    t.moveTo(at.x + at.w / 2, at.y + at.h / 2);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    t.settle(1.2);
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);

    const before = state.pan_tx;
    const cx = at.x + at.w / 2;
    const cy = at.y + at.h / 2;
    t.moveTo(cx + 30, cy + 20);
    t.frame();
    t.moveTo(cx + 60, cy + 40);
    t.frame();
    t.frame();
    try std.testing.expect(state.peek != null);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    // The pan moved (or the clamp at an edge stopped it, which is also a
    // picture that was dragged and stayed where the hand put it).
    try std.testing.expect(state.pan_tx != before or state.pan_ty != 0);

    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
}
