//! Thumbnails: measured and decoded by workers, kept until their memory is needed.
//!
//! The view asks for a picture's size and its thumbnail; the workers read the
//! file and leave the answer in a cache both share. The view never waits:
//! a picture that is not ready yet is drawn as a placeholder.

const std = @import("std");
const nanoui = @import("nanoui");
const decode = @import("decode.zig");
const scan = @import("scan.zig");

/// How many bytes of thumbnails are kept before the oldest are dropped.
pub const budget: usize = 192 * 1024 * 1024;
/// How long a thumbnail's side may be.
pub const thumb_side: u32 = 256;
/// How long a picture shown large may be.
pub const large_side: u32 = 2048;
/// How many files are read at once.
pub const worker_count: usize = 4;
/// How large a file may be to be decoded.
pub const max_file: usize = 256 * 1024 * 1024;

pub const Kind = enum { measure, picture, large };

/// The cache key of a picture shown large: its own entry, so the big pixels
/// do not push the thumbnails out.
pub fn largeKey(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "L:{s}", .{path});
}

/// What is known about one picture.
pub const Cached = struct {
    /// Width over height, from the header.
    aspect: f32 = 1,
    /// Whether the header has been read.
    measured: bool = false,
    /// The thumbnail's pixels, once decoded.
    thumb: ?decode.Pixels = null,
    /// Whether a worker is measuring it.
    measuring: bool = false,
    /// Whether a worker is decoding it.
    decoding: bool = false,
    /// Whether it cannot be read.
    failed: bool = false,
    /// When the thumbnail was made; the oldest goes first.
    made: u64 = 0,
};

/// What the workers and the view share.
pub const Shared = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    /// What is known about each picture, by path. The cache owns the paths.
    items: std.StringHashMapUnmanaged(Cached) = .empty,
    /// The bytes of thumbnails held.
    bytes: usize = 0,
    /// Counts the thumbnails made, to order them.
    counter: u64 = 0,
    /// Bumped when a picture's size is measured, so the layout knows to
    /// be made again.
    changed: u64 = 0,

    fn lock(s: *Shared) void {
        s.mutex.lockUncancelable(s.io);
    }

    fn unlock(s: *Shared) void {
        s.mutex.unlock(s.io);
    }

    pub fn deinit(s: *Shared) void {
        s.lock();
        defer s.unlock();
        var it = s.items.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.thumb) |t| t.deinit(s.gpa);
            s.gpa.free(@constCast(entry.key_ptr.*));
        }
        s.items.deinit(s.gpa);
    }

    /// Forgets everything: another folder is being shown.
    pub fn clear(s: *Shared) void {
        s.lock();
        defer s.unlock();
        var it = s.items.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.thumb) |t| t.deinit(s.gpa);
            s.gpa.free(@constCast(entry.key_ptr.*));
        }
        s.items.clearRetainingCapacity();
        s.bytes = 0;
    }

    /// The entry of a picture, made if it is not there yet. The cache owns
    /// the path it keeps.
    fn entryFor(s: *Shared, path: []const u8) ?*Cached {
        if (s.items.getPtr(path)) |known| return known;
        const key = s.gpa.dupe(u8, path) catch return null;
        s.items.put(s.gpa, key, .{}) catch {
            s.gpa.free(key);
            return null;
        };
        return s.items.getPtr(key);
    }

    /// How many times a picture's size has been measured.
    pub fn changeCounter(s: *Shared) u64 {
        s.lock();
        defer s.unlock();
        return s.changed;
    }

    /// What is known about a picture, if anything is known yet.
    pub fn get(s: *Shared, path: []const u8) ?Cached {
        s.lock();
        defer s.unlock();
        return s.items.get(path);
    }

    /// Whether a worker should be asked for this picture: true when nobody
    /// is on it yet.
    pub fn claim(s: *Shared, path: []const u8, kind: Kind) bool {
        s.lock();
        defer s.unlock();
        const entry = s.entryFor(path) orelse return false;
        if (kind == .measure) {
            if (entry.measured or entry.measuring) return false;
            entry.measuring = true;
        } else {
            if (entry.thumb != null or entry.decoding or entry.failed) return false;
            entry.decoding = true;
        }
        return true;
    }

    /// The picture's size, measured from its header.
    pub fn setAspect(s: *Shared, path: []const u8, aspect: f32) void {
        s.lock();
        defer s.unlock();
        const entry = s.entryFor(path) orelse return;
        entry.aspect = aspect;
        entry.measured = true;
        entry.measuring = false;
        s.changed += 1;
    }

    /// The picture's thumbnail.
    pub fn setThumb(s: *Shared, path: []const u8, pixels: decode.Pixels) void {
        s.lock();
        defer s.unlock();
        const entry = s.entryFor(path) orelse {
            pixels.deinit(s.gpa);
            return;
        };
        if (entry.thumb) |old| {
            old.deinit(s.gpa);
            s.bytes -= old.bgra.len;
        }
        s.counter += 1;
        entry.thumb = pixels;
        entry.decoding = false;
        entry.made = s.counter;
        s.bytes += pixels.bgra.len;
    }

    /// The picture cannot be read.
    pub fn setFailed(s: *Shared, path: []const u8) void {
        s.lock();
        defer s.unlock();
        const entry = s.entryFor(path) orelse return;
        entry.measuring = false;
        entry.decoding = false;
        entry.failed = true;
    }

    /// Drops the oldest thumbnails until the cache is under its budget. The
    /// pictures on screen are kept, however old they are.
    pub fn trim(s: *Shared, keep: []const []const u8) void {
        s.lock();
        defer s.unlock();
        while (s.bytes > budget) {
            var oldest: ?*Cached = null;
            var it = s.items.iterator();
            while (it.next()) |entry| {
                const c = entry.value_ptr;
                if (c.thumb == null or c.made == 0) continue;
                var on_screen = false;
                for (keep) |path| {
                    if (std.mem.eql(u8, path, entry.key_ptr.*)) {
                        on_screen = true;
                        break;
                    }
                }
                if (on_screen) continue;
                if (oldest == null or c.made < oldest.?.made) oldest = c;
            }
            const victim = oldest orelse break;
            victim.thumb.?.deinit(s.gpa);
            s.bytes -= victim.thumb.?.bgra.len;
            victim.thumb = null;
            victim.made = 0;
        }
    }
};

