//! The gallery: the toolbar above the grid of pictures, and the pictures
//! themselves -- measured before they are built, laid out before they are
//! decoded, drawn as they arrive.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const dialogs = @import("dialogs.zig");
const i18n = @import("i18n.zig");
const kit = nanoui.kit;
const large = @import("large.zig");
const masonry = @import("masonry.zig");
const menu = @import("menu.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const shell = @import("shell.zig");
const statusbar = @import("statusbar.zig");
const theme = @import("theme.zig");
const thumbs = @import("thumbs.zig");
const tile = @import("tile.zig");

/// How far ahead the thumbnails are asked for, in windows.
const prefetch_ahead: f32 = 4.0;
/// How far behind, in windows: less, because the view came from there.
const prefetch_behind: f32 = 1.0;
/// How far above and below the window pictures are built, in windows.
const build_margin: f32 = 0.25;

/// Which way the cursor walks: across the columns, or along one.
const Walk = enum { left, right, up, down };

/// The gallery's own column: under it the grid, above it the command bar
/// and the status bar that the shell and the statusbar draw (app.zig's
/// `view` puts them in place).
pub fn view(s: *app.State, c: *ui.Context) void {
    ui.column(c, .{ .grow = 1, .width = .fill, .height = .fill });
    defer ui.end(c);
    viewGrid(s, c);
}

/// The pictures, in columns: only those in view are built.
fn viewGrid(s: *app.State, c: *ui.Context) void {
    const th = c.theme;
    const tr = i18n.strings(s.lang);
    // The menu and the rename box are the kit's own overlays now: they
    // take their own escape, and a click that misses them. The grid's
    // keys belong to the gallery only when none of that is up.
    if (s.menu_for == null and !s.rename_open and s.confirming_trash.items.len == 0 and
        s.tree_focus == null)
    {
        gridKeys(s, c);
    }
    // The grid is the focus ring's other stop: a click anywhere on the wall
    // puts the ring here, and the arrows walk it.
    _ = c.interact(c.stack.items[c.stack.items.len - 1], .{ .focusable = true });
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

    // The grid's own place and size, as the last frame laid it out. The
    // first frame has no rectangle yet: the shell's own geometry says
    // where the column begins, so even that frame lays out a wall that
    // fits instead of one that runs off the window.
    const rect = c.rects.get(id);
    const column_x = if (s.rail_visible) s.rail_w else 0;
    const view_w = if (rect) |r| r.w else @max(1, c.size.w - column_x);
    const view_h = if (rect) |r| r.h else c.size.h;
    const grid_x = if (rect) |r| r.x else column_x;
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
    // The cursor's picture stays where the eye can see it: the walk may
    // have moved it off the screen, and the view follows the keyboard.
    if (s.layout.placements.len == s.shown.len) {
        if (s.select.cursor) |ci| {
            if (ci < s.layout.placements.len) {
                const p = s.layout.placements[ci];
                const top = p.y - offset;
                const bottom = top + p.h;
                if (top < 0) {
                    offset = @max(0, p.y - 8);
                    c.scroll.put(c.gpa, id, offset) catch {};
                } else if (bottom > view_h) {
                    offset = p.y + p.h - view_h + 8;
                    c.scroll.put(c.gpa, id, offset) catch {};
                }
            }
        }
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
        // soon as they answer, so the wait is drawn. The wall itself is
        // sketched while the sizes arrive -- an empty page would read as
        // "there is nothing here", which is not what is happening.
        c.animationFrame();
        {
            const wait = ui.div(c).row().itemsCenter().gap(8).px(4).py(4);
            defer wait.end();
            ui.icon(c, "circle.dotted", .{ .size = 14, .color = th.muted });
            ui.text(c, i18n.measuring(c.alloc(), s.lang, measured, pictures.len), .{ .size = 13, .color = th.muted });
        }
        skeletonWall(s, c, view_w, view_h);
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
        ui.icon(c, if (pictures.len == 0) "photo" else "magnifyingglass", .{ .size = 34, .color = th.muted });
        if (pictures.len == 0) {
            // The folder is really empty: say so, say what would fill it,
            // and leave a way somewhere else.
            ui.text(c, tr.no_pictures, .{ .size = 14, .color = th.muted });
            ui.text(c, tr.formats_hint, .{ .size = 12, .color = th.muted });
            ui.row(c, .{ .gap = 8, .align_items = .center, .padding = .{ .top = 6 } });
            defer c.end();
            if (kit.button(c, tr.open_folder, .{ .size = .sm, .variant = .primary }).clicked) shell.askForFolder(s);
            if (kit.button(c, tr.rescan, .{ .size = .sm }).clicked) {
                s.relist_pending = true;
                c.changed = true;
            }
        } else {
            // What emptied the wall, said its own way: the filter's
            // verdict, or the search's.
            if (s.filter_stars > 0) {
                ui.text(c, i18n.filterEmpty(c.alloc(), s.lang, s.filter_stars), .{ .size = 13, .color = th.muted });
            } else {
                ui.text(c, i18n.noMatches(c.alloc(), s.lang, s.search.text()), .{ .size = 13, .color = th.muted });
            }
            // The way out, at hand: one click undoes whatever stands
            // between the reader and the wall.
            if (kit.button(c, if (s.filter_stars > 0) tr.clear_filter else tr.clear_search, .{ .size = .sm }).clicked) {
                s.search.clear();
                s.filter_stars = 0;
                s.orderChanged();
                c.changed = true;
            }
        }
        return;
    }

    // The room the pictures take, so the grid scrolls. Its empty ground
    // is where the hand draws a marquee: pressed on nothing, it gathers
    // every picture the box comes to hold.
    const room = ui.div(c).wFull().h(s.layout.height).control();
    defer room.end();
    _ = room.interaction();
    {
        const gx = c.input.mouse.x - grid_x;
        const gy = c.input.mouse.y - grid_y + offset;
        const in_room = gx >= 0 and gx < view_w and gy >= 0 and gy < s.layout.height;
        if (c.input.pressed and in_room and tileAt(s, gx, gy) == null) {
            s.select.marquee_from = .{ .x = gx, .y = gy };
            s.select.marquee = .{ .x = gx, .y = gy, .w = 0, .h = 0 };
            c.changed = true;
        } else if (s.select.marquee != null and c.input.released) {
            applyMarquee(s);
            s.select.marquee = null;
            c.changed = true;
        } else if (s.select.marquee != null and c.input.down) {
            s.select.marqueeTo(gx, gy);
        } else if (s.select.marquee != null) {
            s.select.marquee = null;
        }
    }

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
        // The layout may still be the last folder's, or not made yet:
        // a picture with no place waits for the frame that gives it one
        // rather than reading past what there is.
        if (i >= s.layout.placements.len) break;
        const place = s.layout.placements[i];
        const top = place.y - offset;
        const bottom = place.y + place.h - offset;
        if (bottom < -behind or top > view_h + ahead) continue;
        // The thumbnail is asked for now, at the side the current
        // density shows it at, whether the picture is built this frame
        // or not.
        s.pool.askPicture(pic.path, pic.path, s.density.side());
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
        tile.view(s, c, pic, place, i);
    }

    // The box the hand is drawing, over the pictures it is gathering.
    if (s.select.marquee) |mq| {
        const k = theme.colors(s.dark);
        const mq_box = ui.div(c).absolute().offset(mq.x, mq.y).w(mq.w).h(mq.h)
            .bg(k.accent.alpha(0.08));
        defer mq_box.end();
        const n = c.node(c.stack.items[c.stack.items.len - 1]);
        n.style.border = k.accent;
    }

    // While the pictures on their way are still being decoded, another
    // frame is wanted as soon as each one lands -- the view is a
    // function of the state, and the state is still arriving.
    if (waiting > 0) c.animationFrame();
}

