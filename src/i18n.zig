//! The interface's words, in English and Chinese. Everything a view draws
//! comes from here: `strings(lang)` hands back the set for the language,
//! and a view holds it for the frame (`const tr = i18n.strings(s.lang)`).
//! The format strings keep their `{d}`/`{s}` places for `c.print` to fill.
//! Chinese glyphs render through the font fallback (the system's CJK
//! face), which the TrueType shaper already does.

const std = @import("std");
const builtin = @import("builtin");

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
    clear_search: []const u8,
    folder_unreadable: []const u8,
    choose_other_folder: []const u8,
    subfolders: []const u8,
    watching: []const u8,
    folders: []const u8,
    /// The navigation rail: its section's name, and the word a folder
    /// with nothing inside it says.
    rail_library: []const u8,
    rail_no_subfolders: []const u8,
    /// The toolbar's more menu.
    rescan: []const u8,
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
    fit_label: []const u8,
    /// "Fill" -- the picture covers the room, its edges cropped.
    fill_label: []const u8,
    language: []const u8,
    lang_english: []const u8,
    lang_chinese: []const u8,
    /// The command bar's menus.
    sort_by: []const u8,
    sort_ascending: []const u8,
    sort_descending: []const u8,
    density: []const u8,
    density_small: []const u8,
    density_medium: []const u8,
    density_large: []const u8,
    /// "Grid density: Medium".
    density_set: []const u8,
    /// The settings sheet.
    appearance: []const u8,
    appearance_auto: []const u8,
    appearance_light: []const u8,
    appearance_dark: []const u8,
    reduce_motion: []const u8,
    rail_width: []const u8,
    rail_reset: []const u8,
    /// What the operations said back, as toasts.
    trashed: []const u8,
    trash_failed: []const u8,
    pasted: []const u8,
    paste_failed: []const u8,
    copied: []const u8,
    rename_taken: []const u8,
    rate_failed: []const u8,
    /// The status bar, and the tile that cannot be read.
    measuring_progress: []const u8,
    decode_failed: []const u8,
    /// The choice: what the status bar says, and the bulk's own words.
    selected_of: []const u8,
    select_all: []const u8,
    clear_selection: []const u8,
    dim_unselected: []const u8,
    /// What a held left button does on the large view.
    hold_label: []const u8,
    hold_look: []const u8,
    hold_drag: []const u8,
    /// "{d} of the chosen pictures" (a plural sentence of its own).
    trash_confirm_title: []const u8,
    trash_confirm_body: []const u8,
    trash_selected: []const u8,
    /// The large view's panel of facts, folded and open.
    info: []const u8,
    /// The star filter, and its way out.
    filter_min_stars: []const u8,
    clear_filter: []const u8,
    filter_empty: []const u8,
    /// "{d} of the choice the wall is not showing right now".
    hidden_by_filter: []const u8,
    /// The keyboard's map, said in one piece, one line to a key.
    keys_title: []const u8,
    /// "#{d}", where the keyboard's cursor stands.
    cursor_position: []const u8,
    /// "JPG, PNG, HEIC, WebP, AVIF…", under the empty folder's words.
    formats_hint: []const u8,
    /// What the icon buttons are, for the pointer that rests on one.
    filter_label: []const u8,
    more_label: []const u8,
    sidebar_label: []const u8,
    close_label: []const u8,
    fullscreen: []const u8,
    exit_fullscreen: []const u8,
    prev_picture: []const u8,
    next_picture: []const u8,
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
    .clear_search = "Clear search",
    .folder_unreadable = "Can't open this folder",
    .choose_other_folder = "Open another folder",
    .subfolders = "Subfolders",
    .watching = "Watching",
    .folders = "Folders",
    .rail_library = "Library",
    .rail_no_subfolders = "No subfolders here",
    .rescan = "Rescan",
    .open_large = "Open large",
    .open_system = "Open in system",
    .reveal = "Reveal in File Manager",
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
    .fit_label = "Fit",
    .fill_label = "Fill",
    .language = "Language",
    .lang_english = "English",
    .lang_chinese = "中文",
    .sort_by = "Sort by",
    .sort_ascending = "Ascending",
    .sort_descending = "Descending",
    .density = "Grid density",
    .density_small = "Small",
    .density_medium = "Medium",
    .density_large = "Large",
    .density_set = "Grid density: {s}",
    .appearance = "Appearance",
    .appearance_auto = "System",
    .appearance_light = "Light",
    .appearance_dark = "Dark",
    .reduce_motion = "Reduce motion",
    .rail_width = "Sidebar width",
    .rail_reset = "Reset width",
    .trashed = "Moved to Recycle Bin",
    .trash_failed = "Couldn't move it to the bin",
    .pasted = "Pasted {d} files",
    .paste_failed = "Some files couldn't be pasted",
    .copied = "Copied to clipboard",
    .rename_taken = "That name is taken",
    .rate_failed = "Rating wasn't written to the file",
    .measuring_progress = "Measuring {d}%",
    .decode_failed = "Can't read",
    .selected_of = "{d} of {d} selected",
    .select_all = "Select all",
    .clear_selection = "Clear selection",
    .dim_unselected = "Dim unselected while culling",
    .hold_label = "Left button held, large view",
    .hold_look = "Look at 1:1",
    .hold_drag = "Drag only",
    .trash_confirm_title = "Delete {d} pictures?",
    .trash_confirm_body = "First {s} · last {s}. They can be restored from the system bin.",
    .trash_selected = "Move to Recycle Bin",
    .info = "Info",
    .filter_min_stars = "★≥{d}",
    .clear_filter = "Clear filter",
    .filter_empty = "Nothing rated ★≥{d}",
    .hidden_by_filter = "{d} selected, hidden by the filter",
    .keys_title = "Keys",
    .cursor_position = "#{d}",
    .formats_hint = "JPG, PNG, HEIC, WebP, AVIF…",
    .filter_label = "Filter by stars",
    .more_label = "More",
    .sidebar_label = "Sidebar",
    .close_label = "Close",
    .fullscreen = "Full screen",
    .exit_fullscreen = "Exit full screen",
    .prev_picture = "Previous",
    .next_picture = "Next",
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
    .clear_search = "清除搜索",
    .folder_unreadable = "无法打开这个文件夹",
    .choose_other_folder = "打开其他目录",
    .rail_library = "资料库",
    .rail_no_subfolders = "此文件夹没有子文件夹",
    .rescan = "重新扫描",
    .subfolders = "包含子文件夹",
    .watching = "正在监视",
    .folders = "文件夹",
    .open_large = "打开大图",
    .open_system = "用系统打开",
    .reveal = "在文件夹中显示",
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
    .fit_label = "适应窗口",
    .fill_label = "铺满",
    .language = "语言",
    .lang_english = "English",
    .lang_chinese = "中文",
    .sort_by = "排序",
    .sort_ascending = "升序",
    .sort_descending = "降序",
    .density = "网格密度",
    .density_small = "小",
    .density_medium = "中",
    .density_large = "大",
    .density_set = "网格密度：{s}",
    .appearance = "外观",
    .appearance_auto = "跟随系统",
    .appearance_light = "亮",
    .appearance_dark = "暗",
    .reduce_motion = "减少动效",
    .rail_width = "导航栏宽度",
    .rail_reset = "复位宽度",
    .trashed = "已移到回收站",
    .trash_failed = "无法移到回收站",
    .pasted = "已粘贴 {d} 个文件",
    .paste_failed = "有文件没能粘贴",
    .copied = "已复制到剪贴板",
    .rename_taken = "这个名字已经存在",
    .rate_failed = "评分未写入文件",
    .measuring_progress = "正在测量 {d}%",
    .decode_failed = "无法读取",
    .selected_of = "已选 {d} / 共 {d}",
    .select_all = "选择全部",
    .clear_selection = "清除选择",
    .dim_unselected = "挑拣时压暗未选中",
    .hold_label = "大图按住左键",
    .hold_look = "临时 1:1",
    .hold_drag = "只拖动",
    .trash_confirm_title = "删除 {d} 张图片？",
    .trash_confirm_body = "首张 {s} · 末张 {s}。可在系统回收站中恢复。",
    .trash_selected = "移到回收站",
    .info = "信息",
    .filter_min_stars = "★≥{d}",
    .clear_filter = "清除筛选",
    .filter_empty = "没有 ★≥{d} 的图片",
    .hidden_by_filter = "另有 {d} 张已选的被筛选隐藏",
    .keys_title = "键盘",
    .cursor_position = "第 {d} 张",
    .formats_hint = "支持 JPG、PNG、HEIC、WebP、AVIF…",
    .filter_label = "按星级筛选",
    .more_label = "更多",
    .sidebar_label = "导航栏",
    .close_label = "关闭",
    .fullscreen = "全屏",
    .exit_fullscreen = "退出全屏",
    .prev_picture = "上一张",
    .next_picture = "下一张",
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
    // One picture is a picture, not a plural: the count is a sentence.
    if (lang == .en and n == 1) return "1 picture";
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

