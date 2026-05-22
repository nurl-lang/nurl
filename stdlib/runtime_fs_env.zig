const std = @import("std");
const builtin = @import("builtin");
const cjmp = @cImport({
    @cInclude("setjmp.h");
});
const runtime_features = @import("runtime_features_generated.zig");
const runtime_crypto_threads = @import("runtime_crypto_threads.zig");
const runtime_compiler_support = @import("runtime_compiler_support.zig");
const runtime_http = @import("runtime_http.zig");
const runtime_process = @import("runtime_process.zig");
const runtime_sqlite_compress = @import("runtime_sqlite_compress.zig");
const runtime_string_csv = @import("runtime_string_csv.zig");
const runtime_tcp_tls = @import("runtime_tcp_tls.zig");
comptime {
    _ = runtime_compiler_support;
    _ = runtime_crypto_threads;
    _ = runtime_http;
    _ = runtime_process;
    _ = runtime_sqlite_compress;
    _ = runtime_string_csv;
    _ = runtime_tcp_tls;
}

const c = std.c;
const windows = std.os.windows;

const RuntimeStat = if (builtin.os.tag == .windows) extern struct {
    dev: c_uint,
    ino: c_ushort,
    mode: c_ushort,
    nlink: c_short,
    uid: c_short,
    gid: c_short,
    rdev: c_uint,
    atime: c_longlong,
    mtime: c_longlong,
    ctime: c_longlong,
    size: c_longlong,
} else c.Stat;

extern "c" fn remove(path: [*:0]const u8) c_int;
extern "c" fn stat(path: [*:0]const u8, buf: *RuntimeStat) c_int;
extern "c" fn fseek(stream: *c.FILE, offset: c_long, whence: c_int) c_int;
extern "c" fn ftell(stream: *c.FILE) c_long;
extern "c" fn fputs(s: [*:0]const u8, stream: *c.FILE) c_int;
extern "c" fn fputc(ch: c_int, stream: *c.FILE) c_int;
extern "c" fn fflush(stream: *c.FILE) c_int;
extern "c" fn scanf(format: [*:0]const u8, ...) c_int;
extern "c" fn fgetc(stream: *c.FILE) c_int;
extern "c" fn feof(stream: *c.FILE) c_int;
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
    extern "c" fn @"stat$INODE64"(path: [*:0]const u8, buf: *RuntimeStat) c_int;
    extern "c" fn @"fstat$INODE64"(fd: c.fd_t, buf: *RuntimeStat) c_int;
    extern "c" var __stdinp: *c.FILE;
    extern "c" var __stdoutp: *c.FILE;
    extern "c" var __stderrp: *c.FILE;
} else struct {};

const generic_stdio = if (builtin.os.tag == .driverkit or
    builtin.os.tag == .ios or
    builtin.os.tag == .maccatalyst or
    builtin.os.tag == .macos or
    builtin.os.tag == .tvos or
    builtin.os.tag == .visionos or
    builtin.os.tag == .watchos) struct {} else struct {
    extern "c" var stdin: *c.FILE;
    extern "c" var stdout: *c.FILE;
    extern "c" var stderr: *c.FILE;
};

const posix = if (builtin.os.tag == .windows) struct {} else struct {
    extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    extern "c" fn close(fd: c.fd_t) c_int;
    extern "c" fn fstat(fd: c.fd_t, buf: *RuntimeStat) c_int;
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
    extern "kernel32" fn CreateSymbolicLinkA(lpSymlinkFileName: [*:0]const u8, lpTargetFileName: [*:0]const u8, dwFlags: windows.DWORD) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn GetFileAttributesA(lpFileName: [*:0]const u8) callconv(.winapi) windows.DWORD;

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

fn statCall(path: [*:0]const u8, buf: *RuntimeStat) c_int {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => switch (builtin.cpu.arch) {
            .x86_64 => darwin.@"stat$INODE64"(path, buf),
            else => stat(path, buf),
        },
        else => stat(path, buf),
    };
}

fn fstatCall(fd: c.fd_t, buf: *RuntimeStat) c_int {
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

fn statSize(st: *const RuntimeStat) c_longlong {
    return @intCast(st.size);
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

fn stdinFile() *c.FILE {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => darwin.__stdinp,
        else => generic_stdio.stdin,
    };
}

fn stdoutFile() *c.FILE {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => darwin.__stdoutp,
        else => generic_stdio.stdout,
    };
}

