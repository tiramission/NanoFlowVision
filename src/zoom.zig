//! The large view's zoom: four modes (fitted, filling the room, at its
//! own pixels, or wherever the wheel left it), the wheel that anchors on
//! the point under the pointer, and the pan derived from the zoom the
//! frame actually draws -- so the anchor holds on every frame of the
//! easing, not only at its end.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");

/// The easing slot the framework's clock holds the zoom in.
const zoom_anim: u64 = 0x7A00C1A1;

/// The room the picture is shown in, and the two zooms that fit it.
pub const Room = struct {
    w: f32,
    h: f32,
    top: f32,
    img_w: f32,
    img_h: f32,
    /// `min(room / picture)`: the whole picture is visible.
    fit: f32,
    /// `max(room / picture)`: the picture covers the room, cropped.
    cover: f32,
};

/// What the frame draws after a step.
pub const Shown = struct { zoom: f32, pan_x: f32, pan_y: f32 };

/// Reads the mode keys and the wheel, then eases the zoom and derives the
/// pan that holds the anchor under the pointer. Returns what to draw.
pub fn step(s: *app.State, c: *ui.Context, room: Room, wheel: f32, toggle_fit: bool, toggle_fill: bool) Shown {
    if (toggle_fit) toggleFit(s);
    if (toggle_fill) toggleFill(s);
    // The mode says what the zoom is trying to be; "fill" follows the
    // room, so its value is worked out here rather than stored.
    switch (s.zoom_mode) {
        .fit => s.zoom_target = null,
        .fill => s.zoom_target = room.cover,
        .actual => s.zoom_target = 1.0,
        .free => {},
    }

    // The wheel asks for another zoom and says what it wants to keep
    // under the pointer: the picture-space point under it right now, read
    // from the frame the reader is looking at (the eased zoom, not the
    // target). A notch back to the fit hands the size to the window.
    if (wheel != 0) {
        const base = s.zoom;
        const lo = @min(room.fit, 1.0);
        const hi = @max(room.fit, 1.0) * 8.0;
        const next = std.math.clamp(base * std.math.pow(f32, 1.15, wheel / 120), lo, hi);
        if (next <= room.fit + 0.01) {
            s.zoom_mode = .fit;
            s.zoom_target = null;
            s.anchor = null;
        } else {
            s.zoom_mode = .free;
            s.zoom_target = next;
            const bw = room.img_w * base;
            const bh = room.img_h * base;
            const left = (c.size.w - bw) / 2 + s.pan_tx;
            const top = room.top + (room.h - bh) / 2 + s.pan_ty;
            s.anchor = .{
                .x = std.math.clamp((c.input.mouse.x - left) / bw, 0, 1),
                .y = std.math.clamp((c.input.mouse.y - top) / bh, 0, 1),
            };
            s.anchor_mouse = .{ .x = c.input.mouse.x, .y = c.input.mouse.y };
        }
        c.changed = true;
    }

    // Only the zoom eases; the pan is derived from it, so the anchor point
    // sits under the pointer at every step of the way instead of the pan
    // and the zoom easing separately and drifting apart.
    const zoom = c.animate(zoom_anim, 0, s.zoom_target orelse room.fit, 20);
    s.zoom = zoom;
    if (s.anchor) |a| {
        const bw = room.img_w * zoom;
        const bh = room.img_h * zoom;
        s.pan_tx = s.anchor_mouse.x - ((c.size.w - bw) / 2 + a.x * bw);
        s.pan_ty = s.anchor_mouse.y - (room.top + (room.h - bh) / 2 + a.y * bh);
        // A picture that still overflows may not leave the room empty at
        // its edges; one that no longer overflows is put back in the
        // middle.
        const ox = @max(0, (bw - room.w) / 2);
        const oy = @max(0, (bh - room.h) / 2);
        if (ox <= 0) s.pan_tx = 0 else s.pan_tx = std.math.clamp(s.pan_tx, -ox, ox);
        if (oy <= 0) s.pan_ty = 0 else s.pan_ty = std.math.clamp(s.pan_ty, -oy, oy);
    } else {
        s.pan_tx = 0;
        s.pan_ty = 0;
    }
    return .{ .zoom = zoom, .pan_x = s.pan_tx, .pan_y = s.pan_ty };
}

/// Fit and 1:1 change places (`z`, the double click). The mode says which
/// of the two, not the zoom's size against the fit: a small photograph's
/// fit is bigger than 1:1, and the two still trade.
pub fn toggleFit(s: *app.State) void {
    s.zoom_mode = if (s.zoom_mode == .actual) .fit else .actual;
    centre(s);
}

/// Filling the screen and 1:1 change places (`f`): the two ways of
/// looking at a picture's detail against the whole. From any other mode
/// it goes to fill, which is the one that needs saying.
pub fn toggleFill(s: *app.State) void {
    s.zoom_mode = if (s.zoom_mode == .fill) .actual else .fill;
    centre(s);
}

/// The chip's click walks the three named modes: fit, fill, 1:1.
pub fn cycle(s: *app.State) void {
    s.zoom_mode = switch (s.zoom_mode) {
        .fit => .fill,
        .fill => .actual,
        .actual, .free => .fit,
    };
    centre(s);
}

/// The middle of the picture stays put: the anchor goes, and the pan with it.
fn centre(s: *app.State) void {
    s.anchor = null;
    s.pan_tx = 0;
    s.pan_ty = 0;
}

test "the modes trade places as the keys say" {
    const gpa = std.testing.allocator;
    var sample = try @import("tests.zig").makeSample(gpa);
    defer sample.deinit(gpa);
    const s = try app.State.create(gpa, std.testing.io, sample.path);
    defer s.deinit();

    try std.testing.expectEqual(app.ZoomMode.fit, s.zoom_mode);
    toggleFit(s);
    try std.testing.expectEqual(app.ZoomMode.actual, s.zoom_mode);
    toggleFit(s);
    try std.testing.expectEqual(app.ZoomMode.fit, s.zoom_mode);

    // F from the fit goes to fill; then it trades fill with 1:1.
    toggleFill(s);
    try std.testing.expectEqual(app.ZoomMode.fill, s.zoom_mode);
    toggleFill(s);
    try std.testing.expectEqual(app.ZoomMode.actual, s.zoom_mode);
    toggleFill(s);
    try std.testing.expectEqual(app.ZoomMode.fill, s.zoom_mode);

    // The chip cycles fit -> fill -> 1:1 -> fit.
    cycle(s);
    try std.testing.expectEqual(app.ZoomMode.actual, s.zoom_mode);
    cycle(s);
    try std.testing.expectEqual(app.ZoomMode.fit, s.zoom_mode);
    cycle(s);
    try std.testing.expectEqual(app.ZoomMode.fill, s.zoom_mode);
}
