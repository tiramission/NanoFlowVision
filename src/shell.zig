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

/// Asks the reader for a folder, and queues it as the new root. The
/// dialog itself must not open inside the build: the wish is recorded
/// here, and the loop calls back after this frame, from outside any
/// build, where the dialog can open.
pub fn askForFolder(s: *app.State) void {
    s.dialog_pending = true;
    nanoui.App.after(0, s, folderDialogFromMain);
}

/// Runs the dialog, outside any frame (see `askForFolder`).
fn folderDialogFromMain(ctx: ?*anyopaque) callconv(.c) void {
    const s: *app.State = @ptrCast(@alignCast(ctx.?));
    if (!s.dialog_pending) return;
    s.dialog_pending = false;
    runFolderDialog(s);
}

/// The dialog itself: the reader's choice goes to the queue as the new
/// root, and the next frame takes it in.
fn runFolderDialog(s: *app.State) void {
    // The dialog reads a zero-ended path; the tree's own slice has no
    // sentinel, so a copy gets one.
    const start = s.gpa.alloc(u8, s.tree.path.len + 1) catch return;
    defer s.gpa.free(start);
    @memcpy(start[0..s.tree.path.len], s.tree.path);
    start[s.tree.path.len] = 0;
    const picked = nfd.openFolderDialog(start[0..s.tree.path.len :0]) catch return;
    if (picked) |folder| {
        defer nfd.freePath(folder);
        queueReroot(s, folder);
    }
}

/// Holds a chosen folder for the next frame, when no one is walking the
/// tree it replaces.
fn queueReroot(s: *app.State, path: []const u8) void {
    if (s.reroot_pending) |old| s.gpa.free(old);
    s.reroot_pending = s.gpa.dupe(u8, path) catch null;
}

/// How tall the command bar is.
pub const bar_height: f32 = 44;
/// Below this window width the breadcrumb keeps only the folder it is in:
/// the way here would be clipped into meaningless fragments anyway.
const crumbs_narrow: f32 = 760;

pub fn treeKeys(s: *app.State, c: *ui.Context) void {
    // Tab belongs to nanoui's focus ring: the rail is a stop in it, and
    // the ring tells the rail whether it holds the keyboard (see
    // `rail.view`). Nothing here takes the key.
    const focus = s.tree_focus orelse return;
    if (c.input.key) |k| switch (k) {
        .up, .down => {
            var rows: std.ArrayList(*model.Folder) = .empty;
            defer rows.deinit(s.gpa);
            visibleFolders(s.gpa, &s.tree, &rows);
            var at: usize = 0;
            for (rows.items, 0..) |row, i| {
                if (row == focus) {
                    at = i;
                    break;
                }
            }
            const next: usize = if (k == .up) at -| 1 else @min(at + 1, rows.items.len - 1);
            s.tree_focus = rows.items[next];
            c.changed = true;
        },
        .right => {
            if (focus.children.len == 0) return;
            if (focus.expanded) {
                s.tree_focus = &focus.children[0];
            } else focus.expanded = true;
            c.changed = true;
        },
        .left => {
            if (focus.expanded and focus.children.len > 0) {
                focus.expanded = false;
            } else if (model.parentOf(focus.path)) |parent| {
                var found: ?*model.Folder = null;
                findChild(s, &s.tree, parent, &found);
                if (found) |p| s.tree_focus = p;
            }
            c.changed = true;
        },
        .enter => {
            s.open(focus);
            focus.expanded = true;
            c.changed = true;
        },
        else => {},
    };
}

/// The first folder the tree shows, for the Tab that hands the focus in.
pub fn firstVisible(folder: *model.Folder) ?*model.Folder {
    if (folder.children.len == 0) return null;
    return &folder.children[0];
}

/// The folders the tree shows right now, the roots down: the open ones
/// with their children after them, the folded ones alone.
fn visibleFolders(gpa: std.mem.Allocator, folder: *model.Folder, out: *std.ArrayList(*model.Folder)) void {
    for (folder.children) |*child| {
        out.append(gpa, child) catch {};
        if (child.expanded) visibleFolders(gpa, child, out);
    }
}

/// The folder just opened joins the way the reader came: everything
/// ahead of the present goes, the folder goes on the end. The way
/// back and forward walks this line.
pub fn noteHistory(s: *app.State) void {
    if (s.nav_lock) return;
    const folder = s.current orelse return;
    while (s.history.items.len > s.history_at + 1) {
        if (s.history.pop()) |old| s.gpa.free(old);
    }
    if (s.history.items.len > 0) {
        const cur = s.history.items[s.history_at];
        if (std.mem.eql(u8, cur, folder.path)) return;
    }
    const owned = s.gpa.dupe(u8, folder.path) catch return;
    s.history.append(s.gpa, owned) catch s.gpa.free(owned);
    s.history_at = s.history.items.len - 1;
    // The line is not a bottomless well: twenty folders back is a
    // memory no one asks for.
    if (s.history.items.len > 20) {
        const old = s.history.orderedRemove(0);
        s.gpa.free(old);
        s.history_at -= 1;
    }
}

