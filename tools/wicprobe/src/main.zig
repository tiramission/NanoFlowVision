//! A probe: does Windows' WIC decode a picture straight to a thumbnail,
//! without ever holding the whole picture in memory?
//!
//!     cd tools/wicprobe && zig build -Doptimize=ReleaseFast
//!     zig-out/bin/wicprobe.exe <file> [max_side] [wic|wic2|zigimg]
//!
//! It prints the size it got, how long it took, the most memory the
//! process held, and the first pixel -- so the two ways of decoding can be
//! compared. `wic` is WIC, `zigimg` is the way the gallery does it now.
const std = @import("std");

extern "psapi" fn GetProcessMemoryInfo(process: ?*anyopaque, mem: *ProcessMemoryCounters, cb: u32) u32;
extern "kernel32" fn GetCurrentProcess() ?*anyopaque;

const ProcessMemoryCounters = extern struct {
    cb: u32 = 0,
    page_fault_count: u32 = 0,
    peak_working_set: usize = 0,
    working_set: usize = 0,
    quota_peak_paged: usize = 0,
    quota_paged: usize = 0,
    quota_peak_non_paged: usize = 0,
    quota_non_paged: usize = 0,
    pagefile_usage: usize = 0,
    peak_pagefile_usage: usize = 0,
};

/// The most memory this process ever held, in bytes.
fn peakMemory() usize {
    var counters: ProcessMemoryCounters = .{ .cb = @sizeOf(ProcessMemoryCounters) };
    if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, @sizeOf(ProcessMemoryCounters)) == 0) return 0;
    return counters.peak_working_set;
}
const zigimg = @import("zigimg");

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const clsid_factory = GUID{ .data1 = 0xcacaf262, .data2 = 0x9370, .data3 = 0x4615, .data4 = .{ 0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a } };
const iid_factory = GUID{ .data1 = 0xec5ec8a9, .data2 = 0xc395, .data3 = 0x4314, .data4 = .{ 0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70 } };
const iid_decoder = GUID{ .data1 = 0x9edde9e7, .data2 = 0x8dee, .data3 = 0x47ea, .data4 = .{ 0x99, 0xdf, 0xe6, 0xfa, 0xf2, 0xed, 0x44, 0xbf } };
const iid_scaler = GUID{ .data1 = 0x00000302, .data2 = 0xa8f2, .data3 = 0x4877, .data4 = .{ 0xba, 0x0a, 0xfd, 0x2b, 0x66, 0x45, 0xfb, 0x94 } };
const iid_converter = GUID{ .data1 = 0x00000301, .data2 = 0xa8f2, .data3 = 0x4877, .data4 = .{ 0xba, 0x0a, 0xfd, 0x2b, 0x66, 0x45, 0xfb, 0x94 } };
/// 32bpp premultiplied BGRA: the same pixels nanoui draws.
const fmt_bgra_premultiplied = GUID{ .data1 = 0x6fddc324, .data2 = 0x4e03, .data3 = 0x4bfe, .data4 = .{ 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10 } };

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, co_init: u32) i32;
extern "ole32" fn CoCreateInstance(
    clsid: *const GUID,
    outer: ?*anyopaque,
    ctx: u32,
    iid: *const GUID,
    out: *?*anyopaque,
) i32;

const CLSCTX_INPROC_SERVER: u32 = 1;
const COINIT_MULTITHREADED: u32 = 0x2;
const GENERIC_READ: u32 = 0x80000000;
const WICBitmapInterpolationModeFant: i32 = 3;

const Rect = extern struct { x: i32, y: i32, width: u32, height: u32 };

