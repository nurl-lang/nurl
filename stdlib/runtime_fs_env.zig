const std = @import("std");
const builtin = @import("builtin");

const c = std.c;
const windows = std.os.windows;

extern "c" fn remove(path: [*:0]const u8) c_int;
extern "c" fn stat(path: [*:0]const u8, buf: *c.Stat) c_int;
extern "c" fn fseek(stream: *c.FILE, offset: c_long, whence: c_int) c_int;
extern "c" fn ftell(stream: *c.FILE) c_long;
extern "c" fn fputs(s: [*:0]const u8, stream: *c.FILE) c_int;
extern "c" fn fputc(ch: c_int, stream: *c.FILE) c_int;
extern "c" fn atoll(nptr: [*:0]const u8) c_longlong;
extern "c" fn strtod(nptr: [*:0]const u8, endptr: *?[*:0]u8) f64;
extern "c" fn sqrt(x: f64) f64;
extern "c" fn fabs(x: f64) f64;
extern "c" fn floor(x: f64) f64;
extern "c" fn ceil(x: f64) f64;
extern "c" fn round(x: f64) f64;
extern "c" fn pow(x: f64, y: f64) f64;
extern "c" fn log(x: f64) f64;
extern "c" fn exp(x: f64) f64;
extern "c" fn sin(x: f64) f64;
extern "c" fn cos(x: f64) f64;
extern "c" fn tan(x: f64) f64;
extern "c" fn atan2(y: f64, x: f64) f64;
extern "kernel32" fn Sleep(dwMilliseconds: windows.DWORD) callconv(.winapi) void;

const darwin = if (builtin.os.tag == .driverkit or
    builtin.os.tag == .ios or
    builtin.os.tag == .maccatalyst or
    builtin.os.tag == .macos or
    builtin.os.tag == .tvos or
    builtin.os.tag == .visionos or
    builtin.os.tag == .watchos) struct {
    extern "c" fn @"stat$INODE64"(path: [*:0]const u8, buf: *c.Stat) c_int;
    extern "c" fn @"fstat$INODE64"(fd: c.fd_t, buf: *c.Stat) c_int;
} else struct {};

const posix = if (builtin.os.tag == .windows) struct {} else struct {
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    extern "c" fn close(fd: c.fd_t) c_int;
    extern "c" fn fstat(fd: c.fd_t, buf: *c.Stat) c_int;
};

const win = if (builtin.os.tag == .windows) struct {
    const WIN32_FIND_DATAA = extern struct {
        dwFileAttributes: windows.DWORD,
        ftCreationTime: windows.FILETIME,
        ftLastAccessTime: windows.FILETIME,
        ftLastWriteTime: windows.FILETIME,
        nFileSizeHigh: windows.DWORD,
        nFileSizeLow: windows.DWORD,
        dwReserved0: windows.DWORD,
        dwReserved1: windows.DWORD,
        cFileName: [windows.MAX_PATH]u8,
        cAlternateFileName: [14]u8,
    };

    extern "kernel32" fn FindFirstFileA(lpFileName: [*:0]const u8, lpFindFileData: *WIN32_FIND_DATAA) callconv(.winapi) windows.HANDLE;
    extern "kernel32" fn FindNextFileA(hFindFile: windows.HANDLE, lpFindFileData: *WIN32_FIND_DATAA) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn FindClose(hFindFile: windows.HANDLE) callconv(.winapi) windows.BOOL;

    extern "c" fn _putenv_s(name: [*:0]const u8, value: [*:0]const u8) c_int;
    extern "c" fn _getcwd(buf: ?[*]u8, size: c_int) ?[*:0]u8;
    extern "c" fn _chdir(path: [*:0]const u8) c_int;
    extern "c" fn _mkdir(path: [*:0]const u8) c_int;
    extern "c" fn _rmdir(path: [*:0]const u8) c_int;
    extern "c" fn _read(fd: c_int, buf: [*]u8, count: c_uint) c_int;
} else struct {};

fn setErrno(err: c.E) void {
    c._errno().* = @intFromEnum(err);
}

fn ensureErrnoOr(err: c.E) void {
    if (c._errno().* == 0) setErrno(err);
}

fn statCall(path: [*:0]const u8, buf: *c.Stat) c_int {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (builtin.cpu.arch) {
            .x86_64 => darwin.@"stat$INODE64"(path, buf),
            else => stat(path, buf),
        },
        else => stat(path, buf),
    };
}

fn fstatCall(fd: c.fd_t, buf: *c.Stat) c_int {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (builtin.cpu.arch) {
            .x86_64 => darwin.@"fstat$INODE64"(fd, buf),
            else => posix.fstat(fd, buf),
        },
        else => posix.fstat(fd, buf),
    };
}

fn dupZ(src: [*:0]const u8) ?[*:0]u8 {
    const len = std.mem.len(src);
    const raw = c.malloc(len + 1) orelse {
        setErrno(.NOMEM);
        return null;
    };
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..len], src[0..len]);
    buf[len] = 0;
    return @ptrCast(buf);
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

fn allocBytes(len: usize) ?[*]u8 {
    const raw = c.malloc(len) orelse {
        setErrno(.NOMEM);
        return null;
    };
    return @ptrCast(raw);
}

fn concatSlices(parts: []const []const u8) ?[*:0]u8 {
    var total: usize = 0;
    for (parts) |part| total += part.len;
    const raw = c.malloc(total + 1) orelse {
        setErrno(.NOMEM);
        return null;
    };
    const buf: [*]u8 = @ptrCast(raw);
    var cursor: usize = 0;
    for (parts) |part| {
        @memcpy(buf[cursor .. cursor + part.len], part);
        cursor += part.len;
    }
    buf[total] = 0;
    return @ptrCast(buf);
}

fn asciiByte(value: c_longlong) ?u8 {
    if (value < 0 or value > std.math.maxInt(u8)) return null;
    return @intCast(value);
}

fn parseFloatRangeFast(raw: []const u8) f64 {
    if (raw.len == 0) return 0.0;

    var i: usize = 0;
    var neg = false;
    if (raw[0] == '-') {
        neg = true;
        i = 1;
    } else if (raw[0] == '+') {
        i = 1;
    }

    var result: f64 = 0.0;
    while (i < raw.len) : (i += 1) {
        const ch = raw[i];
        if (ch < '0' or ch > '9') break;
        result = result * 10.0 + @as(f64, @floatFromInt(ch - '0'));
    }

    if (i < raw.len and raw[i] == '.') {
        i += 1;
        var scale: f64 = 0.1;
        while (i < raw.len) : (i += 1) {
            const ch = raw[i];
            if (ch < '0' or ch > '9') break;
            result += @as(f64, @floatFromInt(ch - '0')) * scale;
            scale *= 0.1;
        }
    }

    if (i < raw.len and (raw[i] == 'e' or raw[i] == 'E')) {
        i += 1;
        var exp_neg = false;
        if (i < raw.len) {
            if (raw[i] == '-') {
                exp_neg = true;
                i += 1;
            } else if (raw[i] == '+') {
                i += 1;
            }
        }

        var exp_val: u32 = 0;
        while (i < raw.len) : (i += 1) {
            const ch = raw[i];
            if (ch < '0' or ch > '9') break;
            exp_val = exp_val * 10 + (ch - '0');
        }

        var base: f64 = 10.0;
        var mult: f64 = 1.0;
        var exp_left = exp_val;
        while (exp_left > 0) {
            if ((exp_left & 1) != 0) mult *= base;
            base *= base;
            exp_left >>= 1;
        }
        if (exp_neg) result /= mult else result *= mult;
    }

    return if (neg) -result else result;
}