/// The way back, or forward, one folder: a walk through the reader's
/// own recent past. A folder that went away is skipped over.
pub fn historyStep(s: *app.State, step: i32) void {
    if (s.history.items.len == 0) return;
    const at_i: i64 = @as(i64, @intCast(s.history_at)) + step;
    if (at_i < 0 or at_i >= @as(i64, @intCast(s.history.items.len))) return;
    s.history_at = @intCast(at_i);
    var found: ?*model.Folder = null;
    findChild(s, &s.tree, s.history.items[s.history_at], &found);
    const folder = found orelse return;
    s.nav_lock = true;
    defer s.nav_lock = false;
    s.open(folder);
}


/// What happens before a frame is drawn, in the order the frame needs
/// it: the system's appearance is asked after (now and then, not every
/// frame), the folder the reader asked for is opened, and a listing
/// that was asked for is made. The frame that follows draws the answer.
pub fn frameStart(s: *app.State, c: *ui.Context) void {
    // "Follow the system" is in no hurry: once a minute is often
    // enough, and the answer rarely changes under anyone.
    if (s.appearance == .auto and c.time - s.system_checked >= 60) {
        s.system_checked = c.time;
        const lit = nanoui.isDark();
        if (lit != s.dark) s.setDark(lit);
    }
    if (s.reroot_pending) |path| {
        s.reroot_pending = null;
        reroot(s, path);
        s.gpa.free(path);
    }
    if (s.relist_pending) {
        s.relist_pending = false;
        s.relist();
    }
    if (s.listed_at < 0) s.listed_at = c.time;
}

