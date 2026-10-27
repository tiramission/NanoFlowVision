//! The shell the pictures sit in: the navigation column down the left,
//! and the command bar across the top of the grid -- where the folder is
//! said as a path you can walk back along, where the search lives, and
//! where the two menus open from. The count of what is on screen belongs
//! to the status bar (`statusbar.zig`), not here, so a narrow window
//! never has to squeeze it out of existence.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const config = @import("config.zig");
const i18n = @import("i18n.zig");
const model = @import("model.zig");
const nfd = @import("nfd");
const theme = @import("theme.zig");

/// The folder dialog, run from the loop's callback: never inside a
/// frame's build, where the dialog's own message pump would redraw the
/// view inside itself. The reader's choice goes to the queue as the new
/// root (`State.queueReroot`), and the next frame takes it in.
pub fn runFolderDialog(s: *app.State) void {
    // The dialog reads a zero-ended path; the tree's own slice has no
    // sentinel, so a copy gets one.
    const start = s.gpa.alloc(u8, s.tree.path.len + 1) catch return;
    defer s.gpa.free(start);
    @memcpy(start[0..s.tree.path.len], s.tree.path);
    start[s.tree.path.len] = 0;
    const picked = nfd.openFolderDialog(start[0..s.tree.path.len :0]) catch return;
    if (picked) |folder| {
        defer nfd.freePath(folder);
        s.queueReroot(folder);
    }
}

/// How tall the command bar is.
pub const bar_height: f32 = 44;
/// Below this window width the breadcrumb keeps only the folder it is in:
/// the way here would be clipped into meaningless fragments anyway.
const crumbs_narrow: f32 = 760;

/// The folders, down the left.
pub fn rail(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    const side = ui.div(c).column().w(s.rail_w).hFull().bg(k.sidebar).px(10).gap(2);
    defer side.end();
    {
        const top = ui.div(c).row().wFull().h(44).itemsCenter().gap(8).px(6);
        defer top.end();
        // The mark, the app's own: a photograph on the inverted ground,
        // so the one saturated thing in the rail is the logo.
        {
            const mark = ui.div(c).row().w(22).h(22).center().rounded(6).bg(k.accent);
            defer mark.end();
            ui.icon(c, "photo", .{ .size = 12, .color = k.page });
        }
        ui.text(c, "NanoFlowVision", .{ .size = 13, .weight = .bold, .color = k.text });
    }
    sideSection(c, k, tr.folders);
    ui.scroll(c, .{ .width = .fill, .height = .fill, .gap = 2 });
    folders(s, c, k, &s.tree);
    ui.end(c);
    // What the gallery takes in, and the way to another folder altogether.
    {
        const row = ui.div(c).row().wFull().itemsCenter().px(8).py(4);
        defer row.end();
        if (ui.checkbox(c, tr.subfolders, &s.recursive)) {
            if (s.current) |folder| folder.loaded = false;
            s.relist_pending = true;
        }
    }
    {
        var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
        defer row.end();
        row = row.hover(k.hover);
        if (row.clicked()) s.openFolderDialog();
        {
            const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(k.accent.alpha(0.16));
            defer chip.end();
            ui.icon(c, "folder", .{ .size = 11, .color = k.accent });
        }
        ui.text(c, tr.open_folder, .{ .size = 13, .color = k.text });
    }
    // The settings, one click away at the sidebar's foot.
    {
        var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
        defer row.end();
        row = row.hover(k.hover);
        if (row.clicked()) {
            s.settings_open = true;
            c.changed = true;
        }
        {
            const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(k.accent.alpha(0.16));
            defer chip.end();
            ui.icon(c, "slider.horizontal.3", .{ .size = 11, .color = k.accent });
        }
        ui.text(c, tr.settings, .{ .size = 13, .color = k.text });
    }
}

/// A rail section's name.
fn sideSection(c: *ui.Context, k: theme.Colors, name: []const u8) void {
    const d = ui.div(c).row().wFull().px(8).pt(14).pb(4);
    defer d.end();
    ui.text(c, name, .{ .size = 11, .weight = .semibold, .color = k.tertiary });
}