/// The wall, sketched while the pictures' sizes are still arriving: the
/// same columns the density would make, in the well's quiet colour, so
/// the page is a wall being measured rather than a page with nothing on
/// it. Nothing here is clickable, and the real tiles replace it whole.
fn skeletonWall(s: *app.State, c: *ui.Context, view_w: f32, view_h: f32) void {
    const k = theme.colors(s.dark);
    const gap: f32 = 6;
    const pad: f32 = 16;
    const cols = masonry.columnsFor(view_w, .{ .columns = 12, .target = s.density.row(), .gap = gap, .padding = pad });
    const cell = (view_w - 2 * pad - gap * @as(f32, @floatFromInt(cols - 1))) / @as(f32, @floatFromInt(cols));
    if (!(cell > 8)) return;
    const rows_wanted = @as(usize, @intFromFloat(@max(1, (view_h - 40) / (cell + gap))));
    const rows = @min(8, rows_wanted);
    var r: usize = 0;
    while (r < rows) : (r += 1) {
        const line = ui.div(c).row().wFull().gap(gap).px(pad).py(gap / 2);
        defer line.end();
        var i: usize = 0;
        while (i < cols) : (i += 1) {
            _ = c.leaf(.{
                .width = .{ .px = cell },
                .height = .{ .px = cell },
                .radius = 4,
                .background = k.well,
            }, .none, null);
        }
    }
}