pub const Job = struct {
    /// The file to read.
    path: []u8,
    /// Where its answer goes in the cache.
    key: []u8,
    kind: Kind,
};

/// The workers that read the files.
pub const Pool = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    shared: *Shared,
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    queue: std.ArrayListUnmanaged(Job) = .empty,
    running: bool = true,
    threads: []std.Thread = &.{},
    /// The window to draw again when a picture is ready.
    window: ?*nanoui.Window = null,

    pub fn start(self: *Pool, gpa: std.mem.Allocator, io: std.Io, shared: *Shared) !void {
        self.gpa = gpa;
        self.io = io;
        self.shared = shared;
        self.threads = try gpa.alloc(std.Thread, worker_count);
        var started: usize = 0;
        errdefer for (self.threads[0..started]) |t| t.join();
        while (started < self.threads.len) : (started += 1) {
            self.threads[started] = try std.Thread.spawn(.{}, worker, .{self});
        }
    }

    /// Stops the workers and waits for them.
    pub fn stop(self: *Pool) void {
        self.mutex.lockUncancelable(self.io);
        self.running = false;
        self.cond.broadcast(self.io);
        self.mutex.unlock(self.io);
        for (self.threads) |t| t.join();
        self.gpa.free(self.threads);
        self.threads = &.{};
        self.mutex.lockUncancelable(self.io);
        for (self.queue.items) |job| self.gpa.free(job.path);
        self.queue.deinit(self.gpa);
        self.mutex.unlock(self.io);
    }

    /// Asks for a picture's size or its thumbnail, unless a worker is on it.
    /// The file is at `path`; its answer goes to `key` in the cache.
    pub fn ask(self: *Pool, path: []const u8, key: []const u8, kind: Kind) void {
        if (!self.shared.claim(key, kind)) return;
        const owned_path = self.gpa.dupe(u8, path) catch return;
        errdefer self.gpa.free(owned_path);
        const owned_key = self.gpa.dupe(u8, key) catch return;
        self.mutex.lockUncancelable(self.io);
        self.queue.append(self.gpa, .{ .path = owned_path, .key = owned_key, .kind = kind }) catch {
            self.mutex.unlock(self.io);
            self.gpa.free(owned_path);
            self.gpa.free(owned_key);
            self.shared.setFailed(key);
            return;
        };
        self.cond.signal(self.io);
        self.mutex.unlock(self.io);
    }
};

fn worker(pool: *Pool) void {
    var header: [64 * 1024]u8 = undefined;
    while (true) {
        pool.mutex.lockUncancelable(pool.io);
        while (pool.queue.items.len == 0 and pool.running) {
            pool.cond.waitUncancelable(pool.io, &pool.mutex);
        }
        if (pool.queue.items.len == 0 and !pool.running) {
            pool.mutex.unlock(pool.io);
            return;
        }
        const job = pool.queue.orderedRemove(0);
        pool.mutex.unlock(pool.io);

        run(pool, job, header[0..]);
        pool.gpa.free(job.path);
        pool.gpa.free(job.key);
    }
}

fn run(pool: *Pool, job: Job, header: []u8) void {
    const shared = pool.shared;
    switch (job.kind) {
        .measure => {
            const bytes = scan.readHeader(shared.io, job.path, header) catch {
                shared.setFailed(job.key);
                return;
            };
            const size = decode.probeSize(bytes) orelse {
                shared.setFailed(job.key);
                return;
            };
            shared.setAspect(job.key, size.aspect());
        },
        .picture, .large => {
            const side = if (job.kind == .large) large_side else thumb_side;
            const bytes = scan.readAll(shared.gpa, shared.io, job.path, .limited(max_file)) catch {
                shared.setFailed(job.key);
                return;
            };
            defer shared.gpa.free(bytes);
            const pixels = decode.decode(shared.gpa, bytes, side) catch {
                shared.setFailed(job.key);
                return;
            };
            shared.setThumb(job.key, pixels);
        },
    }
    // The view draws again when the picture is ready.
    nanoui.App.onMain(pool, onMainRedraw);
}

fn onMainRedraw(ctx: ?*anyopaque) callconv(.c) void {
    const pool: *Pool = @ptrCast(@alignCast(ctx.?));
    if (pool.window) |w| w.redraw();
}