/// "Grid density: Medium", said when the density changes.
pub fn densitySet(alloc: std.mem.Allocator, lang: Lang, label: []const u8) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.density_set, .{label}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.density_set, .{label}) catch "…",
    };
}

/// "Pasted {d} files".
pub fn pasted(alloc: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.pasted, .{n}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.pasted, .{n}) catch "…",
    };
}

/// "Measuring {d}%", the status bar's line while the sizes arrive.
pub fn measuringProgress(alloc: std.mem.Allocator, lang: Lang, percent: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.measuring_progress, .{percent}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.measuring_progress, .{percent}) catch "…",
    };
}

/// "No matches for query".
pub fn noMatches(alloc: std.mem.Allocator, lang: Lang, query: []const u8) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.no_matches, .{query}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.no_matches, .{query}) catch "…",
    };
}

/// "★≥{d}", the filter's own chip.
pub fn filterMinStars(alloc: std.mem.Allocator, lang: Lang, stars: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.filter_min_stars, .{stars}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.filter_min_stars, .{stars}) catch "…",
    };
}

/// "Nothing rated ★≥{d}", the empty wall's own words.
pub fn filterEmpty(alloc: std.mem.Allocator, lang: Lang, stars: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.filter_empty, .{stars}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.filter_empty, .{stars}) catch "…",
    };
}

