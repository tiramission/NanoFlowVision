//! The picture, large, over a dark room: the one the gallery opened,
//! drawn as large as the window allows, with what the picture says about
//! itself in the corner -- its camera and date, its stars and its tags.
//! The stars go in with the number keys and the tags with `t`; both are
//! written into the picture file itself, so they are there next time.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const exif = @import("exif.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const thumbs = @import("thumbs.zig");
const i18n = @import("i18n.zig");
const xmp = @import("xmp.zig");

/// The easing slots the framework's animation clock holds the large
/// view's zoom and position in. Their own constants, so the same slots
/// are found every frame.
const zoom_anim: u64 = 0x7A00C1A1;
const pan_x_anim: u64 = 0x7A00C1A2;
const pan_y_anim: u64 = 0x7A00C1A3;

/// Opens a picture large. Its own cache key keeps the big pixels from
/// pushing the thumbnails out.
pub fn show(s: *app.State, pic: *model.Picture) void {
    close(s);
    s.zoom = null;
    const key = thumbs.largeKey(s.gpa, pic.path) catch return;
    s.large_key = key;
    s.large = pic;
    s.pool.ask(pic.path, key, .large);
}

/// Closes the large view, and the tag typing with it.
pub fn close(s: *app.State) void {
    s.large = null;
    s.tag_editing = false;
    s.zoom = null;
    s.zoom_target = null;
    s.pan_tx = 0;
    s.pan_ty = 0;
    s.panning = false;
    s.tag_field.clear();
    if (s.large_key) |key| {
        s.gpa.free(key);
        s.large_key = null;
    }
}

/// Opens the picture one over in the gallery: the one before with -1,
/// the one after with 1. Nothing happens at the ends.
fn neighbor(s: *app.State, step: i32) void {
    const current = s.large orelse return;
    var at: i64 = -1;
    for (s.shown, 0..) |p, i| {
        if (p == current) {
            at = @intCast(i);
            break;
        }
    }
    const next = at + step;
    if (next < 0 or next >= @as(i64, @intCast(s.shown.len))) return;
    show(s, s.shown[@intCast(next)]);
}

/// Whether the picture's file is one we know how to write: a jpeg. The
/// other formats' containers are a later write.
fn editable(name: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(name, ".jpg") or
        std.ascii.endsWithIgnoreCase(name, ".jpeg");
}

/// Puts stars on the picture: 1 to 5, or 0 to take them off. The file is
/// written first; the cache follows only if the write worked, so what the
/// panel shows is what the file says.
fn rate(s: *app.State, pic: *model.Picture, m: *exif.Meta, stars: i8) void {
    const r: i8 = if (stars == 0) -1 else stars;
    if (m.rating == r) return;
    m.rating = r;
    save(s, pic, m);
}

fn addTag(s: *app.State, pic: *model.Picture, m: *exif.Meta, tag: []const u8) void {
    m.addTag(tag);
    save(s, pic, m);
}

fn removeTag(s: *app.State, pic: *model.Picture, m: *exif.Meta, i: usize) void {
    m.removeTag(i);
    save(s, pic, m);
}

/// Writes the picture's file with its rating and tags as they are now.
fn save(s: *app.State, pic: *model.Picture, m: *const exif.Meta) void {
    xmp.rewriteFile(s.gpa, s.io, pic.path, m) catch return;
    s.shared.setMeta(pic.path, m.*);
}