/// Makes another folder the root: the tree is read from it anew, the
/// gallery shows what it holds, and the watcher moves with it.
pub fn reroot(s: *app.State, path: []const u8) void {
    const tree = &s.tree;
    if (std.mem.eql(u8, tree.path, path)) return;
    for (tree.children) |*child| child.deinit(s.gpa);
    s.gpa.free(tree.children);
    for (tree.pictures) |*p| p.deinit(s.gpa);
    s.gpa.free(tree.pictures);
    tree.children = &.{};
    tree.pictures = &.{};
    tree.loaded = false;
    tree.expanded = true;
    tree.depth = 0;
    const new_path = s.gpa.dupe(u8, path) catch return;
    const new_name = s.gpa.dupe(u8, model.nameOf(path)) catch {
        s.gpa.free(new_path);
        return;
    };
    s.gpa.free(tree.path);
    s.gpa.free(tree.name);
    tree.path = new_path;
    tree.name = new_name;
    s.open(tree);
    s.saveSettings();
}


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

    // The way back to the rail while it is folded away: without this the
    // only way to unfold it is the keyboard, and a mouse has not one.
    if (!s.rail_visible) {
        const back = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "sidebar.left" });
        if (back.rect) |r| s.rail_toggle_at = r;
        if (back.hovered) kit.tooltip(c, back, tr.sidebar_label, .{});
        if (back.clicked) {
            s.rail_visible = true;
            c.changed = true;
        }
    }

    crumbs(s, c);

    // What the gallery takes in, said as a chip that also takes it back
    // out: the subfolders are a mode, and a mode the eye cannot see is a
    // mode the eye will forget.
    if (s.recursive) {
        var chip = ui.div(c).row().h(22).itemsCenter().gap(5).px(7).rounded(5).bg(k.control).control();
        defer chip.end();
        chip = chip.hover(k.hover);
        ui.icon(c, "folder", .{ .size = 11, .color = k.secondary });
        ui.text(c, tr.subfolders, .{ .size = 12, .color = k.secondary });
        ui.icon(c, "xmark", .{ .size = 9, .color = k.tertiary });
        if (chip.clicked()) {
            s.recursive = false;
            if (s.current) |folder| folder.loaded = false;
            s.relist_pending = true;
            s.saveSettings();
            c.changed = true;
        }
    }

    // The search: what matches stays, the rest waits its turn. It keeps
    // its own width, so the breadcrumb is never squeezed for it. ⌘F puts
    // the caret here; the xmark gives the wall back in one click.
    {
        const frame = ui.div(c).row().h(30).itemsCenter().gap(7).px(10).w(220).rounded(8).bg(k.well).border(k.border);
        defer frame.end();
        ui.icon(c, "magnifyingglass", .{ .size = 12, .color = k.tertiary });
        c.next_key = "search";
        if (s.focus_search) {
            c.focus = c.peekId(null);
            s.focus_search = false;
            c.changed = true;
        }
        const field = ui.textField(c, &s.search, .{ .placeholder = tr.search_placeholder, .width = .fill, .size = 13, .bare = true });
        if (field.changed) s.orderChanged();
        if (s.search.text().len > 0) {
            const clear = ui.div(c).row().w(18).h(18).center().rounded(4).control();
            const it = clear.interaction();
            defer clear.end();
            if (it.rect) |r| s.search_clear_at = r;
            ui.icon(c, "xmark", .{ .size = 9, .color = k.secondary });
            if (it.clicked) {
                s.search.clear();
                s.orderChanged();
                c.changed = true;
            }
        } else s.search_clear_at = .{};
    }

    // The star filter: what the wall keeps, said as a chip when it is
    // on, an icon when it is not. The menu holds the steps and the way
    // back; picking one re-sorts nothing -- it only decides who waits
    // outside.
    const flt = ui.button(
        c,
        if (s.filter_stars > 0) i18n.filterMinStars(c.alloc(), s.lang, s.filter_stars) else "",
        .{ .variant = .ghost, .size = 13, .icon = if (s.filter_stars > 0) "" else "star.fill" },
    );
    if (flt.rect) |r| s.filter_at = r;
    if (flt.hovered) kit.tooltip(c, flt, tr.filter_label, .{});
    if (flt.clicked) {
        s.filter_open = true;
        c.changed = true;
    }
    var filter_items = [_]kit.MenuItem{
        .{ .label = tr.clear_filter, .checked = s.filter_stars == 0 },
        .{ .separator = true },
        .{ .label = "★", .checked = s.filter_stars == 1 },
        .{ .label = "★★", .checked = s.filter_stars == 2 },
        .{ .label = "★★★", .checked = s.filter_stars == 3 },
        .{ .label = "★★★★", .checked = s.filter_stars == 4 },
        .{ .label = "★★★★★", .checked = s.filter_stars == 5 },
    };
    if (kit.menu(c, "filter-menu", &s.filter_open, s.filter_at, &filter_items, .{})) |picked| {
        // The separator holds a place in the count: the steps answer one
        // below their own index, and only the clear is where it says.
        const next: usize = if (picked == 0) 0 else picked - 1;
        if (next != s.filter_stars) {
            s.filter_stars = next;
            s.orderChanged();
            c.changed = true;
        }
    }

    // How the pictures are ordered, and how big they are: two icon
    // buttons whose menus open under them and say the choice with a tick.
    const sort = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "chevron.up.chevron.down" });
    if (sort.rect) |r| s.sort_at = r;
    if (sort.hovered) kit.tooltip(c, sort, c.print("{s} · {s}", .{ tr.sort_by, sortWord(tr, s.sort) }), .{});
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

    const dens = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "square.grid.2x2" });
    // The button's place, written out every frame: the menu hangs from
    // it, and a test finds it there (as the grid's first picture is).
    if (dens.rect) |r| s.density_at = r;
    if (dens.hovered) kit.tooltip(c, dens, tr.density, .{});
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

    // The rest: the words that act on the choice, the subfolders, a
    // rescan, another folder, the settings -- the rail's old foot, kept
    // where the eye goes for what is not on the bar.
    const more = ui.button(c, "", .{ .variant = .ghost, .size = 13, .icon = "ellipsis.circle" });
    if (more.rect) |r| s.more_at = r;
    if (more.hovered) kit.tooltip(c, more, tr.more_label, .{});
    if (more.clicked) {
        s.more_open = true;
        c.changed = true;
    }
    var more_items = [_]kit.MenuItem{
        .{ .label = tr.select_all, .shortcut = ui.keys.label("⌘A") },
        .{ .label = tr.clear_selection, .shortcut = ui.keys.label("Esc") },
        .{ .separator = true },
        .{ .label = tr.subfolders, .checked = s.recursive },
        .{ .label = tr.rescan, .shortcut = ui.keys.label("F5") },
        .{ .label = tr.open_folder, .shortcut = ui.keys.label("⌘O") },
        .{ .separator = true },
        .{ .label = tr.settings, .shortcut = ui.keys.label("⌘,") },
    };
    if (kit.menu(c, "more-menu", &s.more_open, s.more_at, &more_items, .{})) |picked| {
        switch (picked) {
            0 => {
                s.select.all(s.shown);
                c.changed = true;
            },
            1 => {
                s.select.clear();
                c.changed = true;
            },
            3 => {
                s.recursive = !s.recursive;
                if (s.current) |folder| folder.loaded = false;
                s.relist_pending = true;
                s.saveSettings();
                c.changed = true;
            },
            4 => s.relist_pending = true,
            5 => askForFolder(s),
            7 => {
                s.settings_open = true;
                c.changed = true;
            },
            else => {},
        }
    }
}

/// The word the sort tooltip says for a key.
fn sortWord(tr: i18n.Strings, key: app.SortKey) []const u8 {
    return switch (key) {
        .name => tr.sort_name,
        .time => tr.sort_date,
        .size => tr.sort_size,
        .pixels => tr.sort_pixels,
        .stars => tr.sort_stars,
    };
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
    const only_here = c.size.w <= crumbs_narrow;
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
pub fn findChild(s: *app.State, from: *model.Folder, path: []const u8, found: *?*model.Folder) void {
    for (from.children) |*child| {
        if (std.mem.eql(u8, child.path, path)) {
            found.* = child;
            return;
        }
        findChild(s, child, path, found);
    }
}