fn handleToFile(handle: ?*anyopaque) ?*c.FILE {
    const ptr = handle orelse return null;
    return @ptrCast(@alignCast(ptr));
}

const NurlDirIter = if (builtin.os.tag == .windows) struct {
    h: windows.HANDLE,
    fd: win.WIN32_FIND_DATAA,
    primed: bool,
    closed: bool,
} else struct {
    dir: std.Io.Dir,
    iter: std.Io.Dir.Iterator,
};

const nurl_map_buckets = 64;

const NurlMapEntry = struct {
    key: [*:0]u8,
    val: c_longlong,
    next: ?*NurlMapEntry,
};

const NurlMap = struct {
    buckets: [nurl_map_buckets]?*NurlMapEntry,
    size: c_longlong,
};

const max_cgs = 8;

const NurlCG = struct {
    reg: c_int,
    lbl: c_int,
};

fn readFileAlloc(path: [*:0]const u8, nul_terminate: bool, empty_alloc_one: bool) ?[*]u8 {
    const file = c.fopen(path, "rb") orelse return null;
    defer _ = c.fclose(file);

    if (fseek(file, 0, 2) != 0) return null;
    const end = ftell(file);
    if (end < 0) return null;
    if (fseek(file, 0, 0) != 0) return null;

    const size: usize = @intCast(end);
    const alloc_len = if (nul_terminate) size + 1 else @max(size, if (empty_alloc_one) @as(usize, 1) else @as(usize, 0));
    const buf = allocBytes(alloc_len) orelse return null;
    const got = if (size > 0) c.fread(buf, 1, size, file) else 0;

    if (size > 0 and got != size) {
        c.free(buf);
        ensureErrnoOr(.IO);
        return null;
    }
    if (nul_terminate) buf[got] = 0;
    return buf;
}

fn nurlMapHash(s: [*:0]const u8) usize {
    var h: u32 = 5381;
    for (std.mem.span(s)) |ch| {
        h = ((h << 5) + h) ^ ch;
    }
    return h % nurl_map_buckets;
}

