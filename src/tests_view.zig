//! The view's own tests: what the gallery, the tree and the large view
//! do when the reader touches them. The helpers they share -- the sample
//! folder, the waits -- live in tests.zig and are imported from there.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const tests_mod = @import("tests.zig");

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
    t.screenshot("docs/chip-hover.png") catch {};
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
    t.screenshot("docs/tree-expanded.png") catch {};
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
    state.reroot(second);

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
