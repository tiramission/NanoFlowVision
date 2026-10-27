//! The pictures that are chosen: a set of paths, an anchor and a cursor
//! for the ranges and the keyboard, and the box the hand drags across the
//! grid. The set is keyed by path -- not by index -- so what a rename and
//! a rescan leave behind stays chosen, and what a new folder brings
//! starts unchosen.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const model = @import("model.zig");

pub const Select = struct {
    gpa: std.mem.Allocator,
    /// The chosen pictures' paths, owned, as a set: no order, no repeats.
    set: std.StringHashMapUnmanaged(void) = .empty,
    /// Where a range grows from: the index in the gallery's shown list of
    /// the last single pick. Null when nothing is anchored.
    anchor: ?usize = null,
    /// Where the keyboard is: an index in the shown list. Null while the
    /// grid has the reader's whole attention and no one has walked it.
    cursor: ?usize = null,
    /// The box the hand is dragging across the grid, in the coordinates
    /// the layout speaks (x, y from the grid's origin): null unless the
    /// hand is between a press and its release.
    marquee: ?ui.Rect = null,
    /// Where the marquee began, so dragging back up makes a box all the
    /// same; kept apart from `marquee` because the box itself is what a
    /// test reads.
    marquee_from: ui.Point = .{ .x = 0, .y = 0 },

    pub fn deinit(s: *Select) void {
        s.clearSet();
        s.set.deinit(s.gpa);
    }

    fn clearSet(s: *Select) void {
        var it = s.set.keyIterator();
        while (it.next()) |key| s.gpa.free(key.*);
        s.set.clearRetainingCapacity();
    }

    /// Nothing is chosen: a new folder, or the escape that falls all the
    /// way down. The cursor goes with it -- nothing points at anything.
    pub fn clear(s: *Select) void {
        s.clearSet();
        s.anchor = null;
        s.cursor = null;
        s.marquee = null;
    }

    pub fn count(s: *const Select) usize {
        return s.set.count();
    }

    pub fn has(s: *const Select, path: []const u8) bool {
        return s.set.contains(path);
    }

    fn take(s: *Select, path: []const u8) void {
        const owned = s.gpa.dupe(u8, path) catch return;
        s.set.put(s.gpa, owned, {}) catch s.gpa.free(owned);
    }

    fn drop(s: *Select, path: []const u8) void {
        if (s.set.fetchRemove(path)) |kv| s.gpa.free(kv.key);
    }

    /// One picture takes the reader's whole attention: a plain click.
    /// The anchor and the cursor stand on it, so a shift-click after it
    /// grows a range from here.
    pub fn only(s: *Select, pic: *const model.Picture, index: usize) void {
        s.clearSet();
        s.take(pic.path);
        s.anchor = index;
        s.cursor = index;
    }

    /// A picture joins or leaves the chosen, whichever it was: a
    /// command-click. The anchor stays where it was, so the range a
    /// shift-click makes afterwards still grows from the old place.
    pub fn toggle(s: *Select, pic: *const model.Picture, index: usize) void {
        if (s.has(pic.path)) {
            s.drop(pic.path);
        } else {
            s.take(pic.path);
        }
        s.cursor = index;
        if (s.anchor == null) s.anchor = index;
    }

    /// The pictures from the anchor to `index`, whichever way that is,
    /// replace whatever was chosen: a shift-click. The anchor holds.
    pub fn range(s: *Select, shown: []const *model.Picture, index: usize) void {
        const from = s.anchor orelse {
            s.only(shown[index], index);
            return;
        };
        const lo = @min(from, index);
        const hi = @max(from, index);
        s.clearSet();
        for (shown[lo .. hi + 1]) |pic| s.take(pic.path);
        s.cursor = index;
    }

    /// Everything, or nothing: command-A and its escape hatch. The cursor
    /// is left where it was; selecting all does not move the reader.
    pub fn all(s: *Select, shown: []const *const model.Picture) void {
        s.clearSet();
        for (shown) |pic| s.take(pic.path);
    }

    /// The chosen pictures, in the order the gallery shows them. The list
    /// is the caller's to free; the pictures are the folder's own.
    pub fn chosen(s: *const Select, gpa: std.mem.Allocator, shown: []const *model.Picture) ![]*model.Picture {
        var list: std.ArrayList(*model.Picture) = .empty;
        errdefer list.deinit(gpa);
        for (shown) |pic| {
            if (s.has(pic.path)) try list.append(gpa, pic);
        }
        return list.toOwnedSlice(gpa);
    }

    /// The picture was renamed: the set follows the file, not the name.
    pub fn rename(s: *Select, old_path: []const u8, new_path: []const u8) void {
        if (!s.has(old_path)) return;
        s.drop(old_path);
        if (!s.has(new_path)) s.take(new_path);
    }

    /// The folder was listed again: what the disk still holds stays
    /// chosen, and the paths of what went away -- trashed elsewhere,
    /// moved by hand -- leave the set.
    pub fn keepAlive(s: *Select, pictures: []const model.Picture) void {
        var gone: std.ArrayList([]u8) = .empty;
        defer gone.deinit(s.gpa);
        var it = s.set.keyIterator();
        while (it.next()) |key| {
            var found = false;
            for (pictures) |*pic| {
                if (std.mem.eql(u8, pic.path, key.*)) {
                    found = true;
                    break;
                }
            }
            if (!found) gone.append(s.gpa, key.*) catch {};
        }
        for (gone.items) |path| s.drop(path);
    }

    /// The box the hand drags now, from where it pressed to where it is.
    pub fn marqueeTo(s: *Select, x: f32, y: f32) void {
        s.marquee = .{
            .x = @min(s.marquee_from.x, x),
            .y = @min(s.marquee_from.y, y),
            .w = @abs(x - s.marquee_from.x),
            .h = @abs(y - s.marquee_from.y),
        };
    }
};