fn handleToMap(handle: c_longlong) ?*NurlMap {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

var g_cgs: [max_cgs]?*NurlCG = .{null} ** max_cgs;
var g_cg_count: c_int = 0;
var g_last_type: [*:0]const u8 = "i64";
var g_last_type_owned = false;
var g_last_parsed_float: f64 = 0.0;
var g_csv_row_n_cells: c_longlong = 0;
var g_csv_row_next_pos: c_longlong = 0;
var g_log_level: c_longlong = 1;

fn getCg(handle: c_longlong) *NurlCG {
    const idx: c_int = @intCast(handle - 1);
    if (idx < 0 or idx >= g_cg_count or g_cgs[@intCast(idx)] == null) {
        std.debug.print("nurlc: invalid cg handle\n", .{});
        std.process.exit(1);
    }
    return g_cgs[@intCast(idx)].?;
}

fn mapDirOpenError(err: anyerror) void {
    switch (err) {
        error.FileNotFound => setErrno(.NOENT),
        error.NotDir => setErrno(.NOTDIR),
        error.AccessDenied, error.PermissionDenied => setErrno(.ACCES),
        error.ProcessFdQuotaExceeded => setErrno(.MFILE),
        error.SystemFdQuotaExceeded => setErrno(.NFILE),
        error.NoDevice => setErrno(.NODEV),
        error.SystemResources => setErrno(.NOMEM),
        else => setErrno(.IO),
    }
}

fn mapDirIterError(err: anyerror) void {
    switch (err) {
        error.AccessDenied, error.PermissionDenied => setErrno(.ACCES),
        error.SystemResources => setErrno(.NOMEM),
        else => setErrno(.IO),
    }
}

fn mapMmapError(err: anyerror) void {
    switch (err) {
        error.AccessDenied, error.PermissionDenied => setErrno(.ACCES),
        error.LockedMemoryLimitExceeded => setErrno(.AGAIN),
        error.ProcessFdQuotaExceeded => setErrno(.MFILE),
        error.SystemFdQuotaExceeded => setErrno(.NFILE),
        error.OutOfMemory => setErrno(.NOMEM),
        error.MappingAlreadyExists => setErrno(.EXIST),
        error.MemoryMappingNotSupported => setErrno(.NODEV),
        else => setErrno(.IO),
    }
}

fn cwdPosix() ?[*:0]u8 {
    var cap: usize = 256;
    while (true) {
        const raw = c.malloc(cap) orelse {
            setErrno(.NOMEM);
            return null;
        };
        const buf: [*]u8 = @ptrCast(raw);
        if (c.getcwd(buf, cap)) |_| {
            return @ptrCast(buf);
        }
        c.free(raw);
        if (c.errno(-1) != .RANGE) return null;
        if (cap >= (1 << 20)) return null;
        cap *= 2;
    }
}

fn cwdWindows() ?[*:0]u8 {
    const raw = win._getcwd(null, 0) orelse return null;
    defer c.free(raw);
    return dupZ(raw);
}

var g_argc: c_int = 0;
var g_argv: [*c][*c]u8 = null;

pub export fn nurl_init(argc: c_int, argv: [*c][*c]u8) void {
    g_argc = argc;
    g_argv = argv;
}

pub export fn nurl_argc() c_longlong {
    return g_argc;
}

pub export fn nurl_argv(i: c_longlong) ?[*:0]u8 {
    if (i < 0 or i >= g_argc) return dupZ("");
    const raw = g_argv[@intCast(i)];
    if (raw == null) return dupZ("");
    return dupZ(@ptrCast(raw));
}

pub export fn nurl_argv_count() c_longlong {
    return g_argc;
}

pub export fn nurl_argv_get(i: c_longlong) ?[*:0]u8 {
    return nurl_argv(i);
}

pub export fn nurl_exit(code: c_longlong) noreturn {
    std.process.exit(@intCast(code));
}

pub export fn nurl_env_get(name: ?[*:0]const u8) ?[*:0]u8 {
    const key = name orelse return null;
    const value = c.getenv(key) orelse return null;
    return dupZ(value);
}

pub export fn nurl_env_set(name: ?[*:0]const u8, value: ?[*:0]const u8) c_longlong {
    const key = name orelse {
        setErrno(.INVAL);
        return -1;
    };
    const val = value orelse {
        setErrno(.INVAL);
        return -1;
    };

    if (builtin.os.tag == .windows) {
        return if (win._putenv_s(key, val) == 0) 0 else -1;
    }
    return if (posix.setenv(key, val, 1) == 0) 0 else -1;
}

pub export fn nurl_env_unset(name: ?[*:0]const u8) c_longlong {
    const key = name orelse {
        setErrno(.INVAL);
        return -1;
    };

    if (builtin.os.tag == .windows) {
        return if (win._putenv_s(key, "") == 0) 0 else -1;
    }
    return if (posix.unsetenv(key) == 0) 0 else -1;
}

pub export fn nurl_cwd() ?[*:0]u8 {
    if (builtin.os.tag == .windows) return cwdWindows();
    return cwdPosix();
}

pub export fn nurl_chdir(path: ?[*:0]const u8) c_longlong {
    const target = path orelse {
        setErrno(.INVAL);
        return -1;
    };

    if (builtin.os.tag == .windows) {
        return if (win._chdir(target) == 0) 0 else -1;
    }
    return if (c.chdir(target) == 0) 0 else -1;
}

pub export fn nurl_file_exists(path: ?[*:0]const u8) c_longlong {
    const file_path = path orelse return 0;
    var st: c.Stat = undefined;
    return if (statCall(file_path, &st) == 0) 1 else 0;
}

pub export fn nurl_read_file(path: ?[*:0]const u8) ?[*:0]u8 {
    const file_path = path orelse {
        std.debug.print("nurlc: cannot open <null>\n", .{});
        std.process.exit(1);
    };
    const buf = readFileAlloc(file_path, true, false) orelse {
        std.debug.print("nurlc: cannot open '{s}'\n", .{std.mem.span(file_path)});
        std.process.exit(1);
    };
    return @ptrCast(buf);
}

pub export fn nurl_read_file_safe(path: ?[*:0]const u8) ?[*:0]u8 {
    const file_path = path orelse {
        setErrno(.INVAL);
        return null;
    };
    const buf = readFileAlloc(file_path, true, false) orelse return null;
    return @ptrCast(buf);
}

pub export fn nurl_errno_kind() c_longlong {
    return switch (c.errno(-1)) {
        .NOENT => 0,
        .ACCES, .PERM => 1,
        .EXIST => 2,
        .INTR => 3,
        else => 7,
    };
}

pub export fn nurl_file_open(path: ?[*:0]const u8, mode: ?[*:0]const u8) ?*anyopaque {
    const file_path = path orelse return null;
    const file_mode = mode orelse return null;
    const file = c.fopen(file_path, file_mode) orelse return null;
    return @ptrCast(file);
}

pub export fn nurl_file_write(handle: ?*anyopaque, s: ?[*:0]const u8) void {
    const file = handleToFile(handle) orelse return;
    const text = s orelse return;
    _ = fputs(text, file);
}

pub export fn nurl_file_write_range(handle: ?*anyopaque, p: ?[*]const u8, len: c_longlong) void {
    const file = handleToFile(handle) orelse return;
    const ptr = p orelse return;
    if (len <= 0) return;
    _ = c.fwrite(ptr, 1, @intCast(len), file);
}

pub export fn nurl_file_write_byte(handle: ?*anyopaque, value: c_longlong) void {
    const file = handleToFile(handle) orelse return;
    _ = fputc(@intCast(value & 0xff), file);
}

pub export fn nurl_file_close(handle: ?*anyopaque) void {
    const file = handleToFile(handle) orelse return;
    _ = c.fclose(file);
}

pub export fn nurl_file_read(path: ?[*:0]const u8) ?[*:0]u8 {
    return nurl_read_file(path);
}

pub export fn nurl_file_size(path: ?[*:0]const u8) c_longlong {
    const file_path = path orelse {
        setErrno(.INVAL);
        return -1;
    };
    var st: c.Stat = undefined;
    if (statCall(file_path, &st) == 0) return @intCast(st.size);
    return -1;
}

pub export fn nurl_file_del(path: ?[*:0]const u8) void {
    const file_path = path orelse return;
    _ = remove(file_path);
}

pub export fn nurl_write_file_safe(path: ?[*:0]const u8, content: ?[*:0]const u8, mode: ?[*:0]const u8) c_longlong {
    const file_path = path orelse {
        setErrno(.INVAL);
        return -1;
    };
    const text = content orelse {
        setErrno(.INVAL);
        return -1;
    };
    const file_mode = mode orelse {
        setErrno(.INVAL);
        return -1;
    };

    const file = c.fopen(file_path, file_mode) orelse return -1;
    const n = std.mem.len(text);
    if (n > 0) {
        const got = c.fwrite(text, 1, n, file);
        if (got != n) {
            const saved_errno = c._errno().*;
            _ = c.fclose(file);
            c._errno().* = if (saved_errno != 0) saved_errno else @intFromEnum(c.E.IO);
            return -1;
        }
    }
    if (c.fclose(file) != 0) return -1;
    return 0;
}

var g_last_bytes_len: c_longlong = 0;
var g_nurl_mmap_size: c_longlong = 0;

pub export fn nurl_last_bytes_len() c_longlong {
    return g_last_bytes_len;
}

pub export fn nurl_read_file_mmap_size_out() c_longlong {
    return g_nurl_mmap_size;
}

pub export fn nurl_read_file_bytes(path: ?[*:0]const u8) ?[*]const u8 {
    g_last_bytes_len = 0;
    const file_path = path orelse {
        setErrno(.INVAL);
        return null;
    };
    const file = c.fopen(file_path, "rb") orelse {
        return null;
    };
    defer _ = c.fclose(file);

    if (fseek(file, 0, 2) != 0) {
        return null;
    }
    const end = ftell(file);
    if (end < 0) {
        return null;
    }
    if (fseek(file, 0, 0) != 0) {
        return null;
    }

    const size: usize = @intCast(end);
    const buf = allocBytes(@max(size, @as(usize, 1))) orelse return null;
    const got = if (size > 0) c.fread(buf, 1, size, file) else 0;
    if (size > 0 and got != size) {
        c.free(buf);
        ensureErrnoOr(.IO);
        return null;
    }
    g_last_bytes_len = @intCast(got);
    return buf;
}

pub export fn nurl_write_file_bytes(path: ?[*:0]const u8, data: ?[*]const u8, len: c_longlong, mode: ?[*:0]const u8) c_longlong {
    const file_path = path orelse {
        setErrno(.INVAL);
        return -1;
    };
    const file_mode = mode orelse {
        setErrno(.INVAL);
        return -1;
    };
    if (len < 0) {
        setErrno(.INVAL);
        return -1;
    }
    if (len > 0 and data == null) {
        setErrno(.INVAL);
        return -1;
    }

    const file = c.fopen(file_path, file_mode) orelse return -1;
    if (len > 0) {
        const got = c.fwrite(data.?, 1, @intCast(len), file);
        if (got != @as(usize, @intCast(len))) {
            const saved_errno = c._errno().*;
            _ = c.fclose(file);
            c._errno().* = if (saved_errno != 0) saved_errno else @intFromEnum(c.E.IO);
            return -1;
        }
    }
    if (c.fclose(file) != 0) return -1;
    return 0;
}

pub export fn nurl_read_file_mmap_zero(path: ?[*:0]const u8) ?[*]const u8 {
    g_nurl_mmap_size = 0;
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return null;

    const file_path = path orelse {
        setErrno(.INVAL);
        return null;
    };
    const fd = c.open(file_path, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = posix.close(fd);

    var st: c.Stat = undefined;
    if (fstatCall(fd, &st) != 0) return null;
    if (st.size <= 0) return null;

    const size: usize = @intCast(st.size);
    const view = std.posix.mmap(null, size, .{ .READ = true }, std.posix.MAP{ .TYPE = .PRIVATE }, fd, 0) catch |err| {
        mapMmapError(err);
        return null;
    };
    std.posix.madvise(view.ptr, view.len, c.MADV.SEQUENTIAL) catch {};
    g_nurl_mmap_size = @intCast(size);
    return @ptrCast(view.ptr);
}

pub export fn nurl_munmap_file(ptr: ?[*]const u8, sz: c_longlong) void {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return;
    const mapped = ptr orelse return;
    if (sz <= 0) return;
    const size: usize = @intCast(sz);
    const view: []align(std.heap.page_size_min) const u8 = @as([*]align(std.heap.page_size_min) const u8, @ptrCast(@alignCast(mapped)))[0..size];
    std.posix.munmap(view);
}

pub export fn nurl_read_file_mmap(path: ?[*:0]const u8) ?[*:0]u8 {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
        return nurl_read_file_safe(path);
    }

    const file_path = path orelse {
        setErrno(.INVAL);
        return null;
    };
    const fd = c.open(file_path, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = posix.close(fd);

    var st: c.Stat = undefined;
    if (fstatCall(fd, &st) != 0) return null;
    if (st.size <= 0) {
        const buf = allocBytes(1) orelse return null;
        buf[0] = 0;
        return @ptrCast(buf);
    }

    const size: usize = @intCast(st.size);
    const view = std.posix.mmap(null, size, .{ .READ = true }, std.posix.MAP{ .TYPE = .PRIVATE }, fd, 0) catch |err| {
        mapMmapError(err);
        return null;
    };
    defer std.posix.munmap(view);

    std.posix.madvise(view.ptr, view.len, c.MADV.SEQUENTIAL) catch {};
    const buf = allocBytes(size + 1) orelse return null;
    @memcpy(buf[0..size], view[0..size]);
    buf[size] = 0;
    return @ptrCast(buf);
}

pub export fn nurl_read_all_stdin() ?[*:0]u8 {
    var cap: usize = 4096;
    var raw = c.malloc(cap) orelse return null;
    var buf: [*]u8 = @ptrCast(raw);
    var len: usize = 0;

    while (true) {
        var want = cap - len - 1;
        if (want == 0) {
            const ncap = cap * 2;
            raw = c.realloc(raw, ncap) orelse {
                c.free(raw);
                setErrno(.NOMEM);
                return null;
            };
            buf = @ptrCast(raw);
            cap = ncap;
            want = cap - len - 1;
        }

        const got = if (builtin.os.tag == .windows) blk: {
            const rc = win._read(0, buf + len, @intCast(want));
            if (rc < 0) {
                c.free(raw);
                return null;
            }
            break :blk @as(usize, @intCast(rc));
        } else blk: {
            const rc = c.read(0, buf + len, want);
            if (rc < 0) {
                c.free(raw);
                return null;
            }
            break :blk @as(usize, @intCast(rc));
        };
        len += got;
        if (got == 0) break;
    }

    buf[len] = 0;
    return @ptrCast(buf);
}

pub export fn nurl_dir_list_open(path: ?[*:0]const u8) c_longlong {
    const dir_path = path orelse {
        setErrno(.INVAL);
        return 0;
    };

    if (builtin.os.tag == .windows) {
        const path_len = std.mem.len(dir_path);
        const pattern_len = if (path_len == 0 or (dir_path[path_len - 1] != '\\' and dir_path[path_len - 1] != '/'))
            path_len + 2
        else
            path_len + 1;
        const pattern = allocBytes(pattern_len + 1) orelse return 0;
        defer c.free(pattern);

        @memcpy(pattern[0..path_len], dir_path[0..path_len]);
        if (path_len == 0 or (dir_path[path_len - 1] != '\\' and dir_path[path_len - 1] != '/')) {
            pattern[path_len] = '\\';
            pattern[path_len + 1] = '*';
            pattern[path_len + 2] = 0;
        } else {
            pattern[path_len] = '*';
            pattern[path_len + 1] = 0;
        }

        const raw_iter = c.calloc(1, @sizeOf(NurlDirIter)) orelse {
            setErrno(.NOMEM);
            return 0;
        };
        const iter: *NurlDirIter = @ptrCast(@alignCast(raw_iter));
        iter.h = win.FindFirstFileA(@ptrCast(pattern), &iter.fd);
        if (iter.h == windows.INVALID_HANDLE_VALUE) {
            if (windows.GetLastError() == .FILE_NOT_FOUND) {
                iter.closed = true;
                return @intCast(@intFromPtr(iter));
            }
            c.free(raw_iter);
            setErrno(.NOENT);
            return 0;
        }
        iter.primed = true;
        return @intCast(@intFromPtr(iter));
    }

    const io = std.Io.Threaded.global_single_threaded.io();
    const path_slice = std.mem.span(dir_path);
    const dir = if (std.fs.path.isAbsolute(path_slice))
        std.Io.Dir.openDirAbsolute(io, path_slice, .{ .iterate = true })
    else
        std.Io.Dir.openDir(std.Io.Dir.cwd(), io, path_slice, .{ .iterate = true });
    const opened = dir catch |err| {
        mapDirOpenError(err);
        return 0;
    };

    const raw_iter = c.calloc(1, @sizeOf(NurlDirIter)) orelse {
        opened.close(io);
        setErrno(.NOMEM);
        return 0;
    };
    const iter: *NurlDirIter = @ptrCast(@alignCast(raw_iter));
    iter.* = .{
        .dir = opened,
        .iter = opened.iterate(),
    };
    return @intCast(@intFromPtr(iter));
}

pub export fn nurl_dir_list_next(handle: c_longlong) ?[*:0]u8 {
    if (handle == 0) return null;

    if (builtin.os.tag == .windows) {
        const iter: *NurlDirIter = @ptrFromInt(@as(usize, @intCast(handle)));
        if (iter.closed) return null;
        while (true) {
            if (!iter.primed) {
                if (win.FindNextFileA(iter.h, &iter.fd) == .FALSE) return null;
            }
            iter.primed = false;
            const name = iter.fd.cFileName[0..];
            const len = std.mem.indexOfScalar(u8, name, 0) orelse name.len;
            const trimmed = name[0..len];
            if (std.mem.eql(u8, trimmed, ".") or std.mem.eql(u8, trimmed, "..")) continue;
            return dupSliceZ(trimmed);
        }
    }

    const iter: *NurlDirIter = @ptrFromInt(@as(usize, @intCast(handle)));
    const io = std.Io.Threaded.global_single_threaded.io();
    while (true) {
        const entry = iter.iter.next(io) catch |err| {
            mapDirIterError(err);
            return null;
        } orelse return null;
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        return dupSliceZ(entry.name);
    }
}

pub export fn nurl_dir_list_close(handle: c_longlong) void {
    if (handle == 0) return;

    if (builtin.os.tag == .windows) {
        const iter: *NurlDirIter = @ptrFromInt(@as(usize, @intCast(handle)));
        if (!iter.closed and iter.h != windows.INVALID_HANDLE_VALUE) {
            _ = win.FindClose(iter.h);
        }
        c.free(iter);
        return;
    }

    const iter: *NurlDirIter = @ptrFromInt(@as(usize, @intCast(handle)));
    const io = std.Io.Threaded.global_single_threaded.io();
    iter.dir.close(io);
    c.free(iter);
}

pub export fn nurl_dir_create(path: ?[*:0]const u8) c_longlong {
    const dir_path = path orelse {
        setErrno(.INVAL);
        return -1;
    };

    if (builtin.os.tag == .windows) {
        return if (win._mkdir(dir_path) == 0) 0 else -1;
    }
    return if (c.mkdir(dir_path, 0o755) == 0) 0 else -1;
}

pub export fn nurl_dir_remove(path: ?[*:0]const u8) c_longlong {
    const dir_path = path orelse {
        setErrno(.INVAL);
        return -1;
    };

    if (builtin.os.tag == .windows) {
        return if (win._rmdir(dir_path) == 0) 0 else -1;
    }
    return if (c.rmdir(dir_path) == 0) 0 else -1;
}

pub export fn nurl_map_new() c_longlong {
    const raw = c.calloc(1, @sizeOf(NurlMap)) orelse return 0;
    const map: *NurlMap = @ptrCast(@alignCast(raw));
    return @intCast(@intFromPtr(map));
}

pub export fn nurl_map_put(handle: c_longlong, key: ?[*:0]const u8, val: c_longlong) void {
    const map = handleToMap(handle) orelse return;
    const map_key = key orelse return;
    const bucket_index = nurlMapHash(map_key);
    var cursor = map.buckets[bucket_index];
    while (cursor) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.key), std.mem.span(map_key))) {
            entry.val = val;
            return;
        }
        cursor = entry.next;
    }

    const raw_entry = c.calloc(1, @sizeOf(NurlMapEntry)) orelse return;
    const entry: *NurlMapEntry = @ptrCast(@alignCast(raw_entry));
    const duped = dupZ(map_key) orelse {
        c.free(raw_entry);
        return;
    };
    entry.* = .{
        .key = duped,
        .val = val,
        .next = map.buckets[bucket_index],
    };
    map.buckets[bucket_index] = entry;
    map.size += 1;
}

