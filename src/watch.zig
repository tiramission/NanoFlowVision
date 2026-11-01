//! Watching the folder the gallery shows: when something in it changes on
//! the disk -- a picture added from a camera, one removed by hand -- the
//! gallery is listed again, without a finger lifted. Windows is told with
//! ReadDirectoryChangesW on its own thread; the other platforms are a
//! later write.

const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");

const app = @import("app.zig");

extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: u32, share: u32, security: ?*anyopaque, disposition: u32, flags: u32, template: ?*anyopaque) ?*anyopaque;
extern "kernel32" fn ReadDirectoryChangesW(handle: ?*anyopaque, out: [*]u8, len: u32, subtree: i32, filter: u32, returned: ?*u32, overlapped: ?*OVERLAPPED, completion: ?*anyopaque) i32;
extern "kernel32" fn CreateEventW(attrs: ?*anyopaque, manual: i32, initial: i32, name: ?[*:0]const u16) ?*anyopaque;
// The count comes first: `DWORD WaitForMultipleObjects(DWORD nCount,
// const HANDLE *lpHandles, BOOL bWaitAll, DWORD dwMilliseconds)`. Swapped,
// every wait failed at once and the loop under it spun, flooding the main
// thread with changes until the window had no frames left to draw.
extern "kernel32" fn WaitForMultipleObjects(count: u32, handles: [*]const ?*anyopaque, wait_all: i32, ms: u32) u32;
extern "kernel32" fn SetEvent(handle: ?*anyopaque) i32;
extern "kernel32" fn ResetEvent(handle: ?*anyopaque) i32;
extern "kernel32" fn WaitForSingleObject(handle: ?*anyopaque, ms: u32) u32;
extern "kernel32" fn CloseHandle(handle: ?*anyopaque) i32;
extern "kernel32" fn CancelIoEx(handle: ?*anyopaque, overlapped: ?*OVERLAPPED) i32;
extern "kernel32" fn GetOverlappedResult(handle: ?*anyopaque, overlapped: ?*OVERLAPPED, transferred: *u32, wait: i32) i32;

const OVERLAPPED = extern struct {
    internal: usize = 0,
    internal_high: usize = 0,
    union_offset: usize = 0,
    event: ?*anyopaque = null,
};

const FILE_LIST_DIRECTORY: u32 = 0x00000001;
const FILE_SHARE_READ: u32 = 0x00000001;
const FILE_SHARE_WRITE: u32 = 0x00000002;
const FILE_SHARE_DELETE: u32 = 0x00000004;
const OPEN_EXISTING: u32 = 3;
const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x02000000;
const FILE_FLAG_OVERLAPPED: u32 = 0x40000000;
const FILE_NOTIFY_CHANGE_FILE_NAME: u32 = 0x00000001;
const FILE_NOTIFY_CHANGE_DIR_NAME: u32 = 0x00000002;
const FILE_NOTIFY_CHANGE_LAST_WRITE: u32 = 0x00000010;
const INFINITE: u32 = 0xFFFFFFFF;

