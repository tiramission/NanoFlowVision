//! Where each picture sits: columns of pictures, each as tall as it is wide.

const std = @import("std");

pub const Placement = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    /// Whether the picture at this place meets a window from `top` to `bottom`.
    pub fn inView(p: Placement, top: f32, bottom: f32) bool {
        return p.y + p.h > top and p.y < bottom;
    }
};

pub const Options = struct {
    /// The most columns there may be.
    columns: usize = 4,
    /// How wide a column is wanted; narrower ones are not made.
    target: f32 = 200,
    gap: f32 = 10,
    padding: f32 = 10,
};

pub const Layout = struct {
    placements: []Placement = &.{},
    /// How tall the whole thing is.
    height: f32 = 0,
    /// The width it was laid out for.
    width: f32 = 0,
    columns: usize = 0,

    pub fn deinit(self: *Layout, gpa: std.mem.Allocator) void {
        gpa.free(self.placements);
        self.placements = &.{};
    }

    pub fn empty() Layout {
        return .{};
    }
};

/// The number of columns that fit a width, given how wide each column is.
pub fn columnsFor(width: f32, options: Options) usize {
    const usable = width - 2 * options.padding;
    if (usable <= 0) return 1;
    const want = @as(usize, @intFromFloat(usable / @max(1, options.target)));
    return @max(1, @min(want, options.columns));
}

/// Lays the pictures out in columns: each goes in the column that ends highest.
pub fn compute(
    gpa: std.mem.Allocator,
    aspects: []const f32,
    width: f32,
    options: Options,
) !Layout {
    const cols = columnsFor(width, options);
    const count = aspects.len;
    const placements = try gpa.alloc(Placement, count);
    errdefer gpa.free(placements);

    const gap = options.gap;
    const col_w = (width - 2 * options.padding - gap * @as(f32, @floatFromInt(cols - 1))) /
        @as(f32, @floatFromInt(cols));
    if (col_w <= 0) {
        gpa.free(placements);
        return Layout.empty();
    }

    const bottoms = try gpa.alloc(f32, cols);
    defer gpa.free(bottoms);
    for (bottoms) |*bottom| bottom.* = options.padding;

    for (aspects, 0..) |aspect, i| {
        // The column that ends highest takes the picture.
        var best: usize = 0;
        for (bottoms[1..], 1..) |bottom, ci| {
            if (bottom < bottoms[best]) best = ci;
        }
        const h = if (aspect > 0) col_w / aspect else col_w;
        placements[i] = .{
            .x = options.padding + @as(f32, @floatFromInt(best)) * (col_w + gap),
            .y = bottoms[best],
            .w = col_w,
            .h = h,
        };
        bottoms[best] += h + gap;
    }

    var tallest: f32 = 0;
    for (bottoms) |bottom| tallest = @max(tallest, bottom - gap);
    return .{
        .placements = placements,
        .height = tallest + options.padding,
        .width = width,
        .columns = cols,
    };
}

test "pictures fall into the column that ends highest" {
    const gpa = std.testing.allocator;
    // Two tall ones and one wide one, in two columns.
    const aspects = [_]f32{ 0.5, 0.5, 2.0 };
    var layout = try compute(gpa, &aspects, 220, .{ .columns = 2, .target = 100, .gap = 10, .padding = 10 });
    defer layout.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), layout.columns);
    // The first two are side by side, at the top.
    try std.testing.expectEqual(@as(f32, 10), layout.placements[0].y);
    try std.testing.expectEqual(@as(f32, 10), layout.placements[1].y);
    try std.testing.expect(layout.placements[1].x > layout.placements[0].x);
    // The third is short, and sits under the first column.
    try std.testing.expect(layout.placements[2].y > layout.placements[0].y);
    try std.testing.expectEqual(layout.placements[0].x, layout.placements[2].x);
    // The whole thing is as tall as the tallest column, plus the padding.
    try std.testing.expect(layout.height > layout.placements[0].h);
}

test "a placement knows when it is in view" {
    const p = Placement{ .x = 0, .y = 100, .w = 50, .h = 50 };
    try std.testing.expect(p.inView(0, 200));
    try std.testing.expect(!p.inView(0, 100));
    try std.testing.expect(!p.inView(200, 400));
}

test "the columns that fit a width" {
    try std.testing.expectEqual(@as(usize, 1), columnsFor(150, .{}));
    try std.testing.expectEqual(@as(usize, 2), columnsFor(500, .{}));
    try std.testing.expectEqual(@as(usize, 4), columnsFor(2000, .{ .columns = 4 }));
    // Narrower columns than wanted are not made.
    try std.testing.expectEqual(@as(usize, 1), columnsFor(300, .{ .columns = 4, .target = 200 }));
}
