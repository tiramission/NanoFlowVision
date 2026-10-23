//! The picture, large, over a dark room: the one the gallery opened,
//! drawn as large as the window allows, with what the picture says about
//! itself (its camera, its date and its settings) in the corner.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const model = @import("model.zig");
const thumbs = @import("thumbs.zig");

/// Opens a picture large. Its own cache key keeps the big pixels from
/// pushing the thumbnails out.
pub fn show(s: *app.State, pic: *model.Picture) void {
    close(s);
    const key = thumbs.largeKey(s.gpa, pic.path) catch return;
    s.large_key = key;
    s.large = pic;
    s.pool.ask(pic.path, key, .large);
}

/// Closes the large view and frees its key.
pub fn close(s: *app.State) void {
    s.large = null;
    if (s.large_key) |key| {
        s.gpa.free(key);
        s.large_key = null;
    }
}

/// The picture, large, over a dark room.
pub fn view(s: *app.State, c: *ui.Context) void {
    const th = c.theme;
    const pic = s.large orelse return;
    if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
        close(s);
        return;
    }

    const back = ui.div(c).sizeFull().bg(th.background);
    defer back.end();
    if (back.clicked()) {
        close(s);
        return;
    }

    const key = s.large_key orelse return;
    s.pool.ask(pic.path, key, .large);

    // What the picture says about itself, in the corner: its camera,
    // when it was taken, and how.
    if (s.shared.metaOf(pic.path)) |m| {
        if (!m.empty()) {
            var line: [256]u8 = undefined;
            var n: usize = 0;
            var facts: [256]u8 = undefined;
            var f: usize = 0;
            if (m.make_len > 0 and !(m.model_len > 0 and std.mem.startsWith(u8, m.modelOf(), m.makeOf()))) {
                put(&line, &n, "{s}", .{m.makeOf()});
                if (m.model_len > 0) put(&line, &n, " · ", .{});
            }
            if (m.model_len > 0) put(&line, &n, "{s}", .{m.modelOf()});
            if (m.date_len >= 16) {
                var when: [16]u8 = undefined;
                @memcpy(&when, m.dateOf()[0..16]);
                when[4] = '-';
                when[7] = '-';
                put(&facts, &f, "{s}", .{when});
            }
            if (m.aperture_den > 0) {
                if (f > 0) put(&facts, &f, " · ", .{});
                if (m.aperture_den == 1) {
                    put(&facts, &f, "f/{d}", .{m.aperture_num});
                } else {
                    const v = @as(f64, @floatFromInt(m.aperture_num)) / @as(f64, @floatFromInt(m.aperture_den));
                    put(&facts, &f, "f/{d:.1}", .{v});
                }
            }
            if (m.exposure_den > 0) {
                if (f > 0) put(&facts, &f, " · ", .{});
                if (m.exposure_num == 1) {
                    put(&facts, &f, "1/{d} s", .{m.exposure_den});
                } else if (m.exposure_num > m.exposure_den) {
                    const v = @as(f64, @floatFromInt(m.exposure_num)) / @as(f64, @floatFromInt(m.exposure_den));
                    put(&facts, &f, "{d:.1} s", .{v});
                } else {
                    put(&facts, &f, "{d}/{d} s", .{ m.exposure_num, m.exposure_den });
                }
            }
            if (m.iso > 0) {
                if (f > 0) put(&facts, &f, " · ", .{});
                put(&facts, &f, "ISO {d}", .{m.iso});
            }
            if (m.focal_den > 0) {
                if (f > 0) put(&facts, &f, " · ", .{});
                const v = @as(f64, @floatFromInt(m.focal_num)) / @as(f64, @floatFromInt(m.focal_den));
                put(&facts, &f, "{d:.0} mm", .{v});
            }
            if (n > 0 or f > 0) {
                const panel = ui.div(c).absolute().offset(24, 24).gap(4);
                defer panel.end();
                if (n > 0) ui.text(c, c.print("{s}", .{line[0..n]}), .{ .size = 13, .weight = .semibold });
                if (f > 0) ui.text(c, c.print("{s}", .{facts[0..f]}), .{ .size = 13, .color = th.muted });
            }
        }
    }

    const known = s.shared.get(key) orelse return;
    const pixels = known.thumb orelse {
        // The worker is still on it: another frame as soon as it lands.
        c.animationFrame();
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

/// Appends formatted text to a line the info panel is building.
fn put(buf: []u8, n: *usize, comptime fmt: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(buf[n.*..], fmt, args) catch return;
    n.* += written.len;
}