pub export fn nurl_map_get(handle: c_longlong, key: ?[*:0]const u8) c_longlong {
    const map = handleToMap(handle) orelse return 0;
    const map_key = key orelse return 0;
    var cursor = map.buckets[nurlMapHash(map_key)];
    while (cursor) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.key), std.mem.span(map_key))) {
            return entry.val;
        }
        cursor = entry.next;
    }
    return 0;
}

pub export fn nurl_map_has(handle: c_longlong, key: ?[*:0]const u8) c_longlong {
    const map = handleToMap(handle) orelse return 0;
    const map_key = key orelse return 0;
    var cursor = map.buckets[nurlMapHash(map_key)];
    while (cursor) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.key), std.mem.span(map_key))) {
            return 1;
        }
        cursor = entry.next;
    }
    return 0;
}

pub export fn nurl_map_del(handle: c_longlong, key: ?[*:0]const u8) void {
    const map = handleToMap(handle) orelse return;
    const map_key = key orelse return;
    const bucket_index = nurlMapHash(map_key);
    var cursor = &map.buckets[bucket_index];
    while (cursor.*) |entry| {
        if (std.mem.eql(u8, std.mem.span(entry.key), std.mem.span(map_key))) {
            cursor.* = entry.next;
            c.free(entry.key);
            c.free(entry);
            map.size -= 1;
            return;
        }
        cursor = &entry.next;
    }
}