pub const Watcher = struct {
    /// The watched folder, owned. Null when nothing is watched.
    dir_path: ?[]u8 = null,
    handle: ?*anyopaque = null,
    /// The event a stop is rung on, made once and kept: a stop that races
    /// the thread's own start must always have something to ring, or the
    /// join would wait on a thread that waits forever.
    stop_event: ?*anyopaque = null,
    stop: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    app: *app.State,
    gpa: std.mem.Allocator,

    /// Watches `dir` instead of whatever was watched. Safe to call again.
    pub fn start(self: *Watcher, dir: []const u8) void {
        if (comptime builtin.os.tag != .windows) return;
        if (self.dir_path) |have| {
            if (std.mem.eql(u8, have, dir)) return;
            self.stopCurrent();
        }
        const owned = self.gpa.dupe(u8, dir) catch return;
        self.dir_path = owned;
        self.stop.store(false, .release);
        if (self.stop_event == null) {
            self.stop_event = CreateEventW(null, 1, 0, null);
        } else {
            _ = ResetEvent(self.stop_event.?);
        }
        self.thread = std.Thread.spawn(.{}, loop, .{self}) catch {
            self.gpa.free(owned);
            self.dir_path = null;
            return;
        };
    }

    /// Everything a watcher ever took is given back: the thread stopped,
    /// the path freed, the stop event closed.
    pub fn deinit(self: *Watcher) void {
        self.stopCurrent();
        if (self.stop_event) |e| {
            _ = CloseHandle(e);
            self.stop_event = null;
        }
    }

    /// Stops watching and waits for the thread: the pending read is
    /// cancelled, so the wait ends now, not at the next change.
    pub fn stopCurrent(self: *Watcher) void {
        if (self.thread) |t| {
            self.stop.store(true, .release);
            if (self.stop_event) |e| _ = SetEvent(e);
            if (comptime builtin.os.tag == .windows) {
                if (self.handle) |h| _ = CancelIoEx(h, null);
            }
            t.join();
            self.thread = null;
        }
        if (self.dir_path) |p| {
            self.gpa.free(p);
            self.dir_path = null;
        }
    }

    /// The callback that runs on the main thread: the folder is to be
    /// listed again if it is still the watched one. Only the wish is
    /// recorded here -- the callback can fire from inside a modal
    /// dialog's message pump, in the middle of a frame that is walking
    /// the very tree a listing would rebuild, so the listing itself
    /// waits for the top of the next frame.
    fn changed(ctx: ?*anyopaque) callconv(.c) void {
        const self: *Watcher = @ptrCast(@alignCast(ctx.?));
        const watched = self.dir_path orelse return;
        const folder = self.app.current orelse return;
        if (!std.mem.eql(u8, folder.path, watched)) return;
        self.app.relist_pending = true;
        // A frame is asked for as well: the listing happens at the top of
        // the next one, and an idle window draws none of its own (its
        // frames come from the mouse and from what animates).
        if (self.app.window) |win| win.redraw();
    }

    fn loop(self: *Watcher) void {
        if (comptime builtin.os.tag != .windows) return;

        const heap = std.heap.smp_allocator;
        const wide = std.unicode.utf8ToUtf16LeAllocZ(heap, self.dir_path orelse return) catch return;
        defer heap.free(wide);
        const handle = CreateFileW(
            wide.ptr,
            FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            null,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
            null,
        ) orelse return;
        self.handle = handle;
        defer {
            _ = CloseHandle(handle);
            self.handle = null;
        }

        const event = CreateEventW(null, 1, 0, null) orelse return;
        defer _ = CloseHandle(event);
        const stop_event = self.stop_event orelse return;

        var buffer: [64 * 1024]u8 = undefined;
        var overlapped: OVERLAPPED = .{ .event = event };
        const waits = [_]?*anyopaque{ event, stop_event };

        while (!self.stop.load(.acquire)) {
            // The event is the read's, not a latch: reset before asking
            // for the next change, or the wait returns at once on the
            // last completion and the loop spins (a spin that floods the
            // main thread with "changed" and leaves the window with no
            // frames to draw: no menu, no sheet, no hover).
            _ = ResetEvent(event);
            const asked = ReadDirectoryChangesW(
                handle,
                &buffer,
                buffer.len,
                1, // the subfolders too: a recursive gallery follows them
                FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_LAST_WRITE,
                null,
                &overlapped,
                null,
            );
            if (asked == 0) {
                // The folder refused the read (gone, or unreadable): the
                // wait would block on an event that never comes, so pause
                // instead, and try again until a stop or the folder's end.
                if (WaitForSingleObject(stop_event, 250) == 0) break;
                continue;
            }
            // The wait answers a change or the stop, whichever comes
            // first: the stop is rung on its own event, so a join never
            // waits on a thread that waits forever.
            const rung = WaitForMultipleObjects(waits.len, &waits, 0, INFINITE);
            if (self.stop.load(.acquire)) {
                _ = CancelIoEx(handle, &overlapped);
                break;
            }
            if (rung != 0) continue;
            // A read that ended in an error is no change at all: the
            // listing would say the same thing as last time.
            var moved: u32 = 0;
            if (GetOverlappedResult(handle, &overlapped, &moved, 0) != 0 and moved > 0) {
                // One change is enough: the listing says what is there now.
                nanoui.App.onMain(self, changed);
            } else if (WaitForSingleObject(stop_event, 250) == 0) break;
        }
    }
};