/// The picture, large, over a dark room.
pub fn view(s: *app.State, c: *ui.Context) void {
    const th = c.theme;
    const pic = s.large orelse return;
    // The wheel zooms here: nothing in this view scrolls.
    c.wants_wheel = true;
    if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
        // While a tag is being typed, Esc ends the typing first.
        if (s.tag_editing) {
            s.tag_editing = false;
            s.tag_field.clear();
        } else {
            close(s);
            return;
        }
    }

    // The arrows walk the gallery from here; delete takes the picture
    // to the bin, and the large view follows to the next one.
    if (c.input.key == .left or c.shortcut(.{ .key = ui.Shortcut.left, .ctrl = true })) neighbor(s, -1);
    if (c.input.key == .right or c.shortcut(.{ .key = ui.Shortcut.right, .ctrl = true })) neighbor(s, 1);
    if (c.input.key == .delete and editable(pic.name)) {
        if (ops.trash(pic.path)) {
            close(s);
            s.relist_pending = true;
            return;
        }
    }

    const back = ui.div(c).sizeFull().bg(th.background);
    defer back.end();
    if (back.clicked()) {
        close(s);
        return;
    }

    const key = s.large_key orelse return;
    s.pool.ask(pic.path, key, .large);

    var m: exif.Meta = s.shared.metaOf(pic.path) orelse exif.Meta{};
    const tr = i18n.strings(s.lang);
    if (editable(pic.name)) {
        // The number keys rate the picture; `t` starts a tag. While the
        // tag is being typed, the keys belong to the field.
        if (!s.tag_editing) {
            for (c.input.chars) |ch| {
                if (ch >= '0' and ch <= '5') rate(s, pic, &m, @intCast(ch - '0'));
                if (ch == 't' or ch == 'T') {
                    s.tag_editing = true;
                    s.tag_field.clear();
                }
            }
        }
    }

    const known = s.shared.get(key) orelse return;
    if (known.thumb) |pixels| {
        // The picture at its fit size, and the wheel that zooms it: the view
        // takes the wheel where nothing scrolls. Zooming keeps to the fit at
        // the small end and stops at eight times, and it anchors where the
        // pointer is, so the point under it stays under it.
        const room_w = c.size.w - 48;
        const room_h = c.size.h - 48;
        const img_w: f32 = @floatFromInt(pixels.w);
        const img_h: f32 = @floatFromInt(pixels.h);
        const fit = @min(room_w / img_w, room_h / img_h);
        const wheel = c.input.scroll.y;

        // Where the wheel wants the zoom to go, anchored where the
        // pointer is: the point under it stays under it when the easing
        // arrives. A notch is a gentle step, not a leap. The wheel back
        // to the fit hands the size back to the window.
        if (wheel != 0) {
            const base = s.zoom_target orelse fit;
            const lo = @min(fit, 1.0);
            const hi = @max(fit, 1.0) * 8.0;
            const next = std.math.clamp(base * std.math.pow(f32, 1.15, wheel / 120), lo, hi);
            const bw = img_w * base;
            const bh = img_h * base;
            const mx = c.input.mouse.x - ((c.size.w - bw) / 2 + s.pan_tx);
            const my = c.input.mouse.y - ((c.size.h - bh) / 2 + s.pan_ty);
            if (base > 0) {
                s.pan_tx += mx - mx * next / base;
                s.pan_ty += my - my * next / base;
            }
            if (next <= fit + 0.01) {
                s.zoom = null;
                s.zoom_target = null;
            } else {
                s.zoom = next;
                s.zoom_target = next;
            }
            c.changed = true;
        }

        // What the frame shows: the framework's own easing carries the
        // zoom and the position from where they are toward their targets,
        // by the clock rather than by the frame, and it keeps asking for
        // frames until they arrive. Zoom and position travel together, so
        // the anchored point stays put all the way there.
        const at_fit = s.zoom_target == null;
        const zoom = c.animate(zoom_anim, 0, s.zoom_target orelse fit, 10);
        const pan_x = if (at_fit) 0 else c.animate(pan_x_anim, 0, s.pan_tx, 18);
        const pan_y = if (at_fit) 0 else c.animate(pan_y_anim, 0, s.pan_ty, 18);
        const w = img_w * zoom;
        const h = img_h * zoom;

        const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
        {
            const frame = ui.div(c)
                .absolute()
                .offset((c.size.w - w) / 2 + pan_x, (c.size.h - h) / 2 + pan_y)
                .w(w)
                .h(h)
                .shadowMd();
            defer frame.end();
            const inter = frame.interaction();
            // Two clicks: fit and 1:1 change places, eased as the wheel
            // does.
            if (inter.double_clicked) {
                if ((s.zoom orelse fit) > fit + 0.01) {
                    s.zoom_target = null;
                    s.zoom = null;
                } else {
                    s.zoom_target = 1.0;
                    s.zoom = 1.0;
                }
                s.pan_tx = 0;
                s.pan_ty = 0;
                c.changed = true;
            } else if (inter.pressed and zoom > fit + 0.01) {
                // Dragging the picture when it is bigger than the room:
                // the target moves with the hand, held inside the target
                // zoom's own overflow.
                if (s.panning) {
                    const dx = c.input.mouse.x - s.last_mouse_x;
                    const dy = c.input.mouse.y - s.last_mouse_y;
                    const tw = img_w * (s.zoom_target orelse fit);
                    const thh = img_h * (s.zoom_target orelse fit);
                    const ox = @max(0, (tw - room_w) / 2);
                    const oy = @max(0, (thh - room_h) / 2);
                    s.pan_tx = std.math.clamp(s.pan_tx + dx, -ox, ox);
                    s.pan_ty = std.math.clamp(s.pan_ty + dy, -oy, oy);
                    c.changed = true;
                }
                s.panning = true;
                s.last_mouse_x = c.input.mouse.x;
                s.last_mouse_y = c.input.mouse.y;
            } else {
                s.panning = false;
            }
            _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
        }

        // The zoom, fixed in the corner of the window and always there,
        // the way the panel of facts is: at the fit it says so; zoomed,
        // it says how much. The frame is closed by now, or this would be
        // anchored to the picture and travel with it.
        {
            const chip = ui.div(c).absolute()
                .offset(c.size.w - 122, c.size.h - 56)
                .px(12)
                .py(6)
                .rounded(8)
                .bg(ui.Color.black.alpha(0.45));
            defer chip.end();
            if (zoom > fit + 0.01) {
                ui.text(c, c.print("{d:.0}%", .{zoom * 100}), .{ .size = 12, .color = ui.Color.white });
            } else {
                ui.text(c, tr.fit_label, .{ .size = 12, .color = ui.Color.white });
            }
        }
    } else {
        // The worker is still on it: another frame as soon as it lands.
        c.animationFrame();
        const wait = ui.div(c).row().itemsCenter().gap(8).px(4).py(4);
        defer wait.end();
        ui.icon(c, "circle.dotted", .{ .size = 14, .color = th.muted });
        ui.text(c, i18n.strings(s.lang).loading, .{ .size = 14, .color = th.muted });
    }
    // What the picture says about itself, in the corner: its camera,
    // when it was taken, how, and what it means to us.
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

        var stars: [32]u8 = undefined;
        var sn: usize = 0;
        if (m.rating > 0) {
            var k: i8 = 0;
            while (k < 5) : (k += 1) {
                const glyph = if (k < m.rating) "★" else "☆";
                @memcpy(stars[sn..][0..3], glyph);
                sn += 3;
            }
        }

        // The panel rides on a scrim of its own, and its colours are its
        // own: a photograph can be white, black, or anything between, and
        // the words stay legible on all of them.
        const panel = ui.div(c).absolute().offset(24, 24).p(12).gap(5).rounded(10)
            .bg(ui.Color.black.alpha(0.45));
        defer panel.end();
        if (n > 0) ui.text(c, c.print("{s}", .{line[0..n]}), .{ .size = 13, .weight = .semibold, .color = .white });
        if (sn > 0) ui.text(c, c.print("{s}", .{stars[0..sn]}), .{ .size = 16, .color = .white });
        if (f > 0) ui.text(c, c.print("{s}", .{facts[0..f]}), .{ .size = 13, .color = ui.Color.white.alpha(0.78) });
        if (m.tags_n > 0 and editable(pic.name)) {
            ui.row(c, .{ .gap = 6 });
            defer c.end();
            var i: usize = 0;
            while (i < m.tags_n) {
                {
                    const it = ui.pressable(c, .{
                        .padding = .xy(8, 3),
                        .radius = 5,
                        .align_items = .center,
                        .control = true,
                        .background = ui.Color.white.alpha(0.14),
                    }, ui.Color.white.alpha(0.24));
                    defer c.end();
                    ui.text(c, c.print("{s} ✕", .{m.tagOf(i)}), .{ .size = 12, .color = .white });
                    if (it.clicked) {
                        removeTag(s, pic, &m, i);
                        continue;
                    }
                }
                i += 1;
            }
        }
        if (s.tag_editing) {
            const field = ui.textField(c, &s.tag_field, .{
                .placeholder = tr.add_tag,
                .width = .{ .px = 220 },
                .size = 13,
            });
            if (field.submitted) {
                const tag = std.mem.trim(u8, s.tag_field.text(), " ");
                if (tag.len > 0) addTag(s, pic, &m, tag);
                s.tag_field.clear();
                s.tag_editing = false;
            }
        } else if (editable(pic.name)) {
            ui.text(c, tr.keys_hint, .{ .size = 11, .color = ui.Color.white.alpha(0.55) });
        }
    }
}

/// Appends formatted text to a line the info panel is building.
fn put(buf: []u8, n: *usize, comptime fmt: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(buf[n.*..], fmt, args) catch return;
    n.* += written.len;
}
