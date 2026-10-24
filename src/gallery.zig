//! The gallery: the toolbar above the grid of pictures, and the pictures
//! themselves -- measured before they are built, laid out before they are
//! decoded, drawn as they arrive.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const large = @import("large.zig");
const masonry = @import("masonry.zig");
const menu = @import("menu.zig");
const model = @import("model.zig");
const theme = @import("theme.zig");
const thumbs = @import("thumbs.zig");

/// How far ahead the thumbnails are asked for, in windows.
const prefetch_ahead: f32 = 4.0;
/// How far behind, in windows: less, because the view came from there.
const prefetch_behind: f32 = 1.0;
/// How far above and below the window pictures are built, in windows.
const build_margin: f32 = 0.25;

/// The gallery column: the header with the search and the sort, and
/// under it the grid.
pub fn view(s: *app.State, c: *ui.Context) void {
    ui.column(c, .{ .grow = 1, .width = .fill, .height = .fill });
    defer ui.end(c);
    viewToolbar(s, c);
    viewGrid(s, c);
}

/// The page's header, as nanomon draws one: the folder's name and its
/// path on the left, the search and the sort on the right.
fn viewToolbar(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    const current = s.current;
    const head = ui.div(c).row().wFull().h(52).itemsCenter().gap(8).px(20);
    defer head.end();
    if (ui.button(c, tr.up, .{ .variant = .ghost, .size = 13, .icon = "arrow.up" }).clicked) s.goUp();
    if (current) |folder| {
        // The name and where it lies: the column grows to what the row
        // has left, and the path clips rather than pushing the rest away.
        const t = ui.div(c).column().wFull().grow().gap(1).clip();
        defer t.end();
        ui.text(c, folder.name, .{ .size = 15, .weight = .bold, .color = k.text });
        ui.text(c, folder.path, .{ .size = 11, .color = k.secondary });
    }
    // The search, with its glass in the frame: what matches stays, the
    // rest waits its turn. The frame stretches when the window has room
    // and keeps to its base when it has not.
    {
        const frame = ui.div(c).row().h(30).itemsCenter().gap(7).px(10).grow().maxW(206).rounded(8).bg(k.well).border(k.border);
        defer frame.end();
        ui.icon(c, "magnifyingglass", .{ .size = 12, .color = k.tertiary });
        const field = ui.textField(c, &s.search, .{ .placeholder = tr.search_placeholder, .width = .{ .px = 150 }, .size = 13, .bare = true });
        if (field.changed) s.orderChanged();
    }
    // The sort, and the way it goes.
    const sort_labels = [_][]const u8{ tr.sort_name, tr.sort_date, tr.sort_size, tr.sort_pixels, tr.sort_stars };
    var selected: usize = @backingInt(s.sort);
    if (ui.segmented(c, &sort_labels, &selected)) {
        s.sort = @fromBackingInt(@intCast(selected));
        s.sort_ascending = s.sort == .name;
        s.orderChanged();
    }
    // The set has no arrow.down, so the direction speaks in chevrons:
    // they are the same ones the tree's folders fold with.
    if (ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = if (s.sort_ascending) "chevron.up" else "chevron.down" }).clicked) {
        s.sort_ascending = !s.sort_ascending;
        s.orderChanged();
    }
    if (current) |folder| {
        // The count, kept to its own narrow clip so a narrow window cuts
        // it short instead of pushing the toolbar out.
        const count = if (s.shown.len == folder.pictures.len)
            i18n.pictures(c.alloc(), s.lang, folder.pictures.len)
        else
            i18n.picturesOf(c.alloc(), s.lang, s.shown.len, folder.pictures.len);
        const cbox = ui.div(c).column().w(66).clip();
        defer cbox.end();
        ui.text(c, count, .{ .size = 12, .color = k.secondary });
    }
}

