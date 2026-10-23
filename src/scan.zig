//! Reading folders and files.

const std = @import("std");
const model = @import("model.zig");

/// What a folder holds: the folders in it and the pictures in it.
pub const Listing = struct {
    /// The names of the folders inside.
    folders: [][]u8 = &.{},
    /// The names of the pictures inside.
    pictures: [][]u8 = &.{},

    pub fn deinit(self: *Listing, gpa: std.mem.Allocator) void {
        for (self.folders) |name| gpa.free(name);
        gpa.free(self.folders);
        for (self.pictures) |name| gpa.free(name);
        gpa.free(self.pictures);
        self.folders = &.{};
        self.pictures = &.{};
    }
};

/// The folder's contents: the folders and the pictures in it.
pub fn list(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Listing {
    var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var folders: std.ArrayList([]u8) = .empty;
    errdefer {
        for (folders.items) |name| gpa.free(name);
        folders.deinit(gpa);
    }
    var pictures: std.ArrayList([]u8) = .empty;
    errdefer {
        for (pictures.items) |name| gpa.free(name);
        pictures.deinit(gpa);
    }

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => try folders.append(gpa, try gpa.dupe(u8, entry.name)),
            .file => if (model.isPicture(entry.name)) {
                try pictures.append(gpa, try gpa.dupe(u8, entry.name));
            },
            else => {},
        }
    }
    return .{
        .folders = try folders.toOwnedSlice(gpa),
        .pictures = try pictures.toOwnedSlice(gpa),
    };
}

/// The first bytes of a file: enough to read a picture's size from its header.
pub fn readHeader(io: std.Io, path: []const u8, buffer: []u8) ![]u8 {
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    var reader = file.reader(io, buffer);
    const n = try reader.interface.readSliceShort(buffer);
    return buffer[0..n];
}

/// A whole file, for a picture to be decoded.
pub fn readAll(gpa: std.mem.Allocator, io: std.Io, path: []const u8, limit: std.Io.Limit) ![]u8 {
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    var buffer: [64 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(gpa, limit);
}

/// A file's size and its last change, for the gallery to sort by.
pub fn statFile(io: std.Io, path: []const u8) !std.Io.File.Stat {
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    return file.stat(io);
}

test "a name's extension says whether it is a picture" {
    try std.testing.expect(model.isPicture("a.jpg"));
    try std.testing.expect(!model.isPicture("a"));
}
