//! A picture on the wall: its ground, its photograph or the place it
//! waits in, and the marks it wears -- the name along its foot, its
//! stars, the stamp of a choice, the cursor's hairline, the corner that
//! opens its menu. Everything is placed absolutely inside the tile the
//! layout gave it, so nothing here takes room from anything else.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const large = @import("large.zig");
const masonry = @import("masonry.zig");
const model = @import("model.zig");
const statusbar = @import("statusbar.zig");
const theme = @import("theme.zig");

/// Draws one picture where the layout put it.
pub fn view(s: *app.State, c: *ui.Context, pic: *model.Picture, place: masonry.Placement, index: usize) void {
    const th = c.theme;
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    // The tile's own ground: what shows while the photograph is on its
    // way, so the wall keeps its shape and no square is ever a mystery.
    const box = ui.div(c).absolute().offset(place.x, place.y).w(place.w).h(place.h).rounded(4).clip().bg(k.tile);
    defer box.end();
    const inter = box.interaction();
    if (inter.double_clicked) {
        // A double click opens it large, and the cursor goes with it: the
        // escape back to the wall lands on the tile it came from.
        s.select.cursor = index;
        large.show(s, pic);
        c.changed = true;
        return;
    }
    // A single click speaks to the choice: plain, it chooses this one;
    // with the adding key it joins or leaves; with shift it grows the
    // range from the anchor.
    if (inter.clicked) {
        if (c.input.adding()) {
            s.select.toggle(pic, index);
        } else if (c.input.shift) {
            s.select.range(s.shown, index);
        } else {
            s.select.only(pic, index);
        }
        c.changed = true;
    }
    const chosen = s.select.has(pic.path);
    const is_cursor = s.select.cursor != null and s.select.cursor.? == index;
    // The pointer on the picture, decided here from the last layout's
    // rect: nanoui's hot tracking answers a frame late through boxes
    // that may not be what we mean.
    const rect = inter.rect orelse ui.Rect{ .x = place.x, .y = place.y, .w = 0, .h = 0 };
    const mx = c.input.mouse.x;
    const my = c.input.mouse.y;
    const hovered = mx >= rect.x and mx < rect.x + rect.w and
        my >= rect.y and my < rect.y + rect.h;
    // The pointer is on it: a hairline says this is the one the menu
    // and the clicks mean.
    if (hovered) {
        const n = c.node(c.stack.items[c.stack.items.len - 1]);
        n.style.border = th.border;
    }

    // The photograph, or its place while the pixels are on their way.
    const cached = s.shared.get(pic.path);
    var drew_picture = false;
    if (cached) |known| {
        if (known.thumb) |pixels| {
            const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
            _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
            drew_picture = true;
        }
    }
    if (!drew_picture) {
        // Waiting and broken are two different answers: a file on its way
        // is a plain square of tile, a file that cannot be read says so.
        if (cached) |known| {
            if (known.failed) {
                const note = ui.div(c).column().wFull().hFull().center().gap(5);
                defer note.end();
                ui.icon(c, "exclamationmark.triangle", .{ .size = 14, .color = k.tertiary });
                ui.text(c, tr.decode_failed, .{ .size = 12, .color = k.secondary });
            }
        }
    }

    // Culling, seen as the design says it: while a choice stands, the
    // tiles the reader has not chosen stand back, so what is picked
    // reads at a glance. The setting can hold the wall still. It is
    // placed absolutely, over the photograph: as a child in the flow it
    // would be laid out below it, where no one would see it.
    if (s.dim_unselected and s.select.count() > 0 and !chosen) {
        _ = c.leaf(.{ .absolute = true, .width = .{ .px = place.w }, .height = .{ .px = place.h }, .background = k.page.alpha(0.55) }, .none, null);
    }
    // The choice's own ring, round the tile: the one saturated mark the
    // wall makes, in the theme's inverted accent. Drawn over the
    // photograph -- a border under it would never be seen.
    if (chosen) {
        const ring = ui.div(c).absolute().offset(0, 0).w(place.w).h(place.h).rounded(4).border(k.accent).borderW(2);
        defer ring.end();
    }
    // The keyboard's place, a hairline in from the tile's edge: a mark
    // of its own, so the cursor and the choice can stand on one tile
    // and still be told apart.
    if (is_cursor) {
        const inner = ui.div(c).absolute().offset(3, 3).w(place.w - 6).h(place.h - 6);
        defer inner.end();
        const n = c.node(c.stack.items[c.stack.items.len - 1]);
        n.style.border = k.secondary;
    }

    // The photograph's name and weight along its foot: what the eye
    // wants while it hovers, and what the cursor and the choice keep
    // saying without being pointed at. The name is the picture's own
    // slice, so it lives as long as the frame that paints it; the
    // weight goes through `textf`, whose buffer would not.
    const captioned = hovered or is_cursor or chosen;
    if (captioned) {
        const foot = ui.div(c).row().absolute().offset(0, place.h - 26).w(place.w).h(26)
            .itemsCenter().gap(8).px(8).bg(ui.Color.black.alpha(0.45));
        defer foot.end();
        // The name takes the room that is left once the weight has its
        // own: clipped, so a long name ends at the tile's edge instead of
        // pushing the weight out of the window.
        {
            const room = ui.div(c).row().grow().itemsCenter().clip();
            defer room.end();
            ui.text(c, pic.name, .{ .size = 12, .color = ui.Color.white });
        }
        if (s.shared.measuredOf(pic.path)) |known| {
            if (known.bytes > 0) {
                var buf: [24]u8 = undefined;
                ui.textf(c, .{ .size = 11, .mono = true, .color = ui.Color.white.alpha(0.7) }, "{s}", .{statusbar.sizeText(&buf, known.bytes)});
            }
        }
    }

    // What the picture says about itself, when it says anything: the
    // stars sit above the foot while the foot is there, and in the
    // corner when it is not.
    if (s.shared.measuredOf(pic.path)) |known| {
        if (known.rating > 0) {
            const stars = [_][]const u8{ "★", "★★", "★★★", "★★★★", "★★★★★" };
            const how_many: usize = @min(5, @as(usize, @intCast(@min(known.rating, 5))));
            const lifted: f32 = if (captioned) 8 + 26 else 6;
            const chip = ui.div(c).row().absolute().offset(6, place.h - lifted - 18).h(18)
                .itemsCenter().px(5).rounded(4).bg(ui.Color.black.alpha(0.45));
            defer chip.end();
            ui.text(c, stars[how_many - 1], .{ .size = 10, .color = k.grade });
        }
    }

    // And that it is one of the chosen: a stamp in the corner, so the
    // ring is not the only word for it.
    if (chosen) {
        const stamp = ui.div(c).absolute().offset(6, 6).w(20).h(20).center().rounded(5).bg(k.accent);
        defer stamp.end();
        ui.icon(c, "checkmark", .{ .size = 11, .color = k.page });
    }

    // The menu's corner, on hover: a chip that reads on any photograph.
    // It is drawn after the photograph, or the photograph's own pixels
    // would land on top of it -- a corner no one can see, though it
    // still answers clicks.
    if (hovered and s.menu_for == null and s.renaming == null) {
        const corner = ui.div(c).absolute().offset(place.w - 36, 6);
        defer corner.end();
        var chip = ui.div(c).row().w(24).h(24).center().rounded(6)
            .bg(ui.Color.black.alpha(0.55)).control();
        defer chip.end();
        ui.text(c, "⋯", .{ .size = 13, .color = .white });
        if (chip.clicked()) {
            s.menu_for = pic;
            // The menu hangs by its right edge from the picture's
            // right corner, kept inside the window: the menu is about
            // 200 wide and 210 tall.
            s.menu_at = .{
                .x = std.math.clamp(
                    s.grid_x + place.x + place.w - 200,
                    8,
                    @max(8, c.size.w - 208),
                ),
                .y = std.math.clamp(
                    s.grid_y + place.y - s.grid_offset + 44,
                    8,
                    @max(8, c.size.h - 218),
                ),
                .w = 0,
                .h = 0,
            };
            c.changed = true;
        }
    }
}
