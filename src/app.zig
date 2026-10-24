//! The app: the tree o folders, the gallery of pictures, and the one shown large.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const masonry = @import("masonry.zig");
const model = @import("model.zig");
const scan = @import("scan.zig");
const thumbs = @import("thumbs.zig");
const large = @import("large.zig");
const menu = @import("menu.zig");
const ops = @import("ops.zig");
const config = @import("config.zig");
const watch = @import("watch.zig");

/// How much room between and around the pictures.
const gap: f32 = 8;
const padding: f32 = 12;
/// How many columns the gallery has at most.
const max_columns: usize = 6;
/// How far above and below the window pictures are built, in windows.
const build_margin: f32 = 0.15;
/// How far ahead the thumbnails are asked for, in windows.
const prefetch_ahead: f32 = 2.0;
/// How far behind, in windows: less, because the view came from there.
const prefetch_behind: f32 = 0.5;

/// What the gallery sorts by.
pub const SortKey = enum { name, time, size, pixels, stars };

/// The words on the sort control, in the order of `SortKey`.
const sort_labels = [_][]const u8{ "Name", "Date", "Size", "Pixels", "Stars" };

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
    /// The folder the settings are kept in, owned.
    settings_dir: ?[]u8 = null,
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

        // The old goes out, the new goes in.
        for (folder.children) |*child| child.deinit(s.gpa);
        s.gpa.free(folder.children);
        for (folder.pictures) |*p| p.deinit(s.gpa);
        s.gpa.free(folder.pictures);
        folder.children = try children.toOwnedSlice(s.gpa);
        folder.pictures = try pictures.toOwnedSlice(s.gpa);
        folder.loaded = true;
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

    /// The sort or the search changed: the order follows, from the top,
    /// and none of it costs a decode -- the cache is keyed by path.
    pub fn orderChanged(s: *State) void {
        s.order_version += 1;
        s.laid_out_for = 0;
        s.scroll_to_top = true;
    }

    /// Dark or light, as the eye prefers. The window's surface is told
    /// directly; the setting rides along in the config file.
    pub fn toggleDark(s: *State) void {
        s.dark = !s.dark;
        if (s.window) |w| {
            if (w.surface) |surface| surface.theme_override = if (s.dark) ui.Theme.dark_theme else null;
            w.redraw();
        }
    }

    /// The folder above the one shown.
    fn goUp(s: *State) void {
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
    fn updateLayout(s: *State, width: f32) void {
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
        if (c.shortcut(.{ .key = 'd', .ctrl = true })) s.toggleDark();
        if (s.relist_pending) {
            s.relist_pending = false;
            s.relist();
        }
        if (s.large != null) {
            large.view(s, c);
            return;
        }
        ui.row(c, .{ .width = .fill, .height = .fill });
        defer ui.end(c);
        s.viewTree(c);
        s.viewGallery(c);
    }

    /// The folders, down the left.
    fn viewTree(s: *State, c: *ui.Context) void {
        const th = c.theme;
        ui.column(c, .{
            .width = .{ .px = 220 },
            .height = .fill,
            .padding = .{ .top = 14, .left = 10, .right = 10, .bottom = 14 },
            .gap = 4,
            .background = th.surface,
        });
        defer ui.end(c);
        ui.text(c, "NanoFlowVision", .{ .size = 15, .weight = .bold });
        ui.label(c, "folders");
        if (ui.checkbox(c, "Subfolders", &s.recursive)) {
            if (s.current) |folder| folder.loaded = false;
            s.relist_pending = true;
        }
        ui.scroll(c, .{ .width = .fill, .height = .fill, .gap = 2 });
        defer ui.end(c);
        s.viewFolder(c, &s.tree);
    }

    fn viewFolder(s: *State, c: *ui.Context, folder: *model.Folder) void {
        const th = c.theme;
        for (folder.children) |*child| {
            const selected = s.current == child;
            const fg = if (selected) th.accent_text else th.text;
            var row = ui.div(c).row().wFull().h(26).gap(6).itemsCenter().rounded(6);
            row = if (selected) row.bg(th.accent) else row.hover(th.surface_hover);
            row = row.pl(6 + @as(f32, @floatFromInt(child.depth)) * 12);
            if (row.clicked()) {
                s.open(child);
                // The folders inside it show, now that it is open.
                child.expanded = true;
            }
            ui.icon(c, "folder", .{ .size = 12, .frame = 15, .color = fg });
            ui.text(c, child.name, .{ .size = 13, .color = fg });
            ui.spacer(c);
            if (child.pictures.len > 0) {
                ui.textf(c, .{ .size = 11, .color = fg }, "{d}", .{child.pictures.len});
            }
            row.end();
            if (child.expanded) s.viewFolder(c, child);
        }
    }

    /// The gallery, on the right.
    fn viewGallery(s: *State, c: *ui.Context) void {
        ui.column(c, .{ .grow = 1, .width = .fill, .height = .fill });
        defer ui.end(c);
        s.viewToolbar(c);
        s.viewGrid(c);
        menu.view(s, c);
    }

    fn viewToolbar(s: *State, c: *ui.Context) void {
        const th = c.theme;
        const current = s.current;
        ui.row(c, .{
            .width = .fill,
            .height = .{ .px = 46 },
            .padding = .{ .left = 12, .right = 14 },
            .gap = 10,
            .align_items = .center,
            .background = th.surface,
        });
        defer ui.end(c);
        if (ui.button(c, "Up", .{ .variant = .ghost, .size = 13 }).clicked) s.goUp();
        if (current) |folder| {
            ui.text(c, folder.name, .{ .size = 14, .weight = .semibold });
        }
        ui.spacer(c);
        // The search: what matches stays, the rest waits its turn.
        const field = ui.textField(c, &s.search, .{ .placeholder = "Search…", .width = .{ .px = 190 }, .size = 13 });
        if (field.changed) s.orderChanged();
        // The sort, and the way it goes.
        var selected: usize = @backingInt(s.sort);
        if (ui.segmented(c, &sort_labels, &selected)) {
            s.sort = @fromBackingInt(@intCast(selected));
            s.sort_ascending = s.sort == .name;
            s.orderChanged();
        }
        if (ui.button(c, if (s.sort_ascending) "↑" else "↓", .{ .variant = .ghost, .size = 13 }).clicked) {
            s.sort_ascending = !s.sort_ascending;
            s.orderChanged();
        }
        if (current) |folder| {
            if (s.shown.len == folder.pictures.len) {
                ui.textf(c, .{ .size = 12, .color = th.muted }, "{d} pictures", .{folder.pictures.len});
            } else {
                ui.textf(c, .{ .size = 12, .color = th.muted }, "{d} of {d} pictures", .{ s.shown.len, folder.pictures.len });
            }
        }
    }

    /// The pictures, in columns: only those in view are built.
    fn viewGrid(s: *State, c: *ui.Context) void {
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
            ui.label(c, c.print("measuring {d} of {d}…", .{ measured, pictures.len }));
            return;
        }

        s.updateLayout(view_w);

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
            s.viewPicture(c, pic, place);
        }
        // While the pictures on their way are still being decoded, another
        // frame is wanted as soon as each one lands -- the view is a
        // function of the state, and the state is still arriving.
        if (waiting > 0) c.animationFrame();
    }

    fn viewPicture(s: *State, c: *ui.Context, pic: *model.Picture, place: masonry.Placement) void {
        const th = c.theme;
        const box = ui.div(c).absolute().offset(place.x, place.y).w(place.w).h(place.h).rounded(6);
        defer box.end();
        const inter = box.interaction();
        if (inter.double_clicked) {
            large.show(s, pic);
            c.changed = true;
            return;
        }
        // The menu's corner, on hover.
        if (inter.hovered and s.menu_for == null and s.renaming == null) {
            const corner = ui.div(c).absolute().offset(place.w - 36, 6);
            defer corner.end();
            if (ui.button(c, "⋯", .{ .variant = .secondary, .size = 12 }).clicked) {
                s.menu_for = pic;
                s.menu_at = .{
                    .x = s.grid_x + place.x + place.w - 214,
                    .y = s.grid_y + place.y - s.grid_offset + 44,
                    .w = 0,
                    .h = 0,
                };
                c.changed = true;
            }
        }

        const cached = s.shared.get(pic.path);
        if (cached) |known| {
            if (known.thumb) |pixels| {
                const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
                _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
                return;
            }
        }
        // Not ready yet: its place is shown.
        _ = c.leaf(.{ .width = .fill, .height = .fill, .radius = 6, .background = th.surface }, .none, null);
    }
};
