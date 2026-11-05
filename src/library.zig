//! The folder on disk, read into the tree: its subfolders, its pictures,
//! and the order the gallery shows them in. The state owns these; this
//! file only knows how to read a folder and how to sort what it holds.

const std = @import("std");

const app = @import("app.zig");
const model = @import("model.zig");
const scan = @import("scan.zig");
const thumbs = @import("thumbs.zig");
const masonry = @import("masonry.zig");
const shell = @import("shell.zig");
const large = @import("large.zig");
const select = @import("select.zig");

/// The room between and around the pictures, and the most columns.
const gap: f32 = 6;
const padding: f32 = 16;
const max_columns: usize = 12;

pub fn loadChildren(s: *app.State, folder: *model.Folder) !void {
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
    /// it, keyed by paths that did not change.

pub fn orderChanged(s: *app.State) void {
        s.order_version += 1;
        s.laid_out_for = 0;
        s.scroll_to_top = true;
    }

    /// Dark or light, as the eye prefers. The window's surface is told
    /// directly; the setting rides along in the config file.

pub fn rebuildOrder(s: *app.State) void {
        const folder = s.current orelse return;
        const query = s.search.text();

        var list: std.ArrayList(*model.Picture) = .empty;
        defer list.deinit(s.gpa);
        for (folder.pictures) |*pic| {
            if (s.filter_stars > 0) {
                // The filter says how many stars a picture carries: what
                // is not measured yet says nothing, and waits outside.
                const said = s.shared.measuredOf(pic.path) orelse continue;
                if (said.rating < @as(i8, @intCast(s.filter_stars))) continue;
            }
            if (model.matchesFold(pic.name, query)) {
                list.append(s.gpa, pic) catch return;
            }
        }

        const Ctx = struct {
            shared: *thumbs.Shared,
            key: app.SortKey,
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
        // The folder may have been listed again: the choice keeps what
        // the disk still holds, and lets the rest go.
        s.select.keepAlive(folder.pictures);
    }

    /// The pictures' places, made once their sizes are known and again
    /// when the window or the order changes: never a move under the eye.
pub fn updateLayout(s: *app.State, width: f32) void {
        const current = s.current orelse return;
        const pictures = current.pictures;
        if (s.aspects.len != pictures.len) {
            s.gpa.free(s.aspects);
            s.aspects = s.gpa.alloc(f32, pictures.len) catch &.{};
        }
        if (s.shown_version != s.order_version) rebuildOrder(s);
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
        // The density aims the columns at 128, 256 or 512 points tall.
        const layout = masonry.compute(s.gpa, s.aspects[0..s.shown.len], width, .{
            .columns = max_columns,
            .target = s.density.row(),
            .gap = gap,
            .padding = padding,
        }) catch return;
        s.layout.deinit(s.gpa);
        s.layout = layout;
    }