pub export fn nurl_map_size(handle: c_longlong) c_longlong {
    const map = handleToMap(handle) orelse return 0;
    return map.size;
}

pub export fn nurl_map_free(handle: c_longlong) void {
    const map = handleToMap(handle) orelse return;
    for (&map.buckets) |*bucket| {
        var cursor = bucket.*;
        while (cursor) |entry| {
            const next = entry.next;
            c.free(entry.key);
            c.free(entry);
            cursor = next;
        }
        bucket.* = null;
    }
    c.free(map);
}

pub export fn nurl_cg_new() c_longlong {
    if (g_cg_count >= max_cgs) {
        std.debug.print("nurlc: too many codegen handles\n", .{});
        std.process.exit(1);
    }
    const raw = c.calloc(1, @sizeOf(NurlCG)) orelse {
        std.debug.print("nurlc: out of memory allocating cg handle\n", .{});
        std.process.exit(1);
    };
    const cg: *NurlCG = @ptrCast(@alignCast(raw));
    const idx = g_cg_count;
    g_cgs[@intCast(idx)] = cg;
    g_cg_count += 1;
    return idx + 1;
}

pub export fn nurl_cg_reg(handle: c_longlong) ?[*:0]u8 {
    const cg = getCg(handle);
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{c}r{d}", .{ '%', cg.reg }) catch {
        std.debug.print("nurlc: cg reg format failed\n", .{});
        std.process.exit(1);
    };
    cg.reg += 1;
    return dupSliceZ(out);
}

pub export fn nurl_cg_lbl(handle: c_longlong, hint: ?[*:0]const u8) ?[*:0]u8 {
    const cg = getCg(handle);
    const label_hint = hint orelse "";
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{s}_{d}", .{ std.mem.span(label_hint), cg.lbl }) catch {
        std.debug.print("nurlc: cg label format failed\n", .{});
        std.process.exit(1);
    };
    cg.lbl += 1;
    return dupSliceZ(out);
}

