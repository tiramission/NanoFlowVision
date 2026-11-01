//! The folders, down the left: the app's mark, the tree the reader walks
//! (with a count of what each folder holds), and the settings at its
//! foot. The rail says nothing about the pictures; it only says where
//! they are.

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
    folders(s, c, k, &s.tree);
    ui.end(c);
    // A folder with nothing inside it says so: an empty column is not an
    // answer, it is a question.
    if (s.tree.children.len == 0) {
        const none = ui.div(c).wFull().px(8).py(6);
        defer none.end();
        ui.text(c, tr.rail_no_subfolders, .{ .size = 12, .color = k.tertiary });
    }
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
}

/// A rail section's name.
fn section(c: *ui.Context, k: theme.Colors, name: []const u8) void {
    const d = ui.div(c).row().wFull().px(8).pt(14).pb(4);
    defer d.end();
    ui.text(c, name, .{ .size = 11, .weight = .semibold, .color = k.tertiary });
}

fn folders(s: *app.State, c: *ui.Context, k: theme.Colors, folder: *model.Folder) void {
    for (folder.children) |*child| {
        const on = s.current == child;
        const fg = if (on) k.on_picked else k.text;
        {
            var row = ui.div(c).row().wFull().h(30).itemsCenter().gap(9).px(7).rounded(7).control();
            // The keyboard's row stands out the way the pointer's does,
            // so a walk in the tree can be followed without the mouse.
            row = if (on) row.bg(k.picked) else if (s.tree_focus == child) row.bg(k.hover) else row.hover(k.hover);
            row = row.pl(7 + @as(f32, @floatFromInt(child.depth)) * 12);
            defer row.end();
            // The chevron is sampled first: a click on it folds the folder's
            // own in and out, and must not also open the folder -- both
            // boxes sit under the pointer, and both would hear the click.
            var folded = false;
            if (child.children.len > 0) {
                var chev = ui.div(c).row().w(16).h(24).center().rounded(5).control();
                defer chev.end();
                ui.icon(c, if (child.expanded) "chevron.down" else "chevron.right", .{ .size = 10, .color = k.tertiary });
                if (chev.clicked()) {
                    child.expanded = !child.expanded;
                    folded = true;
                    c.changed = true;
                }
            } else {
                _ = c.leaf(.{ .width = .{ .px = 16 }, .height = .{ .px = 24 } }, .none, null);
            }
            if (row.clicked() and !folded) {
                s.open(child);
                // The folders inside it show, now that it is open.
                child.expanded = true;
                c.changed = true;
            }
            {
                const chip = ui.div(c).row().w(20).h(20).center().rounded(6).bg(if (on) k.on_picked.alpha(0.22) else k.accent.alpha(0.16));
                defer chip.end();
                ui.icon(c, "folder", .{ .size = 11, .color = if (on) k.on_picked else k.accent });
            }
            ui.text(c, child.name, .{ .size = 13, .weight = if (on) .semibold else .regular, .color = fg });
            ui.spacer(c);
            if (child.pictures.len > 0) {
                ui.textf(c, .{ .size = 11, .mono = true, .color = if (on) k.on_picked.alpha(0.8) else k.secondary }, "{d}", .{child.pictures.len});
            }
        }
        // The folders inside it, drawn BELOW its row: the row is closed
        // by now, or its children would flow on beside it, a single
        // thirty-point line wide, and never be seen.
        if (child.expanded) folders(s, c, k, child);
    }
}
