//! The view's own tests: what the gallery, the tree and the large view
//! do when the reader touches them. The helpers they share -- the sample
//! folder, the waits -- live in tests.zig and are imported from there.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const tests_mod = @import("tests.zig");
const shell = @import("shell.zig");
const thumbs = @import("thumbs.zig");

comptime {
    _ = @import("tests_shell.zig");
}

test "a picture's exif is read when it is measured, and shows large" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // The bytes a camera writes: an Exif APP1 in front of a real
    // photograph's scan.
    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg });

    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The measurements carry the exif, taken from the bytes it already had.
    const pic_path = state.current.?.pictures[0].path;
    const meta = state.shared.metaOf(pic_path).?;
    try std.testing.expectEqualStrings("Canon", meta.makeOf());
    try std.testing.expectEqual(@as(u32, 200), meta.iso);

    // And the large view says so.
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);

    try std.testing.expect(t.containsText("Canon EOS R5"));
    try std.testing.expect(t.containsText("ISO 200"));
    try std.testing.expect(t.containsText("f/2.8"));
    try std.testing.expect(t.containsText("1/250 s"));
    try std.testing.expect(t.containsText("2024-01-02 03:04"));
}

test "hovering a picture raises the chip, and it opens the menu" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    t.frame();
    t.frame();

    const where = state.first_picture orelse return error.NoPictureOnScreen;

    // The pointer off the pictures: no chip anywhere.
    t.moveTo(450, 590);
    t.frame();
    try std.testing.expect(!t.hasText("⋯"));

    // On the picture: the chip is there, drawn on top of the photograph
    // (not merely among the nodes), and clicking it opens the menu.
    t.moveTo(where.x + where.w - 10, where.y + 10);
    t.frame();
    try std.testing.expect(t.hasText("⋯"));
    try t.clickText("⋯");
    t.frame();
    try std.testing.expect(state.menu_for != null);
    try std.testing.expect(t.hasText("Open large"));
}

test "the tree unfolds at a folder's chevron, without opening it" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album/2024");
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/two.png", .data = png });
    // The folder the walk opens holds a picture of its own, so the grid
    // it lands on has something to walk.
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/2024/one.png", .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try std.testing.expect(t.hasText("album"));

    // The chevron sits left of the folder's chip: clicking it folds the
    // folder open, and does not open the folder itself.
    const where = t.findText("album") orelse return error.TextNotFound;
    t.click(where.x - 46, where.y + where.h / 2);
    t.settle(0.2);
    const album = &state.tree.children[0];
    try std.testing.expect(album.expanded);
    try std.testing.expect(state.current != album);
    try std.testing.expect(t.hasText("2024"));

    // Below the folder's row, not beside it: a child drawn on the row's
    // own line is a child no one will ever see.
    const ralb = t.findText("album").?;
    const r2024 = t.findText("2024").?;
    try std.testing.expect(r2024.y > ralb.y + ralb.h);

    // The disk's changes read the folder again; what was folded open
    // goes on being open, and stays where a reader can see it.
    state.relist();
    t.settle(0.2);
    try std.testing.expect(state.tree.children[0].expanded);
    const ralb2 = t.findText("album").?;
    const r2024b = t.findText("2024").?;
    try std.testing.expect(r2024b.y > ralb2.y + ralb2.h);
}

test "the large view says where it stands, and the strip walks it" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSampleWith(gpa, 12);
    defer sample.deinit(gpa);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();

    // Opened large, the view says which one of twelve it is, and names
    // the file.
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);
    try std.testing.expect(state.large != null);
    try std.testing.expect(t.hasText("1 / 12"));
    try std.testing.expect(t.containsText("pic-0.png"));

    // The strip's cells stand where the state wrote them: the fifth
    // takes the view there, and the count says so.
    try tests_mod.waitForThumbs(&t, state);
    t.frame();
    t.frame();
    const cell = state.filmstrip_at.items[4];
    t.click(cell.x + cell.w / 2, cell.y + cell.h / 2);
    t.settle(0.2);
    try std.testing.expect(t.hasText("5 / 12"));
    try std.testing.expectEqual(@as(usize, 4), state.select.cursor.?);

    // Escape back to the wall: the keyboard lands where the view was.
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expect(state.large == null);
    try std.testing.expectEqual(@as(usize, 4), state.select.cursor.?);
}