pub export fn nurl_cg_reset(handle: c_longlong) void {
    const cg = getCg(handle);
    cg.reg = 0;
    cg.lbl = 0;
}

pub export fn nurl_get_last_type() ?[*:0]u8 {
    return dupZ(g_last_type);
}

pub export fn nurl_set_last_type(t: ?[*:0]const u8) void {
    const dup = dupZ(t orelse "") orelse {
        std.debug.print("nurlc: out of memory setting last type\n", .{});
        std.process.exit(1);
    };
    if (g_last_type_owned) c.free(@constCast(g_last_type));
    g_last_type = dup;
    g_last_type_owned = true;
}

pub export fn nurl_alloc(bytes: c_longlong) ?*anyopaque {
    if (bytes < 0) return null;
    return c.malloc(@intCast(bytes));
}

pub export fn nurl_zalloc(bytes: c_longlong) ?*anyopaque {
    if (bytes < 0) return null;
    return c.calloc(1, @intCast(bytes));
}

pub export fn nurl_realloc(ptr: ?*anyopaque, bytes: c_longlong) ?*anyopaque {
    if (bytes < 0) return null;
    return c.realloc(ptr, @intCast(bytes));
}

pub export fn nurl_free(ptr: ?*anyopaque) void {
    if (ptr) |p| c.free(p);
}

pub export fn nurl_memcpy(dst: ?*anyopaque, src: ?*const anyopaque, bytes: c_longlong) void {
    if (bytes <= 0) return;
    const out = dst orelse return;
    const input = src orelse return;
    @memcpy(@as([*]u8, @ptrCast(out))[0..@intCast(bytes)], @as([*]const u8, @ptrCast(input))[0..@intCast(bytes)]);
}

pub export fn nurl_memset(dst: ?*anyopaque, byte: c_longlong, bytes: c_longlong) void {
    if (bytes <= 0) return;
    const out = dst orelse return;
    @memset(@as([*]u8, @ptrCast(out))[0..@intCast(bytes)], @as(u8, @intCast(byte & 0xff)));
}

pub export fn nurl_peek(base: ?*const anyopaque, idx: c_longlong) c_longlong {
    const ptr = base orelse return 0;
    if (idx < 0) return 0;
    return @as([*]const c_longlong, @ptrCast(@alignCast(ptr)))[@intCast(idx)];
}

pub export fn nurl_poke(base: ?*anyopaque, idx: c_longlong, val: c_longlong) void {
    const ptr = base orelse return;
    if (idx < 0) return;
    @as([*]c_longlong, @ptrCast(@alignCast(ptr)))[@intCast(idx)] = val;
}

pub export fn nurl_malloc(bytes: c_longlong) ?*anyopaque {
    return nurl_alloc(bytes);
}

pub export fn nurl_log_level_get() c_longlong {
    return g_log_level;
}

pub export fn nurl_log_level_set(level: c_longlong) void {
    g_log_level = level;
}

pub export fn nurl_str_len(input: ?[*:0]const u8) c_longlong {
    const raw = input orelse return 0;
    return @intCast(std.mem.len(raw));
}

pub export fn nurl_str_get(input: ?[*:0]const u8, idx: c_longlong) c_longlong {
    const raw = input orelse return 0;
    if (idx < 0) return 0;
    const slice = std.mem.span(raw);
    const index: usize = @intCast(idx);
    if (index >= slice.len) return 0;
    return slice[index];
}

pub export fn nurl_str_eq(a: ?[*:0]const u8, b: ?[*:0]const u8) c_longlong {
    const lhs = std.mem.span(a orelse "");
    const rhs = std.mem.span(b orelse "");
    return if (std.mem.eql(u8, lhs, rhs)) 1 else 0;
}

pub export fn nurl_str_cmp(a: ?[*:0]const u8, b: ?[*:0]const u8) c_longlong {
    const lhs = std.mem.span(a orelse "");
    const rhs = std.mem.span(b orelse "");
    return switch (std.mem.order(u8, lhs, rhs)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub export fn nurl_str_cat(a: ?[*:0]const u8, b: ?[*:0]const u8) ?[*:0]u8 {
    return concatSlices(&.{ std.mem.span(a orelse ""), std.mem.span(b orelse "") });
}

pub export fn nurl_str_cat3(a: ?[*:0]const u8, b: ?[*:0]const u8, c3: ?[*:0]const u8) ?[*:0]u8 {
    return concatSlices(&.{ std.mem.span(a orelse ""), std.mem.span(b orelse ""), std.mem.span(c3 orelse "") });
}

pub export fn nurl_str_cat4(a: ?[*:0]const u8, b: ?[*:0]const u8, c3: ?[*:0]const u8, d: ?[*:0]const u8) ?[*:0]u8 {
    return concatSlices(&.{ std.mem.span(a orelse ""), std.mem.span(b orelse ""), std.mem.span(c3 orelse ""), std.mem.span(d orelse "") });
}

pub export fn nurl_str_int(value: c_longlong) ?[*:0]u8 {
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
        std.debug.print("nurlc: int format failed\n", .{});
        std.process.exit(1);
    };
    return dupSliceZ(out);
}

pub export fn nurl_str_float(value: f64) ?[*:0]u8 {
    var buf: [128]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
        std.debug.print("nurlc: float format failed\n", .{});
        std.process.exit(1);
    };
    return dupSliceZ(out);
}

pub export fn nurl_str_to_int(input: ?[*:0]const u8) c_longlong {
    const raw = input orelse return 0;
    return atoll(raw);
}

pub export fn nurl_str_to_float(input: ?[*:0]const u8) f64 {
    const raw = input orelse return 0.0;
    var end_ptr: ?[*:0]u8 = null;
    return strtod(raw, &end_ptr);
}

pub export fn nurl_parse_int_range(ptr: ?[*]const u8, len: c_longlong) c_longlong {
    const raw = ptr orelse return 0;
    if (len <= 0) return 0;
    const slice = raw[0..@intCast(len)];
    var i: usize = 0;
    var sign: c_longlong = 1;
    if (slice[0] == '-') {
        sign = -1;
        i = 1;
    } else if (slice[0] == '+') {
        i = 1;
    }
    var acc: c_longlong = 0;
    while (i < slice.len) : (i += 1) {
        const ch = slice[i];
        if (ch < '0' or ch > '9') break;
        acc = acc * 10 + @as(c_longlong, @intCast(ch - '0'));
    }
    return acc * sign;
}