/// The picture the grid's coordinates fall on, or null on the ground.
fn tileAt(s: *app.State, gx: f32, gy: f32) ?usize {
    if (s.layout.placements.len != s.shown.len) return null;
    for (s.layout.placements, 0..) |p, i| {
        if (gx >= p.x and gx < p.x + p.w and gy >= p.y and gy < p.y + p.h) return i;
    }
    return null;
}

/// The marquee has said its word: exactly what the box holds is chosen.
fn applyMarquee(s: *app.State) void {
    const box = s.select.marquee orelse return;
    if (s.layout.placements.len != s.shown.len) return;
    var hits: std.ArrayList([]const u8) = .empty;
    defer hits.deinit(s.gpa);
    var last: ?usize = null;
    for (s.layout.placements, 0..) |p, i| {
        const overlap = p.x < box.x + box.w and box.x < p.x + p.w and
            p.y < box.y + box.h and box.y < p.y + p.h;
        if (!overlap) continue;
        hits.append(s.gpa, s.shown[i].path) catch {};
        last = i;
    }
    s.select.onlyPaths(hits.items);
    if (last) |i| s.select.cursor = i;
}

/// What the bulk keys act on: the choice when there is one, the cursor's
/// picture otherwise. Made in the frame's arena, gone with the frame.
fn targets(s: *app.State, c: *ui.Context) []*model.Picture {
    if (s.select.count() > 0) return s.select.chosen(c.alloc(), s.shown) catch &.{};
    if (s.select.cursor) |i| {
        if (i < s.shown.len) {
            const one = c.alloc().alloc(*model.Picture, 1) catch return &.{};
            one[0] = s.shown[i];
            return one[0..1];
        }
    }
    return &.{};
}

/// The grid's keys, when the gallery holds the reader's attention: the
/// cursor walks, the view follows it, a shift extends the choice, and
/// the bulk's keys act on what stands under all of it.
fn gridKeys(s: *app.State, c: *ui.Context) void {
    const shown = s.shown;
    if (shown.len == 0) return;

    // -- walking --
    if (c.input.key) |k| {
        const d: ?Walk = switch (k) {
            .left => .left,
            .right => .right,
            .up => .up,
            .down => .down,
            else => null,
        };
        if (d) |dir| {
            stepCursor(s, c, dir);
        } else switch (k) {
            .home => jumpCursor(s, c, 0),
            .end => jumpCursor(s, c, shown.len - 1),
            .page_up => pageCursor(s, c, .up),
            .page_down => pageCursor(s, c, .down),
            .enter => {
                // The cursor's picture, large: the same as opening it.
                const t = targets(s, c);
                if (t.len > 0) {
                    large.show(s, t[0]);
                    for (s.shown, 0..) |p, j| {
                        if (p == t[0]) s.select.cursor = j;
                    }
                }
            },
            .delete, .backspace => {
                const t = targets(s, c);
                if (t.len > 0) dialogs.askTrash(s, t);
            },
            .f2 => {
                // Renaming is a one-picture affair: only with a single
                // target does the box come up.
                const t = targets(s, c);
                if (t.len == 1) {
                    s.renaming = t[0];
                    s.rename_open = true;
                    s.rename_field.set(t[0].name);
                    s.rename_error = false;
                }
            },
            else => {},
        }
    }

    // -- the bulk's combinations --
    if (c.shortcut(.{ .key = 'a', .ctrl = true })) {
        s.select.all(shown);
        c.changed = true;
    }
    if (c.shortcut(.{ .key = 'c', .ctrl = true })) {
        const t = targets(s, c);
        if (t.len > 0) {
            const paths = c.alloc().alloc([]const u8, t.len) catch return;
            for (t, 0..) |p, i| paths[i] = p.path;
            ops.copyFilesToClipboard(s.gpa, paths);
            s.toast(.success, i18n.strings(s.lang).copied);
        }
    }
    if (c.shortcut(.{ .key = 'r', .ctrl = true, .shift = true })) {
        const t = targets(s, c);
        if (t.len > 0) ops.reveal(t[0].path);
    }
    if (c.shortcut(.{ .key = ui.Shortcut.enter, .ctrl = true })) {
        const t = targets(s, c);
        for (t) |p| _ = ops.open(p.path);
    }

    // -- the keys that come as characters --
    // A rate for the choice, or the cursor; `t` opens the picture large
    // and starts a tag there, where the typing belongs.
    for (c.input.chars) |ch| {
        if (ch >= '0' and ch <= '5') {
            const t = targets(s, c);
            if (t.len > 0) large.rateBatch(s, t, @intCast(ch - '0'));
        } else if (ch == 't' or ch == 'T') {
            const t = targets(s, c);
            if (t.len >= 1 and editable(t[0].name)) {
                large.show(s, t[0]);
                s.tag_editing = true;
                s.tag_field.clear();
            }
        } else if (ch == ' ') {
            // Space is the quick look: the cursor's picture, large.
            const t = targets(s, c);
            if (t.len > 0) {
                large.show(s, t[0]);
                for (s.shown, 0..) |p, j| {
                    if (p == t[0]) s.select.cursor = j;
                }
                c.changed = true;
            }
        }
    }
}

