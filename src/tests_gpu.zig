//! The Direct3D 11 renderer, for what this app draws and nanoui's own parity
//! tests do not cover: a texture the app gave the frame (`ui.texture`), which
//! is every photograph here. nanoui v0.9.2 had no branch for it in the HLSL,
//! so the GPU drew a white quad where the picture was; our nanoui fork adds it
//! (see NANOUI-FORK.md).

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const gpu = nanoui.ui.gpu;
const d3d11 = nanoui.ui.d3d11;

test "the GPU draws an app texture, not a white quad" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var made = d3d11.Renderer.init() catch |e| switch (e) {
        error.NoDevice => return error.SkipZigTest,
        else => return e,
    };
    defer made.deinit();
    const r = &made;

    // A red square, BGRA premultiplied, as the app hands one over.
    const w: u32 = 8;
    const h: u32 = 8;
    const pixels = try gpa.alloc(u8, w * h * 4);
    defer gpa.free(pixels);
    var i: usize = 0;
    while (i < w * h) : (i += 1) {
        pixels[i * 4 + 0] = 0;
        pixels[i * 4 + 1] = 0;
        pixels[i * 4 + 2] = 255;
        pixels[i * 4 + 3] = 255;
    }
    const textures = [_]gpu.Texture{.{ .width = w, .height = h, .bgra = pixels }};

    // The frame is a blue clear with one red square in it (kind 8: a texture
    // the app gave), drawn the way `ui.texture` makes it.
    const clear: ui.Color = .{ .r = 0, .g = 0, .b = 1, .a = 1 };
    const instances = [_]gpu.Instance{.{
        .rect = .{ 0, 0, 30, 30 },
        .color = .{ 1, 1, 1, 1 },
        .uv = .{ 0, 0, 1, 1 },
        .kind = gpu.Kind.texture,
        .border_width = 0,
    }};
    r.draw(&instances, .{ .w = 30, .h = 30 }, 1, clear, null, &textures);
    const shot = try r.read(gpa);
    defer shot.deinit(gpa);
    try std.testing.expect(shot.width >= 30 and shot.height >= 30);
    // The middle of the square: red, not white (the bug drew the quad's
    // fill, which is white here) and not the clear.
    const at = ((shot.height / 2) * shot.width + shot.width / 2) * 4;
    const b = shot.bytes[at];
    const g = shot.bytes[at + 1];
    const rr = shot.bytes[at + 2];
    try std.testing.expect(rr > 200 and g < 40 and b < 40);
}
