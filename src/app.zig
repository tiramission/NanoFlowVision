//! The app: the tree o folders, the gallery of pictures, and the one shown large.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const masonry = @import("masonry.zig");
const model = @import("model.zig");
const select = @import("select.zig");
const dialogs = @import("dialogs.zig");
const thumbs = @import("thumbs.zig");
const large = @import("large.zig");
const menu = @import("menu.zig");
const gallery = @import("gallery.zig");
const rail = @import("rail.zig");
const shell = @import("shell.zig");
const settings = @import("settings.zig");
const statusbar = @import("statusbar.zig");
const screen = @import("screen.zig");
const fullscreen = @import("fullscreen.zig");
const library = @import("library.zig");
const ops = @import("ops.zig");
const config = @import("config.zig");
const watch = @import("watch.zig");
const i18n = @import("i18n.zig");
const theme = @import("theme.zig");
const nfd = @import("nfd");
const win = @import("win.zig");

/// How much room between and around the pictures: 6 between neighbours,
/// 16 around (docs/redesign/02-visual.md).
const gap: f32 = 6;
const padding: f32 = 16;
/// The ceiling the columns never pass; the density sets the target.
const max_columns: usize = 12;

/// A window's rectangle in points: the frame the settings keep
/// while a full screen stands.

/// How the large view sizes the picture: fitted in the room, filling it
/// (cropped), at its own pixels, or wherever the wheel left it.
pub const ZoomMode = enum { fit, fill, actual, free };

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
    /// The tree's keyboard row, when the tree has the focus (Tab hands
    /// it over and back). Null is the grid's.
    tree_focus: ?*model.Folder = null,
    /// Whether the navigation column stands (⌘B folds it away).
    rail_visible: bool = true,
    /// The folder the gallery shows.
    current: ?*model.Folder = null,
    /// Where the pictures sit.
    layout: masonry.Layout = .{},
    aspects: []f32 = &.{},
    /// The width the layout was last made for.
    laid_out_for: f32 = 0,
    /// The picture shown large, if any.
    large: ?*model.Picture = null,
    large_key: ?[]u8 = null,
    /// The thumbnails the cache should keep.
    keep: std.ArrayList([]const u8) = .empty,
    /// Where the first picture on screen was drawn.
    first_picture: ?ui.Rect = null,
    /// Where the gallery was last scrolled to.
    last_offset: f32 = 0,
    /// How many pictures were built in the last frame.
    built: usize = 0,
    /// Whether the gallery must go back to the top.
    scroll_to_top: bool = false,
    /// What the gallery sorts by, and which way it goes.
    sort: SortKey = .name,
    sort_ascending: bool = true,
    search: ui.TextBuffer = .{},
    /// What the gallery shows: filtered by the search, sorted. Pointers
    /// into the folder, nothing copied.
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
    menu_at: ui.Rect = .{},
    /// The rename box, for the picture being renamed; the flag is the
    /// kit dialog's own, outliving `renaming` by its exit frames.
    renaming: ?*model.Picture = null,
    rename_field: ui.TextBuffer = .{},
    rename_open: bool = false,
    recursive: bool = false,
    dark: bool = false,
    /// The folder being watched for changes.
    watcher: watch.Watcher = undefined,
    /// The folder changed on disk: it is listed again before the frame.
    relist_pending: bool = false,
    // A folder dialog was asked for: the loop opens it after the frame.
    dialog_pending: bool = false,
    /// A folder the reader picked, waiting for the frame to end: the
    /// frame is still walking the old tree, not the time to free it.
    reroot_pending: ?[]u8 = null,
    /// The folder the settings are kept in, owned.
    settings_dir: ?[]u8 = null,
    /// A snapshot or a script run: its window's seat is not remembered.
    snapshot_run: bool = false,
    /// The interface's language, and whether the settings panel is open.
    lang: i18n.Lang = .en,
    settings_open: bool = false,
    /// How the room is lit, how big the pictures are, and whether the
    /// interface skips its fades.
    appearance: config.Appearance = .auto,
    density: config.Density = .medium,
    reduce_motion: bool = false,
    /// Whether the unchosen tiles stand back while a choice stands.
    dim_unselected: bool = true,
    /// The rename said a taken name: the box stays and says so.
    rename_error: bool = false,
    /// How wide the navigation column is, 200 to 360.
    rail_w: f32 = 240,
    /// The rail's edge is being dragged: the width it lands on is
    /// written once, when the hand lets go. The grab keeps taking hold
    /// from moving anything on its own.
    rail_dragging: bool = false,
    rail_grab: f32 = 0,
    /// The next frame puts the caret in the search box (⌘F).
    focus_search: bool = false,
    /// Where the button that brings the rail back was drawn, while the
    /// rail is folded away.
    rail_toggle_at: ui.Rect = .{},
    /// The system appearance was last asked then (the "follow the
    /// system" setting is in no hurry).
    system_checked: f64 = 0,
    /// When the folder was last listed (the status bar's "3s ago").
    listed_at: f64 = -1,
    /// The command bar's menus, and the buttons they hang from.
    sort_open: bool = false,
    density_open: bool = false,
    filter_open: bool = false,
    /// The more menu: the choice's bulk words, the subfolders, a rescan,
    /// another folder, the settings.
    more_open: bool = false,
    sort_at: ui.Rect = .{},
    density_at: ui.Rect = .{},
    filter_at: ui.Rect = .{},
    more_at: ui.Rect = .{},
    /// Where the search's xmark was drawn (the tests click it there).
    search_clear_at: ui.Rect = .{},
    /// Where the large view's close chip was drawn.
    large_close_at: ui.Rect = .{},
    /// The star filter: 0 says everything, N says N stars and up. The
    /// folders walked form the way back and forward; `keys_open` says
    /// the keyboard's map is up.
    filter_stars: usize = 0,
    history: std.ArrayList([]u8) = .empty,
    history_at: usize = 0,
    keys_open: bool = false,
    /// The history is walking itself: an open() from those keys does
    /// not join the list it is reading.
    nav_lock: bool = false,
    /// What the operations said back, drawn last in the frame.
    toaster: kit.Toaster,
    /// The reader's chosen pictures, keyed by their paths.
    select: select.Select = undefined,
    /// The pictures waiting for the bin's second word: pointers into
    /// the folder's list, which cannot change while the dialog stands.
    confirming_trash: std.ArrayList(*model.Picture) = .empty,
    /// The folder shown could not be read: the dialog says so, over an
    /// empty page, until another folder opens.
    folder_broken: bool = false,
    /// What the window's title is currently saying about the measuring:
    /// null is the plain name. Only the changes reach the window.
    title_percent: ?usize = null,
    /// The large view's zoom: the mode it is in, what the frame draws
    /// (points per picture pixel), and where it is headed (null fits).
    /// They differ while the easing runs; anything that must stay put
    /// under the pointer reads `zoom`, never the target. `anchor` is the
    /// picture-space point (0..1) that stays under `anchor_mouse`.
    zoom_mode: ZoomMode = .fit,
    zoom: f32 = 1,
    zoom_target: ?f32 = null,
    /// Where the picture sits in the room, in points from its own centre.
    /// Derived from the anchor every frame, so it follows the zoom that
    /// is actually drawn.
    pan_tx: f32 = 0,
    pan_ty: f32 = 0,
    /// The picture-space point (0..1 of its width and height) that must
    /// stay under `anchor_mouse`; null means the middle of the picture.
    anchor: ?ui.Point = null,
    anchor_mouse: ui.Point = .{ .x = 0, .y = 0 },
    panning: bool = false,
    last_mouse_x: f32 = 0,
    last_mouse_y: f32 = 0,
    /// The window is full screen (or maximized where full screen does
    /// not exist), and the change to apply at the top of the next frame
    /// (a window's style is never changed in the middle of a build).
    fullscreen: bool = false,
    fullscreen_pending: ?bool = null,
    /// When the current full screen began, and when it was last asked
    /// for: the Mac's animation is asynchronous and a second request
    /// would fight it.
    fullscreen_since: f64 = 0,
    fullscreen_at: f64 = 0,
    /// The window as it was before full screen: what the settings keep
    /// (a full-screen frame must never be remembered as the window's).
    frame_before: ?fullscreen.WindowRect = null,
    maximized_before: bool = false,
    /// The chrome has stood back in the full screen: the top bar, the
    /// strip and the zoom chip are on their way out, and the picture
    /// takes the room.
    chrome_hidden: bool = false,
    /// The bars' opacity, eased between 1 and 0 by the same frames that
    /// the fit reads.
    chrome_fade: f32 = 1,
    /// When the chrome last had to be up (an entry, a movement, a key):
    /// the quiet is counted from here.
    chrome_shown_at: f64 = 0,
    idle_mouse_x: f32 = 0,
    idle_mouse_y: f32 = 0,
    /// Whether the large view's panel of facts is open; the strip's cells
    /// and the picture's rectangle this frame (the tests click them, and
    /// hold the point under the pointer to its place).
    info_open: bool = true,
    filmstrip_at: std.ArrayList(ui.Rect) = .empty,
    large_at: ui.Rect = .{},
    /// Where the grid sits, and how far it is scrolled.
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
            .tree = .{ .path = root_path, .name = root_name, .expanded = true },
            .toaster = .{ .gpa = gpa },
            .select = .{ .gpa = gpa },
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
        s.select.deinit();
        s.confirming_trash.deinit(s.gpa);
        s.gpa.free(s.shown);
        s.gpa.free(s.aspects);
        if (s.large_key) |key| s.gpa.free(key);
        if (s.reroot_pending) |path| s.gpa.free(path);
        s.keep.deinit(s.gpa);
        for (s.history.items) |p| s.gpa.free(p);
        s.history.deinit(s.gpa);
        s.toaster.deinit();
        s.filmstrip_at.deinit(s.gpa);
        s.gpa.destroy(s);
    }

    /// The folders inside a folder, and its pictures.
    fn loadChildren(s: *State, folder: *model.Folder) !void {
        return library.loadChildren(s, folder);
    }

    /// The folder changed on disk (a picture went to the bin, a paste
    /// landed): what it holds is read again. The cache keeps what is in
    /// it, keyed by paths that did not change.
    pub fn relist(s: *State) void {
        const folder = s.current orelse return;
        folder.loaded = false;
        s.listed_at = -1;
        if (library.loadChildren(s, folder)) {
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
        if (library.loadChildren(s, folder)) {
            s.folder_broken = false;
        } else |_| {
            // Gone, or never was a folder: the view says so over an
            // empty gallery.
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
        // A new folder starts unfiltered and unchosen; the sort stays.
        s.search.clear();
        s.select.clear();
        shell.noteHistory(s);
        s.listed_at = -1;
        s.orderChanged();
        // Every picture's size is read first, so the layout is made once and
        // the gallery does not move under the eye as they are measured.
        for (folder.pictures) |*pic| s.pool.ask(pic.path, pic.path, .measure);
        // The folder is watched from now on: what changes on the disk
        // arrives by itself.
        s.watcher.start(folder.path);
    }

    /// The sort or the search changed: the order follows, from the top.
    pub fn orderChanged(s: *State) void {
        library.orderChanged(s);
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
            .dim_unselected = s.dim_unselected,
            .rail_w = s.rail_w,
            .recursive = s.recursive,
            .lang = s.lang,
            .root = s.tree.path,
        };
        if (fullscreen.frameForSettings(s)) |f| {
            st.x = f.x;
            st.y = f.y;
            st.width = f.width;
            st.height = f.height;
            if (s.fullscreen) {
                // The full-screen frame is not the window's.
                st.maximized = s.maximized_before;
            } else if (builtin.os.tag == .windows) {
                if (s.window) |w| {
                    if (w.hwnd) |hwnd| st.maximized = win.zoomed(@ptrCast(hwnd));
                }
            }
        }
        config.save(s.io, dir, st);
    }

    /// The pictures the gallery shows: the folder's own, filtered by the
    /// search and sorted by the key. Pointers into the folder's list, so
    /// the pictures and their paths are neither copied nor changed.
    fn rebuildOrder(s: *State) void {
        library.rebuildOrder(s);
    }

    /// The pictures' places, made once their sizes are known and again
    /// when the window or the order changes: never a move under the eye.
    pub fn updateLayout(s: *State, width: f32) void {
        library.updateLayout(s, width);
    }

    pub fn view(s: *State, c: *ui.Context) void {
        // What the settings asked for: no fades, no slides. Said before
        // anything below gets the chance to animate.
        if (s.reduce_motion) c.reduced_motion = true;
        // Tab walks the focus ring (rail, the search field, the grid).
        // A window's events do this before the view sees the key; the
        // offscreen tester does not, so the same step is taken here.
        if (c.input.key == .tab and c.input.ops.len == 0) {
            c.focusCycle(c.input.shift);
            c.input.key = null;
            c.changed = true;
        }
        // The window is changed at the frame's top, never in the middle of
        // a build; and the system's answer is read back once the full
        // screen has had the time to move.
        if (s.fullscreen_pending) |on| {
            s.fullscreen_pending = null;
            fullscreen.apply(s, c, on);
        } else if (s.fullscreen and s.window != null and c.time - s.fullscreen_since > 1.0) {
            if (!screen.isOn(s.window)) fullscreen.apply(s, c, false);
        }
        // Dark or light, wherever the eye is.
        if (c.shortcut(.{ .key = 'd', .ctrl = true })) s.toggleDark();
        // The navigation column, folded away and back.
        if (c.shortcut(.{ .key = 'b', .ctrl = true })) {
            s.rail_visible = !s.rail_visible;
            c.changed = true;
        }
        // The way back and forward along the folders just left, the
        // keyboard's own map, the settings, the folder above, and the
        // rescan -- the map's global line, one keypress each.
        if (c.shortcut(.{ .key = ui.Shortcut.left, .alt = true })) shell.historyStep(s, -1);
        if (c.shortcut(.{ .key = ui.Shortcut.right, .alt = true })) shell.historyStep(s, 1);
        if (c.shortcut(.{ .key = ',', .ctrl = true })) {
            s.settings_open = true;
            c.changed = true;
        }
        if (c.shortcut(.{ .key = ui.Shortcut.up, .ctrl = true })) shell.goUp(s);
        // The search is a keystroke away: the caret goes where the words
        // are typed, and the frame after that draws it.
        if (c.shortcut(.{ .key = 'f', .ctrl = true })) {
            s.focus_search = true;
            c.changed = true;
        }
        if (c.shortcut(.{ .key = 'o', .ctrl = true })) shell.askForFolder(s);
        if (c.input.key == .f5) s.relist_pending = true;
        // Full screen: the whole screen for one photograph.
        if (c.input.key == .f11) fullscreen.toggle(s, c);
        if (comptime builtin.os.tag == .macos) {
            if (c.shortcut(.{ .key = 'f', .cmd = true, .ctrl = true })) fullscreen.toggle(s, c);
        }
        if (c.shortcut(.{ .key = '/', .ctrl = true })) {
            s.keys_open = true;
            c.changed = true;
        }
        if (s.keys_open) dialogs.keysDialog(s, c);
        // The escape that falls all the way down the layers: those below
        // take it first, and when nothing is up it lets go of the choice.
        // Only looked at here, never taken -- taking it would steal it
        // from the layer that owns it.
        const plain_esc = if (c.input.shortcut) |sc| sc.key == ui.Shortcut.escape else false;
        if (plain_esc and
            s.large == null and s.menu_for == null and !s.rename_open and
            s.settings_open == false and s.folder_broken == false and
            s.confirming_trash.items.len == 0 and s.tag_editing == false)
        {
            if (s.select.count() > 0) {
                s.select.clear();
                c.changed = true;
            }
        }
        shell.frameStart(s, c);
        statusbar.title(s, c);
        if (s.large != null) {
            large.view(s, c);
            // The large view was closed: a full screen of the wall is not a
            // mode, so the window comes back with it.
            if (s.large == null and s.fullscreen) s.fullscreen_pending = false;
            s.toaster.view(c);
            return;
        }
        ui.row(c, .{ .width = .fill, .height = .fill });
        if (s.rail_visible) rail.view(s, c);
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
        if (s.folder_broken) dialogs.brokenFolder(s, c);
        if (s.confirming_trash.items.len > 0) dialogs.trashConfirm(s, c);
        s.toaster.view(c);
    }
};