fn folders(s: *app.State, c: *ui.Context, k: theme.Colors, folder: *model.Folder) void {
    for (folder.children) |*child| {
        const on = s.current == child;
        const fg = if (on) k.on_picked else k.text;
        {
            var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
            row = if (on) row.bg(k.picked) else row.hover(k.hover);
            row = row.pl(7 + @as(f32, @floatFromInt(child.depth)) * 12);
            defer row.end();
            // The chevron is sampled first: a click on it folds the folder's
            // own in and out, and must not also open the folder -- both
            // boxes sit under the pointer, and both would hear the click.
            var folded = false;
            if (child.children.len > 0) {
                var chev = ui.div(c).row().w(16).h(24).center().rounded(5).control();
                defer chev.end();
                ui.icon(c, if (child.expanded) "chevron.down" else "chevron.right", .{ .size = 10, .color = k.tertiary });
                if (chev.clicked()) {
                    child.expanded = !child.expanded;
                    folded = true;
                    c.changed = true;
                }
            } else {
                _ = c.leaf(.{ .width = .{ .px = 16 }, .height = .{ .px = 24 } }, .none, null);
            }
            if (row.clicked() and !folded) {
                s.open(child);
                // The folders inside it show, now that it is open.
                child.expanded = true;
                c.changed = true;
            }
            {
                const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(if (on) k.on_picked.alpha(0.22) else k.accent.alpha(0.16));
                defer chip.end();
                ui.icon(c, "folder", .{ .size = 11, .color = if (on) k.on_picked else k.accent });
            }
            ui.text(c, child.name, .{ .size = 13, .weight = if (on) .semibold else .regular, .color = fg });
            ui.spacer(c);
            if (child.pictures.len > 0) {
                ui.textf(c, .{ .size = 11, .mono = true, .color = if (on) k.on_picked.alpha(0.8) else k.secondary }, "{d}", .{child.pictures.len});
            }
        }
        // The folders inside it, drawn BELOW its row: the row is closed
        // by now, or its children would flow on beside it, a single
        // thirty-point line wide, and never be seen.
        if (child.expanded) folders(s, c, k, child);
    }
}

/// The bar above the grid: where you are, the search, and the two menus.
pub fn commandBar(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    // The bar, and the hairline under it: a border would draw a frame
    // round three more sides than are wanted.
    const column = ui.div(c).column().wFull();
    defer column.end();
    controls(s, c);
    _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.border }, .none, null);
}

/// Everything that sits in the bar itself.
fn controls(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    const row = ui.div(c).row().wFull().h(bar_height).itemsCenter().gap(8).px(16);
    defer row.end();

    crumbs(s, c);

    // The search: what matches stays, the rest waits its turn. It takes
    // the room the breadcrumb leaves and holds to a readable minimum.
    {
        const frame = ui.div(c).row().h(30).itemsCenter().gap(7).px(10).grow().minW(80).maxW(220).rounded(8).bg(k.well).border(k.border);
        defer frame.end();
        ui.icon(c, "magnifyingglass", .{ .size = 12, .color = k.tertiary });
        const field = ui.textField(c, &s.search, .{ .placeholder = tr.search_placeholder, .width = .{ .px = 150 }, .size = 13, .bare = true });
        if (field.changed) s.orderChanged();
    }

    // How big the pictures are, and how they are ordered: two icon
    // buttons whose menus open under them and say the choice with a tick.
    const dens = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "square.grid.2x2" });
    // The button's place, written out every frame: the menu hangs from
    // it, and a test finds it there (as the grid's first picture is).
    if (dens.rect) |r| s.density_at = r;
    if (dens.clicked) {
        s.density_open = true;
        c.changed = true;
    }
    var dens_items = [_]kit.MenuItem{
        .{ .label = tr.density_small, .checked = s.density == .small },
        .{ .label = tr.density_medium, .checked = s.density == .medium },
        .{ .label = tr.density_large, .checked = s.density == .large },
    };
    if (kit.menu(c, "density-menu", &s.density_open, s.density_at, &dens_items, .{})) |chosen| {
        const next: config.Density = switch (chosen) {
            0 => .small,
            1 => .medium,
            else => .large,
        };
        if (next != s.density) {
            s.density = next;
            // The layout follows the new target row height, and the
            // thumbnails on screen are re-decoded at its side.
            s.orderChanged();
            s.saveSettings();
            s.toast(.info, i18n.densitySet(c.alloc(), s.lang, next.label(s.lang)));
        }
    }

    const sort = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "chevron.up.chevron.down" });
    if (sort.rect) |r| s.sort_at = r;
    if (sort.clicked) {
        s.sort_open = true;
        c.changed = true;
    }
    var sort_items = [_]kit.MenuItem{
        .{ .label = tr.sort_name, .checked = s.sort == .name },
        .{ .label = tr.sort_date, .checked = s.sort == .time },
        .{ .label = tr.sort_size, .checked = s.sort == .size },
        .{ .label = tr.sort_pixels, .checked = s.sort == .pixels },
        .{ .label = tr.sort_stars, .checked = s.sort == .stars },
        .{ .separator = true },
        .{ .label = tr.sort_ascending, .checked = s.sort_ascending },
        .{ .label = tr.sort_descending, .checked = !s.sort_ascending },
    };
    if (kit.menu(c, "sort-menu", &s.sort_open, s.sort_at, &sort_items, .{})) |chosen| {
        if (chosen <= 4) {
            s.sort = @fromBackingInt(@intCast(chosen));
            // A name goes A to Z first; the rest go newest and largest first.
            s.sort_ascending = s.sort == .name;
        } else if (chosen == 6) {
            s.sort_ascending = true;
        } else {
            s.sort_ascending = false;
        }
        s.orderChanged();
    }
}

