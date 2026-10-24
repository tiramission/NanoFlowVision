const std = @import("std");
const exif = @import("exif.zig");
const wic = @import("wic.zig");
const zigimg = @import("zigimg");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    std.debug.print("step 1: encode\n", .{});
    var img = try zigimg.Image.create(gpa, 8, 8, .rgb24);
    defer img.deinit(gpa);
    var px: usize = 0;
    while (px < 64) : (px += 1) {
        const y = px / 8;
        img.pixels.rgb24[px] = .{ .r = 255, .g = @intCast(255 - y * 36), .b = 0 };
    }
    var write_buf: [1 << 16]u8 = undefined;
    const plain = try img.writeToMemory(gpa, write_buf[0..], .{ .jpeg = .{} });
    defer gpa.free(plain);
    std.debug.print("step 2: jpeg {d} bytes\n", .{plain.len});

    const f = exif.Fixture.build(.little);
    var jpeg: std.ArrayList(u8) = .empty;
    defer jpeg.deinit(gpa);
    try jpeg.appendSlice(gpa, plain[0..2]);
    const seg: u16 = @intCast(2 + 6 + 191);
    try jpeg.appendSlice(gpa, &.{ 0xFF, 0xE1, @intCast(seg >> 8), @intCast(seg & 0xFF) });
    try jpeg.appendSlice(gpa, "Exif\x00\x00");
    try jpeg.appendSlice(gpa, f.bytes[0..191]);
    try jpeg.appendSlice(gpa, plain[2..]);

    const dir_path = "C:/Users/jaign/AppData/Local/Temp/flip-dbg";
    std.Io.Dir.createDirAbsolute(io, dir_path, .default_file) catch {};
    const path = try std.fmt.allocPrint(gpa, "{s}/turned.jpg", .{dir_path});
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path[1..], .data = jpeg.items });
    std.debug.print("step 3: written, orientation={d}\n", .{exif.parse(jpeg.items).?.orientation});

    std.debug.print("step 4: decode\n", .{});
    var pixels = wic.decodeFile(gpa, path, 256, 6) catch |err| {
        std.debug.print("wic err: {s}\n", .{@errorName(err)});
        return err;
    };
    defer pixels.deinit(gpa);
    std.debug.print("step 5: decoded {d}x{d} first pixel ({d},{d},{d},{d})\n", .{ pixels.w, pixels.h, pixels.bgra[0], pixels.bgra[1], pixels.bgra[2], pixels.bgra[3] });
}
