//! The folders, down the left: the app's mark, the tree the reader walks
//! -- the folder it is rooted at, and what is inside it, with a count of
//! what each holds -- and the settings at its foot. The rail says
//! nothing about the pictures; it only says where they are.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

const app = @import("app.zig");
const i18n = @import("i18n.zig");
const model = @import("model.zig");
const shell = @import("shell.zig");
const theme = @import("theme.zig");

/// The whole column, as tall as the window.
pub fn view(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    shell.treeKeys(s, c);
    const side = ui.div(c).column().w(s.rail_w).hFull().bg(k.sidebar).px(10).gap(2);
    defer side.end();
    // The rail is one of the two stops in the focus ring: Tab lands here,
    // and the arrows walk the tree. Its id is asked for before the box
    // opens, so the row itself can show the ring.
    const rail_index = c.stack.items[c.stack.items.len - 1];
    const rail_id = c.node(rail_index).id;
    _ = c.interact(rail_index, .{ .focusable = true });
    if (s.tree_focus == null and c.focus == rail_id) {
        s.tree_focus = shell.firstVisible(&s.tree) orelse &s.tree;
        c.changed = true;
    } else if (s.tree_focus != null and c.focus != rail_id) {
        s.tree_focus = null;
        c.changed = true;
    }
    {
        const top = ui.div(c).row().wFull().h(44).itemsCenter().gap(8).px(6);
        defer top.end();
        // The mark, the app's own: a photograph on the inverted ground,
        // so the one saturated thing in the rail is the logo.
        {
            const mark = ui.div(c).row().w(22).h(22).center().rounded(6).bg(k.accent);
            defer mark.end();
            ui.icon(c, "photo", .{ .size = 12, .color = k.page });
        }
        ui.text(c, "NanoFlowVision", .{ .size = 13, .weight = .bold, .color = k.text });
    }
    section(c, k, tr.rail_library);
    ui.scroll(c, .{ .width = .fill, .height = .fill, .gap = 2 });
    // The folder the tree is rooted at is a row of its own: without it a
    // root with no subfolders leaves the column blank, and there is
    // nothing to click to come back to where the reader started.
    folderRow(s, c, k, &s.tree, 0);
    // A folder with nothing inside it says so, under its own row: an
    // empty column is not an answer, it is a question, and the answer
    // belongs where the eye asks it.
    if (s.tree.children.len == 0) {
        const none = ui.div(c).wFull().pl(7 + 12 + 45).py(4);
        defer none.end();
        ui.text(c, tr.rail_no_subfolders, .{ .size = 12, .color = k.tertiary });
    }
    ui.end(c);
    // The settings, one click away at the sidebar's foot, with the key
    // that opens them written beside it.
    {
        var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
        defer row.end();
        row = row.hover(k.hover);
        if (row.clicked()) {
            s.settings_open = true;
            c.changed = true;
        }
        {
            const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(k.accent.alpha(0.16));
            defer chip.end();
            ui.icon(c, "slider.horizontal.3", .{ .size = 11, .color = k.accent });
        }
        ui.text(c, tr.settings, .{ .size = 13, .color = k.text });
        ui.spacer(c);
        ui.text(c, ui.keys.label("⌘,"), .{ .size = 11, .mono = true, .color = k.tertiary });
    }
    // The rail's edge is a handle: drag it to give the folders more room
    // or the pictures more; a double click puts it back where it began.
    {
        const handle = ui.div(c).absolute().offset(s.rail_w - 15, 0).w(5).hFull().control();
        const it = handle.interaction();
        defer handle.end();
        if (it.hovered or it.pressed) c.cursor = .resize_left_right;
        if (it.double_clicked) {
            if (s.rail_w != 240) {
                s.rail_w = 240;
                s.saveSettings();
                c.changed = true;
            }
        } else if (it.pressed and c.input.down) {
            if (!s.rail_dragging) {
                s.rail_dragging = true;
                s.rail_grab = s.rail_w - c.input.mouse.x;
            }
            const want = std.math.clamp(c.input.mouse.x + s.rail_grab, 200, 360);
            if (@abs(want - s.rail_w) >= 0.5) {
                s.rail_w = want;
                c.changed = true;
            }
        } else if (it.rect != null and c.input.released and s.rail_dragging) {
            // The hand let go: the width it chose is remembered.
            s.rail_dragging = false;
            s.saveSettings();
        }
    }
}

/// A rail section's name.
fn section(c: *ui.Context, k: theme.Colors, name: []const u8) void {
    const d = ui.div(c).row().wFull().px(8).pt(14).pb(4);
    defer d.end();
    ui.text(c, name, .{ .size = 11, .weight = .semibold, .color = k.tertiary });
}

/// One folder in the tree, and -- when it is open -- the folders inside
/// it, below its row.
fn folderRow(s: *app.State, c: *ui.Context, k: theme.Colors, folder: *model.Folder, depth: usize) void {
    const on = s.current == folder;
    const fg = if (on) k.on_picked else k.text;
    {
        var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
        // The keyboard's row stands out the way the pointer's does, so a
        // walk in the tree can be followed without the mouse.
        row = if (on) row.bg(k.picked) else if (s.tree_focus == folder) row.bg(k.hover) else row.hover(k.hover);
        row = row.pl(7 + @as(f32, @floatFromInt(depth)) * 12);
        defer row.end();
        // The chevron is sampled first: a click on it folds the folder's
        // own in and out, and must not also open the folder -- both
        // boxes sit under the pointer, and both would hear the click.
        var folded = false;
        if (folder.children.len > 0) {
            var chev = ui.div(c).row().w(16).h(24).center().rounded(5).control();
            defer chev.end();
            ui.icon(c, if (folder.expanded) "chevron.down" else "chevron.right", .{ .size = 10, .color = if (on) k.on_picked.alpha(0.7) else k.tertiary });
            if (chev.clicked()) {
                folder.expanded = !folder.expanded;
                folded = true;
                c.changed = true;
            }
        } else {
            _ = c.leaf(.{ .width = .{ .px = 16 }, .height = .{ .px = 24 } }, .none, null);
        }
        if (row.clicked() and !folded) {
            s.open(folder);
            // The folders inside it show, now that it is open.
            folder.expanded = true;
            c.changed = true;
        }
        {
            const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(if (on) k.on_picked.alpha(0.22) else k.accent.alpha(0.16));
            defer chip.end();
            ui.icon(c, "folder", .{ .size = 11, .color = if (on) k.on_picked else k.accent });
        }
        ui.text(c, folder.name, .{ .size = 13, .weight = if (on) .semibold else .regular, .color = fg });
        ui.spacer(c);
        if (folder.pictures.len > 0) {
            ui.textf(c, .{ .size = 11, .mono = true, .color = if (on) k.on_picked.alpha(0.8) else k.secondary }, "{d}", .{folder.pictures.len});
        }
    }
    // The folders inside it, drawn BELOW its row: the row is closed by
    // now, or its children would flow on beside it, a single thirty-point
    // line wide, and never be seen.
    if (folder.expanded) {
        for (folder.children) |*child| folderRow(s, c, k, child, depth + 1);
    }
}
