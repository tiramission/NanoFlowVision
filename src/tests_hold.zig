//! The look's settings: what the reader has said the left button's hold is
//! for, and what that changes. Split from tests_peek.zig, which was over
//! the 600-line rule.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const model = @import("model.zig");
const thumbs = @import("thumbs.zig");
const tests_mod = @import("tests.zig");
const config = @import("config.zig");

test "the hold setting decides whether the left button looks or only drags" {
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

    const at = state.large_at;
    const cx = at.x + at.w / 2;
    const cy = at.y + at.h / 2;

    // With the default, a held left button looks.
    try std.testing.expectEqual(config.Hold.look, state.hold);
    t.moveTo(cx, cy);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    try std.testing.expect(state.peek != null);
    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();
    t.settle(0.3);

    // Said to be the drag's alone, it does nothing: the size stays.
    state.hold = .drag;
    const size_before = state.zoom;
    t.moveTo(cx, cy);
    t.ctx.input.button = .left;
    t.ctx.pointerDown();
    t.frame();
    try std.testing.expect(state.peek == null);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    try std.testing.expectApproxEqAbs(size_before, state.zoom, 0.01);
    t.ctx.pointerUp();
    t.ctx.input.button = .left;
    t.frame();

    // The right button still looks, whatever the left one is for.
    t.ctx.input.button = .right;
    t.ctx.secondaryDown();
    t.frame();
    try std.testing.expect(state.peek != null);
    try std.testing.expectEqual(app.ZoomMode.fit, state.zoom_mode);
    t.ctx.pointerUp();
    t.ctx.input.button = .right;
    t.frame();
}
