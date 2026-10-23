//! macOS's own picture decoder: ImageIO, the way nanoui itself decodes.
//!
//! `CGImageSourceCreateThumbnailAtIndex` scales a picture while it decodes
//! it ("ImageIO scales while it decodes: no full-size copy is made", as the
//! comment in nanoui's own image.zig says), and reading it through a file
//! URL means the file is never all in memory either. The thumbnail is drawn
//! into a bitmap context of premultiplied BGRA -- the same pixels nanoui
//! draws -- so there is nothing to convert.
//!
//! This one is written to match nanoui's proven declarations, but it has
//! only been compiled on macOS, not measured there: the numbers in the
//! roadmap are Windows'.

const std = @import("std");
const decode = @import("decode.zig");

const CFIndex = c_long;
const CFStringRef = *opaque {};
const CFTypeRef = *opaque {};
const CFURLRef = *opaque {};
const CFDictionaryRef = *opaque {};
const CGColorSpaceRef = *opaque {};
const CGContextRef = *opaque {};
const CGImageRef = *opaque {};
const CGImageSourceRef = *opaque {};

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint = .{}, size: CGSize = .{} };

extern "c" fn CFRelease(ref: CFTypeRef) void;
extern "c" fn CFURLCreateFromFileSystemRepresentation(alloc: ?*anyopaque, path: [*]const u8, len: CFIndex, is_dir: bool) ?CFURLRef;
extern "c" fn CFNumberCreate(alloc: ?*anyopaque, kind: c_int, value: *const anyopaque) ?CFTypeRef;
extern "c" fn CFNumberGetValue(n: CFTypeRef, kind: c_int, out: *anyopaque) bool;
extern "c" fn CFDictionaryGetValue(dict: CFDictionaryRef, key: *const anyopaque) ?CFTypeRef;
extern "c" fn CFDictionaryCreate(alloc: ?*anyopaque, keys: [*]const ?*const anyopaque, values: [*]const ?*const anyopaque, n: CFIndex, key_cb: *const anyopaque, value_cb: *const anyopaque) ?CFDictionaryRef;
extern "c" const kCFTypeDictionaryKeyCallBacks: anyopaque;
extern "c" const kCFTypeDictionaryValueCallBacks: anyopaque;
extern "c" const kCFBooleanTrue: CFTypeRef;
/// kCFNumberSInt32Type.
const cf_number_int32: c_int = 3;

extern "c" fn CGImageSourceCreateWithURL(url: CFURLRef, options: ?CFDictionaryRef) ?CGImageSourceRef;
extern "c" fn CGImageSourceCopyPropertiesAtIndex(src: CGImageSourceRef, index: usize, options: ?CFDictionaryRef) ?CFDictionaryRef;
extern "c" fn CGImageSourceCreateThumbnailAtIndex(src: CGImageSourceRef, index: usize, options: ?CFDictionaryRef) ?CGImageRef;
extern "c" const kCGImageSourceCreateThumbnailFromImageAlways: CFStringRef;
extern "c" const kCGImageSourceThumbnailMaxPixelSize: CFStringRef;
extern "c" const kCGImageSourceCreateThumbnailWithTransform: CFStringRef;
extern "c" const kCGImagePropertyPixelWidth: CFStringRef;
extern "c" const kCGImagePropertyPixelHeight: CFStringRef;

extern "c" fn CGImageGetWidth(img: CGImageRef) usize;
extern "c" fn CGImageGetHeight(img: CGImageRef) usize;
extern "c" fn CGImageRelease(img: CGImageRef) void;
extern "c" fn CGBitmapContextCreate(data: ?*anyopaque, w: usize, h: usize, bpc: usize, bpr: usize, space: ?CGColorSpaceRef, info: u32) ?CGContextRef;
extern "c" fn CGContextDrawImage(ctx: CGContextRef, rect: CGRect, image: CGImageRef) void;
extern "c" const kCGColorSpaceSRGB: CFStringRef;
extern "c" fn CGColorSpaceCreateWithName(name: CFStringRef) ?CGColorSpaceRef;
extern "c" fn CGColorSpaceRelease(space: CGColorSpaceRef) void;

/// Premultiplied BGRA, little endian: `kCGImageAlphaPremultipliedFirst |
/// kCGBitmapByteOrder32Little`.
const bgra_premultiplied: u32 = 2 | (2 << 12);

/// The picture at `path` as pixels, its longest side no longer than
/// `max_side`. The thumbnail is made by ImageIO at the size wanted, so the
/// picture is never whole in memory.
pub fn decodeFile(gpa: std.mem.Allocator, path: []const u8, max_side: u32) !decode.Pixels {
    const url = CFURLCreateFromFileSystemRepresentation(null, path.ptr, @intCast(path.len), false) orelse
        return error.NotPicture;
    defer CFRelease(url);
    const src = CGImageSourceCreateWithURL(url, null) orelse return error.NotPicture;
    defer CFRelease(src);

    // The size the thumbnail will be drawn at, from the picture itself.
    var tw: i32 = 0;
    var th: i32 = 0;
    if (CGImageSourceCopyPropertiesAtIndex(src, 0, null)) |props| {
        defer CFRelease(props);
        if (CFDictionaryGetValue(props, kCGImagePropertyPixelWidth)) |n|
            _ = CFNumberGetValue(n, cf_number_int32, &tw);
        if (CFDictionaryGetValue(props, kCGImagePropertyPixelHeight)) |n|
            _ = CFNumberGetValue(n, cf_number_int32, &th);
    }

    // The thumbnail: the shape kept, the longest side at max_side, drawn
    // the way it should be shown (with its transform, so a turned picture
    // comes out standing).
    const side: i32 = @intCast(max_side);
    const max_n = CFNumberCreate(null, cf_number_int32, &side) orelse return error.NotPicture;
    defer CFRelease(max_n);
    const keys = [_]?*const anyopaque{ kCGImageSourceCreateThumbnailFromImageAlways, kCGImageSourceThumbnailMaxPixelSize, kCGImageSourceCreateThumbnailWithTransform };
    const values = [_]?*const anyopaque{ kCFBooleanTrue, max_n, kCFBooleanTrue };
    const opts = CFDictionaryCreate(null, &keys, &values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks) orelse
        return error.NotPicture;
    defer CFRelease(opts);
    const img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) orelse return error.NotPicture;
    defer CGImageRelease(img);

    const w = CGImageGetWidth(img);
    const h = CGImageGetHeight(img);
    if (w == 0 or h == 0) return error.NotPicture;

    const out = try gpa.alloc(u8, w * h * 4);
    errdefer gpa.free(out);
    @memset(out, 0);
    const space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB) orelse return error.NoDecoder;
    defer CGColorSpaceRelease(space);
    const ctx = CGBitmapContextCreate(out.ptr, w, h, 8, w * 4, space, bgra_premultiplied) orelse
        return error.NoDecoder;
    defer CFRelease(ctx);
    CGContextDrawImage(ctx, .{ .size = .{ .width = @floatFromInt(w), .height = @floatFromInt(h) } }, img);

    return .{
        .w = @intCast(w),
        .h = @intCast(h),
        .bgra = out,
    };
}
