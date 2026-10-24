const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");
    // The pictures: JPEG, PNG, BMP and the rest, in pure Zig.
    const zigimg = b.dependency("zigimg", .{ .target = target, .optimize = optimize }).module("zigimg");
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "nanoui", .module = nanoui },
        .{ .name = "zigimg", .module = zigimg },
    };

    const exe = b.addExecutable(.{ .name = "nanoflowvision", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });

    // Tests render the view offscreen with ui.Tester: no window opens.
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });

    // The system picture decoder, where the platform has one: WIC on
    // Windows, ImageIO on macOS. The pure-Zig way needs neither.
    const os_tag = target.result.os.tag;
    if (os_tag == .windows) {
        exe.root_module.linkSystemLibrary("ole32", .{});
        exe.root_module.linkSystemLibrary("windowscodecs", .{});
        tests.root_module.linkSystemLibrary("ole32", .{});
        tests.root_module.linkSystemLibrary("windowscodecs", .{});
    }
    if (os_tag == .macos) {
        exe.root_module.linkFramework("CoreFoundation", .{});
        exe.root_module.linkFramework("CoreGraphics", .{});
        exe.root_module.linkFramework("ImageIO", .{});
        tests.root_module.linkFramework("CoreFoundation", .{});
        tests.root_module.linkFramework("CoreGraphics", .{});
        tests.root_module.linkFramework("ImageIO", .{});
    }

    // A window of its own on Windows, without a console window beside it,
    // and the icon Explorer and the taskbar show.
    if (os_tag == .windows) {
        exe.subsystem = .windows;
        exe.root_module.addWin32ResourceFile(.{ .file = b.path("res/app.rc") });
    }
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run NanoFlowVision (opens its window)").dependOn(&run.step);

    b.step("test", "Run the tests").dependOn(&b.addRunArtifact(tests).step);
}
