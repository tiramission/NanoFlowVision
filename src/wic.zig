//! Windows' own picture decoder: WIC, through its COM interfaces.
//!
//! The system decoder scales a picture while it decodes it, and reads the
//! file from disk itself, so a 24 MP photograph never sits whole in memory
//! on its way to becoming a 256 pixel thumbnail. The pixels it hands out
//! are premultiplied BGRA -- the same ones nanoui draws -- so there is
//! nothing to convert.
//!
//! The COM declarations here are written against the way the DLL really
//! behaves, not the way Zig's bundled mingw headers say: CreateDecoder-
//! FromFilename takes five arguments, and CreateBitmapScaler and Create-
//! FormatConverter take only the out pointer. Every vtable is declared up
//! to the last method it calls -- a vtable slot is the base interface's
//! methods plus the method's own place, eight bytes each, and skipping the
//! ones in between would call the wrong method.

const std = @import("std");
const decode = @import("decode.zig");

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const clsid_factory = GUID{ .data1 = 0xcacaf262, .data2 = 0x9370, .data3 = 0x4615, .data4 = .{ 0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a } };
const iid_factory = GUID{ .data1 = 0xec5ec8a9, .data2 = 0xc395, .data3 = 0x4314, .data4 = .{ 0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70 } };
const iid_decoder = GUID{ .data1 = 0x9edde9e7, .data2 = 0x8dee, .data3 = 0x47ea, .data4 = .{ 0x99, 0xdf, 0xe6, 0xfa, 0xf2, 0xed, 0x44, 0xbf } };
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

/// IWICImagingFactory, its methods in their places. The two that only hand
/// out a new object take no interface id -- that is what the DLL wants.
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

/// IWICBitmapDecoder, up to GetFrame, where it is called.
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

/// IWICBitmapSource, the base the frame, the scaler and the converter share.
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

/// IWICBitmapScaler: the source's seven methods, then Initialize (slot 8).
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

/// IWICFormatConverter: the source's seven methods, then Initialize (slot
/// 8) and CanConvert (slot 9).
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

/// The vtable sits at the object's first member, as a pointer to the
/// pointers of its methods.
fn vtable(com: *anyopaque, comptime T: type) *const T {
    const p: *const *const T = @ptrCast(@alignCast(com));
    return p.*;
}

/// COM is initialised once for each thread that decodes: the workers are
/// threads, and the tests decode on the main one.
threadlocal var com_ready = false;

fn ensureCom() bool {
    if (com_ready) return true;
    const hr = CoInitializeEx(null, COINIT_MULTITHREADED);
    if (hr < 0) return false;
    com_ready = true;
    return true;
}

/// The picture at `path` as pixels, its longest side no longer than
/// `max_side`. The file stays on disk: WIC reads it itself, and the scaler
/// is asked for the thumbnail's size before any pixel is copied.
pub fn decodeFile(gpa: std.mem.Allocator, path: []const u8, max_side: u32) !decode.Pixels {
    if (!ensureCom()) return error.NoDecoder;

    var factory: ?*anyopaque = null;
    if (CoCreateInstance(&clsid_factory, null, CLSCTX_INPROC_SERVER, &iid_factory, &factory) < 0)
        return error.NoDecoder;
    const f = factory orelse return error.NoDecoder;
    const fv = vtable(f, Factory);
    defer _ = fv.release(f);

    const wide = try std.unicode.utf8ToUtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);

    var decoder: ?*anyopaque = null;
    if (fv.createDecoderFromFilename(f, wide.ptr, null, GENERIC_READ, &iid_decoder, &decoder) < 0)
        return error.NotPicture;
    const dv = vtable(decoder.?, Decoder);
    defer _ = dv.release(decoder.?);

    var frame: ?*anyopaque = null;
    if (dv.getFrame(decoder.?, 0, &frame) < 0) return error.NotPicture;
    const fv_source = vtable(frame.?, Source);
    defer _ = fv_source.release(frame.?);

    var fw: u32 = 0;
    var fh: u32 = 0;
    if (fv_source.getSize(frame.?, &fw, &fh) < 0) return error.NotPicture;
    if (fw == 0 or fh == 0) return error.NotPicture;

    // The thumbnail's own size: the shape kept, the longest side at max_side.
    const longest = @max(fw, fh);
    var tw = fw;
    var th = fh;
    if (longest > max_side) {
        tw = @max(1, fw * max_side / longest);
        th = @max(1, fh * max_side / longest);
    }

    var scaler: ?*anyopaque = null;
    if (fv.createBitmapScaler(f, &scaler) < 0) return error.NotPicture;
    const scaler_source = vtable(scaler.?, Source);
    defer _ = scaler_source.release(scaler.?);
    const sv = vtable(scaler.?, Scaler);
    if (sv.initialize(scaler.?, frame.?, tw, th, WICBitmapInterpolationModeFant) < 0)
        return error.NotPicture;

    var converter: ?*anyopaque = null;
    if (fv.createFormatConverter(f, &converter) < 0) return error.NotPicture;
    const converter_source = vtable(converter.?, Source);
    defer _ = converter_source.release(converter.?);
    const cv = vtable(converter.?, Converter);
    if (cv.initialize(converter.?, scaler.?, &fmt_bgra_premultiplied, 0, null, 0.0, 0) < 0)
        return error.NotPicture;

    const out = try gpa.alloc(u8, @as(usize, tw) * th * 4);
    errdefer gpa.free(out);
    if (cv.copyPixels(converter.?, null, tw * 4, @intCast(out.len), out.ptr) < 0)
        return error.NotPicture;

    return .{ .w = tw, .h = th, .bgra = out };
}
