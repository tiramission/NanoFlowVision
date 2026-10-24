//! Tests for what goes into the picture files: the stars and the tags of
//! xmp.zig, from the bytes a camera would have written (src/exif.zig's
//! fixture) to the file on disk and back.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const exif = @import("exif.zig");
const xmp = @import("xmp.zig");
const theme = @import("theme.zig");
const config = @import("config.zig");
const i18n = @import("i18n.zig");
const ops = @import("ops.zig");
const thumbs = @import("thumbs.zig");
const tests_mod = @import("tests.zig");

/// The bytes of a jpeg that carries the fixture's exif: a real
/// photograph's scan with the fixture's APP1 hung in front, so the
/// decoders read a whole picture and the exif says what the fixture says.
const exifJpeg = tests_mod.exifJpeg;

test "stars go into the picture file, and the gallery sorts by them" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = try exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const dir_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(dir_path);

    const names = [_][]const u8{ "a.jpg", "b.jpg", "c.jpg" };
    for (names, 0..) |name, i| {
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = jpeg[0..] });
        var m: exif.Meta = .{};
        m.rating = @intCast(1 + i * 2);
        const file_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir_path, name });
        defer gpa.free(file_path);
        try xmp.rewriteFile(gpa, std.testing.io, file_path, &m);
    }

    const state = try app.State.create(gpa, std.testing.io, dir_path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // By stars: the most first.
    try t.clickText("Stars");
    t.settle(0.2);
    try std.testing.expectEqualStrings("c.jpg", state.shown[0].name);
    try std.testing.expectEqualStrings("a.jpg", state.shown[2].name);

    // The other way: the least first. The direction is its own icon now,
    // in the ghost button just right of the sort's segmented control.
    const stars = t.findText("Stars") orelse return error.TextNotFound;
    t.click(stars.x + stars.w + 38, stars.y + stars.h / 2);
    t.settle(0.2);
    try std.testing.expectEqualStrings("a.jpg", state.shown[0].name);
    try std.testing.expectEqualStrings("c.jpg", state.shown[2].name);
}

test "the number keys rate a picture, and t tags it, into the file" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = exif.Fixture.build(.little);
    const jpeg = try exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg[0..] });
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

    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    t.settle(0.2);

    // Four stars: the cache knows, and the file on disk says the same.
    t.typeText("4");
    t.settle(0.2);
    const pic_path = state.current.?.pictures[0].path;
    try std.testing.expectEqual(@as(i8, 4), state.shared.metaOf(pic_path).?.rating);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(bytes);
    try std.testing.expectEqual(@as(i8, 4), exif.parse(bytes).?.rating);

    // A tag: t opens the typing, the field takes the word, enter sets it.
    t.typeText("t");
    t.settle(0.1);
    try t.clickText("Add a tag…");
    t.typeText("family");
    t.key(.enter);
    t.settle(0.2);
    const meta = state.shared.metaOf(pic_path).?;
    try std.testing.expectEqual(@as(usize, 1), meta.tags_n);
    try std.testing.expectEqualStrings("family", meta.tagOf(0));
    const tagged = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(tagged);
    const on_disk = exif.parse(tagged).?;
    try std.testing.expectEqual(@as(usize, 1), on_disk.tags_n);
    try std.testing.expectEqualStrings("family", on_disk.tagOf(0));

    // Zero takes the stars off; the tags stay.
    t.typeText("0");
    t.settle(0.2);
    const cleared = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, pic_path, gpa, .limited(1 << 20));
    defer gpa.free(cleared);
    const out = exif.parse(cleared).?;
    try std.testing.expectEqual(@as(i8, -1), out.rating);
    try std.testing.expectEqual(@as(usize, 1), out.tags_n);
}