fn stderrFile() *c.FILE {
    return switch (builtin.os.tag) {
        .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => darwin.__stderrp,
        else => generic_stdio.stderr,
    };
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

const NurlThreadFn = *const fn (?*anyopaque) callconv(.c) void;

const NurlPanicFrame = struct {
    jb: cjmp.jmp_buf,
    msg: ?[*:0]u8,
    prev: ?*NurlPanicFrame,
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

fn fatalRuntime(msg: [*:0]const u8) noreturn {
    _ = fputs(msg, stderrFile());
    std.process.exit(1);
}

fn nurlIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

var g_log_level: c_longlong = 1;
var g_stdin_eof_flag = false;
var g_outbuf: ?[*]u8 = null;
var g_outbuf_len: usize = 0;
var g_outbuf_mode = false;
threadlocal var g_panic_top: ?*NurlPanicFrame = null;
threadlocal var g_panic_last_msg: ?[*:0]u8 = null;

const outbuf_size = 8 * 1024 * 1024;
const c_eof: c_int = -1;

fn outbufInit() void {
    if (g_outbuf != null) return;
    const raw = c.malloc(outbuf_size) orelse return;
    const buf: [*]u8 = @ptrCast(raw);
    buf[0] = 0;
    g_outbuf = buf;
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

pub export fn nurl_print_int(value: c_longlong) void {
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
    const file = stdoutFile();
    _ = c.fwrite(out.ptr, 1, out.len, file);
    _ = fputc('\n', file);
}

pub export fn nurl_print_str(text: ?[*:0]const u8) void {
    const file = stdoutFile();
    _ = fputs(text orelse "", file);
    _ = fputc('\n', file);
}

pub export fn nurl_print_bool(value: c_int) void {
    const file = stdoutFile();
    _ = fputs(if (value != 0) "true" else "false", file);
    _ = fputc('\n', file);
}

pub export fn nurl_read_int() c_longlong {
    var value: c_longlong = 0;
    if (scanf("%lld", &value) != 1) return 0;
    return value;
}

pub export fn nurl_read_line() ?[*:0]u8 {
    var cap: usize = 128;
    var raw = c.malloc(cap) orelse return dupSliceZ("");
    var buf: [*]u8 = @ptrCast(raw);
    var len: usize = 0;
    var got_any = false;
    const file = stdinFile();
    while (true) {
        const ch = fgetc(file);
        if (ch == c_eof) break;
        got_any = true;
        if (ch == '\n') break;
        if (len + 2 > cap) {
            cap *= 2;
            raw = c.realloc(raw, cap) orelse {
                c.free(buf);
                return dupSliceZ("");
            };
            buf = @ptrCast(raw);
        }
        buf[len] = @intCast(ch);
        len += 1;
    }
    if (!got_any and feof(file) != 0) {
        g_stdin_eof_flag = true;
        c.free(buf);
        return dupSliceZ("");
    }
    buf[len] = 0;
    return @ptrCast(buf);
}

pub export fn nurl_stdin_eof() c_longlong {
    return if (g_stdin_eof_flag) 1 else 0;
}

pub export fn nurl_flush_stdout() void {
    _ = fflush(stdoutFile());
}

pub export fn nurl_flush_stderr() void {
    _ = fflush(stderrFile());
}

pub export fn nurl_read_n_bytes(n: c_longlong) ?[*:0]u8 {
    g_last_bytes_len = 0;
    if (n <= 0) return dupSliceZ("");
    const size: usize = @intCast(n);
    const raw = c.malloc(size + 1) orelse return dupSliceZ("");
    const buf: [*]u8 = @ptrCast(raw);
    const file = stdinFile();
    const got = c.fread(buf, 1, size, file);
    if (got == 0 and feof(file) != 0) g_stdin_eof_flag = true;
    buf[got] = 0;
    g_last_bytes_len = @intCast(got);
    return @ptrCast(buf);
}

pub export fn nurl_print_buf_start() void {
    outbufInit();
    g_outbuf_mode = true;
}

pub export fn nurl_print_buf_stop() ?[*:0]u8 {
    g_outbuf_mode = false;
    return dupSliceZ(if (g_outbuf) |buf| std.mem.span(@as([*:0]u8, @ptrCast(buf))) else "");
}

pub export fn nurl_print_buf_reset() void {
    outbufInit();
    g_outbuf_len = 0;
    if (g_outbuf) |buf| buf[0] = 0;
}

pub export fn nurl_print(text: ?[*:0]const u8) void {
    const slice = std.mem.span(text orelse "");
    if (g_outbuf_mode) {
        outbufInit();
        if (g_outbuf) |buf| {
            if (g_outbuf_len + slice.len + 1 < outbuf_size) {
                @memcpy(buf[g_outbuf_len .. g_outbuf_len + slice.len], slice);
                g_outbuf_len += slice.len;
                buf[g_outbuf_len] = 0;
            }
        }
        return;
    }
    const file = stdoutFile();
    _ = fputs(text orelse "", file);
    _ = fflush(file);
}

pub export fn nurl_eprint(text: ?[*:0]const u8) void {
    const file = stderrFile();
    _ = fputs(text orelse "", file);
    _ = fflush(file);
}

pub export fn nurl_eprintln(text: ?[*:0]const u8) void {
    const file = stderrFile();
    _ = fputs(text orelse "", file);
    _ = fputc('\n', file);
    _ = fflush(file);
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
    var st: RuntimeStat = undefined;
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
    var st: RuntimeStat = undefined;
    if (statCall(file_path, &st) == 0) return statSize(&st);
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

    var st: RuntimeStat = undefined;
    if (fstatCall(fd, &st) != 0) return null;
    if (statSize(&st) <= 0) return null;

    const size: usize = @intCast(statSize(&st));
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

    var st: RuntimeStat = undefined;
    if (fstatCall(fd, &st) != 0) return null;
    if (statSize(&st) <= 0) {
        const buf = allocBytes(1) orelse return null;
        buf[0] = 0;
        return @ptrCast(buf);
    }

    const size: usize = @intCast(statSize(&st));
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

fn windowsSymlinkImpl(target: ?[*:0]const u8, linkpath: ?[*:0]const u8) callconv(.c) c_int {
    const target_path = target orelse {
        setErrno(.INVAL);
        return -1;
    };
    const link_path = linkpath orelse {
        setErrno(.INVAL);
        return -1;
    };

    const symbolic_link_flag_directory: windows.DWORD = 0x1;
    const symbolic_link_flag_allow_unprivileged_create: windows.DWORD = 0x2;
    const invalid_file_attributes: windows.DWORD = 0xffff_ffff;
    const file_attribute_directory: windows.DWORD = 0x10;

    var flags: windows.DWORD = symbolic_link_flag_allow_unprivileged_create;
    const attrs = win.GetFileAttributesA(target_path);
    if (attrs != invalid_file_attributes and (attrs & file_attribute_directory) != 0) {
        flags |= symbolic_link_flag_directory;
    }

    if (win.CreateSymbolicLinkA(link_path, target_path, flags) != .FALSE) return 0;

    const last = windows.GetLastError();
    switch (last) {
        .ALREADY_EXISTS => setErrno(.EXIST),
        .ACCESS_DENIED, .PRIVILEGE_NOT_HELD => setErrno(.ACCES),
        .PATH_NOT_FOUND, .FILE_NOT_FOUND => setErrno(.NOENT),
        else => setErrno(.IO),
    }
    return -1;
}

comptime {
    if (builtin.os.tag == .windows) {
        @export(&windowsSymlinkImpl, .{ .name = "symlink" });
    }
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

pub export fn nurl_recover(fn_ptr: ?*anyopaque, env_ptr: ?*anyopaque) c_longlong {
    if (fn_ptr == null) return 0;
    if (builtin.os.tag == .wasi) {
        const closure: NurlThreadFn = @ptrFromInt(@intFromPtr(fn_ptr.?));
        closure(env_ptr);
        return 0;
    }

    var frame = NurlPanicFrame{
        .jb = undefined,
        .msg = null,
        .prev = g_panic_top,
    };
    g_panic_top = &frame;

    if (cjmp.setjmp(&frame.jb) == 0) {
        const closure: NurlThreadFn = @ptrFromInt(@intFromPtr(fn_ptr.?));
        closure(env_ptr);
        g_panic_top = frame.prev;
        return 0;
    }

    g_panic_top = frame.prev;
    if (g_panic_last_msg) |prev| c.free(prev);
    g_panic_last_msg = frame.msg orelse dupSliceZ("(no panic message)");
    return 1;
}

pub export fn nurl_panic_last_msg() ?[*:0]const u8 {
    return g_panic_last_msg orelse "";
}

pub export fn nurl_panic(msg: ?[*:0]const u8) void {
    const text = msg orelse "(no message)";
    if (builtin.os.tag == .wasi or g_panic_top == null) {
        _ = fputs("nurl panic: ", stderrFile());
        _ = fputs(text, stderrFile());
        _ = fputc('\n', stderrFile());
        _ = fflush(stderrFile());
        c.abort();
    }

    g_panic_top.?.msg = dupZ(text);
    cjmp.longjmp(&g_panic_top.?.jb, 1);
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