pub export fn nurl_parse_float_range(ptr: ?[*]const u8, len: c_longlong) f64 {
    const raw = ptr orelse return 0.0;
    if (len <= 0) return 0.0;
    const span_len: usize = @intCast(len);
    const slice = raw[0..span_len];

    var stack: [64]u8 = undefined;
    var heap_buf: ?[*]u8 = null;
    defer if (heap_buf) |buf| c.free(buf);

    const buf: [*]u8 = if (slice.len + 1 <= stack.len) &stack else blk: {
        const allocated = allocBytes(slice.len + 1) orelse return 0.0;
        heap_buf = allocated;
        break :blk allocated;
    };
    @memcpy(buf[0..slice.len], slice);
    buf[slice.len] = 0;

    var end_ptr: ?[*:0]u8 = null;
    const parsed = strtod(@ptrCast(buf), &end_ptr);
    const end = end_ptr orelse return 0.0;
    return if (@intFromPtr(end) == @intFromPtr(buf)) 0.0 else parsed;
}

pub export fn nurl_csv_fast_float_range(ptr: ?[*]const u8, len: c_longlong) f64 {
    const raw = ptr orelse return 0.0;
    if (len <= 0) return 0.0;
    return parseFloatRangeFast(raw[0..@intCast(len)]);
}

pub export fn nurl_has_byte(ptr: ?[*]const u8, len: c_longlong, target: c_longlong) c_longlong {
    const raw = ptr orelse return 0;
    if (len <= 0) return 0;
    const byte = asciiByte(target) orelse return 0;
    return if (std.mem.indexOfScalar(u8, raw[0..@intCast(len)], byte) != null) 1 else 0;
}

pub export fn nurl_count_byte(ptr: ?[*]const u8, len: c_longlong, target: c_longlong) c_longlong {
    const raw = ptr orelse return 0;
    if (len <= 0) return 0;
    const byte = asciiByte(target) orelse return 0;
    var count: c_longlong = 0;
    var cursor: usize = 0;
    const slice = raw[0..@intCast(len)];
    while (cursor < slice.len) {
        const found = std.mem.indexOfScalarPos(u8, slice, cursor, byte) orelse break;
        count += 1;
        cursor = found + 1;
    }
    return count;
}

pub export fn nurl_csv_scan_cell(ptr: ?[*]const u8, len: c_longlong, delim: c_longlong) c_longlong {
    const raw = ptr orelse return 0;
    if (len <= 0) return 0;
    const d = asciiByte(delim) orelse return len;
    const slice = raw[0..@intCast(len)];
    for (slice, 0..) |ch, idx| {
        if (ch == d or ch == '\n' or ch == '\r') return @intCast(idx);
    }
    return len;
}

pub export fn nurl_csv_row_n_cells_out() c_longlong {
    return g_csv_row_n_cells;
}

pub export fn nurl_csv_row_next_pos_out() c_longlong {
    return g_csv_row_next_pos;
}

pub export fn nurl_csv_scan_row_pairs(
    content: ?[*]const u8,
    clen: c_longlong,
    pos: c_longlong,
    delim: c_longlong,
    out_pairs: ?[*]c_longlong,
    out_pair_cap: c_longlong,
) c_longlong {
    g_csv_row_n_cells = 0;
    g_csv_row_next_pos = pos;

    const raw = content orelse return 0;
    if (pos >= clen) return 0;
    if (clen < 0 or pos < 0 or out_pair_cap < 0) return -1;
    const pairs = out_pairs orelse return -1;

    const d = asciiByte(delim) orelse return -1;
    const slice = raw[0..@intCast(clen)];
    var p: usize = @intCast(pos);
    var field_start = p;
    var n: c_longlong = 0;
    var row_done = false;

    while (!row_done) {
        while (p < slice.len) : (p += 1) {
            const ch = slice[p];
            if (ch == d or ch == '\n' or ch == '\r') break;
        }

        if (n >= out_pair_cap) return -1;
        const base: usize = @intCast(n * 2);
        pairs[base] = @intCast(field_start);
        pairs[base + 1] = @intCast(p - field_start);
        n += 1;

        if (p >= slice.len) {
            row_done = true;
            break;
        }

        const ch = slice[p];
        if (ch == d) {
            p += 1;
            field_start = p;
            continue;
        }

        p += 1;
        if (ch == '\r' and p < slice.len and slice[p] == '\n') p += 1;
        row_done = true;
    }

    g_csv_row_n_cells = n;
    g_csv_row_next_pos = @intCast(p);
    return 0;
}

pub export fn nurl_memmem_range(
    hay_ptr: ?[*]const u8,
    hay_len: c_longlong,
    needle_ptr: ?[*]const u8,
    needle_len: c_longlong,
) c_longlong {
    const hay = hay_ptr orelse return -1;
    const needle = needle_ptr orelse return -1;
    if (hay_len < 0 or needle_len < 0) return -1;
    const hay_slice = hay[0..@intCast(hay_len)];
    const needle_slice = needle[0..@intCast(needle_len)];
    const idx = std.mem.indexOf(u8, hay_slice, needle_slice) orelse return -1;
    return @intCast(idx);
}

