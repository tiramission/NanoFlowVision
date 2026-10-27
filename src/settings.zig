//! The settings, in a panel that slides in from the right over the scrim
//! kit draws for it -- so the page behind is dimmed and knows it is not
//! the thing being talked to. Everything here lands in the settings file
//! the moment it is made; nothing needs a save button.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

const app = @import("app.zig");
const config = @import("config.zig");
const i18n = @import("i18n.zig");
const theme = @import("theme.zig");

/// Draws the panel; call it only while `s.settings_open`, from the
/// window's own level so the scrim covers everything.
pub fn view(s: *app.State, c: *ui.Context) void {
    const k = theme.colors(s.dark);
    const tr = i18n.strings(s.lang);
    const panel = kit.sheet(c, "settings", &s.settings_open, .{ .side = .right, .size = 360, .title = tr.settings }) orelse return;
    defer panel.end();

    // The language, each written as its speakers write it.
    group(c, tr.language, k.secondary);
    const lang_names = [_][]const u8{ i18n.ownName(.en), i18n.ownName(.zh) };
    var li: usize = @backingInt(s.lang);
    if (ui.segmented(c, &lang_names, &li)) {
        s.lang = @fromBackingInt(@intCast(li));
        s.saveSettings();
        c.changed = true;
    }

    // How the room is lit: with the system, or held at either end.
    group(c, tr.appearance, k.secondary);
    const appearances = [_][]const u8{ tr.appearance_auto, tr.appearance_light, tr.appearance_dark };
    var ai: usize = @backingInt(s.appearance);
    if (ui.segmented(c, &appearances, &ai)) {
        s.setAppearance(@fromBackingInt(@intCast(ai)));
        c.changed = true;
    }

    // How big the pictures are in the grid.
    group(c, tr.density, k.secondary);
    const densities = [_][]const u8{ tr.density_small, tr.density_medium, tr.density_large };
    var di: usize = @backingInt(s.density);
    if (ui.segmented(c, &densities, &di)) {
        s.density = @fromBackingInt(@intCast(di));
        s.orderChanged();
        s.saveSettings();
        c.changed = true;
    }

    // What the gallery takes in.
    if (ui.checkbox(c, tr.subfolders, &s.recursive)) {
        if (s.current) |folder| folder.loaded = false;
        s.relist_pending = true;
        s.saveSettings();
    }

    // Fades and slides, for a reader who would rather they were gone.
    // What carries state -- the hover, the selection ring -- still changes.
    if (ui.checkbox(c, tr.reduce_motion, &s.reduce_motion)) {
        s.saveSettings();
        c.changed = true;
    }

    // How wide the navigation column is, and the way back to the default.
    group(c, tr.rail_width, k.secondary);
    {
        const row = ui.div(c).row().wFull().itemsCenter().gap(10);
        defer row.end();
        if (ui.slider(c, &s.rail_w, .{ .min = 200, .max = 360, .width = .fill })) {
            s.saveSettings();
            c.changed = true;
        }
        ui.textf(c, .{ .size = 12, .mono = true, .color = k.secondary }, "{d:.0}", .{s.rail_w});
    }
    {
        const row = ui.div(c).row().wFull();
        defer row.end();
        ui.spacer(c);
        if (ui.button(c, tr.rail_reset, .{ .variant = .ghost, .size = 12 }).clicked) {
            s.rail_w = 240;
            s.saveSettings();
            c.changed = true;
        }
    }
}

/// The name of the group of controls that follows.
fn group(c: *ui.Context, label: []const u8, color: ui.Color) void {
    const d = ui.div(c).row().wFull().pt(6);
    defer d.end();
    ui.text(c, label, .{ .size = 12, .color = color });
}