/// "{d} selected, hidden by the filter", when the choice outlasts the
/// wall it was made on.
pub fn hiddenByFilter(alloc: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.hidden_by_filter, .{n}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.hidden_by_filter, .{n}) catch "…",
    };
}

/// "#{d}" / "第 {d} 张": where the keyboard's cursor stands.
pub fn cursorPosition(alloc: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.cursor_position, .{n}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.cursor_position, .{n}) catch "…",
    };
}

/// "{d} of {d} selected", the status bar's line while a choice stands.
pub fn selectedOf(alloc: std.mem.Allocator, lang: Lang, chosen: usize, total: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.selected_of, .{ chosen, total }) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.selected_of, .{ chosen, total }) catch "…",
    };
}

/// "Delete {d} pictures?", the confirmation's title.
pub fn trashConfirmTitle(alloc: std.mem.Allocator, lang: Lang, n: usize) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.trash_confirm_title, .{n}) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.trash_confirm_title, .{n}) catch "…",
    };
}

/// "First {s} · last {s}. They can be restored from the system bin."
pub fn trashConfirmBody(alloc: std.mem.Allocator, lang: Lang, first: []const u8, last: []const u8) []const u8 {
    return switch (lang) {
        .en => std.fmt.allocPrint(alloc, en.trash_confirm_body, .{ first, last }) catch "…",
        .zh => std.fmt.allocPrint(alloc, zh.trash_confirm_body, .{ first, last }) catch "…",
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
            s.clear_search, s.folder_unreadable,
            s.choose_other_folder,
            s.subfolders,   s.watching,
            s.folders,      s.rail_library,
            s.rail_no_subfolders, s.rescan,
            s.open_large,
            s.open_system,  s.reveal,
            s.copy,         s.rename_menu,
            s.to_bin,       s.rename_title,
            s.cancel,       s.add_tag,
            s.keys_hint,    s.loading,
            s.settings,     s.language,
            s.lang_english, s.lang_chinese,
            s.sort_by,      s.sort_ascending,
            s.sort_descending, s.density,
            s.density_small, s.density_medium,
            s.density_large, s.density_set,
            s.appearance,   s.appearance_auto,
            s.appearance_light, s.appearance_dark,
            s.reduce_motion, s.rail_width,
            s.rail_reset,   s.trashed,
            s.trash_failed, s.pasted,
            s.paste_failed, s.copied,
            s.rename_taken, s.rate_failed,
            s.measuring_progress, s.decode_failed,
            s.selected_of,   s.select_all,
            s.clear_selection, s.dim_unselected,
            s.hold_label,       s.hold_look,
            s.hold_drag,        s.trash_confirm_title,
            s.trash_confirm_body,
            s.trash_selected,   s.info,
            s.filter_min_stars, s.clear_filter,
            s.filter_empty,     s.hidden_by_filter,
            s.keys_title,
            s.cursor_position,
            s.formats_hint,
            s.filter_label,
            s.more_label,
            s.sidebar_label,
            s.close_label,
            s.fullscreen,
            s.exit_fullscreen,
            s.prev_picture,
            s.next_picture,
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

