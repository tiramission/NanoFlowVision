//! The menu of what a picture -- or the choice -- can have done to it,
//! and the rename box it can open. The menu is the kit's own: it hangs
//! from the corner it was opened at, dismisses on a click that misses,
//! and says each command's key beside it.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const dialogs = @import("dialogs.zig");
const large = @import("large.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const i18n = @import("i18n.zig");
const keys = @import("keys.zig");

/// The clipboard's files land in this folder, under names that do not
/// collide, and the gallery lists them.
pub fn paste(s: *app.State) void {
    const files = ops.clipboardFiles(s.gpa) orelse return;
    defer {
        for (files) |f| s.gpa.free(f);
        s.gpa.free(files);
    }
    const dir = s.current orelse return;
    const tr = i18n.strings(s.lang);
    var landed: usize = 0;
    var missed: usize = 0;
    for (files) |f| {
        const dest = ops.pasteInto(s.gpa, s.io, f, dir.path) catch {
            missed += 1;
            continue;
        };
        if (dest) |d| {
            s.gpa.free(d);
            landed += 1;
        } else missed += 1;
    }
    s.relist_pending = true;
    // What happened, said back: a paste that half worked says so rather
    // than leaving the reader counting files.
    if (missed > 0 and landed == 0) {
        s.toast(.danger, tr.paste_failed);
    } else if (missed > 0) {
        s.toast(.warning, tr.paste_failed);
    } else if (landed > 0) {
        const title = i18n.pasted(s.gpa, s.lang, landed);
        s.toast(.success, title);
        s.gpa.free(title);
    }
}

/// Copies the pictures onto the clipboard, as files, in the order shown.
fn copyPics(s: *app.State, pics: []const *model.Picture) void {
    if (pics.len == 0) return;
    const paths = s.gpa.alloc([]const u8, pics.len) catch return;
    defer s.gpa.free(paths);
    for (pics, 0..) |p, i| paths[i] = p.path;
    ops.copyFilesToClipboard(s.gpa, paths);
    s.toast(.success, i18n.strings(s.lang).copied);
}

/// The menu, over the gallery it belongs to: one picture's commands, or
/// -- while a choice stands that is more than the one it was opened
/// from -- the choice's own two.
pub fn view(s: *app.State, c: *ui.Context) void {
    if (s.rename_open) {
        renameDialog(s, c);
        return;
    }
    if (s.menu_for == null) return;

    var open = s.menu_for != null;
    const tr = i18n.strings(s.lang);
    var items: [8]kit.MenuItem = undefined;
    var n: usize = 0;

    if (s.select.count() > 1 and s.select.has(s.menu_for.?.path)) {
        // The choice's menu: the two things a handful of pictures can
        // ask for together, and nothing that would have to ask one by
        // one. The bin's own line is in the command bar's colour of
        // trouble, so the hand lands there on purpose.
        items[n] = .{ .label = tr.copy, .icon = "doc.on.doc", .shortcut = "⌘C" };
        n += 1;
        items[n] = .{ .label = tr.trash_selected, .icon = "trash", .shortcut = keys.delete_key, .danger = true };
        n += 1;
    } else {
        const mp = s.menu_for.?;
        items[n] = .{ .label = tr.open_large, .icon = "photo", .shortcut = "␣" };
        n += 1;
        items[n] = .{ .label = tr.open_system, .icon = "arrow.right.square", .shortcut = "⌘↩" };
        n += 1;
        items[n] = .{ .label = tr.reveal, .icon = "folder", .shortcut = "⌘⇧R" };
        n += 1;
        items[n] = .{ .label = tr.copy, .icon = "doc.on.doc", .shortcut = "⌘C" };
        n += 1;
        items[n] = .{ .label = tr.rename_menu, .icon = "pencil", .shortcut = "F2", .disabled = !large.editable(mp.name) };
        n += 1;
        items[n] = .{ .separator = true };
        n += 1;
        items[n] = .{ .label = tr.to_bin, .icon = "trash", .shortcut = keys.delete_key, .danger = true };
        n += 1;
    }

    if (kit.menu(c, "picture-menu", &open, s.menu_at, items[0..n], .{})) |chosen| {
        const mp = s.menu_for.?;
        // What the command lands on: the whole choice when the menu was
        // the choice's own, the one picture otherwise.
        var picked: []*model.Picture = &.{};
        var owned = false;
        if (s.select.count() > 1 and s.select.has(mp.path)) {
            if (s.select.chosen(s.gpa, s.shown)) |got| {
                picked = got;
                owned = true;
            } else |_| {}
        } else {
            if (s.gpa.alloc(*model.Picture, 1)) |one| {
                one[0] = mp;
                picked = one[0..1];
                owned = true;
            } else |_| {}
        }
        defer if (owned) s.gpa.free(picked);
        const multi = picked.len > 1;
        if (!multi) {
            switch (chosen) {
                0 => large.show(s, mp),
                1 => _ = ops.open(mp.path),
                2 => ops.reveal(mp.path),
                3 => copyPics(s, picked),
                4 => {
                    s.renaming = mp;
                    s.rename_open = true;
                    s.rename_field.set(mp.name);
                    s.rename_error = false;
                },
                6 => dialogs.askTrash(s, picked),
                else => {},
            }
        } else {
            switch (chosen) {
                0 => copyPics(s, picked),
                1 => dialogs.askTrash(s, picked),
                else => {},
            }
        }
    }
    // The menu dismissed itself -- a click that missed, or the key --
    // and the state follows it out.
    if (!open and s.menu_for != null) s.menu_for = null;
}

/// The box that renames a picture: its name in a field, Cancel beside
/// Rename. A name that is taken does not close the box -- it says so
/// beside the field, and the typing carries on.
fn renameDialog(s: *app.State, c: *ui.Context) void {
    const tr = i18n.strings(s.lang);
    const d = kit.dialog(c, "rename", &s.rename_open, .{
        .title = tr.rename_title,
        .ok = tr.rename_title,
        .cancel = tr.cancel,
        .close_button = false,
    }) orelse {
        // Gone, and the exit with it: nothing left over.
        if (s.renaming != null) {
            s.renaming = null;
            s.rename_field.clear();
            s.rename_error = false;
        }
        return;
    };
    const field = ui.textField(c, &s.rename_field, .{ .width = .{ .px = 380 }, .size = 13 });
    if (s.rename_error) {
        ui.text(c, tr.rename_taken, .{ .size = 12, .color = c.theme.danger });
    }
    const said = d.end();
    if (field.submitted or said == .ok) tryRename(s);
    if (!s.rename_open and s.renaming != null) {
        // Escaped, or cancelled: the name is left as it was.
        s.renaming = null;
        s.rename_field.clear();
        s.rename_error = false;
    }
}

/// Puts the new name on the file, and into the tree, the gallery and the
/// cache. A name that is taken keeps the box up, with the word beside
/// the field; anything else that fails says so and closes.
fn tryRename(s: *app.State) void {
    const rp = s.renaming orelse return;
    const new_name = std.mem.trim(u8, s.rename_field.text(), " ");
    if (new_name.len == 0 or std.mem.eql(u8, new_name, rp.name)) {
        // The same name, or nothing: the box goes, nothing changed.
        s.rename_open = false;
        s.renaming = null;
        s.rename_field.clear();
        s.rename_error = false;
        return;
    }
    const new_path = ops.renameFile(s.gpa, s.io, rp.path, new_name) catch |err| {
        if (err == error.NameExists) {
            // The word, beside the field, where the typing is.
            s.rename_error = true;
            return;
        }
        s.toast(.danger, i18n.strings(s.lang).rename_taken);
        s.rename_open = false;
        s.renaming = null;
        s.rename_field.clear();
        return;
    };
    s.rename_error = false;
    s.rename_open = false;
    s.renaming = null;
    s.rename_field.clear();
    // The cache moves the picture's entries to the new path, so nothing
    // decodes again; the choice follows the file, not the name.
    s.shared.renameKey(s.gpa, rp.path, new_path);
    s.select.rename(rp.path, new_path);
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