const Factory = struct {
    queryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    addRef: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    createDecoderFromFilename: *const fn (*anyopaque, [*:0]const u16, ?*anyopaque, u32, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createDecoderFromStream: *const fn (*anyopaque, *anyopaque, u32, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createDecoderFromFileHandle: *const fn (*anyopaque, *anyopaque, u32, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createComponentInfo: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createDecoder: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createEncoder: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createPalette: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    createFormatConverter: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    createBitmapScaler: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
};

const Decoder = struct {
    queryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    addRef: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    queryCapability: *const fn (*anyopaque, *anyopaque, *u32) callconv(.winapi) i32,
    initialize: *const fn (*anyopaque, *anyopaque, u32, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    getContainerFormat: *const fn (*anyopaque, *const GUID) callconv(.winapi) i32,
    getDecoderInfo: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    copyPalette: *const fn (*anyopaque, *anyopaque) callconv(.winapi) i32,
    getMetadataQueryReader: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    getPreview: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    getColorContexts: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    getThumbnail: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) i32,
    getFrameCount: *const fn (*anyopaque, *u32) callconv(.winapi) i32,
    getFrame: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) i32,
};

/// IWICBitmapSource, the base of the scaler and the converter.
const Source = struct {
    queryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    addRef: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    getSize: *const fn (*anyopaque, *u32, *u32) callconv(.winapi) i32,
    getPixelFormat: *const fn (*anyopaque, *const GUID) callconv(.winapi) i32,
    getResolution: *const fn (*anyopaque, *f64, *f64) callconv(.winapi) i32,
    copyPalette: *const fn (*anyopaque, *anyopaque) callconv(.winapi) i32,
    copyPixels: *const fn (*anyopaque, ?*const Rect, u32, u32, [*]u8) callconv(.winapi) i32,
};

const Scaler = struct {
    queryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    addRef: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    getSize: *const fn (*anyopaque, *u32, *u32) callconv(.winapi) i32,
    getPixelFormat: *const fn (*anyopaque, *const GUID) callconv(.winapi) i32,
    getResolution: *const fn (*anyopaque, *f64, *f64) callconv(.winapi) i32,
    copyPalette: *const fn (*anyopaque, *anyopaque) callconv(.winapi) i32,
    copyPixels: *const fn (*anyopaque, ?*const Rect, u32, u32, [*]u8) callconv(.winapi) i32,
    initialize: *const fn (*anyopaque, *anyopaque, u32, u32, i32) callconv(.winapi) i32,
};

const Converter = struct {
    queryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) i32,
    addRef: *const fn (*anyopaque) callconv(.winapi) u32,
    release: *const fn (*anyopaque) callconv(.winapi) u32,
    getSize: *const fn (*anyopaque, *u32, *u32) callconv(.winapi) i32,
    getPixelFormat: *const fn (*anyopaque, *const GUID) callconv(.winapi) i32,
    getResolution: *const fn (*anyopaque, *f64, *f64) callconv(.winapi) i32,
    copyPalette: *const fn (*anyopaque, *anyopaque) callconv(.winapi) i32,
    copyPixels: *const fn (*anyopaque, ?*const Rect, u32, u32, [*]u8) callconv(.winapi) i32,
    initialize: *const fn (*anyopaque, *anyopaque, *const GUID, i32, ?*anyopaque, f64, i32) callconv(.winapi) i32,
    canConvert: *const fn (*anyopaque, *const GUID, *i32) callconv(.winapi) i32,
};

fn vtable(com: *anyopaque, comptime T: type) *const T {
    const p: *const *const T = @ptrCast(@alignCast(com));
    return p.*;
}

fn hrText(hr: i32) []const u8 {
    return switch (@as(u32, @bitCast(hr))) {
        0x8007007f => "ERROR_PROC_NOT_FOUND",
        0x80070002 => "ERROR_FILE_NOT_FOUND",
        0x80070005 => "E_ACCESSDENIED",
        0x80070006 => "E_HANDLE",
        0x80070057 => "E_INVALIDARG",
        0x88982f85 => "WINCODEC_ERR_COMPONENTNOTFOUND",
        0x88982f87 => "WINCODEC_ERR_FILENOTFOUND",
        0x88982f8b => "WINCODEC_ERR_WRONGSTATE",
        else => "unknown",
    };
}

fn check(hr: i32, what: []const u8) !void {
    if (hr < 0) {
        std.debug.print("failed: {s} (hr=0x{x} {s})\n", .{ what, @as(u32, @bitCast(hr)), hrText(hr) });
        return error.Failed;
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var args = std.process.Args.iterateAllocator(init.minimal.args, gpa) catch return error.Args;
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse return error.NoFile;
    const max_side: u32 = if (args.next()) |m| (std.fmt.parseInt(u32, m, 10) catch 256) else 256;
    const mode = args.next() orelse "wic";
    if (std.mem.eql(u8, mode, "zigimg")) return zigimgPath(gpa, init.io, path, max_side);
    if (std.mem.eql(u8, mode, "wic2")) return wicTwoStep(gpa, path, max_side);

    const hr = CoInitializeEx(null, COINIT_MULTITHREADED);
    std.debug.print("CoInitializeEx hr = 0x{x}\n", .{@as(u32, @bitCast(hr))});
    if (hr < 0) return error.CoInit;

    var factory: ?*anyopaque = null;
    const chr = CoCreateInstance(&clsid_factory, null, CLSCTX_INPROC_SERVER, &iid_factory, &factory);
    std.debug.print("CoCreateInstance hr = 0x{x}\n", .{@as(u32, @bitCast(chr))});
    try check(chr, "CoCreateInstance");
    const f = factory.?;
    const fv = vtable(f, Factory);

    const wide = try std.unicode.utf8ToUtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);
    const wide_z: [*:0]const u16 = wide.ptr;

    var t0: i64 = 0;
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t0);

    var decoder: ?*anyopaque = null;
    const dhr = fv.createDecoderFromFilename(f, wide_z, null, GENERIC_READ, &iid_decoder, &decoder);
    std.debug.print("CreateDecoderFromFilename hr = 0x{x} ({s})\n", .{ @as(u32, @bitCast(dhr)), hrText(dhr) });
    try check(dhr, "CreateDecoderFromFilename");
    const dv = vtable(decoder.?, Decoder);

    var frame: ?*anyopaque = null;
    std.debug.print("decoder ok, getting frame\n", .{});
    try check(dv.getFrame(decoder.?, 0, &frame), "GetFrame");
    std.debug.print("frame = {*}\n", .{frame.?});
    std.debug.print("reading frame vtable\n", .{});
    const sv = vtable(frame.?, Source);
    var fw: u32 = 0;
    var fh: u32 = 0;
    std.debug.print("reading size\n", .{});
    try check(sv.getSize(frame.?, &fw, &fh), "GetSize");
    std.debug.print("size {d}x{d}\n", .{ fw, fh });

    // The thumbnail's own size.
    const longest = @max(fw, fh);
    var tw: u32 = max_side;
    var th: u32 = max_side;
    if (longest > max_side) {
        tw = @max(1, fw * max_side / longest);
        th = @max(1, fh * max_side / longest);
    }

    var scaler: ?*anyopaque = null;
    std.debug.print("creating scaler\n", .{});
    try check(fv.createBitmapScaler(f, &scaler), "CreateBitmapScaler");
    std.debug.print("scaler = {*}\n", .{scaler.?});
    const scv = vtable(scaler.?, Scaler);
    try check(scv.initialize(scaler.?, frame.?, tw, th, WICBitmapInterpolationModeFant), "Scaler.Initialize");

    var converter: ?*anyopaque = null;
    std.debug.print("creating converter\n", .{});
    try check(fv.createFormatConverter(f, &converter), "CreateFormatConverter");
    std.debug.print("converter = {*}\n", .{converter.?});
    const cv = vtable(converter.?, Converter);
    try check(cv.initialize(converter.?, scaler.?, &fmt_bgra_premultiplied, 0, null, 0.0, 0), "Converter.Initialize");

    const out = try gpa.alloc(u8, @as(usize, tw) * th * 4);
    defer gpa.free(out);
    try check(cv.copyPixels(converter.?, null, tw * 4, @intCast(out.len), out.ptr), "CopyPixels");

    var t1: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t1);
    const elapsed: i64 = @divTrunc(t1 - t0, @max(1, @divTrunc(freq, 1000)));

    std.debug.print("source {d}x{d} -> thumbnail {d}x{d}\n", .{ fw, fh, tw, th });
    std.debug.print("took {d} ms\n", .{elapsed});
    std.debug.print("first pixel BGRA = {d} {d} {d} {d}\n", .{ out[0], out[1], out[2], out[3] });
    std.debug.print("peak memory: {d:.1} MB\n", .{@as(f64, @floatFromInt(peakMemory())) / (1024 * 1024)});
}


