//! The app: the tree of folders, the gallery of pictures, and the one shown large.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const masonry = @import("masonry.zig");
const model = @import("model.zig");
const scan = @import("scan.zig");
const thumbs = @import("thumbs.zig");

/// How much room between and around the pictures.
const gap: f32 = 8;
const padding: f32 = 12;
/// How many points of pictures to build above and below the window.
const overscan: f32 = 600;
/// How many columns the gallery has at most.
const max_columns: usize = 6;

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
    /// The pictures' sizes, as far as they are known.
    aspects: []f32 = &.{},
    /// The change counter the layout was last made at.
    laid_out_at: u64 = 0,
    /// The width the layout was last made for.
    laid_out_for: f32 = 0,
    /// The picture shown large, if any.
    large: ?usize = null,
    /// The cache key of the picture shown large.
    large_key: ?[]u8 = null,
    /// The paths on screen, so their thumbnails are kept.
    visible: std.ArrayList([]const u8) = .empty,
    /// Where the first picture on screen was drawn: a test clicks it.
    first_picture: ?ui.Rect = null,

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
        try s.pool.start(gpa, io, &s.shared);
        s.loadChildren(&s.tree) catch {};
        s.current = &s.tree;
        return s;
    }

    pub fn deinit(s: *State) void {
        s.pool.stop();
        s.pool.window = null;
        s.shared.deinit();
        s.tree.deinit(s.gpa);
        s.layout.deinit(s.gpa);
        s.gpa.free(s.aspects);
        if (s.large_key) |key| s.gpa.free(key);
        s.visible.deinit(s.gpa);
        s.gpa.destroy(s);
    }

    /// The folders inside a folder, read the first time it is opened.
    fn loadChildren(s: *State, folder: *model.Folder) !void {
        if (folder.loaded) return;
        var listing = try scan.list(s.gpa, s.io, folder.path);
        defer listing.deinit(s.gpa);

        const children = try s.gpa.alloc(model.Folder, listing.folders.len);
        for (children) |*child| child.* = .{ .path = &.{}, .name = &.{} };
        errdefer {
            for (children) |*child| child.deinit(s.gpa);
            s.gpa.free(children);
        }
        for (listing.folders, 0..) |name, i| {
            children[i] = .{
                .path = try model.join(s.gpa, folder.path, name),
                .name = try s.gpa.dupe(u8, name),
                .depth = folder.depth + 1,
            };
        }

        const pictures = try s.gpa.alloc(model.Picture, listing.pictures.len);
        for (pictures) |*pic| pic.* = .{ .path = &.{}, .name = &.{} };
        errdefer {
            for (pictures) |*pic| pic.deinit(s.gpa);
            s.gpa.free(pictures);
        }
        for (listing.pictures, 0..) |name, i| {
            pictures[i] = .{
                .path = try model.join(s.gpa, folder.path, name),
                .name = try s.gpa.dupe(u8, name),
            };
        }

        folder.children = children;
        folder.pictures = pictures;
        folder.loaded = true;
    }

    /// Shows a folder's pictures.
    fn open(s: *State, folder: *model.Folder) void {
        s.loadChildren(folder) catch {};
        s.current = folder;
        s.closeLarge();
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

    fn closeLarge(s: *State) void {
        s.large = null;
        if (s.large_key) |key| {
            s.gpa.free(key);
            s.large_key = null;
        }
    }

    /// The pictures' places, made again when their sizes or the width change.
    fn updateLayout(s: *State, width: f32) void {
        const current = s.current orelse return;
        const pictures = current.pictures;
        if (s.aspects.len != pictures.len) {
            s.gpa.free(s.aspects);
            s.aspects = s.gpa.alloc(f32, pictures.len) catch &.{};
        }
        const changed = s.shared.changeCounter();
        if (changed == s.laid_out_at and width == s.laid_out_for and s.layout.placements.len == pictures.len) return;
        s.laid_out_at = changed;
        s.laid_out_for = width;

        for (pictures, 0..) |*pic, i| {
            s.aspects[i] = 1;
            if (s.shared.get(pic.path)) |cached| {
                if (cached.measured) s.aspects[i] = cached.aspect;
            }
        }
        const layout = masonry.compute(s.gpa, s.aspects, width, .{
            .columns = max_columns,
            .gap = gap,
            .padding = padding,
        }) catch return;
        s.layout.deinit(s.gpa);
        s.layout = layout;
    }

    pub fn view(s: *State, c: *ui.Context) void {
        if (s.large) |index| {
            s.viewLarge(c, index);
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
            ui.spacer(c);
            ui.textf(c, .{ .size = 12, .color = th.muted }, "{d} pictures", .{folder.pictures.len});
        }
    }

    /// The pictures, in columns: only those in view are built.
    fn viewGrid(s: *State, c: *ui.Context) void {
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
        const offset = c.scroll.get(id) orelse 0;

        s.updateLayout(view_w);

        // The room the pictures take, so the grid scrolls.
        _ = c.leaf(.{ .width = .fill, .height = .{ .px = s.layout.height } }, .none, null);

        s.visible.clearRetainingCapacity();
        s.first_picture = null;
        const current = s.current orelse return;
        for (current.pictures, 0..) |*pic, i| {
            const place = s.layout.placements[i];
            if (!place.inView(offset - overscan, offset + view_h + overscan)) continue;
            s.visible.append(s.gpa, pic.path) catch {};
            if (s.first_picture == null) {
                s.first_picture = .{
                    .x = grid_x + place.x,
                    .y = grid_y + place.y - offset,
                    .w = place.w,
                    .h = place.h,
                };
            }
            s.viewPicture(c, pic, place, i);
        }
        // The thumbnails on screen are kept, however old they are.
        s.shared.trim(s.visible.items);
    }

    fn viewPicture(s: *State, c: *ui.Context, pic: *model.Picture, place: masonry.Placement, index: usize) void {
        const th = c.theme;
        const box = ui.div(c).absolute().offset(place.x, place.y).w(place.w).h(place.h).rounded(6);
        defer box.end();
        if (box.interaction().double_clicked) {
            s.showLarge(index);
            c.changed = true;
            return;
        }

        const cached = s.shared.get(pic.path);
        if (cached) |known| {
            if (known.thumb) |pixels| {
                const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
                _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
                return;
            }
        }
        // Not ready yet: ask the workers, and show its place.
        s.pool.ask(pic.path, pic.path, .measure);
        s.pool.ask(pic.path, pic.path, .picture);
        _ = c.leaf(.{ .width = .fill, .height = .fill, .radius = 6, .background = th.surface }, .none, null);
    }

    /// Shows a picture large.
    pub fn showLarge(s: *State, index: usize) void {
        const current = s.current orelse return;
        if (index >= current.pictures.len) return;
        s.closeLarge();
        const key = thumbs.largeKey(s.gpa, current.pictures[index].path) catch return;
        s.large_key = key;
        s.large = index;
        s.pool.ask(current.pictures[index].path, key, .large);
    }

    /// The picture, large, over a dark room.
    fn viewLarge(s: *State, c: *ui.Context, index: usize) void {
        const th = c.theme;
        const current = s.current orelse return;
        if (index >= current.pictures.len) {
            s.closeLarge();
            return;
        }
        if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
            s.closeLarge();
            return;
        }

        const back = ui.div(c).sizeFull().bg(th.background);
        defer back.end();
        if (back.clicked()) {
            s.closeLarge();
            return;
        }

        const key = s.large_key orelse return;
        s.pool.ask(current.pictures[index].path, key, .large);
        const known = s.shared.get(key) orelse return;
        const pixels = known.thumb orelse {
            ui.text(c, "loading…", .{ .size = 14, .color = th.muted });
            return;
        };

        // The picture, as large as the window allows.
        const room_w = c.size.w - 48;
        const room_h = c.size.h - 48;
        const scale = @min(
            room_w / @as(f32, @floatFromInt(pixels.w)),
            room_h / @as(f32, @floatFromInt(pixels.h)),
        );
        const w = @as(f32, @floatFromInt(pixels.w)) * scale;
        const h = @as(f32, @floatFromInt(pixels.h)) * scale;
        const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
        const frame = ui.div(c)
            .absolute()
            .offset(@max(0, (c.size.w - w) / 2), @max(0, (c.size.h - h) / 2))
            .w(w)
            .h(h)
            .shadowMd();
        defer frame.end();
        _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
    }
};
