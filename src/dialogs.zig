//! The dialogs the app itself raises: the folder that could not be read,
//! and the bin's second thought before a handful of pictures goes into
//! it. Both are the kit's own dialogs -- drawn in the frame, over the
//! scrim the kit supplies -- and both lead out or through with a button.

const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const keys = @import("keys.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const shell = @import("shell.zig");

/// The keyboard's map, as a table: keys in mono on the left, what they
/// do on the right, grouped by where they act. Two columns of groups,
/// so the whole map fits a window without scrolling. Escape, the dimming
/// or the button takes it away.
pub fn keysDialog(s: *app.State, c: *ui.Context) void {
    const tr = i18n.strings(s.lang);
    const d = kit.dialog(c, "keys", &s.keys_open, .{
        .title = tr.keys_title,
        .ok = "",
        .cancel = "",
        .width = 780,
    }) orelse return;
    const groups = keys.forLang(@intFromEnum(s.lang));
    const split = @min(2, groups.len);
    ui.row(c, .{ .width = .fill, .gap = 40, .align_items = .start });
    var side: usize = 0;
    while (side < 2) : (side += 1) {
        ui.column(c, .{ .grow = 1, .gap = 10 });
        const from = if (side == 0) 0 else split;
        const to = if (side == 0) split else groups.len;
        for (groups[from..to]) |group| {
            ui.column(c, .{ .width = .fill, .gap = 2 });
            ui.text(c, group.title, .{ .size = 11, .weight = .semibold, .color = c.theme.muted });
            for (group.rows) |row| {
                _ = ui.div(c).row().wFull().h(18).itemsCenter().gap(10);
                _ = ui.div(c).row().w(136).justifyEnd().itemsCenter();
                ui.text(c, row.keys, .{ .size = 12, .mono = true, .color = c.theme.text });
                ui.end(c);
                ui.text(c, row.what, .{ .size = 12.5, .color = c.theme.muted });
                ui.end(c);
            }
            ui.end(c);
        }
        ui.end(c);
    }
    ui.end(c);
    _ = d.end();
}

/// Asks for the bin: one picture goes at once; several wait for the
/// word, and the confirmation stands over the folder they belong to,
/// which cannot change while it does.
pub fn askTrash(s: *app.State, pics: []const *model.Picture) void {
    if (pics.len == 0) return;
    const tr = i18n.strings(s.lang);
    if (pics.len == 1) {
        if (ops.trash(pics[0].path)) {
            s.toast(.success, tr.trashed);
            s.relist_pending = true;
        } else s.toast(.danger, tr.trash_failed);
        return;
    }
    s.confirming_trash.clearRetainingCapacity();
    for (pics) |p| s.confirming_trash.append(s.gpa, p) catch return;
}

/// The folder could not be read: said in a dialog over the page, with
/// the way out at hand. The system dialog it can lead to opens after
/// the frame, as always.
pub fn brokenFolder(s: *app.State, c: *ui.Context) void {
    const tr = i18n.strings(s.lang);
    const d = kit.dialog(c, "folder-broken", &s.folder_broken, .{
        .title = tr.folder_unreadable,
        .description = if (s.current) |f|
            model.tildeOf(c.alloc(), s.home, f.path) catch f.path
        else
            "",
        .ok = tr.choose_other_folder,
        .cancel = "",
        .close_button = false,
    }) orelse return;
    if (d.end() == .ok) shell.askForFolder(s);
}

/// The bin's second thought: the pictures named in `confirming_trash` go
/// only when the dialog says so. One picture goes without asking; this
/// is for the handful a selection holds.
pub fn trashConfirm(s: *app.State, c: *ui.Context) void {
    const tr = i18n.strings(s.lang);
    var wants = s.confirming_trash.items.len > 0;
    const d = kit.dialog(c, "trash-confirm", &wants, .{
        .title = i18n.trashConfirmTitle(c.alloc(), s.lang, s.confirming_trash.items.len),
        .description = i18n.trashConfirmBody(
            c.alloc(),
            s.lang,
            s.confirming_trash.items[0].name,
            s.confirming_trash.items[s.confirming_trash.items.len - 1].name,
        ),
        .ok = tr.trash_selected,
        .cancel = tr.cancel,
        .ok_variant = .danger,
        .close_button = false,
    }) orelse return;
    const said = d.end();
    if (said == .ok) {
        var moved: usize = 0;
        for (s.confirming_trash.items) |pic| {
            if (ops.trash(pic.path)) moved += 1;
        }
        if (moved > 0) {
            s.toast(.success, tr.trashed);
            s.relist_pending = true;
        }
        if (moved < s.confirming_trash.items.len) s.toast(.danger, tr.trash_failed);
    }
    if (said != .none) {
        s.confirming_trash.clearRetainingCapacity();
        c.changed = true;
    }
}
