const std = @import("std");
const builtin = @import("builtin");

const c = std.c;

const NurlThreadFn = *const fn (?*anyopaque) callconv(.c) void;

const NurlThread = struct {
    handle: std.Thread,
    fn_ptr: NurlThreadFn,
    env: ?*anyopaque,
};

const NurlMutex = struct {
    mutex: std.Io.Mutex = .init,
};

const NurlCond = struct {
    cond: std.Io.Condition = .init,
};

const NurlDosIpEntry = struct {
    ip: [*:0]u8,
    count: c_longlong,
};

const NurlDosState = struct {
    max_concurrent: c_longlong,
    max_per_ip: c_longlong,
    active_count: c_longlong,
    ip_entries: ?[*]NurlDosIpEntry,
    ip_count: usize,
    ip_cap: usize,
    mutex: std.Io.Mutex = .init,
};

fn setErrno(err: c.E) void {
    c._errno().* = @intFromEnum(err);
}

fn dupSliceZ(src: []const u8) ?[*:0]u8 {
    const raw = c.malloc(src.len + 1) orelse {
        setErrno(.NOMEM);
        return null;
    };
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return @ptrCast(buf);
}

fn handleToThread(handle: c_longlong) ?*NurlThread {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn handleToMutex(handle: c_longlong) ?*NurlMutex {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn handleToCond(handle: c_longlong) ?*NurlCond {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn handleToDosState(handle: c_longlong) ?*NurlDosState {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn nurlThreadTrampoline(thread: *NurlThread) void {
    thread.fn_ptr(thread.env);
}

fn nurlIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn dosLock(state: *NurlDosState) void {
    if (builtin.os.tag == .wasi) return;
    state.mutex.lockUncancelable(nurlIo());
}

fn dosUnlock(state: *NurlDosState) void {
    if (builtin.os.tag == .wasi) return;
    state.mutex.unlock(nurlIo());
}

fn dosFindIp(state: *NurlDosState, ip: []const u8) ?usize {
    const entries = state.ip_entries orelse return null;
    var i: usize = 0;
    while (i < state.ip_count) : (i += 1) {
        if (std.mem.eql(u8, std.mem.span(entries[i].ip), ip)) return i;
    }
    return null;
}

fn hexEncodeInto(bytes: []const u8, out: []u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        out[i * 2] = alphabet[byte >> 4];
        out[i * 2 + 1] = alphabet[byte & 0x0f];
    }
    out[bytes.len * 2] = 0;
}

fn fillRandomBytes(buf: []u8) bool {
    std.Io.randomSecure(nurlIo(), buf) catch {
        const now = std.Io.Clock.now(.real, nurlIo());
        var state: u64 = @bitCast(std.Io.Timestamp.toMilliseconds(now));
        state ^= @intFromPtr(buf.ptr);
        state ^= (@as(u64, buf.len) << 17);
        for (buf, 0..) |*byte, i| {
            state = state *% 6364136223846793005 +% 1442695040888963407;
            byte.* = @truncate((state >> @as(u6, @intCast((i & 7) * 8))) ^ state >> 33);
        }
        return false;
    };
    return true;
}

pub export fn nurl_sha256_hex(text: ?[*:0]const u8) ?[*:0]u8 {
    const input = std.mem.span(text orelse "");
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(input);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    const raw = c.malloc(digest.len * 2 + 1) orelse return dupSliceZ("");
    const out: [*]u8 = @ptrCast(raw);
    hexEncodeInto(&digest, out[0 .. digest.len * 2 + 1]);
    return @ptrCast(out);
}

pub export fn nurl_hmac_sha256_hex(key_ptr: ?[*:0]const u8, msg_ptr: ?[*:0]const u8) ?[*:0]u8 {
    const key = std.mem.span(key_ptr orelse "");
    const msg = std.mem.span(msg_ptr orelse "");
    var mac: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, msg, key);

    const raw = c.malloc(mac.len * 2 + 1) orelse return dupSliceZ("");
    const out: [*]u8 = @ptrCast(raw);
    hexEncodeInto(&mac, out[0 .. mac.len * 2 + 1]);
    return @ptrCast(out);
}

pub export fn nurl_rand_u64() c_longlong {
    var buf: [8]u8 = undefined;
    _ = fillRandomBytes(&buf);
    const value = std.mem.readInt(u64, &buf, .big);
    return @bitCast(value);
}

pub export fn nurl_rand_bytes_hex(n: c_longlong) ?[*:0]u8 {
    if (n <= 0) return dupSliceZ("");
    const clamped_n: usize = @intCast(@min(n, 4096));
    const raw = c.malloc(clamped_n) orelse return dupSliceZ("");
    defer c.free(raw);
    const buf: [*]u8 = @ptrCast(raw);
    _ = fillRandomBytes(buf[0..clamped_n]);

    const out_raw = c.malloc(clamped_n * 2 + 1) orelse return dupSliceZ("");
    const out: [*]u8 = @ptrCast(out_raw);
    hexEncodeInto(buf[0..clamped_n], out[0 .. clamped_n * 2 + 1]);
    return @ptrCast(out);
}

pub export fn nurl_sha1_bytes(data_ptr: ?[*]const u8, len: c_longlong, out_ptr: ?[*]u8) void {
    const out = out_ptr orelse return;
    var hasher = std.crypto.hash.Sha1.init(.{});
    if (data_ptr) |data| {
        if (len > 0) hasher.update(data[0..@intCast(len)]);
    }
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    hasher.final(&digest);
    @memcpy(out[0..digest.len], &digest);
}

pub export fn nurl_thread_spawn(fn_ptr: ?*anyopaque, env: ?*anyopaque) c_longlong {
    if (builtin.os.tag == .wasi or fn_ptr == null) return 0;
    const raw = c.calloc(1, @sizeOf(NurlThread)) orelse return 0;
    const thread: *NurlThread = @ptrCast(@alignCast(raw));
    thread.fn_ptr = @ptrFromInt(@intFromPtr(fn_ptr.?));
    thread.env = env;
    thread.handle = std.Thread.spawn(.{}, nurlThreadTrampoline, .{thread}) catch {
        c.free(thread);
        return 0;
    };
    return @intCast(@intFromPtr(thread));
}

pub export fn nurl_thread_join(handle: c_longlong) c_longlong {
    if (builtin.os.tag == .wasi) return -1;
    const thread = handleToThread(handle) orelse return -1;
    thread.handle.join();
    c.free(thread);
    return 0;
}

pub export fn nurl_thread_detach(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const thread = handleToThread(handle) orelse return;
    thread.handle.detach();
    c.free(thread);
}

pub export fn nurl_mutex_new() c_longlong {
    if (builtin.os.tag == .wasi) return 0;
    const raw = c.calloc(1, @sizeOf(NurlMutex)) orelse return 0;
    const mutex: *NurlMutex = @ptrCast(@alignCast(raw));
    mutex.* = .{};
    return @intCast(@intFromPtr(mutex));
}

pub export fn nurl_mutex_lock(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const mutex = handleToMutex(handle) orelse return;
    mutex.mutex.lockUncancelable(nurlIo());
}

pub export fn nurl_mutex_unlock(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const mutex = handleToMutex(handle) orelse return;
    mutex.mutex.unlock(nurlIo());
}

pub export fn nurl_mutex_free(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const mutex = handleToMutex(handle) orelse return;
    c.free(mutex);
}

pub export fn nurl_cond_new() c_longlong {
    if (builtin.os.tag == .wasi) return 0;
    const raw = c.calloc(1, @sizeOf(NurlCond)) orelse return 0;
    const cond: *NurlCond = @ptrCast(@alignCast(raw));
    cond.* = .{};
    return @intCast(@intFromPtr(cond));
}

pub export fn nurl_cond_wait(cond_handle: c_longlong, mutex_handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const cond = handleToCond(cond_handle) orelse return;
    const mutex = handleToMutex(mutex_handle) orelse return;
    cond.cond.waitUncancelable(nurlIo(), &mutex.mutex);
}

pub export fn nurl_cond_signal(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const cond = handleToCond(handle) orelse return;
    cond.cond.signal(nurlIo());
}

pub export fn nurl_cond_broadcast(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const cond = handleToCond(handle) orelse return;
    cond.cond.broadcast(nurlIo());
}

pub export fn nurl_cond_free(handle: c_longlong) void {
    if (builtin.os.tag == .wasi) return;
    const cond = handleToCond(handle) orelse return;
    c.free(cond);
}

pub export fn nurl_dos_state_new(max_concurrent: c_longlong, max_per_ip: c_longlong) c_longlong {
    const raw = c.calloc(1, @sizeOf(NurlDosState)) orelse return 0;
    const state: *NurlDosState = @ptrCast(@alignCast(raw));
    state.* = .{
        .max_concurrent = max_concurrent,
        .max_per_ip = max_per_ip,
        .active_count = 0,
        .ip_entries = null,
        .ip_count = 0,
        .ip_cap = 0,
        .mutex = .init,
    };
    return @intCast(@intFromPtr(state));
}

pub export fn nurl_dos_state_try_acquire(handle: c_longlong, ip_ptr: ?[*:0]const u8) c_longlong {
    const state = handleToDosState(handle) orelse return 1;
    dosLock(state);
    defer dosUnlock(state);

    if (state.max_concurrent > 0 and state.active_count >= state.max_concurrent) return 0;

    const ip = std.mem.span(ip_ptr orelse "");
    if (state.max_per_ip > 0 and ip.len > 0) {
        if (dosFindIp(state, ip)) |idx| {
            const entries = state.ip_entries.?;
            if (entries[idx].count >= state.max_per_ip) return 0;
            entries[idx].count += 1;
        } else if (state.ip_count < 256) {
            if (state.ip_count == state.ip_cap) {
                var new_cap = if (state.ip_cap == 0) @as(usize, 16) else state.ip_cap * 2;
                if (new_cap > 256) new_cap = 256;
                if (new_cap > state.ip_cap) {
                    const grown = c.realloc(state.ip_entries, new_cap * @sizeOf(NurlDosIpEntry));
                    if (grown != null) {
                        state.ip_entries = @ptrCast(@alignCast(grown));
                        state.ip_cap = new_cap;
                    }
                }
            }
            if (state.ip_count < state.ip_cap) {
                const copy = dupSliceZ(ip) orelse {
                    state.active_count += 1;
                    return 1;
                };
                const entries = state.ip_entries.?;
                entries[state.ip_count] = .{
                    .ip = copy,
                    .count = 1,
                };
                state.ip_count += 1;
            }
        }
    }

    state.active_count += 1;
    return 1;
}

pub export fn nurl_dos_state_release(handle: c_longlong, ip_ptr: ?[*:0]const u8) void {
    const state = handleToDosState(handle) orelse return;
    dosLock(state);
    defer dosUnlock(state);

    if (state.active_count > 0) state.active_count -= 1;

    const ip = std.mem.span(ip_ptr orelse "");
    if (ip.len == 0) return;
    const idx = dosFindIp(state, ip) orelse return;
    const entries = state.ip_entries.?;
    if (entries[idx].count > 0) entries[idx].count -= 1;
    if (entries[idx].count != 0) return;

    c.free(entries[idx].ip);
    const last = state.ip_count - 1;
    if (idx != last) entries[idx] = entries[last];
    state.ip_count -= 1;
}

pub export fn nurl_dos_state_free(handle: c_longlong) void {
    const state = handleToDosState(handle) orelse return;
    if (state.ip_entries) |entries| {
        var i: usize = 0;
        while (i < state.ip_count) : (i += 1) c.free(entries[i].ip);
        c.free(entries);
    }
    c.free(state);
}

pub export fn nurl_dos_state_active(handle: c_longlong) c_longlong {
    const state = handleToDosState(handle) orelse return 0;
    dosLock(state);
    defer dosUnlock(state);
    return state.active_count;
}