test "snapshot: the exif panel with stars and tags" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = exif.Fixture.build(.little);
    const jpeg = try exifJpeg(gpa, &f);
    defer gpa.free(jpeg);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "pic.jpg", .data = jpeg[0..] });
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    const path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
    defer gpa.free(path);

    var m: exif.Meta = .{};
    m.rating = 4;
    m.addTag("family");
    m.addTag("sea");
    const file_path = try std.fmt.allocPrint(gpa, "{s}/pic.jpg", .{path});
    defer gpa.free(file_path);
    try xmp.rewriteFile(gpa, std.testing.io, file_path, &m);

    const state = try app.State.create(gpa, std.testing.io, path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 1280, .height = 800, .theme = theme.forDark(true) });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.doubleClick(where.x + where.w / 2, where.y + where.h / 2);
    // The panel is there at once; wait for the picture itself, so the
    // snapshot shows the photograph under it.
    const large_key = try thumbs.largeKey(gpa, file_path);
    defer gpa.free(large_key);
    for (0..400) |_| {
        t.frame();
        if (state.shared.get(large_key)) |cached| {
            if (cached.thumb != null) break;
        }
        std.Io.sleep(std.testing.io, .fromMilliseconds(5), .awake) catch {};
    }
    t.frame();
    t.screenshot("docs/app-rating.png") catch {};
}

test "snapshot: chinese glyphs render" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The search field renders what is typed: Chinese goes through the
    // same shaping as everything else.
    state.search.set("搜索图片 深色 设置");
    t.frame();
    t.screenshot("docs/cjk-probe.png") catch {};
    try std.testing.expect(t.containsText("搜索图片 深色 设置"));
}

test "the settings panel switches the language, and it persists" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // A settings folder of its own: the panel's changes land there.
    std.Io.Dir.createDirAbsolute(std.testing.io, "C:/Users/jaign/AppData/Local/Temp/nfv-settings-test", .default_file) catch {};
    const dir_path = "C:/Users/jaign/AppData/Local/Temp/nfv-settings-test";

    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    const owned_dir = try gpa.dupe(u8, dir_path);
    defer gpa.free(owned_dir);
    state.settings_dir = owned_dir;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);

    // The sidebar's foot has the settings; open it.
    try t.clickText("Settings");
    t.settle(0.1);
    try std.testing.expect(state.settings_open);

    // The language, to Chinese: the sort speaks Chinese right away.
    try t.clickText("中文");
    t.settle(0.1);
    try std.testing.expectEqual(i18n.Lang.zh, state.lang);
    try t.clickText("关闭");
    t.settle(0.1);
    try std.testing.expect(!state.settings_open);
    try std.testing.expect(t.hasText("名称"));
    try std.testing.expect(t.hasText("上级"));

    // And the file on disk says so. The root it carries is the load's
    // own memory, and goes back when the test is done with it.
    const saved = config.load(gpa, std.testing.io, dir_path);
    defer if (saved.root.len > 0) gpa.free(saved.root);
    try std.testing.expectEqual(i18n.Lang.zh, saved.lang);
}

test "snapshot: the interface in chinese" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    state.lang = .zh;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);
    t.settle(0.1);
    t.screenshot("docs/app-zh.png") catch {};
    try std.testing.expect(t.containsText("张图片"));
}

test "snapshot: the settings panel open" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    state.lang = .zh;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600 });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try t.clickText("设置");
    t.settle(0.1);
    t.screenshot("docs/settings-open.png") catch {};
}

test "snapshot: the picture menu and the dark settings" {
    const gpa = std.testing.allocator;
    var sample = try tests_mod.makeSample(gpa);
    defer sample.deinit(gpa);
    const state = try app.State.create(gpa, std.testing.io, sample.path);
    defer state.deinit();
    state.lang = .zh;
    state.dark = true;
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(state, app.State.view), .{ .width = 900, .height = 600, .theme = theme.forDark(true) });
    defer t.deinit();
    try tests_mod.waitForLayout(&t, state);
    try tests_mod.waitForThumbs(&t, state);

    // The menu, opened from the picture's corner.
    t.frame();
    t.frame();
    const where = state.first_picture orelse return error.NoPictureOnScreen;
    t.moveTo(where.x + where.w / 2, where.y + where.h / 2);
    t.frame();
    try t.clickText("⋯");
    t.settle(0.1);
    t.screenshot("docs/menu-zh.png") catch {};
    state.menu_for = null;
    t.frame();

    // The dark settings card.
    try t.clickText("设置");
    t.settle(0.1);
    t.screenshot("docs/settings-dark.png") catch {};
}
