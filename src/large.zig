//! The picture, large, over a dark room: the one the gallery opened,
//! drawn as large as the window allows, with what the picture says about
//! itself in the corner -- its camera and date, its stars and its tags.
//! The stars go in with the number keys and the tags with `t`; both are
//! written into the picture file itself, so they are there next time.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const exif = @import("exif.zig");
const filmstrip = @import("filmstrip.zig");
const fullscreen = @import("fullscreen.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const theme = @import("theme.zig");
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
/// pushing the thumbnails out. The keyboard's place follows it, so the
/// escape back to the wall lands on the tile it came from.
pub fn show(s: *app.State, pic: *model.Picture) void {
    close(s);
    s.zoom = null;
    const key = thumbs.largeKey(s.gpa, pic.path) catch return;
    s.large_key = key;
    s.large = pic;
    s.pool.ask(pic.path, key, .large);
    for (s.shown, 0..) |p, i| {
        if (p == pic) {
            s.select.cursor = i;
            break;
        }
    }
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
pub fn editable(name: []const u8) bool {
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

/// Stars for the whole choice at once: the grid's 0 to 5 over a
/// selection. Each file is written on its own; the ones that made it say
/// so in the cache, the ones that did not keep their old stars.
pub fn rateBatch(s: *app.State, pics: []const *model.Picture, stars: i8) void {
    for (pics) |pic| {
        var m = s.shared.metaOf(pic.path) orelse exif.Meta{};
        rate(s, pic, &m, stars);
    }
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
    xmp.rewriteFile(s.gpa, s.io, pic.path, m) catch {
        // The stars the panel now shows are not in the file: say so,
        // rather than let the picture go on claiming them.
        s.toast(.danger, i18n.strings(s.lang).rate_failed);
        return;
    };
    s.shared.setMeta(pic.path, m.*);
}

/// Fit and 1:1 change places: the wheel's double click, the chip and
/// `z` all say the same thing. The pan goes back to the middle, eased
/// like any other move. Which of the two the view is at is the
/// target's own word, not the zoom's size against the fit -- a small
/// photograph's fit is bigger than 1:1, and the two must still trade.
fn toggleZoom(s: *app.State) void {
    if (s.zoom_target != null) {
        s.zoom_target = null;
        s.zoom = null;
    } else {
        s.zoom_target = 1.0;
        s.zoom = 1.0;
    }
    s.pan_tx = 0;
    s.pan_ty = 0;
}

/// The picture, large, over a dark room.
pub fn view(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const pic = s.large orelse return;
    // In full screen the chrome stands back after a moment of quiet;
    // any movement brings it back.
    fullscreen.noteInput(s, c);
    // The wheel zooms here: nothing in this view scrolls.
    c.wants_wheel = true;
    if (c.shortcut(.{ .key = ui.Shortcut.escape })) {
        // While a tag is being typed, Esc ends the typing first.
        if (s.tag_editing) {
            s.tag_editing = false;
            s.tag_field.clear();
        } else if (s.fullscreen) {
            // Full screen is the outer layer: Esc gives the window back
            // and keeps the picture large.
            s.fullscreen_pending = false;
            c.changed = true;
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
        const here = i18n.strings(s.lang);
        if (ops.trash(pic.path)) {
            s.toast(.success, here.trashed);
            close(s);
            s.relist_pending = true;
            return;
        }
        s.toast(.danger, here.trash_failed);
    }

    const back = ui.div(c).sizeFull().bg(k.room);
    defer back.end();
    if (back.clicked()) {
        close(s);
        return;
    }

    const key = s.large_key orelse return;
    s.pool.ask(pic.path, key, .large);

    // The place this one holds in the gallery: the count at the top,
    // and the strip's ring.
    var at: usize = 0;
    for (s.shown, 0..) |p, i| {
        if (p == pic) {
            at = i;
            break;
        }
    }

    var m: exif.Meta = s.shared.metaOf(pic.path) orelse exif.Meta{};
    const tr = i18n.strings(s.lang);
    // `z` lands where the fit is known: the keys are read here, the
    // zoom answers when the picture's own size is on the table.
    var zoom_toggle = false;
    if (editable(pic.name)) {
        // The number keys rate the picture; `t` starts a tag; `i` folds
        // the panel of facts. While the tag is being typed, the keys
        // belong to the field.
        if (!s.tag_editing) {
            for (c.input.chars) |ch| {
                if (ch >= '0' and ch <= '5') rate(s, pic, &m, @intCast(ch - '0'));
                if (ch == 't' or ch == 'T') {
                    s.tag_editing = true;
                    s.tag_field.clear();
                }
                if (ch == 'z' or ch == 'Z') zoom_toggle = true;
                if (ch == 'i' or ch == 'I') s.info_open = !s.info_open;
            }
        }
    }
    // Space is the way back to the wall, as it was the way in -- whatever
    // kind of file is on the table.
    if (!s.tag_editing) {
        for (c.input.chars) |ch| {
            if (ch == ' ') {
                close(s);
                return;
            }
        }
    }

    const known = s.shared.get(key) orelse return;
    if (known.thumb) |pixels| {
        // The picture at its fit size, and the wheel that zooms it: the view
        // takes the wheel where nothing scrolls. Zooming keeps to the fit at
        // the small end and stops at eight times, and it anchors where the
        // pointer is, so the point under it stays under it.
        //
        // The room leaves the bars alone: the fit is the space between the
        // top bar and the strip, so a picture is never shown under them.
        const top_room: f32 = if (s.chrome_hidden) 16 else 44 + 16;
        const bottom_room: f32 = if (s.chrome_hidden) 16 else filmstrip.strip_h + 16;
        const room_w = c.size.w - 48;
        const room_h = c.size.h - top_room - bottom_room;
        const img_w: f32 = @floatFromInt(pixels.w);
        const img_h: f32 = @floatFromInt(pixels.h);
        const fit = @min(room_w / img_w, room_h / img_h);
        const wheel = c.input.scroll.y;
        if (zoom_toggle) toggleZoom(s);

        // Where the wheel wants the zoom to go, anchored where the
        // pointer is: the point under it stays under it when the easing
        // arrives. A notch is a gentle step, not a leap. The wheel back
        // to the fit hands the size back to the window. Over the strip
        // at the foot, the wheel steps along the gallery instead.
        if (wheel != 0 and c.input.mouse.y >= c.size.h - filmstrip.strip_h) {
            neighbor(s, if (wheel < 0) 1 else -1);
            c.changed = true;
        } else if (wheel != 0) {
            const base = s.zoom_target orelse fit;
            const lo = @min(fit, 1.0);
            const hi = @max(fit, 1.0) * 8.0;
            const next = std.math.clamp(base * std.math.pow(f32, 1.15, wheel / 120), lo, hi);
            const bw = img_w * base;
            const bh = img_h * base;
            const mx = c.input.mouse.x - ((c.size.w - bw) / 2 + s.pan_tx);
            const my = c.input.mouse.y - (top_room + (room_h - bh) / 2 + s.pan_ty);
            if (base > 0) {
                s.pan_tx += mx - mx * next / base;
                s.pan_ty += my - my * next / base;
            }
            // The target stays inside the target zoom's own overflow:
            // zooming out must not leave the room empty at the edges.
            const nw = img_w * next;
            const nh = img_h * next;
            const nox = @max(0, (nw - room_w) / 2);
            const noy = @max(0, (nh - room_h) / 2);
            s.pan_tx = std.math.clamp(s.pan_tx, -nox, nox);
            s.pan_ty = std.math.clamp(s.pan_ty, -noy, noy);
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
        // frames until they arrive. One speed for all three, or the
        // anchored point would drift while they travelled; at the fit the
        // position's target is the middle, eased to like any other.
        const at_fit = s.zoom_target == null;
        const zoom = c.animate(zoom_anim, 0, s.zoom_target orelse fit, 12);
        const pan_x = c.animate(pan_x_anim, 0, if (at_fit) 0 else s.pan_tx, 12);
        const pan_y = c.animate(pan_y_anim, 0, if (at_fit) 0 else s.pan_ty, 12);
        const w = img_w * zoom;
        const h = img_h * zoom;

        const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
        {
            const frame = ui.div(c)
                .absolute()
                .offset((c.size.w - w) / 2 + pan_x, top_room + (room_h - h) / 2 + pan_y)
                .w(w)
                .h(h)
                .shadowMd();
            defer frame.end();
            const inter = frame.interaction();
            // Two clicks: fit and 1:1 change places, eased as the wheel
            // does.
            if (inter.double_clicked) {
                toggleZoom(s);
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

        // The zoom, at the foot of the window, just above the strip: at
        // the fit it says so; zoomed, it says how much. A click on it,
        // like the wheel's double click and `z`, makes fit and 1:1
        // change places. Hidden with the rest of the chrome.
        if (!s.chrome_hidden) {
            const chip = ui.div(c).absolute()
                .offset(c.size.w - 122, c.size.h - filmstrip.strip_h - 48)
                .px(12)
                .py(6)
                .rounded(8)
                .bg(k.scrim).control();
            defer chip.end();
            if (s.zoom_target != null) {
                ui.textf(c, .{ .size = 12, .mono = true, .color = ui.Color.white }, "{d:.0}%", .{zoom * 100});
            } else {
                ui.text(c, tr.fit_label, .{ .size = 12, .mono = true, .color = ui.Color.white });
            }
            if (chip.clicked()) toggleZoom(s);
        }
    } else {
        // The worker is still on it -- or it tried and cannot read the
        // file. Those are different answers, and the room says which.
        if (known.failed) {
            const note = ui.div(c).absolute().offset(0, 0).sizeFull().column().center().gap(8);
            defer note.end();
            ui.icon(c, "exclamationmark.triangle", .{ .size = 28, .color = k.room_muted });
            ui.text(c, tr.decode_failed, .{ .size = 14, .color = k.room_muted });
            ui.text(c, pic.path, .{ .size = 12, .mono = true, .color = k.room_muted });
        } else {
            c.animationFrame();
            const wait = ui.div(c).row().itemsCenter().gap(8).px(4).py(4);
            defer wait.end();
            ui.icon(c, "circle.dotted", .{ .size = 14, .color = k.room_muted });
            ui.text(c, tr.loading, .{ .size = 14, .color = k.room_muted });
        }
    }

    // The bar along the top: where this one stands in the gallery, its
    // name, its stars -- which take a click, where the panel's take the
    // keys -- and the two ways out of the way: the facts folded or shown,
    // and the view closed. It rides on the veil, so it reads on any
    // photograph under it.
    if (!s.chrome_hidden) {
        const bar = ui.div(c).absolute().offset(0, 0).w(c.size.w).h(44)
            .row().itemsCenter().gap(12).px(16)
            .bg(k.scrim);
        defer bar.end();
        ui.textf(c, .{ .size = 13, .mono = true, .color = ui.Color.white.alpha(0.7) }, "{d} / {d}", .{ at + 1, s.shown.len });
        ui.text(c, pic.name, .{ .size = 13, .color = .white });
        ui.spacer(c);
        if (editable(pic.name)) {
            var st: i8 = 1;
            while (st <= 5) : (st += 1) {
                const star = ui.div(c).row().w(26).h(26).center().rounded(6).control();
                const s_it = star.interaction();
                defer star.end();
                ui.text(c, if (m.rating >= st) "★" else "☆", .{ .size = 15, .color = if (m.rating >= st) k.grade else ui.Color.white.alpha(0.45) });
                if (s_it.clicked) rate(s, pic, &m, st);
            }
            ui.spacer(c);
        }
        const fs = barButton(c, "arrow.up.left.and.arrow.down.right", if (s.fullscreen) tr.exit_fullscreen else tr.fullscreen, s.fullscreen);
        if (fs.clicked) fullscreen.toggle(s, c);
        const info = barButton(c, "info.circle", tr.info, s.info_open);
        if (info.clicked) s.info_open = !s.info_open;
        const shut = barButton(c, "xmark", tr.close_label, false);
        if (shut.rect) |r| s.large_close_at = r;
        if (shut.clicked) {
            close(s);
            return;
        }
    }

    // The strip: the gallery as it stands around this one, a click away,
    // with the wheel over it stepping along instead of zooming.
    s.filmstrip_at.clearRetainingCapacity();
    if (!s.chrome_hidden) {
        if (filmstrip.view(s, c, at)) |i| show(s, s.shown[i]);
    }
    // What the picture says about itself, in its panel card at the
    // corner: its camera, when it was taken, how, and what it means to
    // us. `i`, or a click on the panel's own mark, folds it to a single
    // line and back.
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
            var st: i8 = 0;
            while (st < 5) : (st += 1) {
                const glyph = if (st < m.rating) "★" else "☆";
                @memcpy(stars[sn..][0..3], glyph);
                sn += 3;
            }
        }

        // The panel stands in the picture's corner, on a card of its own:
        // a photograph can be white, black, or anything between, and the
        // words stay legible on all of them. It is the one opaque thing
        // allowed over a picture. Folded, it is one line -- the mark and
        // the word -- and no more.
        const corner = ui.div(c).absolute().offset(16, 0)
            .w(320).h(c.size.h - filmstrip.strip_h - 12)
            .column().itemsStart().justifyEnd();
        defer corner.end();
        if (s.info_open) {
            const panel = ui.div(c).w(300).p(12).gap(5).rounded(10)
                .bg(k.card).border(k.border).shadowMd();
            defer panel.end();
            {
                const head = ui.div(c).row().wFull().itemsCenter().gap(6).control();
                defer head.end();
                ui.icon(c, "info.circle", .{ .size = 12, .color = k.secondary });
                ui.text(c, tr.info, .{ .size = 12, .weight = .semibold, .color = k.text });
                ui.spacer(c);
                ui.icon(c, "chevron.up", .{ .size = 11, .color = k.tertiary });
                if (head.clicked()) s.info_open = false;
            }
            if (n > 0) ui.text(c, c.print("{s}", .{line[0..n]}), .{ .size = 13, .weight = .semibold, .color = k.text });
            if (sn > 0) ui.text(c, c.print("{s}", .{stars[0..sn]}), .{ .size = 16, .color = k.grade });
            if (f > 0) ui.text(c, c.print("{s}", .{facts[0..f]}), .{ .size = 12, .mono = true, .color = k.secondary });
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
                            .background = k.control,
                        }, k.line2);
                        defer c.end();
                        ui.text(c, c.print("{s} ✕", .{m.tagOf(i)}), .{ .size = 12, .color = k.text });
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
                ui.text(c, tr.keys_hint, .{ .size = 11, .color = k.tertiary });
            }
        } else {
            const mark = ui.div(c)
                .row().itemsCenter().gap(6).px(10).py(6).rounded(8)
                .bg(k.card).border(k.border).shadowMd().control();
            defer mark.end();
            ui.icon(c, "info.circle", .{ .size = 12, .color = k.secondary });
            ui.text(c, tr.info, .{ .size = 12, .color = k.text });
            if (mark.clicked()) s.info_open = true;
        }
    }
}

/// A chip in the large view's top bar: an icon on the veil, its name
/// said on hover.
fn barButton(c: *ui.Context, icon: []const u8, label: []const u8, on: bool) ui.Interaction {
    var chip = ui.div(c).row().w(28).h(28).center().rounded(7).control();
    const it = chip.interaction();
    if (on) chip = chip.bg(ui.Color.white.alpha(0.18));
    chip = chip.hover(ui.Color.white.alpha(0.16));
    defer chip.end();
    ui.icon(c, icon, .{ .size = 14, .color = .white });
    if (it.hovered) kit.tooltip(c, it, label, .{});
    return it;
}

/// Appends formatted text to a line the info panel is building.
fn put(buf: []u8, n: *usize, comptime fmt: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(buf[n.*..], fmt, args) catch return;
    n.* += written.len;
}
