//! The menu of what one picture can have done to it -- opened large, put
//! on the clipboard, renamed, taken to the bin -- and the rename box it
//! can open. The menu sits at the corner it was opened from, over a sheet
//! that takes any click that misses it.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const large = @import("large.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const i18n = @import("i18n.zig");

/// The clipboard's files land in this folder, under names that do not
/// collide, and the gallery lists them.
pub fn paste(s: *app.State) void {
    const files = ops.clipboardFiles(s.gpa) orelse return;
    defer {
        for (files) |f| s.gpa.free(f);
        s.gpa.free(files);
    }
    const dir = s.current orelse return;
    for (files) |f| {
        const dest = ops.pasteInto(s.gpa, s.io, f, dir.path) catch continue;
        if (dest) |d| s.gpa.free(d);
    }
    s.relist_pending = true;
}

const Action = enum { open_large, open_system, reveal, copy, rename, trash };

/// The menu and the rename box, over the gallery they belong to.
pub fn view(s: *app.State, c: *ui.Context) void {
    const th = c.theme;
    if (s.renaming) |rp| {
        renameBox(s, c, th, rp);
        return;
    }
    const mp = s.menu_for orelse return;

    // A click that misses the menu closes it.
    const sheet = ui.div(c).absolute().offset(0, 0).w(c.size.w).h(c.size.h);
    defer sheet.end();
    {
        const it = ui.pressable(c, .{ .width = .fill, .height = .fill }, null);
        defer c.end();
        if (it.clicked) s.menu_for = null;
    }

    const menu = ui.div(c).absolute()
        .offset(s.menu_at.x, s.menu_at.y)
        .w(200)
        .p(4)
        .gap(2)
        .rounded(10)
        .bg(th.surface)
        .shadowMd();
    defer menu.end();
    const tr = i18n.strings(s.lang);
    item(s, c, th, mp, tr.open_large, .open_large);
    item(s, c, th, mp, tr.open_system, .open_system);
    item(s, c, th, mp, tr.reveal, .reveal);
    item(s, c, th, mp, tr.copy, .copy);
    item(s, c, th, mp, tr.rename_menu, .rename);
    item(s, c, th, mp, tr.to_bin, .trash);
}

fn item(s: *app.State, c: *ui.Context, th: anytype, mp: *model.Picture, label: []const u8, action: Action) void {
    const it = ui.pressable(c, .{
        .width = .fill,
        .padding = .xy(10, 6),
        .radius = 6,
        .control = true,
        .align_items = .center,
    }, th.surface_hover);
    defer c.end();
    ui.text(c, label, .{ .size = 13 });
    if (it.clicked) {
        s.menu_for = null;
        switch (action) {
            .open_large => large.show(s, mp),
            .open_system => _ = ops.open(mp.path),
            .reveal => ops.reveal(mp.path),
            .copy => ops.copyFileToClipboard(s.gpa, mp.path),
            .rename => {
                s.renaming = mp;
                s.rename_field.set(mp.name);
            },
            .trash => {
                if (ops.trash(mp.path)) s.relist_pending = true;
            },
        }
    }
}

/// The box that renames a picture: its name in a field, or a click on
/// the rest of the window to leave it as it is.
fn renameBox(s: *app.State, c: *ui.Context, th: anytype, rp: *model.Picture) void {
    const sheet = ui.div(c).absolute().offset(0, 0).w(c.size.w).h(c.size.h);
    defer sheet.end();
    {
        const it = ui.pressable(c, .{ .width = .fill, .height = .fill }, null);
        defer c.end();
        if (it.clicked) {
            s.renaming = null;
            s.rename_field.clear();
        }
    }

    const box = ui.div(c).absolute()
        .offset(@max(0, (c.size.w - 340) / 2), @max(0, (c.size.h - 110) / 2))
        .w(340)
        .p(14)
        .gap(8)
        .rounded(10)
        .bg(th.surface)
        .shadowMd();
    defer box.end();
    const tr = i18n.strings(s.lang);
    ui.text(c, tr.rename_title, .{ .size = 13, .weight = .semibold });
    const field = ui.textField(c, &s.rename_field, .{ .width = .fill, .size = 13 });
    ui.row(c, .{ .gap = 8, .align_items = .center });
    defer c.end();
    ui.spacer(c);
    if (ui.button(c, tr.cancel, .{ .variant = .ghost, .size = 13 }).clicked) {
        s.renaming = null;
        s.rename_field.clear();
    }
    if (ui.button(c, tr.rename_title, .{ .size = 13 }).clicked) commit(s, rp);
    if (field.submitted) commit(s, rp);
}

/// Puts the new name on the file, and into the tree, the gallery and the
/// cache. A name that is taken leaves everything as it was.
fn commit(s: *app.State, rp: *model.Picture) void {
    const new_name = std.mem.trim(u8, s.rename_field.text(), " ");
    defer s.rename_field.clear();
    s.renaming = null;
    if (new_name.len == 0 or std.mem.eql(u8, new_name, rp.name)) return;
    const new_path = ops.renameFile(s.gpa, s.io, rp.path, new_name) catch return;
    // The cache moves the picture's entries to the new path, so nothing
    // decodes again.
    s.shared.renameKey(s.gpa, rp.path, new_path);
    const name = s.gpa.dupe(u8, new_name) catch {
        s.gpa.free(new_path);
        return;
    };
    s.gpa.free(rp.name);
    rp.name = name;
    s.gpa.free(rp.path);
    rp.path = new_path;
    s.orderChanged();
}
