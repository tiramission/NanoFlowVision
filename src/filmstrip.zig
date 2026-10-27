//! The strip of neighbours along the bottom of the large view: the
//! pictures around the one shown, small, the shown one ringed. A click
//! goes there; the wheel over the strip steps along the gallery, which
//! the large view gives it instead of the zoom.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const theme = @import("theme.zig");

/// How many neighbours the strip shows at most -- the shown one as close
/// to the middle as the gallery's ends allow.
pub const visible: usize = 15;
/// How tall a strip thumbnail is, and the strip that holds them.
pub const thumb_h: f32 = 44;
pub const strip_h: f32 = 60;

/// Draws the strip for the picture at `current` in the shown list, and
/// hands back the index the reader clicked, if any.
pub fn view(s: *app.State, c: *ui.Context, current: usize) ?usize {
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
        .bg(ui.Color.black.alpha(0.45));
    defer strip.end();

    // The cells sit at their own exact places, from the middle out: a
    // test (and a reader's eye) can find each one without asking the
    // last frame where it was.
    const cell_w = thumb_h + 4;
    const total = @as(f32, @floatFromInt(count)) * cell_w - 4;
    const x0 = @max(8, (c.size.w - total) / 2);
    var clicked: ?usize = null;
    for (first..last) |i| {
        const at: f32 = x0 + @as(f32, @floatFromInt(i - first)) * cell_w;
        const on = i == current;
        {
            const cell = ui.div(c).absolute()
                .offset(at, (strip_h - thumb_h) / 2)
                .w(thumb_h).h(thumb_h).rounded(4)
                .bg(if (on) k.accent.alpha(0.25) else ui.Color.black.alpha(0.2))
                .control();
            const it = cell.interaction();
            if (on) {
                const ring = c.node(c.stack.items[c.stack.items.len - 1]);
                ring.style.border = k.accent;
            }
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
            if (it.clicked) clicked = i;
            cell.end();
        }
        // Where each cell stands, for the tests that click them.
        s.filmstrip_at.append(s.gpa, .{
            .x = at,
            .y = c.size.h - strip_h + (strip_h - thumb_h) / 2,
            .w = thumb_h,
            .h = thumb_h,
        }) catch {};
    }
    return clicked;
}
