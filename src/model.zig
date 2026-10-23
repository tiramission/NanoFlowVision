//! What the app shows: the folders of the tree, and the pictures of a folder.

const std = @import("std");
const decode = @import("decode.zig");

pub const Load = enum {
    /// Nothing asked for yet.
    waiting,
    /// Asked for; the workers have it.
    working,
    /// The thumbnail is ready.
    ready,
    /// It cannot be read.
    failed,
};

pub const Picture = struct {
    /// The file's full path.
    path: []u8,
    /// Its name, without the folder.
    name: []u8,
    /// Width over height; 1 until the header has been read.
    aspect: f32 = 1,
    /// Whether the header has been read.
    measured: bool = false,
    load: Load = .waiting,
    /// The thumbnail's pixels, once decoded.
    thumb: ?decode.Pixels = null,

    pub fn deinit(self: *Picture, gpa: std.mem.Allocator) void {
        if (self.path.len > 0) gpa.free(self.path);
        if (self.name.len > 0) gpa.free(self.name);
        if (self.thumb) |t| t.deinit(gpa);
        self.thumb = null;
    }
};

/// A folder in the tree, and the pictures inside it.
pub const Folder = struct {
    /// The folder's full path.
    path: []u8,
    /// Its name, without the parent.
    name: []u8,
    /// How deep it sits under the root.
    depth: usize = 0,
    /// Whether it is open in the tree.
    expanded: bool = false,
    /// Whether its folders inside have been read.
    loaded: bool = false,
    /// The folders inside it.
    children: []Folder = &.{},
    /// The pictures inside it.
    pictures: []Picture = &.{},

    pub fn deinit(self: *Folder, gpa: std.mem.Allocator) void {
        if (self.path.len > 0) gpa.free(self.path);
        if (self.name.len > 0) gpa.free(self.name);
        for (self.children) |*child| child.deinit(gpa);
        gpa.free(self.children);
        for (self.pictures) |*p| p.deinit(gpa);
        gpa.free(self.pictures);
        self.children = &.{};
        self.pictures = &.{};
    }
};

/// The picture extensions the gallery shows.
pub const picture_extensions = [_][]const u8{
    ".jpg",  ".jpeg", ".png",  ".gif",  ".bmp",
    ".webp", ".tif",  ".tiff", ".heic", ".avif",
    ".qoi",  ".ico",
};

/// Whether a name is one of the pictures the gallery shows.
pub fn isPicture(name: []const u8) bool {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
    const ext = name[dot..];
    for (picture_extensions) |known| {
        if (std.ascii.eqlIgnoreCase(ext, known)) return true;
    }
    return false;
}

/// A path with a name inside it.
pub fn join(gpa: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, dir.len + 1 + name.len);
    @memcpy(out[0..dir.len], dir);
    out[dir.len] = '/';
    @memcpy(out[dir.len + 1 ..], name);
    return out;
}

/// The folder a path is in, or null for a path at the root.
pub fn parentOf(path: []const u8) ?[]const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return null;
    if (slash == 0) return null;
    return path[0..slash];
}

/// The last part of a path.
pub fn nameOf(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[slash + 1 ..];
}

test "a name is a picture when its extension is one" {
    try std.testing.expect(isPicture("a.JPG"));
    try std.testing.expect(isPicture("holiday.heic"));
    try std.testing.expect(!isPicture("notes.txt"));
    try std.testing.expect(!isPicture("no-extension"));
}

test "a path splits into its folder and its name" {
    try std.testing.expectEqualStrings("a/b", parentOf("a/b/c.jpg").?);
    try std.testing.expectEqualStrings("c.jpg", nameOf("a/b/c.jpg"));
    try std.testing.expect(parentOf("c.jpg") == null);
}