pub export fn nurl_memcmp_lex(
    a_ptr: ?[*]const u8,
    a_len: c_longlong,
    b_ptr: ?[*]const u8,
    b_len: c_longlong,
) c_longlong {
    const a = a_ptr orelse return if (b_len <= 0) 0 else -1;
    const b = b_ptr orelse return if (a_len <= 0) 0 else 1;
    if (a_len < 0 or b_len < 0) return 0;
    return switch (std.mem.order(u8, a[0..@intCast(a_len)], b[0..@intCast(b_len)])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub export fn nurl_is_alpha(value: c_longlong) c_longlong {
    const byte = asciiByte(value) orelse return 0;
    return if (std.ascii.isAlphabetic(byte)) 1 else 0;
}

pub export fn nurl_is_digit(value: c_longlong) c_longlong {
    const byte = asciiByte(value) orelse return 0;
    return if (std.ascii.isDigit(byte)) 1 else 0;
}

pub export fn nurl_is_space(value: c_longlong) c_longlong {
    const byte = asciiByte(value) orelse return 0;
    return if (std.ascii.isWhitespace(byte)) 1 else 0;
}

pub export fn nurl_is_alnum_(value: c_longlong) c_longlong {
    const byte = asciiByte(value) orelse return 0;
    return if (std.ascii.isAlphanumeric(byte) or byte == '_') 1 else 0;
}

pub export fn nurl_sqrt(x: f64) f64 {
    return sqrt(x);
}

pub export fn nurl_fabs(x: f64) f64 {
    return fabs(x);
}

pub export fn nurl_floor(x: f64) f64 {
    return floor(x);
}

pub export fn nurl_ceil(x: f64) f64 {
    return ceil(x);
}

pub export fn nurl_round(x: f64) f64 {
    return round(x);
}

pub export fn nurl_pow(x: f64, y: f64) f64 {
    return pow(x, y);
}

pub export fn nurl_log(x: f64) f64 {
    return log(x);
}

pub export fn nurl_exp(x: f64) f64 {
    return exp(x);
}

pub export fn nurl_sin(x: f64) f64 {
    return sin(x);
}

pub export fn nurl_cos(x: f64) f64 {
    return cos(x);
}

pub export fn nurl_tan(x: f64) f64 {
    return tan(x);
}

pub export fn nurl_atan2(y: f64, x: f64) f64 {
    return atan2(y, x);
}

pub export fn nurl_is_nan(x: f64) c_longlong {
    return if (std.math.isNan(x)) 1 else 0;
}

pub export fn nurl_is_inf(x: f64) c_longlong {
    return if (std.math.isInf(x)) 1 else 0;
}

pub export fn nurl_iabs(value: c_longlong) c_longlong {
    if (value == std.math.minInt(c_longlong)) return std.math.minInt(c_longlong);
    return if (value < 0) -value else value;
}

pub export fn nurl_ipow(x: c_longlong, y: c_longlong) c_longlong {
    if (y < 0) return 0;
    var result: c_longlong = 1;
    var base = x;
    var exp_left = y;
    while (exp_left > 0) {
        if ((exp_left & 1) != 0) result *= base;
        exp_left >>= 1;
        if (exp_left != 0) base *= base;
    }
    return result;
}

pub export fn nurl_str_slice(input: ?[*:0]const u8, start: c_longlong, len: c_longlong) ?[*:0]u8 {
    const raw = input orelse return dupSliceZ("");
    const slice = std.mem.span(raw);
    var from: usize = if (start < 0) 0 else @intCast(start);
    if (from > slice.len) from = slice.len;
    var want: usize = if (len < 0) 0 else @intCast(len);
    if (from + want > slice.len) want = slice.len - from;
    return dupSliceZ(slice[from .. from + want]);
}

pub export fn nurl_str_starts(input: ?[*:0]const u8, prefix: ?[*:0]const u8) c_longlong {
    const raw = std.mem.span(input orelse "");
    const prefix_slice = std.mem.span(prefix orelse "");
    return if (std.mem.startsWith(u8, raw, prefix_slice)) 1 else 0;
}

pub export fn nurl_str_find(haystack: ?[*:0]const u8, needle: ?[*:0]const u8) c_longlong {
    const hay = std.mem.span(haystack orelse "");
    const ndl = std.mem.span(needle orelse "");
    const idx = std.mem.indexOf(u8, hay, ndl) orelse return -1;
    return @intCast(idx);
}

pub export fn nurl_str_ends(input: ?[*:0]const u8, suffix: ?[*:0]const u8) c_longlong {
    const raw = std.mem.span(input orelse "");
    const suffix_slice = std.mem.span(suffix orelse "");
    return if (std.mem.endsWith(u8, raw, suffix_slice)) 1 else 0;
}

pub export fn nurl_str_to_float_safe(input: ?[*:0]const u8) c_longlong {
    g_last_parsed_float = 0.0;
    const raw = input orelse return 0;
    var trimmed = raw;
    while (trimmed[0] == ' ' or trimmed[0] == '\t') trimmed += 1;
    if (trimmed[0] == 0) return 0;

    c._errno().* = 0;
    var end_ptr: ?[*:0]u8 = null;
    const parsed = strtod(trimmed, &end_ptr);
    const end = end_ptr orelse return 0;
    if (@intFromPtr(end) == @intFromPtr(trimmed)) return 0;
    if (c._errno().* == @intFromEnum(c.E.RANGE)) return 0;

    var tail = end;
    while (tail[0] == ' ' or tail[0] == '\t') tail += 1;
    if (tail[0] != 0) return 0;

    g_last_parsed_float = parsed;
    return 1;
}

pub export fn nurl_str_float_value() f64 {
    return g_last_parsed_float;
}

pub export fn nurl_now_ms() c_longlong {
    if (builtin.os.tag == .windows) {
        const ticks_100ns: u64 = @intCast(windows.ntdll.RtlGetSystemTimePrecise());
        const unix_ticks = ticks_100ns - 116444736000000000;
        return @intCast(unix_ticks / 10000);
    }

    var ts: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK.REALTIME, &ts) != 0) return 0;
    return @as(c_longlong, @intCast(ts.sec)) * 1000 + @divTrunc(@as(c_longlong, @intCast(ts.nsec)), 1_000_000);
}

pub export fn nurl_now_seconds() c_longlong {
    if (builtin.os.tag == .windows) return @divTrunc(nurl_now_ms(), 1000);

    var ts: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK.REALTIME, &ts) != 0) return 0;
    return @intCast(ts.sec);
}

pub export fn nurl_monotonic_ns() c_longlong {
    if (builtin.os.tag == .windows) {
        var freq: windows.LARGE_INTEGER = undefined;
        var ctr: windows.LARGE_INTEGER = undefined;
        if (!windows.ntdll.RtlQueryPerformanceFrequency(&freq).toBool()) return 0;
        if (!windows.ntdll.RtlQueryPerformanceCounter(&ctr).toBool()) return 0;

        const sec = @divTrunc(ctr, freq);
        const rem = @mod(ctr, freq);
        const ns_part = @divTrunc(rem * 1_000_000_000, freq);
        return sec * 1_000_000_000 + ns_part;
    }

    var ts: c.timespec = undefined;
    const clock_id = if (builtin.os.tag == .linux or builtin.os.tag == .emscripten or builtin.os.tag == .wasi or
        builtin.os.tag == .driverkit or builtin.os.tag == .ios or builtin.os.tag == .maccatalyst or
        builtin.os.tag == .macos or builtin.os.tag == .tvos or builtin.os.tag == .visionos or
        builtin.os.tag == .watchos or builtin.os.tag == .freebsd or builtin.os.tag == .openbsd or
        builtin.os.tag == .netbsd or builtin.os.tag == .dragonfly or builtin.os.tag == .solaris or
        builtin.os.tag == .illumos or builtin.os.tag == .haiku)
        c.CLOCK.MONOTONIC
    else
        c.CLOCK.REALTIME;
    if (c.clock_gettime(clock_id, &ts) != 0) return 0;
    return @as(c_longlong, @intCast(ts.sec)) * 1_000_000_000 + @as(c_longlong, @intCast(ts.nsec));
}

pub export fn nurl_sleep_ms(ms: c_longlong) void {
    if (ms <= 0) return;
    if (builtin.os.tag == .windows) {
        Sleep(@intCast(ms));
        return;
    }

    var req = c.timespec{
        .sec = @intCast(@divTrunc(ms, 1000)),
        .nsec = @intCast(@mod(ms, 1000) * 1_000_000),
    };
    while (c.nanosleep(&req, &req) != 0 and c._errno().* == @intFromEnum(c.E.INTR)) {}
}