test "a choice follows the click, the command and the shift" {
    const gpa = std.testing.allocator;
    var s: Select = .{ .gpa = gpa };
    defer s.deinit();

    var a = model.Picture{ .path = @constCast("a.png"), .name = @constCast("a.png") };
    var b = model.Picture{ .path = @constCast("b.png"), .name = @constCast("b.png") };
    var c = model.Picture{ .path = @constCast("c.png"), .name = @constCast("c.png") };
    var d = model.Picture{ .path = @constCast("d.png"), .name = @constCast("d.png") };
    const shown = [_]*model.Picture{ &a, &b, &c, &d };

    // A plain click chooses one, and anchors there.
    s.only(shown[1], 1);
    try std.testing.expectEqual(@as(usize, 1), s.count());
    try std.testing.expect(s.has("b.png"));
    try std.testing.expectEqual(@as(?usize, 1), s.anchor);

    // A command-click adds and takes away, and leaves the anchor.
    s.toggle(shown[3], 3);
    try std.testing.expectEqual(@as(usize, 2), s.count());
    s.toggle(shown[3], 3);
    try std.testing.expectEqual(@as(usize, 1), s.count());
    try std.testing.expectEqual(@as(?usize, 1), s.anchor);

    // A shift-click grows the range from the anchor, whichever way.
    s.range(&shown, 3);
    try std.testing.expectEqual(@as(usize, 3), s.count());
    try std.testing.expect(s.has("b.png") and s.has("c.png") and s.has("d.png"));
    s.range(&shown, 0);
    try std.testing.expectEqual(@as(usize, 2), s.count());
    try std.testing.expect(s.has("a.png") and s.has("b.png"));

    // The chosen come back in the gallery's own order.
    s.only(shown[2], 2);
    s.toggle(shown[0], 0);
    const picked = try s.chosen(gpa, &shown);
    defer gpa.free(picked);
    try std.testing.expectEqual(@as(usize, 2), picked.len);
    try std.testing.expectEqualStrings("a.png", picked[0].name);
    try std.testing.expectEqualStrings("c.png", picked[1].name);
}

test "a rename follows, a rescan keeps the survivors, a folder clears" {
    const gpa = std.testing.allocator;
    var s: Select = .{ .gpa = gpa };
    defer s.deinit();

    var a = model.Picture{ .path = @constCast("a.png"), .name = @constCast("a.png") };
    var b = model.Picture{ .path = @constCast("b.png"), .name = @constCast("b.png") };

    s.only(&a, 0);
    s.toggle(&b, 1);

    // Renamed: the set says the new name, not the old.
    s.rename("a.png", "renamed.png");
    try std.testing.expect(s.has("renamed.png"));
    try std.testing.expect(!s.has("a.png"));
    try std.testing.expectEqual(@as(usize, 2), s.count());

    // Rescanned and b is gone from the disk: a survives, b does not.
    var a2 = model.Picture{ .path = @constCast("renamed.png"), .name = @constCast("renamed.png") };
    s.keepAlive(&.{a2});
    try std.testing.expect(s.has("renamed.png"));
    try std.testing.expectEqual(@as(usize, 1), s.count());

    // Another folder: nothing carries over.
    s.clear();
    try std.testing.expectEqual(@as(usize, 0), s.count());
    try std.testing.expect(s.anchor == null and s.cursor == null);
}

test "the marquee is a box from the press to the hand, either way" {
    const gpa = std.testing.allocator;
    var s: Select = .{ .gpa = gpa };
    defer s.deinit();

    s.marquee_from = .{ .x = 100, .y = 200 };
    s.marqueeTo(40, 260);
    const box = s.marquee.?;
    try std.testing.expectEqual(@as(f32, 40), box.x);
    try std.testing.expectEqual(@as(f32, 200), box.y);
    try std.testing.expectEqual(@as(f32, 60), box.w);
    try std.testing.expectEqual(@as(f32, 60), box.h);

    s.marqueeTo(160, 150);
    const box2 = s.marquee.?;
    try std.testing.expectEqual(@as(f32, 100), box2.x);
    try std.testing.expectEqual(@as(f32, 150), box2.y);
    try std.testing.expectEqual(@as(f32, 60), box2.w);
    try std.testing.expectEqual(@as(f32, 50), box2.h);
}
