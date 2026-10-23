const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zigimg = b.dependency("zigimg", .{ .target = target, .optimize = optimize }).module("zigimg");
    const exe = b.addExecutable(.{ .name = "wicprobe", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zigimg", .module = zigimg }},
    }) });
    exe.root_module.linkSystemLibrary("ole32", .{});
    exe.root_module.linkSystemLibrary("windowscodecs", .{});
    exe.root_module.linkSystemLibrary("psapi", .{});
    b.installArtifact(exe);
}