/// The way it is done now: decode the whole picture, then make it smaller.
fn zigimgPath(gpa: std.mem.Allocator, io: std.Io, path: []const u8, max_side: u32) !void {
    var t0: i64 = 0;
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t0);

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024 * 1024));
    defer gpa.free(bytes);
    var img = try zigimg.Image.fromMemory(gpa, bytes);
    defer img.deinit(gpa);
    try img.convert(gpa, .rgba32);
    const src = img.pixels.rgba32;
    const sw: u32 = @intCast(img.width);
    const sh: u32 = @intCast(img.height);
    const longest = @max(sw, sh);
    var dw = sw;
    var dh = sh;
    if (longest > max_side) {
        dw = @max(1, sw * max_side / longest);
        dh = @max(1, sh * max_side / longest);
    }
    const out = try gpa.alloc(u8, @as(usize, dw) * dh * 4);
    defer gpa.free(out);
    for (0..dh) |y| {
        const sy0 = y * sh / dh;
        const sy1 = @max(sy0 + 1, (y + 1) * sh / dh);
        for (0..dw) |x| {
            const sx0 = x * sw / dw;
            const sx1 = @max(sx0 + 1, (x + 1) * sw / dw);
            var sum = [4]u64{ 0, 0, 0, 0 };
            var over = [3]u64{ 0, 0, 0 };
            for (sy0..sy1) |sy| for (sx0..sx1) |sx| {
                const p = src[@as(usize, sy) * sw + sx];
                sum[0] += p.r; sum[1] += p.g; sum[2] += p.b; sum[3] += p.a;
                over[0] += @as(u64, p.r) * p.a;
                over[1] += @as(u64, p.g) * p.a;
                over[2] += @as(u64, p.b) * p.a;
            };
            const n: u64 = @intCast((sy1 - sy0) * (sx1 - sx0));
            const o = (@as(usize, y) * dw + x) * 4;
            out[o + 0] = @intCast(over[2] / (n * 255));
            out[o + 1] = @intCast(over[1] / (n * 255));
            out[o + 2] = @intCast(over[0] / (n * 255));
            out[o + 3] = @intCast(sum[3] / n);
        }
    }
    var t1: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t1);
    const elapsed: i64 = @divTrunc(t1 - t0, @max(1, @divTrunc(freq, 1000)));
    std.debug.print("source {d}x{d} -> thumbnail {d}x{d}", .{ sw, sh, dw, dh });
    std.debug.print("took {d} ms", .{elapsed});
    std.debug.print("first pixel BGRA = {d} {d} {d} {d}", .{ out[0], out[1], out[2], out[3] });
    std.debug.print("peak memory: {d:.1} MB\n", .{@as(f64, @floatFromInt(peakMemory())) / (1024 * 1024)});
}


