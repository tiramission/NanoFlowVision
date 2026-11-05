//! nanoui v0.9.2, vendored: `src/` as upstream has it, plus one fix the app
//! needs (PATCHES.md). The build here is only the module — the examples,
//! the `nui` command and the reels are upstream's, not ours.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const portable = b.option(bool, "portable", "Use portable text and CPU rendering instead of native rasterization (for tests)") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "portable", portable);
    options.addOption([]const u8, "version", @import("build.zig.zon").version);

    const nanoui = b.addModule("nanoui", .{
        .root_source_file = b.path("src/nanoui.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    nanoui.addOptions("build_options", options);
    const os = target.result.os.tag;
    const frameworks = [_][]const u8{ "AppKit", "WebKit", "Metal", "QuartzCore", "CoreText", "CoreGraphics", "CoreFoundation", "Foundation", "ImageIO", "UniformTypeIdentifiers", "CoreVideo" };
    const ios_frameworks = [_][]const u8{ "UIKit", "CoreLocation", "MapKit", "Metal", "QuartzCore", "CoreText", "CoreGraphics", "CoreFoundation", "Foundation", "ImageIO", "UniformTypeIdentifiers", "CoreVideo" };
    if (os == .macos) {
        if (!target.query.isNative()) {
            if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk| {
                nanoui.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
                nanoui.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
            }
        }
        for (frameworks) |f| nanoui.linkFramework(f, .{});
        nanoui.linkSystemLibrary("objc", .{});
    } else if (os == .ios) {
        if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk| {
            nanoui.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
            nanoui.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
        }
        for (ios_frameworks) |f| nanoui.linkFramework(f, .{});
        nanoui.linkSystemLibrary("objc", .{});
    }
    if (target.result.abi.isAndroid()) {
        if (@import("tools/android/apk.zig").Sdk.find(b)) |sdk| if (sdk.libDir(b, target.result)) |dir| nanoui.addLibraryPath(.{ .cwd_relative = dir });
        for ([_][]const u8{ "android", "log", "EGL" }) |l| nanoui.linkSystemLibrary(l, .{});
    }
    if (os == .windows) {
        // The D3D11 renderer (`ui/d3d11.zig`): d3d11 and dxgi are the
        // system's, and d3dcompiler_47 turns the HLSL into shaders at
        // startup (it ships with Windows and every DirectX runtime).
        for ([_][]const u8{ "d3d11", "dxgi", "d3dcompiler_47" }) |l| nanoui.linkSystemLibrary(l, .{});
    }
    // HTTP there is http-zig's (nanoui.http), fetched only for those targets.
    if (os != .macos and os != .ios) {
        if (b.lazyDependency("http_zig", .{ .target = target, .optimize = optimize })) |d| nanoui.addImport("http_zig", d.module("http_zig"));
    }

    const tests = b.addTest(.{ .root_module = nanoui });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