test "the large view's panel folds to a line, and the zoom speaks" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);

    // The large pixels first: the keys below land where the picture's
    // own size is known.
    const large_key = try thumbs.largeKey(gpa, state.large.?.path);
    defer gpa.free(large_key);
    var decoded = false;
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(large_key)) |known| {
            if (known.thumb != null) {
                decoded = true;
                break;
            }
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    try std.testing.expect(decoded);

    // Open, the panel says what the picture says about itself.
    try std.testing.expect(t.containsText("ISO 200"));

    // `i` folds it to a line: the facts are gone, the word is not.
    t.typeText("i");
    t.settle(0.1);
    try std.testing.expect(!state.info_open);
    try std.testing.expect(!t.containsText("ISO 200"));
    try std.testing.expect(t.hasText("Info"));

    // And back.
    t.typeText("i");
    t.settle(0.1);
    try std.testing.expect(state.info_open);
    try std.testing.expect(t.containsText("ISO 200"));

    // `z`: the zoom stands at 1:1 and says so, in its own figures --
    // said once the easing has arrived, which takes its few frames.
    t.typeText("z");
    t.settle(0.5);
    try std.testing.expect(state.zoom_target != null);
    try std.testing.expect(t.hasText("100%"));

    // Again: back to the fit, said in words.
    t.typeText("z");
    t.settle(0.2);
    try std.testing.expect(state.zoom_target == null);
    try std.testing.expect(t.hasText("Fit"));
}

test "the tree takes the keyboard, and gives it back" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    try sample.tmp.dir.createDirPath(std.testing.io, "album/2024");
    var red = [_]u8{ 0, 0, 255, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/two.png", .data = png });
    // The folder the walk opens holds a picture of its own, so the grid
    // it lands on has something to walk.
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "album/2024/one.png", .data = png });

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 900 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // Tab: the tree has the keyboard, on its first row.
    t.key(.tab);
    t.settle(0.1);
    try std.testing.expect(state.tree_focus != null);
    try std.testing.expectEqualStrings("album", state.tree_focus.?.name);

    // Down walks the visible rows; right opens and goes in; Enter
    // opens what the highlight stands on.
    t.key(.right);
    t.settle(0.1);
    try std.testing.expect(state.tree.children[0].expanded);
    try std.testing.expectEqualStrings("album", state.tree_focus.?.name);
    // The second right goes in: the folder is open now.
    t.key(.right);
    t.settle(0.1);
    try std.testing.expectEqualStrings("2024", state.tree_focus.?.name);
    t.key(.enter);
    t.settle(0.2);
    try std.testing.expectEqualStrings("2024", state.current.?.name);

    // Tab again: the keyboard is the grid's, and the arrows walk it.
    t.key(.tab);
    t.settle(0.1);
    try std.testing.expect(state.tree_focus == null);
    const before = state.select.cursor;
    t.key(.down);
    t.settle(0.2);
    try std.testing.expect(state.select.cursor != before);
}

test "another folder can become the root" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);

    // A second folder, with a photograph of its own.
    var red = [_]u8{ 0, 255, 0, 255 };
    const png = try ui.png.encode(gpa, .{ .bytes = red[0..], .width = 1, .height = 1 });
    defer gpa.free(png);
    try sample.tmp.dir.createDirPath(std.testing.io, "second");
    try sample.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "second/own.png", .data = png });
    const second = try std.fmt.allocPrint(gpa, "{s}/second", .{sample.path});
    defer gpa.free(second);

    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    shell.reroot(state, second);

    // The tree is rooted at it, the root folder is shown, and its
    // picture is the gallery's own.
    try std.testing.expectEqualStrings("second", state.tree.name);
    try std.testing.expectEqual(@as(usize, 1), state.tree.pictures.len);
    try std.testing.expectEqualStrings("own.png", state.tree.pictures[0].name);
    try std.testing.expect(state.current == &state.tree);

    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try std.testing.expect(t.hasText("second"));

    // The old root's pictures are gone from the tree.
    try std.testing.expect(!t.hasText("pic-0.png"));
}

test "the large view's chrome stands off the picture, and its chips work" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = try tests_mod.exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1000, .height = 800, .theme = @import("theme.zig").forDark(false) });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);
    t.frame();

    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.3);
    try std.testing.expect(state.large != null);

    // The index and name live in the top bar; the facts stand below it,
    // in the picture's corner -- never under the bar they would hide.
    const index = t.findText("1 / 1") orelse return error.TextNotFound;
    try std.testing.expect(index.y < 44);
    const info = t.findText("Info") orelse return error.TextNotFound;
    try std.testing.expect(info.y > 44);

    // The strip's cells keep the pictures' shapes and stay in the
    // window: nothing runs off the edge.
    t.frame();
    try std.testing.expect(state.filmstrip_at.items.len >= 1);
    for (state.filmstrip_at.items) |cell| {
        try std.testing.expect(cell.x >= 0 and cell.x + cell.w <= 1000.5);
        try std.testing.expect(cell.y + cell.h <= 800.5);
        try std.testing.expect(cell.h <= 48.5);
    }

    // The way out is a click, not only a key.
    const shut = state.large_close_at;
    try std.testing.expect(shut.w > 0);
    t.click(shut.x + shut.w / 2, shut.y + shut.h / 2);
    t.settle(0.3);
    try std.testing.expect(state.large == null);
}
