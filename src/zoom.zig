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
///
/// `peek` is a button held down for a look: the left one at 1:1 about the
/// pointer, the right one fitting the picture to the room. Everything the
/// view was in before -- mode, target, anchor, pan -- is kept and put back
/// when the button is let go.
pub fn step(s: *app.State, c: *ui.Context, room: Room, wheel: f32, toggle_fit: bool, toggle_fill: bool, peek: ?app.ZoomMode, drag: ?ui.Point) Shown {
    if (toggle_fit) toggleFit(s);
    if (toggle_fill) toggleFill(s);

    // A held button, and the moment it is let go.
    if (peek) |want| {
        if (s.peek == null) {
            // The frame the reader is looking at now, whole: the look has
            // to give this back, not a fit, or a picture the wheel had
            // zoomed and panned would jump home on release.
            s.peek = .{
                .mode = want,
                .before = s.zoom_mode,
                .zoom = s.zoom,
                .zoom_target = s.zoom_target,
                .anchor = s.anchor,
                .anchor_mouse = s.anchor_mouse,
                .pan_x = s.pan_tx,
                .pan_y = s.pan_ty,
            };
            s.zoom_mode = want;
            if (want == .actual) {
                // At 1:1 the point under the pointer stays under it, the
                // way the wheel would put it there.
                anchorAt(s, c, room);
            } else {
                centre(s, c, room);
            }
        }
    } else if (s.peek != null) {
        const was = s.peek.?;
        s.peek = null;
        s.zoom_mode = was.before;
        s.zoom = was.zoom;
        s.zoom_target = was.zoom_target;
        s.anchor = was.anchor;
        s.anchor_mouse = was.anchor_mouse;
        s.pan_tx = was.pan_x;
        s.pan_ty = was.pan_y;
    }

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
    // With an anchor, the pan is derived from it -- that is what keeps the
    // point under the pointer. Without one, the picture is where the reader
    // dragged it, and the pan stays as it is: a picture at 1:1 is bigger than
    // the room, so it is draggable, and zeroing the pan here every frame is
    // what made a double click's zoom refuse to be dragged.
    //
    // A drag moves the anchor's mouse point rather than the pan: the picture
    // point that was under the pointer is still meant to be under the
    // pointer, and the pointer has moved -- so the derivation above puts the
    // picture under the hand. Writing the pan instead would fight it, and
    // the anchor would win.
    if (drag) |d| {
        if (s.anchor == null) {
            s.pan_tx += d.x;
            s.pan_ty += d.y;
        } else {
            s.anchor_mouse.x += d.x;
            s.anchor_mouse.y += d.y;
        }
    }
    if (s.anchor) |a| {
        const bw = room.img_w * zoom;
        const bh = room.img_h * zoom;
        s.pan_tx = s.anchor_mouse.x - ((c.size.w - bw) / 2 + a.x * bw);
        s.pan_ty = s.anchor_mouse.y - (room.top + (room.h - bh) / 2 + a.y * bh);
    }
    // A picture that still overflows may not leave the room empty at its
    // edges; one that no longer overflows is put back in the middle.
    {
        const bw = room.img_w * zoom;
        const bh = room.img_h * zoom;
        const ox = @max(0, (bw - room.w) / 2);
        const oy = @max(0, (bh - room.h) / 2);
        if (ox <= 0) s.pan_tx = 0 else s.pan_tx = std.math.clamp(s.pan_tx, -ox, ox);
        if (oy <= 0) s.pan_ty = 0 else s.pan_ty = std.math.clamp(s.pan_ty, -oy, oy);
    }
    // The anchor and the pan have to agree after the clamp, or a drag held
    // against an edge would keep asking for more than the edge allows and
    // the picture would shudder on release.
    if (s.anchor) |a| {
        const bw = room.img_w * zoom;
        const bh = room.img_h * zoom;
        s.anchor_mouse.x = (c.size.w - bw) / 2 + a.x * bw + s.pan_tx;
        s.anchor_mouse.y = room.top + (room.h - bh) / 2 + a.y * bh + s.pan_ty;
    }
    return .{ .zoom = zoom, .pan_x = s.pan_tx, .pan_y = s.pan_ty };
}

/// Fit and 1:1 change places (`z`, the double click). The mode says which
/// of the two, not the zoom's size against the fit: a small photograph's
/// fit is bigger than 1:1, and the two still trade.
pub fn toggleFit(s: *app.State) void {
    s.zoom_mode = if (s.zoom_mode == .actual) .fit else .actual;
    // A mode change centres the picture; the frame that follows derives
    // the pan from the anchor, and an anchor of the middle is the middle.
    s.anchor = .{ .x = 0.5, .y = 0.5 };
}

/// Filling the screen and 1:1 change places (`f`): the two ways of
/// looking at a picture's detail against the whole. From any other mode
/// it goes to fill, which is the one that needs saying.
pub fn toggleFill(s: *app.State) void {
    s.zoom_mode = if (s.zoom_mode == .fill) .actual else .fill;
    s.anchor = .{ .x = 0.5, .y = 0.5 };
}

/// The chip's click walks the three named modes: fit, fill, 1:1.
pub fn cycle(s: *app.State) void {
    s.zoom_mode = switch (s.zoom_mode) {
        .fit => .fill,
        .fill => .actual,
        .actual, .free => .fit,
    };
    s.anchor = .{ .x = 0.5, .y = 0.5 };
}

/// A mode change puts the middle of the picture in the middle of the room.
/// It is an anchor like any other, so a later wheel or drag starts from
/// here instead of from nothing -- and the anchor's mouse point has to be
/// the room's middle too, or the pan derived from it would centre the
/// picture on wherever the pointer happened to be.
fn centre(s: *app.State, c: *ui.Context, room: Room) void {
    s.anchor = .{ .x = 0.5, .y = 0.5 };
    s.anchor_mouse = .{ .x = c.size.w / 2, .y = room.top + room.h / 2 };
    s.pan_tx = 0;
    s.pan_ty = 0;
}

/// The reader took hold of the picture and moved it: the pan is now the
/// reader's, not the anchor's.
pub fn dragged(s: *app.State) void {
    s.anchor = null;
}

/// The anchor at the pointer, from the frame as it is drawn now.
fn anchorAt(s: *app.State, c: *ui.Context, room: Room) void {
    const bw = room.img_w * s.zoom;
    const bh = room.img_h * s.zoom;
    const left = (c.size.w - bw) / 2 + s.pan_tx;
    const top = room.top + (room.h - bh) / 2 + s.pan_ty;
    if (bw <= 0 or bh <= 0) return;
    s.anchor = .{
        .x = std.math.clamp((c.input.mouse.x - left) / bw, 0, 1),
        .y = std.math.clamp((c.input.mouse.y - top) / bh, 0, 1),
    };
    s.anchor_mouse = .{ .x = c.input.mouse.x, .y = c.input.mouse.y };
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
