//! The look: a button held down shows the picture at 1:1, or fitted to the
//! window, and letting go gives back the frame that was there before.
//! Split from tests_zoom.zig, which was over the 600-line rule.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const model = @import("model.zig");
const thumbs = @import("thumbs.zig");
const tests_mod = @import("tests.zig");

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
    // The press itself is the ask: no delay, the way the right button
    // behaves.
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

test "holding the right button fits the picture to the room, and letting go puts it back" {
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

    // The right button held: the picture is fitted to the room, whatever
    // the wheel had made of it.
    const at = state.large_at;
    t.moveTo(at.x + at.w / 2, at.y + at.h / 2);
    // First take it somewhere that is not the fit, so the look has
    // something to undo.
    t.scroll(at.x + at.w / 2, at.y + at.h / 2, 600);
    t.settle(0.6);
    t.frame();
    const zoomed = state.zoom;
    try std.testing.expect(zoomed > 1.0);

    t.ctx.input.button = .right;
    t.ctx.secondaryDown();
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    // Fitted: the picture is inside the room, not overflowing it.
    const fitted = state.large_at;
    try std.testing.expect(fitted.w <= 900 and fitted.h <= 800);

    // Let go: the wheel's zoom comes back, not a default.
    t.ctx.pointerUp();
    t.ctx.input.button = .right;
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.free, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expectApproxEqAbs(zoomed, state.zoom, 0.05);
}

test "a wheel-zoomed picture still takes a look, and gives back its zoom" {
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

    // Somewhere between the fit and 1:1: the mode the wheel leaves is
    // nobody's named mode, and the look must work from it all the same.
    const at = state.large_at;
    t.scroll(at.x + at.w * 0.4, at.y + at.h * 0.6, 600);
    t.settle(0.6);
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.free, state.zoom_mode);
    const zoomed = state.zoom;
    try std.testing.expect(zoomed > 1.0);

    // Hold the left button still: the look is 1:1, and it comes about the
    // pointer -- not about the middle of the room.
    const px = at.x + at.w * 0.4;
    const py = at.y + at.h * 0.6;
    t.moveTo(px, py);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), state.zoom, 0.02);
    // The point under the pointer is the same point of the picture that
    // was under it: at 1:1 the picture overflows the room, so nothing
    // forces it to the middle and the anchor has to hold exactly.
    const shown = state.large_at;
    try std.testing.expect(shown.w > 900 and shown.h > 800);
    const fx = (px - shown.x) / shown.w;
    const fy = (py - shown.y) / shown.h;
    try std.testing.expectApproxEqAbs(0.4, fx, 0.03);
    try std.testing.expectApproxEqAbs(0.6, fy, 0.03);

    // Let go: the wheel's zoom and its place come back, not the fit.
    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.free, state.zoom_mode);
    t.settle(1.2);
    t.frame();
    try std.testing.expectApproxEqAbs(zoomed, state.zoom, 0.05);
}

test "a still press looks at once, without waiting for a clock" {
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

    // One frame, no waiting: the look is there on the frame the press
    // arrives in. A press held still used to need the clock to keep
    // running, and the window draws no frame while nothing happens -- so
    // it waited for the next mouse movement instead of its own delay.
    const at = state.large_at;
    t.moveTo(at.x + at.w / 2, at.y + at.h / 2);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    try std.testing.expect(state.peek != null);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    // And it does not ask for frames it does not need.
    try std.testing.expect(!t.ctx.animating or state.zoom_target != null);
}



test "the look at 1:1 can be dragged while the button is held" {
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

    // The fit, so the look has a size to change to and a room to move in.
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    const before = state.large_at;

    // Press on the photograph and hold: it goes to 1:1 about the pointer.
    const cx = before.x + before.w / 2;
    const cy = before.y + before.h / 2;
    t.moveTo(cx, cy);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    t.settle(1.2);
    t.frame();
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    try std.testing.expect(state.peek != null);

    // Now move, with the button still down. The look must survive it and
    // the picture must follow the hand: at 1:1 it is bigger than the room,
    // so there is something to move.
    const at_1to1 = state.large_at;
    t.moveTo(cx + 40, cy + 30);
    t.frame();
    t.moveTo(cx + 80, cy + 60);
    t.frame();
    try std.testing.expect(state.peek != null);
    try std.testing.expectEqual(app.ZoomMode.actual, state.zoom_mode);
    try std.testing.expect(state.drag_started);
    const moved = state.large_at;
    try std.testing.expect(moved.x > at_1to1.x + 20 or moved.y > at_1to1.y + 10);

    // Still down a frame later: nothing takes it back.
    t.frame();
    t.frame();
    const later = state.large_at;
    try std.testing.expectApproxEqAbs(moved.x, later.x, 1);
    try std.testing.expectApproxEqAbs(moved.y, later.y, 1);

    // Let go: the frame that was there before the press comes back -- the
    // fit, and where it was.
    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();
    try std.testing.expect(state.peek == null);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
}
