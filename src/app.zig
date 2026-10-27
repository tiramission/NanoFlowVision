//! The app: the tree o folders, the gallery of pictures, and the one shown large.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const masonry = @import("masonry.zig");
const model = @import("model.zig");
const scan = @import("scan.zig");
const thumbs = @import("thumbs.zig");
const large = @import("large.zig");
const menu = @import("menu.zig");
const gallery = @import("gallery.zig");
const shell = @import("shell.zig");
const settings = @import("settings.zig");
const statusbar = @import("statusbar.zig");
const ops = @import("ops.zig");
const config = @import("config.zig");
const watch = @import("watch.zig");
const i18n = @import("i18n.zig");
const theme = @import("theme.zig");
const nfd = @import("nfd");
const win = @import("win.zig");

/// How much room between and around the pictures: the 4-point grid of
/// the design, with 6 between neighbours (docs/redesign/03-visual.md).
const gap: f32 = 6;
const padding: f32 = 16;
/// How many columns the gallery has at most. The density sets the
/// target row height; this is only the ceiling the columns never pass.
const max_columns: usize = 12;

/// The window's own name, when nothing else is being said in the title.
pub const app_name = "NanoFlowVision";

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
    // A folder dialog was asked for, and the loop is to open it after
    // the frame ends.
    dialog_pending: bool = false,
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
    /// How the room is lit, how big the pictures are, and whether the
    /// interface skips its fades: the settings sheet's three choices.
    appearance: config.Appearance = .auto,
    density: config.Density = .medium,
    reduce_motion: bool = false,
    /// How wide the navigation column is, 200 to 360.
    rail_w: f32 = 240,
    /// The system appearance was last asked at this frame's time, for
    /// the "follow the system" setting, which is in no hurry.
    system_checked: f64 = 0,
    /// When the folder was last listed: the status bar's "3s ago".
    /// Negative until the first frame knows what time it is.
    listed_at: f64 = -1,
    /// The command bar's two menus, and the buttons they hang from.
    sort_open: bool = false,
    density_open: bool = false,
    sort_at: ui.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    density_at: ui.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    /// What the operations said back, drawn last in the frame.
    toaster: kit.Toaster,
    /// The folder shown could not be read: the dialog says so, over an
    /// empty page, until another folder opens.
    folder_broken: bool = false,
    /// What the window's title is currently saying about the measuring:
    /// null is the plain name. Only the changes reach the window.
    title_percent: ?usize = null,
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
            .toaster = .{ .gpa = gpa },
        };
        s.watcher = .{ .app = s, .gpa = gpa };
        try s.pool.start(gpa, io, &s.shared);
        s.open(&s.tree);
        return s;
    }

    pub fn deinit(s: *State) void {
        s.watcher.deinit();
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
        s.toaster.deinit();
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
        s.listed_at = -1;
        if (s.loadChildren(folder)) {
            s.folder_broken = false;
        } else |_| {
            // The folder went away under the eye: the view says so.
            s.folder_broken = true;
        }
        // The pictures the listing brought are measured like any others.
        for (folder.pictures) |*pic| s.pool.ask(pic.path, pic.path, .measure);
        s.orderChanged();
    }

    /// Shows a folder's pictures.
    pub fn open(s: *State, folder: *model.Folder) void {
        if (s.loadChildren(folder)) {
            s.folder_broken = false;
        } else |_| {
            // The folder could not be read -- gone, or never was one. The
            // gallery stands empty and the view says what happened.
            s.folder_broken = true;
        }
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
        s.listed_at = -1;
        s.orderChanged();
        // Every picture's size is read first, so the layout is made once and
        // the gallery does not move under the eye as they are measured.
        for (folder.pictures) |*pic| s.pool.ask(pic.path, pic.path, .measure);
        // The folder is watched from now on: what changes on the disk
        // arrives by itself.
        s.watcher.start(folder.path);
    }

    /// Asks the reader for a folder, and queues it as the new root. The
    /// dialog itself must not open inside the build: `shell.askFolder`
    /// takes the wish and the loop calls back after this frame, from
    /// outside any build, where the dialog can open.
    pub fn openFolderDialog(s: *State) void {
        s.dialog_pending = true;
        nanoui.App.after(0, s, folderDialogFromMain);
    }

    /// Runs the dialog, outside any frame (see `openFolderDialog`).
    fn folderDialogFromMain(ctx: ?*anyopaque) callconv(.c) void {
        const s: *State = @ptrCast(@alignCast(ctx.?));
        if (!s.dialog_pending) return;
        s.dialog_pending = false;
        shell.runFolderDialog(s);
    }

    /// Holds a chosen folder for the next frame, when no one is walking
    /// the tree it replaces.
    pub fn queueReroot(s: *State, path: []const u8) void {
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
        s.setAppearance(if (s.dark) .light else .dark);
    }

    /// Lights the room the way it was asked for. "Auto" reads the
    /// system's own answer; the other two hold it still. The setting is
    /// remembered, so the next start opens the same way.
    pub fn setAppearance(s: *State, want: config.Appearance) void {
        s.appearance = want;
        s.setDark(switch (want) {
            .auto => nanoui.isDark(),
            .light => false,
            .dark => true,
        });
        s.saveSettings();
    }

    /// Says something back to the reader: what an operation did, or how
    /// the grid is now set. Drawn last in the frame, over everything.
    pub fn toast(s: *State, status: kit.Status, title: []const u8) void {
        s.toaster.push(.{ .status = status, .title = title });
    }

    /// The folder could not be read: said in a dialog over the page, with
    /// the way out at hand. The dialog is drawn here, in the frame; the
    /// system dialog it can lead to opens after the frame, as always.
    fn brokenFolderDialog(s: *State, c: *ui.Context) void {
        const tr = i18n.strings(s.lang);
        const d = kit.dialog(c, "folder-broken", &s.folder_broken, .{
            .title = tr.folder_unreadable,
            .description = if (s.current) |f| f.path else "",
            .ok = tr.choose_other_folder,
            .cancel = "",
            .close_button = false,
        }) orelse return;
        if (d.end() == .ok) s.openFolderDialog();
    }

    /// Writes the settings as they are now: the window's frame, the look,
    /// what the gallery takes in, the language. Called when a setting
    /// changes and when the window closes. A maximized window is recorded
    /// as such, and its frame with it -- the next start would rather open
    /// at its own size than at the screen's.
    pub fn saveSettings(s: *State) void {
        const dir = s.settings_dir orelse return;
        var st: config.Settings = .{
            .appearance = s.appearance,
            .density = s.density,
            .reduce_motion = s.reduce_motion,
            .rail_w = s.rail_w,
            .recursive = s.recursive,
            .lang = s.lang,
            .root = s.tree.path,
        };
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

    /// The folder above the one shown: `shell.goUp` walks the tree.

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
        // No room to speak of yet: the window is between sizes, or the
        // grid's box has not been placed this frame. Laying out into
        // nothing would leave a wall of placements with nowhere to stand,
        // so this waits for a width it can use.
        if (width < 2 * padding + 8) return;
        if (width == s.laid_out_for and s.layout.placements.len == s.shown.len) return;
        s.laid_out_for = width;

        for (s.shown, 0..) |pic, i| {
            s.aspects[i] = s.shared.aspectOf(pic.path) orelse 1;
        }
        // The density sets how wide a column is aiming to be: 128, 256
        // or 512 points tall, which is the same thing said as a picture
        // of square proportions.
        const layout = masonry.compute(s.gpa, s.aspects[0..s.shown.len], width, .{
            .columns = max_columns,
            .target = s.density.row(),
            .gap = gap,
            .padding = padding,
        }) catch return;
        s.layout.deinit(s.gpa);
        s.layout = layout;
    }

    pub fn view(s: *State, c: *ui.Context) void {
        // What the settings asked for: no fades, no slides. Said before
        // anything below gets the chance to animate.
        if (s.reduce_motion) c.reduced_motion = true;
        // Dark or light, wherever the eye is.
        if (c.shortcut(.{ .key = 'd', .ctrl = true })) s.toggleDark();
        // "Follow the system" is in no hurry: once a minute is often
        // enough, and the answer rarely changes under anyone.
        if (s.appearance == .auto and c.time - s.system_checked >= 60) {
            s.system_checked = c.time;
            const lit = nanoui.isDark();
            if (lit != s.dark) s.setDark(lit);
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
        // The clock the status bar counts from starts here: "3s" means
        // three seconds since the folder was last listed.
        if (s.listed_at < 0) s.listed_at = c.time;
        statusbar.title(s, c);
        if (s.large != null) {
            large.view(s, c);
            s.toaster.view(c);
            return;
        }
        ui.row(c, .{ .width = .fill, .height = .fill });
        shell.rail(s, c);
        ui.column(c, .{ .grow = 1, .width = .fill, .height = .fill });
        shell.commandBar(s, c);
        statusbar.progress(s, c);
        gallery.view(s, c);
        statusbar.view(s, c);
        ui.end(c);
        ui.end(c);
        // The overlays hang off the window itself: an absolute box inside
        // them positions against the window, not against a column.
        menu.view(s, c);
        if (s.settings_open) settings.view(s, c);
        if (s.folder_broken) s.brokenFolderDialog(c);
        // And what the operations said, over all of it.
        s.toaster.view(c);
    }

};
