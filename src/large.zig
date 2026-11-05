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
const zoom_mod = @import("zoom.zig");
const fullscreen = @import("fullscreen.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const theme = @import("theme.zig");
const thumbs = @import("thumbs.zig");
const i18n = @import("i18n.zig");
const xmp = @import("xmp.zig");

/// Opens a picture large. Its own cache key keeps the big pixels from
/// pushing the thumbnails out. The keyboard's place follows it, so the
/// escape back to the wall lands on the tile it came from.
pub fn show(s: *app.State, pic: *model.Picture) void {
    close(s);
    s.zoom_mode = .fit;
    s.zoom_target = null;
    s.anchor = null;
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
    s.zoom_mode = .fit;
    s.zoom_target = null;
    s.anchor = null;
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

/// How far the pointer may travel while a press is still a look. One
/// point, the smallest movement a hand makes on purpose: a click that
/// wobbles is a look, a press that is meant to drag leaves it at once.
const peek_slop: f32 = 1.0;

/// The button held down for a look, as the mode it shows: the left one
/// at 1:1 about the pointer, the right one fitting the picture to the
/// room. Null when neither is held, and when the pointer is not on the
/// photograph -- a press on the top bar's stars is a press on a star, not
/// a look.
///
/// Both buttons look from the moment they go down, in any mode, a
/// wheel-zoomed one included: the question is how the picture looks at its
/// own pixels or fitted, and that does not depend on where the wheel left
/// it. Waiting for the press to prove itself still made the left button
/// feel unlike the right one -- and it needed frames to keep arriving, so
/// a press held without moving waited for the next mouse movement instead
/// of its own delay. The look begins at once; a press that turns out to be
/// a drag ends it and takes over, which is a thing the hand decides, not
/// a clock.
fn peekMode(s: *app.State, c: *ui.Context) ?app.ZoomMode {
    // A look already begun keeps itself, wherever the picture moved to:
    // the pointer was on the photograph when the press started, and asking
    // again would end it the moment a 1:1 picture shrank from under the
    // hand.
    if (s.peek) |held| {
        // A hand that moves has taken over: the look ends, the drag it
        // became continues from the picture the reader is looking at.
        return switch (held.mode) {
            .actual => if (c.input.down and !c.input.secondary_down and !s.press_moved) .actual else null,
            .fit => if (c.input.secondary_down) .fit else null,
            else => null,
        };
    }
    const at = s.large_at;
    if (at.w <= 0 or at.h <= 0) return null;
    const m = c.input.mouse;
    if (m.x < at.x or m.x >= at.x + at.w or m.y < at.y or m.y >= at.y + at.h) return null;
    if (c.input.secondary_down) return .fit;
    // The left button looks until the hand moves. A drag has begun by then,
    // and the drag is what the press was for.
    if (c.input.down and !c.input.secondary_down and !s.press_moved) return .actual;
    return null;
}

/// The picture, large, over a dark room.
pub fn view(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const pic = s.large orelse return;
    // In full screen the chrome stands back after a moment of quiet;
    // any movement brings it back. One value, read by the bars below.
    fullscreen.noteInput(s, c);
    const chrome_live = fullscreen.chromeLive(s);
    const chrome_drawn = fullscreen.chromeDrawn(s);
    const chrome_alpha = fullscreen.chromeOpacity(s);
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
    // The keys that shape the view: `z` fits and 1:1 change places, `f`
    // fills the screen and 1:1 do, `i` folds the facts. None of them
    // needs the file to be writable, so they are read for any picture;
    // only rating and tagging do.
    var zoom_toggle = false;
    var fill_toggle = false;
    if (!s.tag_editing) {
        for (c.input.chars) |ch| {
            if (ch == 'z' or ch == 'Z') zoom_toggle = true;
            if (ch == 'f' or ch == 'F') fill_toggle = true;
            if (ch == 'i' or ch == 'I') s.info_open = !s.info_open;
            if (editable(pic.name)) {
                if (ch >= '0' and ch <= '5') rate(s, pic, &m, @intCast(ch - '0'));
                if (ch == 't' or ch == 'T') {
                    s.tag_editing = true;
                    s.tag_field.clear();
                }
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
        // The picture and the wheel that zooms it, from the fit to eight
        // times, anchored on the point under the pointer.
        //
        // The room the bars take, followed frame by frame as they fade: the
        // fit grows with them instead of jumping when they are gone, and a
        // picture is never shown under a bar that still stands.
        const top_room: f32 = fullscreen.topRoom(s, 44, 16);
        const bottom_room: f32 = fullscreen.topRoom(s, filmstrip.strip_h, 16);
        const room_w = c.size.w - 48;
        const room_h = c.size.h - top_room - bottom_room;
        const img_w: f32 = @floatFromInt(pixels.w);
        const img_h: f32 = @floatFromInt(pixels.h);
        const fit = @min(room_w / img_w, room_h / img_h);
        // Filling the room: the picture covers it, its edges cropped.
        const cover = @max(room_w / img_w, room_h / img_h);
        // The keys shape the view, and the wheel zooms it about the
        // pointer; `zoom.step` owns both, and hands back what to draw.
        var wheel = c.input.scroll.y;
        if (wheel != 0 and chrome_live and c.input.mouse.y >= c.size.h - filmstrip.strip_h) {
            // Over the strip, the wheel steps along the gallery instead.
            neighbor(s, if (wheel < 0) 1 else -1);
            wheel = 0;
            c.changed = true;
        }
        // The press's state, read before the frame is built: a press that
        // has moved is a drag, and the drag has to reach `step` this frame,
        // not the next one. A press that has not moved is the start of a
        // look, and `press_moved` says whether the hand has taken over.
        var drag: ?ui.Point = null;
        if (c.input.down and !c.input.secondary_down) {
            // The press's own frame: the clock starts here, and nothing has
            // moved yet.
            if (c.input.pressed or !s.panning) s.press_moved = false;
            if (s.panning) {
                const dx = c.input.mouse.x - s.last_mouse_x;
                const dy = c.input.mouse.y - s.last_mouse_y;
                if (@abs(dx) > peek_slop or @abs(dy) > peek_slop) s.press_moved = true;
                if (s.press_moved) drag = .{ .x = dx, .y = dy };
            }
            s.panning = true;
            s.last_mouse_x = c.input.mouse.x;
            s.last_mouse_y = c.input.mouse.y;
        } else {
            s.panning = false;
            s.press_moved = false;
        }
        const shown = zoom_mod.step(s, c, .{
            .w = room_w,
            .h = room_h,
            .top = top_room,
            .img_w = img_w,
            .img_h = img_h,
            .fit = fit,
            .cover = cover,
        }, wheel, zoom_toggle, fill_toggle, peekMode(s, c), drag);
        const zoom = shown.zoom;
        const w = img_w * zoom;
        const h = img_h * zoom;
        // The rectangle the picture takes, for the tests that hold the
        // point under the pointer to its place.
        s.large_at = .{ .x = (c.size.w - w) / 2 + shown.pan_x, .y = top_room + (room_h - h) / 2 + shown.pan_y, .w = w, .h = h };

        const texture = ui.Texture{ .width = pixels.w, .height = pixels.h, .bgra = pixels.bgra };
        {
            const frame = ui.div(c)
                .absolute()
                .offset(s.large_at.x, s.large_at.y)
                .w(w)
                .h(h)
                .shadowMd();
            defer frame.end();
            const inter = frame.interaction();
            // Two clicks: fit and 1:1 change places, eased as the wheel
            // does.
            if (inter.double_clicked) {
                zoom_mod.toggleFit(s);
                c.changed = true;
            }
            _ = ui.texture(c, .{ .width = .fill, .height = .fill }, texture, .{ 0, 0, 1, 1 }, 1);
        }

        // The zoom, at the foot of the window just above the strip: at the
        // fit it says so, zoomed it says how much. It goes with the chrome,
        // and stops taking clicks before it has faded out completely.
        if (chrome_drawn) {
            const chip = ui.div(c).absolute()
                .offset(c.size.w - 122, c.size.h - bottom_room - 32)
                .px(12)
                .py(6)
                .rounded(8)
                .opacity(chrome_alpha)
                .bg(k.scrim).control();
            defer chip.end();
            // The chip names the mode, and a click walks through the
            // three that are named: fit, fill, 1:1. A wheel zoom is
            // nobody's mode, and says its own percentage.
            const label: []const u8 = switch (s.zoom_mode) {
                .fit => tr.fit_label,
                .fill => tr.fill_label,
                .actual => "",
                .free => "",
            };
            if (label.len > 0) {
                ui.text(c, label, .{ .size = 12, .mono = true, .color = ui.Color.white });
            } else {
                ui.textf(c, .{ .size = 12, .mono = true, .color = ui.Color.white }, "{d:.0}%", .{zoom * 100});
            }
            if (chip.clicked()) zoom_mod.cycle(s);
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
    if (chrome_drawn) {
        const bar = ui.div(c).absolute().offset(0, 0).w(c.size.w).h(44)
            .row().itemsCenter().gap(12).px(16)
            .opacity(chrome_alpha)
            .bg(k.scrim);
        defer bar.end();
        ui.textf(c, .{ .size = 13, .mono = true, .color = ui.Color.white.alpha(0.7) }, "{d} / {d}", .{ at + 1, s.shown.len });
        ui.text(c, pic.name, .{ .size = 13, .color = .white, .truncate = .middle });
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
    if (chrome_drawn) {
        if (filmstrip.view(s, c, at, chrome_alpha, chrome_live)) |i| show(s, s.shown[i]);
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
