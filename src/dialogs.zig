//! The dialogs the app itself raises: the folder that could not be read,
//! and the bin's second thought before a handful of pictures goes into
//! it. Both are the kit's own dialogs -- drawn in the frame, over the
//! scrim the kit supplies -- and both lead out or through with a button.

const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const model = @import("model.zig");
const ops = @import("ops.zig");
const shell = @import("shell.zig");

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
        .description = if (s.current) |f| f.path else "",
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
