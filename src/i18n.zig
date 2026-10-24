//! The interface's words, in English and Chinese. Everything a view draws
//! comes from here: `strings(lang)` hands back the set for the language,
//! and a view holds it for the frame (`const tr = i18n.strings(s.lang)`).
//! The format strings keep their `{d}`/`{s}` places for `c.print` to fill.
//! Chinese glyphs render through the font fallback (the system's CJK
//! face), which the TrueType shaper already does.

const std = @import("std");

pub const Lang = enum { en, zh };

/// Every string the interface draws, in one language.
pub const Strings = struct {
    up: []const u8,
    search_placeholder: []const u8,
    sort_name: []const u8,
    sort_date: []const u8,
    sort_size: []const u8,
    sort_pixels: []const u8,
    sort_stars: []const u8,
    /// "{d} pictures" and "{d} of {d} pictures".
    pictures: []const u8,
    pictures_of: []const u8,
    /// "measuring {d} of {d}…".
    measuring: []const u8,
    no_pictures: []const u8,
    /// "No matches for \"{s}\"".
    no_matches: []const u8,
    subfolders: []const u8,
    watching: []const u8,
    folders: []const u8,
    open_large: []const u8,
    open_system: []const u8,
    reveal: []const u8,
    copy: []const u8,
    rename_menu: []const u8,
    to_bin: []const u8,
    rename_title: []const u8,
    cancel: []const u8,
    add_tag: []const u8,
    keys_hint: []const u8,
    loading: []const u8,
    settings: []const u8,
    open_folder: []const u8,
    language: []const u8,
    dark_mode: []const u8,
    lang_english: []const u8,
    lang_chinese: []const u8,
    close: []const u8,
};

const en: Strings = .{
    .up = "Up",
    .search_placeholder = "Search…",
    .sort_name = "Name",
    .sort_date = "Date",
    .sort_size = "Size",
    .sort_pixels = "Pixels",
    .sort_stars = "Stars",
    .pictures = "{d} pictures",
    .pictures_of = "{d} of {d} pictures",
    .measuring = "measuring {d} of {d}…",
    .no_pictures = "No pictures here",
    .no_matches = "No matches for \"{s}\"",
    .subfolders = "Subfolders",
    .watching = "Watching",
    .folders = "Folders",
    .open_large = "Open large",
    .open_system = "Open in system",
    .reveal = "Reveal in Explorer",
    .copy = "Copy",
    .rename_menu = "Rename…",
    .to_bin = "Move to Recycle Bin",
    .rename_title = "Rename",
    .cancel = "Cancel",
    .add_tag = "Add a tag…",
    .keys_hint = "1-5 rate · t tag · 0 clear",
    .loading = "loading…",
    .settings = "Settings",
    .open_folder = "Open folder",
    .language = "Language",
    .dark_mode = "Dark mode",
    .lang_english = "English",
    .lang_chinese = "中文",
    .close = "Close",
};

const zh: Strings = .{
    .up = "上级",
    .search_placeholder = "搜索…",
    .sort_name = "名称",
    .sort_date = "日期",
    .sort_size = "大小",
    .sort_pixels = "像素",
    .sort_stars = "评分",
    .pictures = "{d} 张图片",
    .pictures_of = "第 {d} 张，共 {d} 张",
    .measuring = "正在测量 {d} / {d}…",
    .no_pictures = "这里没有图片",
    .no_matches = "没有匹配“{s}”的结果",
    .subfolders = "包含子文件夹",
    .watching = "正在监视",
    .folders = "文件夹",
    .open_large = "打开大图",
    .open_system = "用系统打开",
    .reveal = "在资源管理器中显示",
    .copy = "复制",
    .rename_menu = "重命名…",
    .to_bin = "移到回收站",
    .rename_title = "重命名",
    .cancel = "取消",
    .add_tag = "添加标签…",
    .keys_hint = "1-5 评分 · t 标签 · 0 清除",
    .loading = "加载中…",
    .settings = "设置",
    .open_folder = "打开目录",
    .language = "语言",
    .dark_mode = "深色模式",
    .lang_english = "English",
    .lang_chinese = "中文",
    .close = "关闭",
};

/// The strings for `lang`.
pub fn strings(lang: Lang) Strings {
    return switch (lang) {
        .en => en,
        .zh => zh,
    };
}

/// The language's name in the settings' own list, where each is written
/// as its speakers write it.
pub fn ownName(lang: Lang) []const u8 {
    return switch (lang) {
        .en => "English",
        .zh => "中文",
    };
}

/// The two languages, for a control that lists them.
pub const langs = [_]Lang{ .en, .zh };

// The strings with places in them, allocated in the frame's arena (the
// format functions want a comptime fmt, so each language formats in its
// own branch).

/// "{n} pictures", the header's count of a whole folder.
pub fn pictures(alloc: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.pictures, .{n}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.pictures, .{n}) catch "…",
    };
}

/// "{shown} of {total} pictures", when a search narrows the folder.
pub fn picturesOf(alloc: std.mem.Allocator, lang: Lang, shown: usize, total: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.pictures_of, .{ shown, total }) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.pictures_of, .{ shown, total }) catch "…",
    };
}

/// "measuring {done} of {total}…", before the layout is made.
pub fn measuring(alloc: std.mem.Allocator, lang: Lang, done: usize, total: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.measuring, .{ done, total }) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.measuring, .{ done, total }) catch "…",
    };
}

/// "No matches for query".
pub fn noMatches(alloc: std.mem.Allocator, lang: Lang, query: []const u8) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.no_matches, .{query}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.no_matches, .{query}) catch "…",
    };
}

test "both languages carry every string, non-empty" {
    inline for (langs) |lang| {
        const s = strings(lang);
        const all = [_][]const u8{
            s.up,           s.search_placeholder,
            s.sort_name,    s.sort_date,
            s.sort_size,    s.sort_pixels,
            s.sort_stars,   s.pictures,
            s.pictures_of,  s.measuring,
            s.no_pictures,  s.no_matches,
            s.subfolders,   s.watching,
            s.folders,      s.open_large,
            s.open_system,  s.reveal,
            s.copy,         s.rename_menu,
            s.to_bin,       s.rename_title,
            s.cancel,       s.add_tag,
            s.keys_hint,    s.loading,
            s.settings,     s.language,
            s.dark_mode,    s.lang_english,
            s.lang_chinese, s.close,
        };
        for (all) |v| try std.testing.expect(v.len > 0);
    }
}

test "the languages differ where it matters" {
    const s_en = strings(.en);
    const s_zh = strings(.zh);
    try std.testing.expect(!std.mem.eql(u8, s_en.sort_name, s_zh.sort_name));
    try std.testing.expect(!std.mem.eql(u8, s_en.to_bin, s_zh.to_bin));
    // But the language names are written as their speakers write them.
    try std.testing.expectEqualStrings(s_en.lang_english, ownName(.en));
    try std.testing.expectEqualStrings(s_zh.lang_chinese, ownName(.zh));
}
