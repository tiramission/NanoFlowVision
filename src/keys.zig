//! The keyboard map, as data: four groups, each a list of "keys do
//! this" rows, in both languages. The dialog lays it out as a table and
//! the tests hold the two languages to the same shape. Kept out of
//! `i18n.zig` so that file stays the words, not the whole map.

const std = @import("std");
const builtin = @import("builtin");

// The key that deletes: the glyph where the system font has it, the word
// where it does not (the mono font on Windows has no ⌫).
pub const delete_key = if (builtin.os.tag == .macos) "⌫" else "Del";

// The keyboard's map, as data rather than one block of text: the dialog
// lays it out as a table, keys on the left in mono, what they do on the
// right. The groups are the four places the keys act in.
pub const KeyRow = struct { keys: []const u8, what: []const u8 };
pub const KeyGroup = struct { title: []const u8, rows: []const KeyRow };

const en_keys = [_]KeyGroup{
    .{ .title = "Everywhere", .rows = &.{
        .{ .keys = "Ctrl+O", .what = "Open a folder" },
        .{ .keys = "Ctrl+,", .what = "Settings" },
        .{ .keys = "Ctrl+B", .what = "Show / hide the sidebar" },
        .{ .keys = "Ctrl+F", .what = "Search" },
        .{ .keys = "Ctrl+/", .what = "This table" },
        .{ .keys = "Ctrl+D", .what = "Light / dark" },
        .{ .keys = "Ctrl+↑", .what = "Up one folder" },
        .{ .keys = "F5", .what = "Rescan" },
        .{ .keys = "Esc", .what = "Let go, one layer at a time" },
        .{ .keys = "F11", .what = "Full screen" },
    } },
    .{ .title = "Grid", .rows = &.{
        .{ .keys = "← →", .what = "Across columns" },
        .{ .keys = "↑ ↓", .what = "Along a column" },
        .{ .keys = "Home End", .what = "First / last" },
        .{ .keys = "PgUp PgDn", .what = "A screen at a time" },
        .{ .keys = "Space Enter", .what = "Open large" },
        .{ .keys = "0–5", .what = "Rate (0 clears)" },
        .{ .keys = delete_key, .what = "Move to the bin" },
        .{ .keys = "F2", .what = "Rename" },
        .{ .keys = "Ctrl+C", .what = "Copy the files" },
        .{ .keys = "Ctrl+V", .what = "Paste into this folder" },
        .{ .keys = "Ctrl+A", .what = "Select all" },
        .{ .keys = "Ctrl+Shift+R", .what = "Reveal in the file manager" },
        .{ .keys = "Ctrl+Enter", .what = "Open with the system app" },
        .{ .keys = "T", .what = "Open large, typing a tag" },
    } },
    .{ .title = "Large view", .rows = &.{
        .{ .keys = "← →", .what = "Previous / next" },
        .{ .keys = "Space Esc", .what = "Close" },
        .{ .keys = "0–5", .what = "Rate" },
        .{ .keys = "T", .what = "Tag" },
        .{ .keys = "Z", .what = "Fit ⇄ 1:1" },
        .{ .keys = "F", .what = "Fill the screen ⇄ 1:1" },
        .{ .keys = "I", .what = "Fold the facts" },
        .{ .keys = delete_key, .what = "Bin it, then the next" },
        .{ .keys = "Wheel / drag", .what = "Zoom / pan" },
        .{ .keys = "LMB hold", .what = "Look at 1:1 under the pointer (drag to pan)" },
        .{ .keys = "RMB hold", .what = "Look at it fitted to the window" },
    } },
    .{ .title = "Sidebar", .rows = &.{
        .{ .keys = "↑ ↓", .what = "Move the highlight" },
        .{ .keys = "→", .what = "Unfold, or go in" },
        .{ .keys = "←", .what = "Fold, or go up" },
        .{ .keys = "Enter", .what = "Open the highlighted folder" },
        .{ .keys = "Tab", .what = "Back to the grid" },
    } },
};