/// The way here, as crumbs: the folders from the root down, the last one
/// taking the room that is left. A crumb goes back to its folder.
fn crumbs(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const current = s.current orelse return;

    // Deepest first: the walk up stops at the tree's own root.
    var names: std.ArrayList([]const u8) = .empty;
    var paths: std.ArrayList([]const u8) = .empty;
    var path: []const u8 = current.path;
    while (true) {
        names.append(c.alloc(), model.nameOf(path)) catch break;
        paths.append(c.alloc(), path) catch break;
        if (std.mem.eql(u8, path, s.tree.path)) break;
        path = model.parentOf(path) orelse break;
    }
    if (names.items.len == 0) return;

    const room = ui.div(c).row().grow().minW(120).itemsCenter().gap(6).clip();
    defer room.end();
    const only_here = c.size.w < crumbs_narrow;
    var drawn: usize = 0;
    var i: usize = names.items.len;
    while (i > 0) {
        i -= 1;
        const last = i == 0;
        if (only_here and !last) continue;
        if (drawn > 0) ui.icon(c, "chevron.right", .{ .size = 9, .color = k.tertiary });
        drawn += 1;
        if (last) {
            // The folder the gallery shows, in a box that holds at least
            // 120 points however narrow the window: a title that vanishes
            // is a title that may as well not be there. It wraps, so a
            // long name fills the box instead of pushing the search out.
            const box = ui.div(c).row().grow().minW(120).h(20).itemsCenter().clip();
            defer box.end();
            ui.text(c, names.items[0], .{ .size = 13, .weight = .medium, .color = k.text, .wrap = true });
        } else {
            const crumb = ui.div(c).control();
            const it = crumb.interaction();
            ui.text(c, names.items[i], .{ .size = 13, .color = if (it.hovered) k.text else k.secondary });
            crumb.end();
            if (it.clicked) openPath(s, paths.items[i]);
        }
    }
}

/// Shows the folder at `path`: the tree already holds it, unless the
/// walk found an ancestor the tree never listed.
fn openPath(s: *app.State, path: []const u8) void {
    if (s.current) |here| {
        if (std.mem.eql(u8, here.path, path)) return;
    }
    var found: ?*model.Folder = null;
    findChild(s, &s.tree, path, &found);
    if (found) |folder| s.open(folder);
}

/// The folder above the one shown, if the tree holds it.
pub fn goUp(s: *app.State) void {
    const current = s.current orelse return;
    if (current.depth == 0) return;
    const parent_path = model.parentOf(current.path) orelse return;
    var found: ?*model.Folder = null;
    findChild(s, &s.tree, parent_path, &found);
    if (found) |parent| s.open(parent);
}

/// Finds the folder at `path` in the tree, the roots down.
fn findChild(s: *app.State, from: *model.Folder, path: []const u8, found: *?*model.Folder) void {
    for (from.children) |*child| {
        if (std.mem.eql(u8, child.path, path)) {
            found.* = child;
            return;
        }
        findChild(s, child, path, found);
    }
}