/// WIC, but scaled in two steps: first to a size the decoder can make
/// itself (a half, a quarter, an eighth of the picture), then to the size
/// wanted. The decoder skips the rest of the picture it never decodes.
fn wicTwoStep(gpa: std.mem.Allocator, path: []const u8, max_side: u32) !void {
    const hr = CoInitializeEx(null, COINIT_MULTITHREADED);
    if (hr < 0) return error.CoInit;
    var factory: ?*anyopaque = null;
    try check(CoCreateInstance(&clsid_factory, null, CLSCTX_INPROC_SERVER, &iid_factory, &factory), "CoCreateInstance");
    const f = factory.?;
    const fv = vtable(f, Factory);

    const wide = try std.unicode.utf8ToUtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);
    const wide_z: [*:0]const u16 = wide.ptr;

    var t0: i64 = 0;
    var freq: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceFrequency(&freq);
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t0);

    var decoder: ?*anyopaque = null;
    try check(fv.createDecoderFromFilename(f, wide_z, null, GENERIC_READ, &iid_decoder, &decoder), "CreateDecoderFromFilename");
    const dv = vtable(decoder.?, Decoder);
    var frame: ?*anyopaque = null;
    try check(dv.getFrame(decoder.?, 0, &frame), "GetFrame");
    const sv = vtable(frame.?, Source);
    var fw: u32 = 0;
    var fh: u32 = 0;
    try check(sv.getSize(frame.?, &fw, &fh), "GetSize");

    const longest = @max(fw, fh);
    var tw: u32 = max_side;
    var th: u32 = max_side;
    if (longest > max_side) {
        tw = @max(1, fw * max_side / longest);
        th = @max(1, fh * max_side / longest);
    }

    // The biggest size the decoder can make itself that is still no smaller
    // than the one wanted: a half, a quarter, an eighth.
    var step_div: u32 = 1;
    const divs = [_]u32{ 8, 4, 2 };
    for (divs) |d| {
        if (fw / d >= tw and fh / d >= th) {
            step_div = d;
            break;
        }
    }
    const iw: u32 = if (step_div == 1) fw else fw / step_div;
    const ih: u32 = if (step_div == 1) fh else fh / step_div;

    var scaler: ?*anyopaque = null;
    try check(fv.createBitmapScaler(f, &scaler), "CreateBitmapScaler");
    const scv = vtable(scaler.?, Scaler);
    try check(scv.initialize(scaler.?, frame.?, iw, ih, WICBitmapInterpolationModeFant), "Scaler.Initialize");

    // The second step, down to the size wanted.
    var source2: *anyopaque = scaler.?;
    if (step_div != 1) {
        var scaler2: ?*anyopaque = null;
        try check(fv.createBitmapScaler(f, &scaler2), "CreateBitmapScaler 2");
        const scv2 = vtable(scaler2.?, Scaler);
        try check(scv2.initialize(scaler2.?, scaler.?, tw, th, WICBitmapInterpolationModeFant), "Scaler2.Initialize");
        source2 = scaler2.?;
    }

    var converter: ?*anyopaque = null;
    try check(fv.createFormatConverter(f, &converter), "CreateFormatConverter");
    const cv = vtable(converter.?, Converter);
    try check(cv.initialize(converter.?, source2, &fmt_bgra_premultiplied, 0, null, 0.0, 0), "Converter.Initialize");

    const out = try gpa.alloc(u8, @as(usize, tw) * th * 4);
    defer gpa.free(out);
    try check(cv.copyPixels(converter.?, null, tw * 4, @intCast(out.len), out.ptr), "CopyPixels");

    var t1: i64 = 0;
    _ = std.os.windows.ntdll.RtlQueryPerformanceCounter(&t1);
    const elapsed: i64 = @divTrunc(t1 - t0, @max(1, @divTrunc(freq, 1000)));
    std.debug.print("source {d}x{d} -> step {d}x{d} -> thumbnail {d}x{d}\n", .{ fw, fh, iw, ih, tw, th });
    std.debug.print("took {d} ms\n", .{elapsed});
    std.debug.print("first pixel BGRA = {d} {d} {d} {d}\n", .{ out[0], out[1], out[2], out[3] });
    std.debug.print("peak memory: {d:.1} MB\n", .{@as(f64, @floatFromInt(peakMemory())) / (1024 * 1024)});
}