/// Whether a file's name can carry stars and tags in its own bytes --
/// the same rule the large view's panel goes by.
const editable = large.editable;

/// The cursor walks one place, the view follows, and a shift extends
/// the choice from the anchor. No cursor yet: the walk starts one.
fn stepCursor(s: *app.State, c: *ui.Context, dir: Walk) void {
    const to = neighborOf(s, s.select.cursor, dir) orelse return;
    moveCursorTo(s, c, to);
}

/// The cursor to an index, whole: Home, End, the walk's own first step.
fn jumpCursor(s: *app.State, c: *ui.Context, to: usize) void {
    moveCursorTo(s, c, to);
}

fn moveCursorTo(s: *app.State, c: *ui.Context, to: usize) void {
    if (to >= s.shown.len) return;
    s.select.cursor = to;
    if (c.input.shift) s.select.range(s.shown, to);
    c.changed = true;
}

/// The same column one viewport away: the page keys keep the reader's
/// place across the screenful.
fn pageCursor(s: *app.State, c: *ui.Context, dir: Walk) void {
    const cur = s.select.cursor orelse {
        moveCursorTo(s, c, if (dir == .down) 0 else s.shown.len - 1);
        return;
    };
    if (cur >= s.layout.placements.len) return;
    const here = s.layout.placements[cur];
    const page = @max(1.0, c.size.h);
    var best: ?usize = null;
    for (s.layout.placements, 0..) |p, i| {
        if (p.x != here.x) continue;
        const far = if (dir == .down) p.y >= here.y + page else p.y + p.h <= here.y - page + p.h;
        if (!far) continue;
        if (best) |b| {
            const b_y = s.layout.placements[b].y;
            if (if (dir == .down) p.y < b_y else p.y > b_y) best = i;
        } else best = i;
    }
    moveCursorTo(s, c, best orelse if (dir == .down) s.shown.len - 1 else 0);
}

/// The place next door: along the same column for up and down, across
/// to the nearest column for left and right, at the height nearest the
/// one the cursor is at. Nothing next door: the cursor stays.
fn neighborOf(s: *app.State, cur: ?usize, dir: Walk) ?usize {
    const n = s.shown.len;
    if (n == 0 or s.layout.placements.len != n) return null;
    const at = cur orelse return 0;
    if (at >= n) return 0;
    const here = s.layout.placements[at];
    var best: ?usize = null;
    var best_d2: f32 = 1e18;
    for (s.layout.placements, 0..) |p, i| {
        if (i == at) continue;
        switch (dir) {
            .up, .down => {
                if (p.x != here.x) continue;
                if (dir == .up and p.y + p.h > here.y + 1) continue;
                if (dir == .down and p.y < here.y + here.h - 1) continue;
            },
            .left, .right => {
                if (dir == .left and p.x >= here.x) continue;
                if (dir == .right and p.x <= here.x) continue;
            },
        }
        const dx = p.x + p.w / 2 - (here.x + here.w / 2);
        const dy = p.y + p.h / 2 - (here.y + here.h / 2);
        const d2 = dx * dx + dy * dy;
        if (d2 < best_d2) {
            best_d2 = d2;
            best = i;
        }
    }
    return best;
}
