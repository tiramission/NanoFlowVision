//! The app: the tree o folders, the gallery of pictures, and the one shown large.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const masonry = @import("masonry.zig");
const model = @import("model.zig");
const scan = @import("scan.zig");
const thumbs = @import("thumbs.zig");
const large = @import("large.zig");
const menu = @import("menu.zig");
const gallery = @import("gallery.zig");
const ops = @import("ops.zig");
const config = @import("config.zig");
const watch = @import("watch.zig");
const i18n = @import("i18n.zig");
const theme = @import("theme.zig");
const win = @import("win.zig");

/// How much room between and around the pictures.
const gap: f32 = 8;
const padding: f32 = 20;
/// How many columns the gallery has at most.
const max_columns: usize = 6;

/// What the gallery sorts by.
pub const SortKey = enum { name, time, size, pixels, stars };

pub const State = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    shared: thumbs.Shared,
    pool: thumbs.Pool,
    window: ?*nanoui.Window = null,

    /// The folders of the tree.
    tree: model.Folder,
    /// The folder the gallery shows.
    current: ?*model.Folder = null,
    /// Where the pictures sit.
    layout: masonry.Layout = .{},
    /// The pictures' sizes.
    aspects: []f32 = &.{},
    /// The width the layout was last made for.
    laid_out_for: f32 = 0,
    /// The picture shown large, if any.
    large: ?*model.Picture = null,
    /// The cache key of the picture shown large.
    large_key: ?[]u8 = null,
    /// The paths whose thumbnails are wanted, so the cache keeps them.
    keep: std.ArrayList([]const u8) = .empty,
    /// Where the first picture on screen was drawn: a test clicks it.
    first_picture: ?ui.Rect = null,
    /// The offset the gallery was last scrolled to, to know which way it goes.
    last_offset: f32 = 0,
    /// How many pictures were built in the last frame.
    built: usize = 0,
    /// Whether the gallery must go back to the top.
    scroll_to_top: bool = false,
    /// What the gallery sorts by, and which way it goes. A name goes A to Z
    /// first; the rest go newest and largest first.
    sort: SortKey = .name,
    sort_ascending: bool = true,
    /// The words in the search box.
    search: ui.TextBuffer = .{},
    /// The pictures the gallery shows: the folder's own, filtered by the
    /// search and sorted. Pointers into the folder, so nothing is copied.
    shown: []*model.Picture = &.{},
    /// The tag being typed for the picture shown large.
    tag_field: ui.TextBuffer = .{},
    tag_editing: bool = false,
    /// Bumped when the sort or the search changed; the order follows.
    order_version: u64 = 0,
    /// The version the shown list was built for.
    shown_version: u64 = 0,
    /// The menu of one picture, and the corner it opens from.
    menu_for: ?*model.Picture = null,
    menu_at: ui.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    /// The rename box, for the picture being renamed.
    renaming: ?*model.Picture = null,
    rename_field: ui.TextBuffer = .{},
    /// Whether the gallery lists the folders inside as well.
    recursive: bool = false,
    /// Whether the gallery is drawn dark.
    dark: bool = false,
    /// The folder being watched for changes.
    watcher: watch.Watcher = undefined,
    /// The folder changed on disk: it is listed again before the frame.
    relist_pending: bool = false,
    /// A folder the reader picked in the dialog, waiting for the frame to
    /// end before it becomes the root: the frame is still walking the old
    /// tree, and the old tree is not the time to free.
    reroot_pending: ?[]u8 = null,
    /// The folder the settings are kept in, owned.
    settings_dir: ?[]u8 = null,
    /// A snapshot or a script run: its window never sat anywhere, so the
    /// way it sat is not worth remembering.
    snapshot_run: bool = false,
    /// The language the interface speaks, and whether the settings panel
    /// is open.
    lang: i18n.Lang = .en,
    settings_open: bool = false,
    /// The large view's zoom target (points per picture pixel; null
    /// fits), and where its picture is headed: the frame's own easing
    /// carries what is drawn there by the clock.
    zoom: ?f32 = null,
    zoom_target: ?f32 = null,
    pan_tx: f32 = 0,
    pan_ty: f32 = 0,
    panning: bool = false,
    last_mouse_x: f32 = 0,
    last_mouse_y: f32 = 0,
    /// Where the grid sits in the window, and how far it is scrolled:
    /// the menu opens at a picture's corner.
    grid_x: f32 = 0,
    grid_y: f32 = 0,
    grid_offset: f32 = 0,

    pub fn create(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !*State {
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        const root_path = try gpa.dupe(u8, root);
        errdefer gpa.free(root_path);
        const root_name = try gpa.dupe(u8, model.nameOf(root));
        errdefer gpa.free(root_name);
        s.* = .{
            .gpa = gpa,
            .io = io,
            .shared = .{ .gpa = gpa, .io = io },
            .pool = .{ .gpa = gpa, .io = io, .shared = &s.shared },
            .tree = .{ .path = root_path, .name = root_name },
        };
        s.watcher = .{ .app = s, .gpa = gpa };
        try s.pool.start(gpa, io, &s.shared);
        s.open(&s.tree);
        return s;
    }

    pub fn deinit(s: *State) void {
        s.watcher.stopCurrent();
        s.pool.stop();
        s.pool.window = null;
        s.shared.deinit();
        s.tree.deinit(s.gpa);
        s.layout.deinit(s.gpa);
        s.gpa.free(s.shown);
        s.gpa.free(s.aspects);
        if (s.large_key) |key| s.gpa.free(key);
        if (s.reroot_pending) |path| s.gpa.free(path);
        s.keep.deinit(s.gpa);
        s.gpa.destroy(s);
    }

    /// The folders inside a folder, and its pictures: the pictures of
    /// the subfolders too, when the gallery is set to take them. A folder
    /// that is already loaded is left as it is unless a listing is asked
    /// for, because the tree keeps what the eye opened.
    fn loadChildren(s: *State, folder: *model.Folder) !void {
        if (folder.loaded and !s.relist_pending) return;

        var listing = try scan.list(s.gpa, s.io, folder.path);
        defer listing.deinit(s.gpa);

        var children: std.ArrayList(model.Folder) = .empty;
        errdefer children.deinit(s.gpa);
        for (listing.folders) |name| {
            try children.append(s.gpa, .{
                .path = try model.join(s.gpa, folder.path, name),
                .name = try s.gpa.dupe(u8, name),
                .depth = folder.depth + 1,
            });
        }

        var pictures: std.ArrayList(model.Picture) = .empty;
        errdefer pictures.deinit(s.gpa);
        if (s.recursive) {
            var paths: std.ArrayList([]u8) = .empty;
            defer {
                for (paths.items) |p| s.gpa.free(p);
                paths.deinit(s.gpa);
            }
            try scan.listPictures(s.gpa, s.io, folder.path, true, 8, &paths);
            for (paths.items) |p| {
                try pictures.append(s.gpa, .{
                    .path = try s.gpa.dupe(u8, p),
                    .name = try s.gpa.dupe(u8, model.nameOf(p)),
                });
            }
        } else {
            for (listing.pictures) |name| {
                try pictures.append(s.gpa, .{
                    .path = try model.join(s.gpa, folder.path, name),
                    .name = try s.gpa.dupe(u8, name),
                });
            }
        }

        // The folders keep their fold across the listing: what was open
        // goes on being open, by name. The disk's changes read the tree
        // again; the reader's open folders are not the disk's to close.
        for (children.items) |*child| {
            for (folder.children) |*old| {
                if (std.mem.eql(u8, old.name, child.name)) child.expanded = old.expanded;
            }
        }

        // The old goes out, the new goes in.
        for (folder.children) |*child| child.deinit(s.gpa);
        s.gpa.free(folder.children);
        for (folder.pictures) |*p| p.deinit(s.gpa);
        s.gpa.free(folder.pictures);
        folder.children = try children.toOwnedSlice(s.gpa);
        folder.pictures = try pictures.toOwnedSlice(s.gpa);
        folder.loaded = true;

        // The next level of folders is listed too, so a folder that holds
        // folders shows its chevron before it is ever opened: one listing
        // each, nothing decoded. The folder itself stays unloaded -- its
        // pictures are listed only when it is opened.
        for (folder.children) |*child| {
            if (child.loaded or child.children.len > 0) continue;
            var sub = scan.list(s.gpa, s.io, child.path) catch continue;
            defer sub.deinit(s.gpa);
            var subs: std.ArrayList(model.Folder) = .empty;
            errdefer subs.deinit(s.gpa);
            for (sub.folders) |name| {
                try subs.append(s.gpa, .{
                    .path = try model.join(s.gpa, child.path, name),
                    .name = try s.gpa.dupe(u8, name),
                    .depth = child.depth + 1,
                });
            }
            child.children = try subs.toOwnedSlice(s.gpa);
        }
    }

    /// The folder changed on disk (a picture went to the bin, a paste
    /// landed): what it holds is read again. The cache keeps what is in
    /// it -- the pictures that remain are keyed by their paths, which
    /// did not change.
    pub fn relist(s: *State) void {
        const folder = s.current orelse return;
        folder.loaded = false;
        s.loadChildren(folder) catch {};
        // The pictures the listing brought are measured like any others.
        for (folder.pictures) |*pic| s.pool.ask(pic.path, pic.path, .measure);
        s.orderChanged();
    }

    /// Shows a folder's pictures.
    fn open(s: *State, folder: *model.Folder) void {
        s.loadChildren(folder) catch {};
        s.current = folder;
        large.close(s);
        // The cache belongs to this folder now: the answers for the old one
        // are dropped when they come back.
        s.shared.clear();
        s.keep.clearRetainingCapacity();
        s.laid_out_for = 0;
        s.last_offset = 0;
        s.scroll_to_top = true;
        // A new folder starts unfiltered; the sort stays as it was.
        s.search.clear();
        s.orderChanged();
        // Every picture's size is read first, so the layout is made once and
        // the gallery does not move under the eye as they are measured.
        for (folder.pictures) |*pic| s.pool.ask(pic.path, pic.path, .measure);
        // The folder is watched from now on: what changes on the disk
        // arrives by itself.
        s.watcher.start(folder.path);
    }

    /// Asks the reader for a folder, and queues it as the new root. The
    /// dialog is modal here, in the middle of a frame: the tree it would
    /// replace is the tree this frame is still walking, so the change
    /// waits for the next one.
    pub fn openFolderDialog(s: *State) void {
        const ask = i18n.strings(s.lang).open_folder;
        if (builtin.os.tag == .windows) {
            const w = s.window orelse return;
            const hwnd = w.hwnd orelse return;
            const picked = win.pickFolder(s.gpa, @ptrCast(hwnd), s.tree.path, ask) orelse return;
            defer s.gpa.free(picked);
            s.queueReroot(picked);
        } else {
            const picked = nanoui.dialog.open(s.gpa, .{
                .title = ask,
                .directories = true,
                .files = false,
                .directory = s.tree.path,
            }) catch return;
            if (picked) |paths| {
                defer nanoui.dialog.freePaths(s.gpa, paths);
                if (paths.len > 0) s.queueReroot(paths[0]);
            }
        }
    }

    /// Holds a chosen folder for the next frame, when no one is walking
    /// the tree it replaces.
    fn queueReroot(s: *State, path: []const u8) void {
        if (s.reroot_pending) |old| s.gpa.free(old);
        s.reroot_pending = s.gpa.dupe(u8, path) catch null;
    }

    /// Makes another folder the root: the tree is read from it anew, the
    /// gallery shows what it holds, and the watcher moves with it.
    pub fn reroot(s: *State, path: []const u8) void {
        const tree = &s.tree;
        if (std.mem.eql(u8, tree.path, path)) return;
        for (tree.children) |*child| child.deinit(s.gpa);
        s.gpa.free(tree.children);
        for (tree.pictures) |*p| p.deinit(s.gpa);
        s.gpa.free(tree.pictures);
        tree.children = &.{};
        tree.pictures = &.{};
        tree.loaded = false;
        tree.expanded = false;
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

    /// The sort or the search changed: the order follows, from the top,
    /// and none of it costs a decode -- the cache is keyed by path.
    pub fn orderChanged(s: *State) void {
        s.order_version += 1;
        s.laid_out_for = 0;
        s.scroll_to_top = true;
    }

    /// Dark or light, as the eye prefers. The window's surface is told
    /// directly; the setting rides along in the config file.
    pub fn setDark(s: *State, value: bool) void {
        s.dark = value;
        if (s.window) |w| {
            if (w.surface) |surface| surface.theme_override = theme.forDark(value);
            w.redraw();
        }
    }

    pub fn toggleDark(s: *State) void {
        s.setDark(!s.dark);
        s.saveSettings();
    }

    /// Writes the settings as they are now: the window's frame, the look,
    /// what the gallery takes in, the language. Called when a setting
    /// changes and when the window closes. A maximized window is recorded
    /// as such, and its frame with it -- the next start would rather open
    /// at its own size than at the screen's.
    pub fn saveSettings(s: *State) void {
        const dir = s.settings_dir orelse return;
        var st: config.Settings = .{ .dark = s.dark, .recursive = s.recursive, .lang = s.lang, .root = s.tree.path };
        if (s.window) |w| {
            const f = w.frame();
            st.x = f.x;
            st.y = f.y;
            st.width = f.width;
            st.height = f.height;
            if (builtin.os.tag == .windows) {
                if (w.hwnd) |hwnd| st.maximized = win.zoomed(@ptrCast(hwnd));
            }
        }
        config.save(s.io, dir, st);
    }

    /// The folder above the one shown.
    pub fn goUp(s: *State) void {
        const current = s.current orelse return;
        if (current.depth == 0) return;
        const parent_path = model.parentOf(current.path) orelse return;
        var found: ?*model.Folder = null;
        s.findChild(&s.tree, parent_path, &found);
        if (found) |parent| s.open(parent);
    }

    fn findChild(s: *State, from: *model.Folder, path: []const u8, found: *?*model.Folder) void {
        for (from.children) |*child| {
            if (std.mem.eql(u8, child.path, path)) {
                found.* = child;
                return;
            }
            s.findChild(child, path, found);
        }
    }

    /// The pictures the gallery shows: the folder's own, filtered by the
    /// search and sorted by the key. Pointers into the folder's list, so
    /// the pictures and their paths are neither copied nor changed.
    fn rebuildOrder(s: *State) void {
        const folder = s.current orelse return;
        const query = s.search.text();

        var list: std.ArrayList(*model.Picture) = .empty;
        defer list.deinit(s.gpa);
        for (folder.pictures) |*pic| {
            if (model.matchesFold(pic.name, query)) {
                list.append(s.gpa, pic) catch return;
            }
        }

        const Ctx = struct {
            shared: *thumbs.Shared,
            key: SortKey,
            ascending: bool,
            fn lessThan(ctx: @This(), a: *model.Picture, b: *model.Picture) bool {
                const sa = ctx.shared.measuredOf(a.path) orelse thumbs.Measured{ .aspect = 1 };
                const sb = ctx.shared.measuredOf(b.path) orelse thumbs.Measured{ .aspect = 1 };
                const order: std.math.Order = switch (ctx.key) {
                    .name => model.orderFold(a.name, b.name),
                    .time => std.math.order(sa.mtime, sb.mtime),
                    .size => std.math.order(sa.bytes, sb.bytes),
                    .pixels => std.math.order(sa.pixels, sb.pixels),
                    .stars => std.math.order(sa.rating, sb.rating),
                };
                // Pictures that tie go by their name, whatever the direction.
                if (order == .eq) return model.orderFold(a.name, b.name) == .lt;
                return if (ctx.ascending) order == .lt else order == .gt;
            }
        };
        std.mem.sort(*model.Picture, list.items, Ctx{ .shared = &s.shared, .key = s.sort, .ascending = s.sort_ascending }, Ctx.lessThan);

        const shown = s.gpa.dupe(*model.Picture, list.items) catch return;
        s.gpa.free(s.shown);
        s.shown = shown;
        s.shown_version = s.order_version;
    }

    /// The pictures' places. Made once their sizes are known, and again when
    /// the window is another width or the order changed: the gallery never
    /// moves under the eye while it stays.
    pub fn updateLayout(s: *State, width: f32) void {
        const current = s.current orelse return;
        const pictures = current.pictures;
        if (s.aspects.len != pictures.len) {
            s.gpa.free(s.aspects);
            s.aspects = s.gpa.alloc(f32, pictures.len) catch &.{};
        }
        if (s.shown_version != s.order_version) s.rebuildOrder();
        if (width == s.laid_out_for and s.layout.placements.len == s.shown.len) return;
        s.laid_out_for = width;

        for (s.shown, 0..) |pic, i| {
            s.aspects[i] = s.shared.aspectOf(pic.path) orelse 1;
        }
        const layout = masonry.compute(s.gpa, s.aspects[0..s.shown.len], width, .{
            .columns = max_columns,
            .gap = gap,
            .padding = padding,
        }) catch return;
        s.layout.deinit(s.gpa);
        s.layout = layout;
    }

    pub fn view(s: *State, c: *ui.Context) void {
        // Dark or light, wherever the eye is.
        if (c.shortcut(.{ .key = 'd', .ctrl = true })) {
            s.toggleDark();
            s.saveSettings();
        }
        // A new root first, if one was picked: the folder it replaced
        // has no business being listed again.
        if (s.reroot_pending) |path| {
            s.reroot_pending = null;
            s.reroot(path);
            s.gpa.free(path);
        }
        if (s.relist_pending) {
            s.relist_pending = false;
            s.relist();
        }
        if (s.large != null) {
            large.view(s, c);
            return;
        }
        ui.row(c, .{ .width = .fill, .height = .fill });
        s.viewTree(c);
        gallery.view(s, c);
        ui.end(c);
        // The overlays hang off the window itself: an absolute box inside
        // them positions against the window, not against a column.
        menu.view(s, c);
        if (s.settings_open) s.viewSettings(c);
    }

    /// The folders, down the left.
    /// The sidebar, the way nanomon draws one: the name on top, the folders
    /// as rows with their counts, and the watch's status at the bottom.
    fn viewTree(s: *State, c: *ui.Context) void {
        const k = theme.colors(s.dark);
        const tr = i18n.strings(s.lang);
        const side = ui.div(c).column().w(214).hFull().bg(k.sidebar).px(10).gap(2);
        defer side.end();
        {
            const top = ui.div(c).row().wFull().h(52).itemsCenter().gap(8).px(6);
            defer top.end();
            // The mark, the app's own: a photograph on amber. It closes
            // before the name, which is no child of a twenty-two point
            // box, however fond of it the mark may be.
            {
                const mark = ui.div(c).row().w(22).h(22).center().rounded(6).bg(k.accent);
                defer mark.end();
                ui.icon(c, "photo", .{ .size = 12, .color = k.page });
            }
            ui.text(c, "NanoFlowVision", .{ .size = 13, .weight = .bold, .color = k.text });
        }
        sideSection(c, k, tr.folders);
        ui.scroll(c, .{ .width = .fill, .height = .fill, .gap = 2 });
        s.viewFolder(c, k, &s.tree);
        ui.end(c);
        // What the gallery takes in, whether the folder is watched, and
        // the way to another folder altogether.
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
        {
            const row = ui.div(c).row().wFull().gap(7).itemsCenter().px(8).pb(2);
            defer row.end();
            _ = c.leaf(.{ .width = .{ .px = 7 }, .height = .{ .px = 7 }, .radius = 3.5, .background = k.green }, .none, null);
            ui.text(c, tr.watching, .{ .size = 11, .color = k.secondary });
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

    /// A sidebar section's name.
    fn sideSection(c: *ui.Context, k: theme.Colors, name: []const u8) void {
        const d = ui.div(c).row().wFull().px(8).pt(14).pb(4);
        defer d.end();
        ui.text(c, name, .{ .size = 11, .weight = .semibold, .color = k.tertiary });
    }

    fn viewFolder(s: *State, c: *ui.Context, k: theme.Colors, folder: *model.Folder) void {
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
            if (child.expanded) s.viewFolder(c, k, child);
        }
    }
    /// The settings, on a card over the page: the language, the look, and
    /// what the gallery takes in. A change lands in the settings file the
    /// moment it is made.
    fn viewSettings(s: *State, c: *ui.Context) void {
        const k = theme.colors(s.dark);
        const tr = i18n.strings(s.lang);
        // The layer covers the window; the sheet under the card takes the
        // clicks that miss it; the card is a flex child, centered.
        const layer = ui.div(c).absolute().offset(0, 0).sizeFull();
        defer layer.end();
        {
            const sheet = ui.div(c).absolute().offset(0, 0).sizeFull().control();
            defer sheet.end();
            if (sheet.clicked()) {
                s.settings_open = false;
                c.changed = true;
            }
        }
        const center = ui.div(c).row().sizeFull().itemsCenter().justifyCenter();
        defer center.end();
        const card = ui.div(c).column().w(380).p(16).gap(12).rounded(10).bg(k.card).border(k.border).shadowMd();
        defer card.end();
        ui.text(c, tr.settings, .{ .size = 15, .weight = .bold, .color = k.text });

        // The language, each written as its speakers write it.
        ui.row(c, .{ .width = .{ .px = 348 }, .gap = 10, .align_items = .center });
        ui.text(c, tr.language, .{ .size = 13, .color = k.text });
        ui.spacer(c);
        const lang_names = [_][]const u8{ i18n.ownName(.en), i18n.ownName(.zh) };
        var li: usize = @backingInt(s.lang);
        if (ui.segmented(c, &lang_names, &li)) {
            s.lang = @fromBackingInt(@intCast(li));
            s.saveSettings();
            c.changed = true;
        }
        ui.end(c);

        if (ui.checkbox(c, tr.dark_mode, &s.dark)) {
            s.setDark(s.dark);
            s.saveSettings();
        }
        if (ui.checkbox(c, tr.subfolders, &s.recursive)) {
            if (s.current) |folder| folder.loaded = false;
            s.relist_pending = true;
            s.saveSettings();
        }

        ui.row(c, .{ .width = .{ .px = 348 }, .align_items = .center });
        ui.spacer(c);
        if (ui.button(c, tr.close, .{ .size = 13 }).clicked) {
            s.settings_open = false;
            c.changed = true;
        }
        ui.end(c);
    }
};
