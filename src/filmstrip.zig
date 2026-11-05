//! The strip of neighbours along the bottom of the large view: the
//! pictures around the one shown, small and at their own proportions,
//! the shown one ringed. A click goes there; the wheel over the strip
//! steps along the gallery, which the large view gives it instead of
//! the zoom.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const theme = @import("theme.zig");

/// How many neighbours the strip shows at most -- the shown one as close
/// to the middle as the gallery's ends allow.
pub const visible: usize = 15;
/// How tall a strip thumbnail is, and the strip that holds them.
pub const thumb_h: f32 = 48;
pub const strip_h: f32 = 76;
/// The narrowest and widest a cell may be, whatever the picture's shape:
/// a panorama gets a wide cell, a portrait a tall one, but neither takes
/// the strip over.
const cell_min: f32 = 44;
const cell_max: f32 = 96;
/// The room between cells.
const cell_gap: f32 = 4;

/// Draws the strip for the picture at `current` in the shown list, and
/// hands back the index the reader clicked, if any.
pub fn view(s: *app.State, c: *ui.Context, current: usize, alpha: f32, live: bool) ?usize {
    const k = theme.colors(s.dark);
    const n = s.shown.len;
    if (n == 0) return null;
    var first: usize = 0;
    if (n > visible) {
        first = current - @min(current, visible / 2);
        first = @min(first, n - visible);
    }
    const last = @min(first + visible, n);
    const count = last - first;

    // The strip, over the foot of the picture: dark enough to read on
    // any photograph, the way the panels of the large view are.
    const strip = ui.div(c).absolute().offset(0, c.size.h - strip_h).w(c.size.w).h(strip_h)
        .opacity(alpha)
        .bg(k.scrim);
    defer strip.end();

    // The cells keep the pictures' own shapes: a cell is as wide as its
    // picture is, at the strip's height, within reason. When fifteen of
    // them would not fit, they all come down together rather than the
    // strip running off the window.
    var widths: [visible]f32 = undefined;
    var sum: f32 = 0;
    for (first..last, 0..) |i, j| {
        const aspect = s.shared.aspectOf(s.shown[i].path) orelse 1;
        widths[j] = std.math.clamp(thumb_h * aspect, cell_min, cell_max);
        sum += widths[j];
    }
    const room = @max(0, c.size.w - 32);
    const gaps = cell_gap * @as(f32, @floatFromInt(count - 1));
    const squeeze = if (sum + gaps > room and sum > 0) (room - gaps) / sum else 1;
    const height = thumb_h * squeeze;

    const total = sum * squeeze + gaps;
    var x = @max(16, (c.size.w - total) / 2);
    const y = c.size.h - strip_h + (strip_h - height) / 2;
    var clicked: ?usize = null;
    for (first..last, 0..) |i, j| {
        const w = widths[j] * squeeze;
        const on = i == current;
        {
            const cell = ui.div(c).absolute()
                .offset(x, (strip_h - height) / 2)
                .w(w).h(height).rounded(4).clip()
                .bg(if (on) ui.Color.white.alpha(0.18) else ui.Color.white.alpha(0.06))
                .control();
            const it = cell.interaction();
            const shown = c.node(c.stack.items[c.stack.items.len - 1]);
            // The one shown stands out in full and wears a ring; the
            // others stand back a little, so the eye lands where it is.
            shown.style.opacity = if (on) 1 else 0.72;
            // The picture itself, or the square it will be: the strip
            // reads the same cache the wall does, so nothing decodes
            // twice.
            if (s.shared.get(s.shown[i].path)) |known| {
                if (known.thumb) |pixels| {
                    const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
                    _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
                }
            } else {
                s.pool.askPicture(s.shown[i].path, s.shown[i].path, s.density.side());
            }
            // The ring goes over the picture, never under it: a border on
            // the cell is painted before the pixels and would not be seen.
            if (on or it.hovered) {
                const ring = ui.div(c).absolute().offset(0, 0).wFull().hFull().rounded(4)
                    .border(ui.Color.white.alpha(if (on) 1 else 0.55))
                    .borderW(if (on) 2 else 1);
                ring.end();
            }
            if (it.clicked and live) clicked = i;
            cell.end();
        }
        // Where each cell stands, for the tests that click them.
        s.filmstrip_at.append(s.gpa, .{ .x = x, .y = y, .w = w, .h = height }) catch {};
        x += w + cell_gap;
    }
    return clicked;
}