/// The pictures, in columns: only those in view are built.
fn viewGrid(s: *app.State, c: *ui.Context) void {
    const th = c.theme;
    const tr = i18n.strings(s.lang);
    // Esc takes the menu or the rename box away; a paste lands the
    // clipboard's files in this folder.
    if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
        if (s.renaming != null) {
            s.renaming = null;
            s.rename_field.clear();
        } else if (s.menu_for != null) {
            s.menu_for = null;
        }
    }
    if (c.shortcut(.{ .key = 'v', .ctrl = true })) menu.paste(s);
    const id = c.peekId(null);
    _ = c.open(.{
        .direction = .column,
        .width = .fill,
        .height = .fill,
        .scroll = true,
        .clip = true,
    }, null);
    defer c.end();

    // The grid's own place and size, as the last frame laid it out.
    const rect = c.rects.get(id);
    const view_w = if (rect) |r| r.w else c.size.w;
    const view_h = if (rect) |r| r.h else c.size.h;
    const grid_x = if (rect) |r| r.x else 0;
    const grid_y = if (rect) |r| r.y else 0;
    var offset = c.scroll.get(id) orelse 0;
    s.grid_x = grid_x;
    s.grid_y = grid_y;
    s.grid_offset = offset;

    // A new folder starts at the top.
    if (s.scroll_to_top) {
        s.scroll_to_top = false;
        c.scroll.put(c.gpa, id, 0) catch {};
        offset = 0;
    }
    // Which way the gallery goes: more is asked for in that direction.
    const going_down = offset >= s.last_offset;
    s.last_offset = offset;

    const current = s.current orelse return;
    const pictures = current.pictures;

    // The pictures' sizes come first: the layout is made once, and the
    // gallery does not move under the eye as they are measured.
    const measured = s.shared.measuredCount();
    if (measured < pictures.len) {
        // The workers are on the headers: another frame is wanted as
        // soon as they answer, so the wait is drawn.
        c.animationFrame();
        const wait = ui.div(c).row().itemsCenter().gap(8).px(4).py(4);
        defer wait.end();
        ui.icon(c, "circle.dotted", .{ .size = 14, .color = th.muted });
        ui.text(c, i18n.measuring(c.alloc(), s.lang, measured, pictures.len), .{ .size = 13, .color = th.muted });
        return;
    }

    s.updateLayout(view_w);

    // Nothing to show, and the words to say so: an empty folder, or a
    // search that matched nothing.
    if (s.shown.len == 0) {
        s.first_picture = null;
        s.built = 0;
        ui.row(c, .{ .width = .fill, .height = .{ .px = view_h }, .align_items = .center, .justify = .center });
        defer c.end();
        const empty = ui.div(c).column().itemsCenter().gap(10);
        defer empty.end();
        ui.icon(c, "photo", .{ .size = 34, .color = th.muted });
        if (pictures.len == 0) {
            ui.label(c, tr.no_pictures);
        } else {
            ui.text(c, i18n.noMatches(c.alloc(), s.lang, s.search.text()), .{ .size = 13, .color = th.muted });
        }
        return;
    }

    // The room the pictures take, so the grid scrolls.
    _ = c.leaf(.{ .width = .fill, .height = .{ .px = s.layout.height } }, .none, null);

    // The room the thumbnails are asked for: further than the pictures
    // are built, so they are ready by the time they come into view.
    const ahead = view_h * (if (going_down) prefetch_ahead else prefetch_behind);
    const behind = view_h * (if (going_down) prefetch_behind else prefetch_ahead);
    const built = view_h * build_margin;

    // The cache gives up what is not wanted, before any of it is used.
    s.shared.trim(thumbs.budget, s.keep.items);
    s.keep.clearRetainingCapacity();

    s.first_picture = null;
    s.built = 0;
    var waiting: usize = 0;
    for (s.shown, 0..) |pic, i| {
        const place = s.layout.placements[i];
        const top = place.y - offset;
        const bottom = place.y + place.h - offset;
        if (bottom < -behind or top > view_h + ahead) continue;
        // The thumbnail is asked for now, whether the picture is built
        // this frame or not.
        s.pool.ask(pic.path, pic.path, .picture);
        if (s.shared.get(pic.path)) |known| {
            if (known.thumb == null) waiting += 1;
        } else waiting += 1;
        s.keep.append(s.gpa, pic.path) catch {};
        if (top < -built or bottom > view_h + built) continue;
        if (s.first_picture == null) {
            s.first_picture = .{
                .x = grid_x + place.x,
                .y = grid_y + place.y - offset,
                .w = place.w,
                .h = place.h,
            };
        }
        s.built += 1;
        viewPicture(s, c, pic, place);
    }
    // While the pictures on their way are still being decoded, another
    // frame is wanted as soon as each one lands -- the view is a
    // function of the state, and the state is still arriving.
    if (waiting > 0) c.animationFrame();
}

fn viewPicture(s: *app.State, c: *ui.Context, pic: *model.Picture, place: masonry.Placement) void {
    const th = c.theme;
    const box = ui.div(c).absolute().offset(place.x, place.y).w(place.w).h(place.h).rounded(8);
    defer box.end();
    const inter = box.interaction();
    if (inter.double_clicked) {
        large.show(s, pic);
        c.changed = true;
        return;
    }
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
        _ = c.leaf(.{ .width = .fill, .height = .fill, .radius = 8, .background = theme.colors(s.dark).well }, .none, null);
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