const zh_keys = [_]KeyGroup{
    .{ .title = "全局", .rows = &.{
        .{ .keys = "Ctrl+O", .what = "打开目录" },
        .{ .keys = "Ctrl+,", .what = "设置" },
        .{ .keys = "Ctrl+B", .what = "显示 / 隐藏导航栏" },
        .{ .keys = "Ctrl+F", .what = "搜索" },
        .{ .keys = "Ctrl+/", .what = "这张表" },
        .{ .keys = "Ctrl+D", .what = "亮 / 暗" },
        .{ .keys = "Ctrl+↑", .what = "上级目录" },
        .{ .keys = "F5", .what = "重新扫描" },
        .{ .keys = "Esc", .what = "逐层放开" },
        .{ .keys = "F11", .what = "全屏" },
    } },
    .{ .title = "网格", .rows = &.{
        .{ .keys = "← →", .what = "跨列走" },
        .{ .keys = "↑ ↓", .what = "沿列走" },
        .{ .keys = "Home End", .what = "第一张 / 最后一张" },
        .{ .keys = "PgUp PgDn", .what = "上 / 下一屏" },
        .{ .keys = "Space Enter", .what = "打开大图" },
        .{ .keys = "0–5", .what = "评分（0 清除）" },
        .{ .keys = delete_key, .what = "移到回收站" },
        .{ .keys = "F2", .what = "重命名" },
        .{ .keys = "Ctrl+C", .what = "复制文件" },
        .{ .keys = "Ctrl+V", .what = "粘贴到当前文件夹" },
        .{ .keys = "Ctrl+A", .what = "全选" },
        .{ .keys = "Ctrl+Shift+R", .what = "在文件夹中显示" },
        .{ .keys = "Ctrl+Enter", .what = "用系统打开" },
        .{ .keys = "T", .what = "打开大图并加标签" },
    } },
    .{ .title = "大图", .rows = &.{
        .{ .keys = "← →", .what = "上一张 / 下一张" },
        .{ .keys = "Space Esc", .what = "关闭" },
        .{ .keys = "0–5", .what = "评分" },
        .{ .keys = "T", .what = "标签" },
        .{ .keys = "Z", .what = "适应 ⇄ 1:1" },
        .{ .keys = "F", .what = "铺满 ⇄ 1:1" },
        .{ .keys = "I", .what = "收起信息" },
        .{ .keys = delete_key, .what = "回收站，然后下一张" },
        .{ .keys = "滚轮 / 拖动", .what = "缩放 / 平移" },
        .{ .keys = "按住左键", .what = "在指针处看 1:1" },
        .{ .keys = "按住右键", .what = "看适应窗口的样子" },
    } },
    .{ .title = "导航栏", .rows = &.{
        .{ .keys = "↑ ↓", .what = "移动高亮行" },
        .{ .keys = "→", .what = "展开 / 进入子项" },
        .{ .keys = "←", .what = "折叠 / 回到父项" },
        .{ .keys = "Enter", .what = "打开高亮的文件夹" },
        .{ .keys = "Tab", .what = "回到网格" },
    } },
};

/// The keyboard's map for a language, group by group.
pub fn forLang(lang: u1) []const KeyGroup {
    return if (lang == 0) &en_keys else &zh_keys;
}

test "every key group has rows in both languages" {
    inline for ([_]u1{ 0, 1 }) |lang| {
        const groups = forLang(lang);
        try std.testing.expectEqual(@as(usize, 4), groups.len);
        for (groups) |g| {
            try std.testing.expect(g.title.len > 0);
            try std.testing.expect(g.rows.len > 0);
            for (g.rows) |row| {
                try std.testing.expect(row.keys.len > 0);
                try std.testing.expect(row.what.len > 0);
            }
        }
    }
}
