//! The strip along the bottom of the window: what is here and how heavy
//! it is, whether the folder is being watched and how long since it
//! moved, and -- while the workers are still reading sizes -- the line of
//! progress across the top of the page. Numbers are set in mono so a
//! count that changes does not shuffle the words beside it.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const model = @import("model.zig");
const theme = @import("theme.zig");
const thumbs = @import("thumbs.zig");

/// The bar's height, and the hairline above it.
const height: f32 = 27;

/// The title while the sizes arrive: how far they have got, then the
/// app's name. One allocation, freed by the frame's arena. Assembled in
/// one place so a test can hold it to its shape.
pub fn progressTitle(alloc: std.mem.Allocator, lang: i18n.Lang, percent: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, i18n.strings(.en).measuring_progress ++ " · " ++ app.app_name, .{percent}) catch app.app_name,
        .zh => std.fmt.allocPrint(alloc, i18n.strings(.zh).measuring_progress ++ " · " ++ app.app_name, .{percent}) catch app.app_name,
    };
}

/// The window's title follows the measuring, and goes back to the plain
/// name when the sizes are in. Only the changes reach the window: a
/// title is set when its percent changes, not every frame.
pub fn title(s: *app.State, c: *ui.Context) void {
    const w = s.window orelse return;
    var percent: ?usize = null;
    if (s.current) |folder| {
        const total = folder.pictures.len;
        const done = s.shared.measuredCount();
        if (total > 0 and done < total) percent = done * 100 / total;
    }
    if (percent == s.title_percent) return;
    s.title_percent = percent;
    w.setTitle(if (percent) |p| progressTitle(c.alloc(), s.lang, p) else app.app_name);
}

/// The line of progress across the top of the page, while the pictures'
/// sizes are still arriving. Nothing else in the app draws a bar like
/// this: it is the one moment the app is waiting on the disk.
pub fn progress(s: *app.State, c: *ui.Context) void {
    const current = s.current orelse return;
    const total = current.pictures.len;
    if (total == 0) return;
    const done = s.shared.measuredCount();
    if (done >= total) return;
    const k = theme.colors(s.dark);
    const fraction: f32 = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total));
    const track = ui.div(c).row().wFull().h(2).bg(k.control);
    defer track.end();
    _ = c.leaf(.{
        .width = .{ .px = fraction * @max(0, c.size.w - s.rail_w - 1) },
        .height = .{ .px = 2 },
        .background = k.accent,
    }, .none, null);
}

/// The bar itself.
pub fn view(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.border }, .none, null);
    const bar = ui.div(c).row().wFull().h(height).itemsCenter().gap(8).px(16).bg(k.page);
    defer bar.end();

    // What is on screen: the count, then how much of it weighs. Each is
    // its own line of text, so a test (and a reader) can find the count
    // on its own.
    const current = s.current;
    const measuring = if (current) |folder| s.shared.measuredCount() < folder.pictures.len else false;
    if (measuring) {
        const percent: usize = if (current) |folder|
            (100 * s.shared.measuredCount()) / @max(1, folder.pictures.len)
        else
            0;
        ui.textf(c, .{ .size = 12, .mono = true, .color = k.secondary }, "{s}", .{i18n.measuringProgress(c.alloc(), s.lang, percent)});
    } else if (current) |folder| {
        // What the choice says, while there is one: how many of the
        // folder's pictures are in it -- and how many of those the wall
        // is not showing right now, because the search or the filter
        // took them off. Otherwise, how many there are.
        if (s.select.count() > 0) {
            ui.text(c, i18n.selectedOf(c.alloc(), s.lang, s.select.count(), folder.pictures.len), .{ .size = 12, .color = k.secondary });
            var hidden: usize = 0;
            for (folder.pictures) |*pic| {
                if (!s.select.has(pic.path)) continue;
                var on_wall = false;
                for (s.shown) |sp| {
                    if (sp == pic) {
                        on_wall = true;
                        break;
                    }
                }
                if (!on_wall) hidden += 1;
            }
            if (hidden > 0) {
                ui.text(c, "·", .{ .size = 12, .color = k.tertiary });
                ui.text(c, i18n.hiddenByFilter(c.alloc(), s.lang, hidden), .{ .size = 12, .color = k.secondary });
            }
        } else {
            const count = if (s.shown.len == folder.pictures.len)
                i18n.pictures(c.alloc(), s.lang, folder.pictures.len)
            else
                i18n.picturesOf(c.alloc(), s.lang, s.shown.len, folder.pictures.len);
            ui.text(c, count, .{ .size = 12, .color = k.secondary });
        }
        ui.text(c, "·", .{ .size = 12, .color = k.tertiary });
        // Said through `textf`: the frame paints after the view returns, so
        // the text must live in the frame's arena, not in a buffer here
        // that is gone by then (a slice into it draws as so many tofu).
        var buf: [24]u8 = undefined;
        ui.textf(c, .{ .size = 12, .mono = true, .color = k.secondary }, "{s}", .{sizeText(&buf, shownBytes(s))});
        // Where the keyboard stands, when it has walked somewhere: the
        // cursor is a place on the wall, and a place deserves a number.
        if (s.select.cursor) |ci| {
            if (ci < s.shown.len) {
                ui.text(c, "·", .{ .size = 12, .color = k.tertiary });
                ui.text(c, i18n.cursorPosition(c.alloc(), s.lang, ci + 1), .{ .size = 12, .mono = true, .color = k.secondary });
            }
        }
    }
    ui.spacer(c);

    // How the wall is ordered, said here so the eye never has to open a
    // menu to learn it: the key, then the way it runs.
    ui.text(c, c.print("{s} {s}", .{ sortWord(tr, s.sort), if (s.sort_ascending) "↑" else "↓" }), .{ .size = 12, .color = k.tertiary });
    ui.text(c, "·", .{ .size = 12, .color = k.tertiary });

    // The watcher: a dot, the word, and how long since the folder moved.
    // The dot is green because the watch is running; the time says when.
    _ = c.leaf(.{ .width = .{ .px = 7 }, .height = .{ .px = 7 }, .radius = 3.5, .background = k.green }, .none, null);
    ui.text(c, tr.watching, .{ .size = 12, .color = k.secondary });
    {
        var buf: [24]u8 = undefined;
        const since = if (s.listed_at < 0) 0 else @max(0, c.time - s.listed_at);
        ui.textf(c, .{ .size = 12, .mono = true, .color = k.tertiary }, "{s}", .{agoText(&buf, since)});
    }
}

/// The word the bar says for the sort key.
fn sortWord(tr: i18n.Strings, key: app.SortKey) []const u8 {
    return switch (key) {
        .name => tr.sort_name,
        .time => tr.sort_date,
        .size => tr.sort_size,
        .pixels => tr.sort_pixels,
        .stars => tr.sort_stars,
    };
}

/// The weight of what the gallery is showing, in bytes.
fn shownBytes(s: *app.State) u64 {
    var total: u64 = 0;
    for (s.shown) |pic| {
        if (s.shared.measuredOf(pic.path)) |m| total += m.bytes;
    }
    return total;
}

/// A byte count as the interface says it: "512 B", "24.6 MB", "1.2 GB".
pub fn sizeText(buf: []u8, bytes: u64) []const u8 {
    const kib: f64 = 1024;
    const value: f64 = @floatFromInt(bytes);
    if (bytes < 1024) return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "?";
    if (value < kib * kib) return std.fmt.bufPrint(buf, "{d:.1} KB", .{value / kib}) catch "?";
    if (value < kib * kib * kib) return std.fmt.bufPrint(buf, "{d:.1} MB", .{value / (kib * kib)}) catch "?";
    return std.fmt.bufPrint(buf, "{d:.1} GB", .{value / (kib * kib * kib)}) catch "?";
}

/// How long since the folder moved: "3s", "5m", "2h", "4d". Units are
/// letters whichever language is on screen, and the figure is mono.
pub fn agoText(buf: []u8, seconds: f64) []const u8 {
    if (seconds < 60) return std.fmt.bufPrint(buf, "{d}s", .{@as(u64, @intFromFloat(seconds))}) catch "?";
    if (seconds < 3600) return std.fmt.bufPrint(buf, "{d}m", .{@as(u64, @intFromFloat(seconds / 60))}) catch "?";
    if (seconds < 86400) return std.fmt.bufPrint(buf, "{d}h", .{@as(u64, @intFromFloat(seconds / 3600))}) catch "?";
    return std.fmt.bufPrint(buf, "{d}d", .{@as(u64, @intFromFloat(seconds / 86400))}) catch "?";
}

test "a byte count is said the way the status bar says it" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("512 B", sizeText(&buf, 512));
    try std.testing.expectEqualStrings("1.0 KB", sizeText(&buf, 1024));
    try std.testing.expectEqualStrings("24.6 MB", sizeText(&buf, 25_790_000));
    try std.testing.expectEqualStrings("1.2 GB", sizeText(&buf, 1_288_490_188));
}

test "time since the folder moved" {
    var buf: [24]u8 = undefined;
    try std.testing.expectEqualStrings("3s", agoText(&buf, 3.4));
    try std.testing.expectEqualStrings("59s", agoText(&buf, 59));
    try std.testing.expectEqualStrings("5m", agoText(&buf, 300));
    try std.testing.expectEqualStrings("2h", agoText(&buf, 7200));
    try std.testing.expectEqualStrings("4d", agoText(&buf, 4 * 86400));
}
