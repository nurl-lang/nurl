const std = @import("std");
const builtin = @import("builtin");
const cjmp = @cImport({
    @cInclude("setjmp.h");
});
const runtime_features = @import("runtime_features_generated.zig");
const zlib = if (runtime_features.have_zlib) @cImport({
    @cInclude("zlib.h");
}) else struct {};
const sqlite = if (runtime_features.have_sqlite3) @cImport({
    @cInclude("sqlite3.h");
}) else struct {};
const curl = if (runtime_features.have_libcurl and builtin.os.tag != .windows and builtin.os.tag != .wasi) @cImport({
    @cInclude("curl/curl.h");
}) else struct {};

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
extern "c" fn execvp(file: [*:0]const u8, argv: [*c]?[*:0]const u8) c_int;
extern "c" fn signal(sig: c_int, handler: usize) usize;
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

const max_syms = 1_000_000;
const max_symtabs = 16;

const NurlSymEntry = struct {
    depth: c_int,
    name: [*:0]u8,
    ty: [*:0]u8,
};

const NurlSymTab = struct {
    entries: ?[*]NurlSymEntry,
    count: usize,
    cap: usize,
    depth: c_int,
};

const max_lex = 1024;

const ltt_eof: c_int = 0;
const ltt_ident: c_int = 1;
const ltt_int: c_int = 2;
const ltt_str: c_int = 3;
const ltt_bool: c_int = 4;
const ltt_type_kw: c_int = 5;
const ltt_at: c_int = 6;
const ltt_colon: c_int = 7;
const ltt_eq: c_int = 8;
const ltt_arrow: c_int = 9;
const ltt_caret: c_int = 10;
const ltt_quest: c_int = 11;
const ltt_tilde: c_int = 12;
const ltt_lparen: c_int = 13;
const ltt_rparen: c_int = 14;
const ltt_lbrace: c_int = 15;
const ltt_rbrace: c_int = 16;
const ltt_dot: c_int = 17;
const ltt_hash: c_int = 18;
const ltt_bang: c_int = 19;
const ltt_plus: c_int = 20;
const ltt_minus: c_int = 21;
const ltt_star: c_int = 22;
const ltt_slash: c_int = 23;
const ltt_percent: c_int = 24;
const ltt_amp: c_int = 25;
const ltt_pipe: c_int = 26;
const ltt_lt: c_int = 27;
const ltt_gt: c_int = 28;
const ltt_eqeq: c_int = 29;
const ltt_ne: c_int = 30;
const ltt_le: c_int = 31;
const ltt_ge: c_int = 32;
const ltt_lbrack: c_int = 33;
const ltt_rbrack: c_int = 34;
const ltt_float: c_int = 35;
const ltt_sizeof: c_int = 36;
const ltt_semicol: c_int = 37;
const ltt_backslash: c_int = 38;
const ltt_dollar: c_int = 39;
const ltt_questquest: c_int = 40;
const ltt_shl: c_int = 41;
const ltt_shr: c_int = 42;
const ltt_ellipsis: c_int = 43;
const ltt_pub: c_int = 44;
const ltt_caretcaret: c_int = 45;

const NurlToken = struct {
    type: c_int,
    val: ?[*:0]u8,
    inum: c_longlong,
    fnum: f64,
    line: c_longlong,
    start_pos: c_int,
};

const NurlLex = struct {
    src: [*:0]u8,
    filename: [*:0]u8,
    pos: c_int,
    len: c_int,
    line: c_longlong,
    cur: NurlToken,
    peek: NurlToken,
    peek_valid: bool,
    peek2: NurlToken,
    peek2_valid: bool,
    peek3: NurlToken,
    peek3_valid: bool,
    peek4: NurlToken,
    peek4_valid: bool,
};

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

const NurlPanicFrame = struct {
    jb: cjmp.jmp_buf,
    msg: ?[*:0]u8,
    prev: ?*NurlPanicFrame,
};

const NurlSqliteDb = struct {
    db: ?*sqlite.sqlite3,
    err_kind: c_longlong,
    errmsg: ?[*:0]u8,
};

const NurlSqliteStmt = struct {
    stmt: ?*sqlite.sqlite3_stmt,
    err_kind: c_longlong,
    text_buf: ?[*:0]u8,
    bound_texts: ?[*]?[*:0]u8,
    bound_text_count: usize,
    bound_text_cap: usize,
};

const NurlHttpHeader = extern struct {
    name: ?[*:0]u8,
    value: ?[*:0]u8,
};

const NurlHttpResponse = extern struct {
    status: c_longlong,
    err_kind: c_longlong,
    header_count: c_longlong,
    headers: ?[*]NurlHttpHeader,
    body: ?[*:0]u8,
    body_len: c_longlong,
};

const NurlHttpBuf = struct {
    data: ?[*:0]u8,
    len: usize,
    cap: usize,
};

const NurlHttpHeaderBuf = struct {
    items: ?[*]NurlHttpHeader,
    len: usize,
    cap: usize,
};

const NurlHttpStream = if (runtime_features.have_libcurl and builtin.os.tag != .windows and builtin.os.tag != .wasi) struct {
    multi: ?*curl.CURLM,
    easy: ?*curl.CURL,
    req_headers: ?*curl.struct_curl_slist,
    body_buf: NurlHttpBuf,
    hdr_buf: NurlHttpHeaderBuf,
    headers_done: c_int,
    still_running: c_int,
    finished: c_int,
    status: c_longlong,
    err_kind: c_longlong,
} else struct {
    _dummy: u8 = 0,
};

const NurlProcResult = extern struct {
    exit_code: c_longlong,
    err_kind: c_longlong,
    stdout_buf: ?[*:0]u8,
    stdout_len: c_longlong,
    stderr_buf: ?[*:0]u8,
    stderr_len: c_longlong,
};

const NurlProcBuf = struct {
    data: ?[*]u8 = null,
    len: usize = 0,
    cap: usize = 0,
};

const NurlProcChild = extern struct {
    err_kind: c_longlong,
    last_io_err: c_longlong,
    exit_code: c_longlong,
    eof: c_int,
    waited: c_int,
    pid_or_0: c_longlong,
    pid: c.pid_t,
    fd_in: c.fd_t,
    fd_out: c.fd_t,
    scratch: ?[*]u8,
    scratch_len: usize,
    scratch_cap: usize,
    line_buf: ?[*]u8,
    line_len: usize,
    line_cap: usize,
};

const NurlTcpPrefix = extern struct {
    fd: c.fd_t,
    err_kind: c_longlong,
    kind: c_int,
    peer: ?[*:0]u8,
};

const max_cgs = 8;

const NurlCG = struct {
    reg: c_int,
    lbl: c_int,
};

const nurl_proc_err_ok: c_longlong = 0;
const nurl_proc_err_notfound: c_longlong = 1;
const nurl_proc_err_exec_failed: c_longlong = 2;
const nurl_proc_err_io: c_longlong = 3;
const nurl_proc_err_other: c_longlong = 4;
const nurl_net_err_other: c_longlong = 8;
const nurl_invalid_sock: c.fd_t = -1;
const nurl_gzip_err_unsupported: c_int = -98;
const nurl_sqlite_err_ok: c_longlong = 0;
const nurl_sqlite_err_row: c_longlong = 100;
const nurl_sqlite_err_done: c_longlong = 101;
const nurl_sqlite_err_unsupported: c_longlong = 99;
const nurl_http_err_ok: c_longlong = 0;
const nurl_http_err_connect: c_longlong = 1;
const nurl_http_err_timeout: c_longlong = 2;
const nurl_http_err_tls: c_longlong = 3;
const nurl_http_err_dns: c_longlong = 4;
const nurl_http_err_invalid: c_longlong = 5;
const nurl_http_err_other: c_longlong = 6;

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

fn getSymTab(handle: c_longlong) *NurlSymTab {
    const idx: c_int = @intCast(handle - 1);
    if (idx < 0 or idx >= g_symtab_count or g_symtabs[@intCast(idx)] == null) {
        fatalRuntime("nurlc: invalid symtab handle\n");
    }
    return g_symtabs[@intCast(idx)].?;
}

fn ensureSymCap(tab: *NurlSymTab, need: usize) void {
    if (need <= tab.cap) return;
    var new_cap = if (tab.cap == 0) @as(usize, 16) else tab.cap;
    while (new_cap < need) : (new_cap *= 2) {}
    if (new_cap > max_syms) new_cap = max_syms;
    if (new_cap < need) fatalRuntime("nurlc: symbol table full\n");

    const new_bytes = new_cap * @sizeOf(NurlSymEntry);
    const raw = c.realloc(tab.entries, new_bytes) orelse fatalRuntime("nurlc: symbol table full\n");
    tab.entries = @ptrCast(@alignCast(raw));
    tab.cap = new_cap;
}

fn emptyToken() NurlToken {
    return .{
        .type = ltt_eof,
        .val = null,
        .inum = 0,
        .fnum = 0.0,
        .line = 0,
        .start_pos = 0,
    };
}

fn freeToken(tok: *NurlToken) void {
    if (tok.val) |val| c.free(val);
    tok.* = emptyToken();
}

fn floatToIntLossy(value: f64) c_longlong {
    const max_i: f64 = @floatFromInt(std.math.maxInt(c_longlong));
    const min_i: f64 = @floatFromInt(std.math.minInt(c_longlong));
    if (value >= max_i) return std.math.maxInt(c_longlong);
    if (value <= min_i) return std.math.minInt(c_longlong);
    return @intFromFloat(value);
}

fn makeTokOwned(tok_type: c_int, owned: [*:0]u8, inum: c_longlong, line: c_longlong, start_pos: c_int) NurlToken {
    return .{
        .type = tok_type,
        .val = owned,
        .inum = inum,
        .fnum = 0.0,
        .line = line,
        .start_pos = start_pos,
    };
}

fn makeTok(tok_type: c_int, val: []const u8, inum: c_longlong, line: c_longlong, start_pos: c_int) NurlToken {
    const owned = dupSliceZ(val) orelse fatalRuntime("nurlc: out of memory\n");
    return makeTokOwned(tok_type, owned, inum, line, start_pos);
}

fn makeFloatTokOwned(owned: [*:0]u8, fnum: f64, line: c_longlong, start_pos: c_int) NurlToken {
    return .{
        .type = ltt_float,
        .val = owned,
        .inum = floatToIntLossy(fnum),
        .fnum = fnum,
        .line = line,
        .start_pos = start_pos,
    };
}

fn readIdent(lx: *NurlLex) [*:0]u8 {
    const src = std.mem.span(lx.src);
    const start: usize = @intCast(lx.pos);
    while (lx.pos < lx.len) {
        const ch = src[@intCast(lx.pos)];
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') break;
        lx.pos += 1;
    }
    return dupSliceZ(src[start..@intCast(lx.pos)]) orelse fatalRuntime("nurlc: out of memory\n");
}

fn skipWsComments(lx: *NurlLex) void {
    const src = std.mem.span(lx.src);
    while (true) {
        while (lx.pos < lx.len) {
            const ch = src[@intCast(lx.pos)];
            if (!std.ascii.isWhitespace(ch)) break;
            if (ch == '\n') lx.line += 1;
            lx.pos += 1;
        }
        if (lx.pos + 1 < lx.len and
            src[@intCast(lx.pos)] == '/' and
            src[@intCast(lx.pos + 1)] == '/')
        {
            while (lx.pos < lx.len and src[@intCast(lx.pos)] != '\n') lx.pos += 1;
            continue;
        }
        break;
    }
}

fn lexNumberToken(lx: *NurlLex, line: c_longlong, start_pos: c_int, negative: bool) NurlToken {
    const src = std.mem.span(lx.src);
    const start: usize = @intCast(start_pos);
    if (negative) lx.pos += 1;
    while (lx.pos < lx.len and std.ascii.isDigit(src[@intCast(lx.pos)])) lx.pos += 1;

    if (lx.pos < lx.len and src[@intCast(lx.pos)] == '.' and
        lx.pos + 1 < lx.len and std.ascii.isDigit(src[@intCast(lx.pos + 1)]))
    {
        lx.pos += 1;
        while (lx.pos < lx.len and std.ascii.isDigit(src[@intCast(lx.pos)])) lx.pos += 1;
        if (lx.pos < lx.len and (src[@intCast(lx.pos)] == 'e' or src[@intCast(lx.pos)] == 'E')) {
            lx.pos += 1;
            if (lx.pos < lx.len and (src[@intCast(lx.pos)] == '+' or src[@intCast(lx.pos)] == '-')) {
                lx.pos += 1;
            }
            while (lx.pos < lx.len and std.ascii.isDigit(src[@intCast(lx.pos)])) lx.pos += 1;
        }
        const slice = src[start..@intCast(lx.pos)];
        const owned = dupSliceZ(slice) orelse fatalRuntime("nurlc: out of memory\n");
        return makeFloatTokOwned(owned, parseFloatRangeFast(slice), line, start_pos);
    }

    const slice = src[start..@intCast(lx.pos)];
    const owned = dupSliceZ(slice) orelse fatalRuntime("nurlc: out of memory\n");
    return makeTokOwned(ltt_int, owned, atoll(owned), line, start_pos);
}

fn lexNextTok(lx: *NurlLex) NurlToken {
    skipWsComments(lx);
    const src = std.mem.span(lx.src);
    const line = lx.line;
    const start_pos = lx.pos;

    if (lx.pos >= lx.len) return makeTok(ltt_eof, "", 0, line, start_pos);

    const ch = src[@intCast(lx.pos)];

    if (ch == 0xE2 and lx.pos + 2 < lx.len and
        src[@intCast(lx.pos + 1)] == 0x86 and
        src[@intCast(lx.pos + 2)] == 0x92)
    {
        lx.pos += 3;
        return makeTok(ltt_arrow, "\xE2\x86\x92", 0, line, start_pos);
    }

    if (ch == '`') {
        lx.pos += 1;
        const raw = c.malloc(@as(usize, @intCast(lx.len)) + 1) orelse fatalRuntime("nurlc: out of memory\n");
        const buf: [*]u8 = @ptrCast(raw);
        var blen: usize = 0;
        while (lx.pos < lx.len and src[@intCast(lx.pos)] != '`') {
            const cur = src[@intCast(lx.pos)];
            if (cur == '\n') lx.line += 1;
            if (cur == '\\' and lx.pos + 1 < lx.len) {
                const next = src[@intCast(lx.pos + 1)];
                switch (next) {
                    'n' => {
                        buf[blen] = '\n';
                        blen += 1;
                        lx.pos += 2;
                        continue;
                    },
                    't' => {
                        buf[blen] = '\t';
                        blen += 1;
                        lx.pos += 2;
                        continue;
                    },
                    'r' => {
                        buf[blen] = '\r';
                        blen += 1;
                        lx.pos += 2;
                        continue;
                    },
                    '\\' => {
                        buf[blen] = '\\';
                        blen += 1;
                        lx.pos += 2;
                        continue;
                    },
                    else => {},
                }
            }
            buf[blen] = cur;
            blen += 1;
            lx.pos += 1;
        }
        buf[blen] = 0;
        if (lx.pos < lx.len) lx.pos += 1;
        const tok = makeTok(ltt_str, buf[0..blen], 0, line, start_pos);
        c.free(buf);
        return tok;
    }

    if (ch == '-' and lx.pos + 1 < lx.len and std.ascii.isDigit(src[@intCast(lx.pos + 1)])) {
        return lexNumberToken(lx, line, start_pos, true);
    }

    if (std.ascii.isDigit(ch)) {
        return lexNumberToken(lx, line, start_pos, false);
    }

    if (std.ascii.isAlphabetic(ch) or ch == '_') {
        var ident = readIdent(lx);
        while (lx.pos + 2 < lx.len and
            src[@intCast(lx.pos)] == ':' and
            src[@intCast(lx.pos + 1)] == ':' and
            (std.ascii.isAlphabetic(src[@intCast(lx.pos + 2)]) or src[@intCast(lx.pos + 2)] == '_'))
        {
            lx.pos += 2;
            const next_ident = readIdent(lx);
            const joined = concatSlices(&.{ std.mem.span(ident), "__", std.mem.span(next_ident) }) orelse fatalRuntime("nurlc: out of memory\n");
            c.free(ident);
            c.free(next_ident);
            ident = joined;
        }

        const ident_slice = std.mem.span(ident);
        if (std.mem.eql(u8, ident_slice, "T")) return makeTokOwned(ltt_bool, ident, 1, line, start_pos);
        if (std.mem.eql(u8, ident_slice, "F")) return makeTokOwned(ltt_bool, ident, 0, line, start_pos);
        if (std.mem.eql(u8, ident_slice, "Z")) return makeTokOwned(ltt_sizeof, ident, 0, line, start_pos);
        if (std.mem.eql(u8, ident_slice, "pub")) return makeTokOwned(ltt_pub, ident, 0, line, start_pos);
        if (ident_slice.len == 1 and std.mem.indexOfScalar(u8, "iufbsv", ident_slice[0]) != null) {
            return makeTokOwned(ltt_type_kw, ident, 0, line, start_pos);
        }
        if (std.mem.eql(u8, ident_slice, "i8") or
            std.mem.eql(u8, ident_slice, "i16") or
            std.mem.eql(u8, ident_slice, "i32") or
            std.mem.eql(u8, ident_slice, "i64") or
            std.mem.eql(u8, ident_slice, "u16") or
            std.mem.eql(u8, ident_slice, "u32") or
            std.mem.eql(u8, ident_slice, "u64") or
            std.mem.eql(u8, ident_slice, "f32"))
        {
            return makeTokOwned(ltt_type_kw, ident, 0, line, start_pos);
        }
        return makeTokOwned(ltt_ident, ident, 0, line, start_pos);
    }

    if (ch == '.' and lx.pos + 2 < lx.len and
        src[@intCast(lx.pos + 1)] == '.' and
        src[@intCast(lx.pos + 2)] == '.')
    {
        lx.pos += 3;
        return makeTok(ltt_ellipsis, "...", 0, line, start_pos);
    }

    if (lx.pos + 1 < lx.len) {
        const ch2 = src[@intCast(lx.pos + 1)];
        if (ch == '=' and ch2 == '=') {
            lx.pos += 2;
            return makeTok(ltt_eqeq, "==", 0, line, start_pos);
        }
        if (ch == '!' and ch2 == '=') {
            lx.pos += 2;
            return makeTok(ltt_ne, "!=", 0, line, start_pos);
        }
        if (ch == '<' and ch2 == '=') {
            lx.pos += 2;
            return makeTok(ltt_le, "<=", 0, line, start_pos);
        }
        if (ch == '>' and ch2 == '=') {
            lx.pos += 2;
            return makeTok(ltt_ge, ">=", 0, line, start_pos);
        }
        if (ch == '<' and ch2 == '<') {
            lx.pos += 2;
            return makeTok(ltt_shl, "<<", 0, line, start_pos);
        }
        if (ch == '>' and ch2 == '>') {
            lx.pos += 2;
            return makeTok(ltt_shr, ">>", 0, line, start_pos);
        }
        if (ch == '?' and ch2 == '?') {
            lx.pos += 2;
            return makeTok(ltt_questquest, "??", 0, line, start_pos);
        }
        if (ch == '^' and ch2 == '^') {
            lx.pos += 2;
            return makeTok(ltt_caretcaret, "^^", 0, line, start_pos);
        }
    }

    lx.pos += 1;
    return switch (ch) {
        '@' => makeTok(ltt_at, "@", 0, line, start_pos),
        ':' => makeTok(ltt_colon, ":", 0, line, start_pos),
        '=' => makeTok(ltt_eq, "=", 0, line, start_pos),
        '^' => makeTok(ltt_caret, "^", 0, line, start_pos),
        '?' => makeTok(ltt_quest, "?", 0, line, start_pos),
        '~' => makeTok(ltt_tilde, "~", 0, line, start_pos),
        '(' => makeTok(ltt_lparen, "(", 0, line, start_pos),
        ')' => makeTok(ltt_rparen, ")", 0, line, start_pos),
        '{' => makeTok(ltt_lbrace, "{", 0, line, start_pos),
        '}' => makeTok(ltt_rbrace, "}", 0, line, start_pos),
        '.' => makeTok(ltt_dot, ".", 0, line, start_pos),
        '#' => makeTok(ltt_hash, "#", 0, line, start_pos),
        '!' => makeTok(ltt_bang, "!", 0, line, start_pos),
        '+' => makeTok(ltt_plus, "+", 0, line, start_pos),
        '-' => makeTok(ltt_minus, "-", 0, line, start_pos),
        '*' => makeTok(ltt_star, "*", 0, line, start_pos),
        '/' => makeTok(ltt_slash, "/", 0, line, start_pos),
        '%' => makeTok(ltt_percent, "%", 0, line, start_pos),
        '&' => makeTok(ltt_amp, "&", 0, line, start_pos),
        '|' => makeTok(ltt_pipe, "|", 0, line, start_pos),
        '<' => makeTok(ltt_lt, "<", 0, line, start_pos),
        '>' => makeTok(ltt_gt, ">", 0, line, start_pos),
        '[' => makeTok(ltt_lbrack, "[", 0, line, start_pos),
        ']' => makeTok(ltt_rbrack, "]", 0, line, start_pos),
        ';' => makeTok(ltt_semicol, ";", 0, line, start_pos),
        '\\' => makeTok(ltt_backslash, "\\", 0, line, start_pos),
        '$' => makeTok(ltt_dollar, "$", 0, line, start_pos),
        else => blk: {
            var buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "?{X:0>2}", .{ch}) catch "?00";
            break :blk makeTok(ltt_ident, text, 0, line, start_pos);
        },
    };
}

fn getLex(handle: c_longlong) *NurlLex {
    const idx: c_int = @intCast(handle - 1);
    if (idx < 0 or idx >= g_lex_count or g_lexers[@intCast(idx)] == null) {
        fatalRuntime("nurlc: invalid lexer handle\n");
    }
    return g_lexers[@intCast(idx)].?;
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

fn csvCellPtr(content: [*]const u8, escape_buf: ?[*]const u8, off: c_longlong) ?[*]const u8 {
    if (off >= 0) return content + @as(usize, @intCast(off));
    const escaped = escape_buf orelse return null;
    return escaped + @as(usize, @intCast(-(off + 1)));
}

fn csvCellContains(hay_ptr: [*]const u8, hay_len: c_longlong, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay_len < 0) return false;
    const hay = hay_ptr[0..@intCast(hay_len)];
    return std.mem.indexOf(u8, hay, needle) != null;
}

fn hexEncodeInto(bytes: []const u8, out: []u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        out[i * 2] = alphabet[byte >> 4];
        out[i * 2 + 1] = alphabet[byte & 0x0f];
    }
    out[bytes.len * 2] = 0;
}

fn nurlIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
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

fn allocProcResult() ?*NurlProcResult {
    const raw = c.calloc(1, @sizeOf(NurlProcResult)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn procEmptyResult(err_kind: c_longlong) c_longlong {
    const result = allocProcResult() orelse return 0;
    result.* = .{
        .exit_code = 0,
        .err_kind = err_kind,
        .stdout_buf = dupSliceZ(""),
        .stdout_len = 0,
        .stderr_buf = dupSliceZ(""),
        .stderr_len = 0,
    };
    return @intCast(@intFromPtr(result));
}

fn procBufAppend(buf: *NurlProcBuf, src: []const u8) bool {
    if (buf.len + src.len + 1 > buf.cap) {
        var new_cap = if (buf.cap == 0) @as(usize, 256) else buf.cap;
        while (new_cap < buf.len + src.len + 1) new_cap *= 2;
        const raw = c.realloc(buf.data, new_cap) orelse return false;
        buf.data = @ptrCast(raw);
        buf.cap = new_cap;
    }
    const data = buf.data orelse return false;
    @memcpy(data[buf.len .. buf.len + src.len], src);
    buf.len += src.len;
    data[buf.len] = 0;
    return true;
}

fn procBufOwnedOrEmpty(buf: *NurlProcBuf) ?[*:0]u8 {
    return if (buf.data) |data| @ptrCast(data) else dupSliceZ("");
}

fn procClosePair(pair: *[2]c.fd_t) void {
    if (pair[0] >= 0) _ = posix.close(pair[0]);
    if (pair[1] >= 0) _ = posix.close(pair[1]);
    pair[0] = -1;
    pair[1] = -1;
}

fn waitStatusExited(status: c_int) bool {
    return (status & 0x7f) == 0;
}

fn waitStatusExitCode(status: c_int) c_longlong {
    return @intCast((status >> 8) & 0xff);
}

fn waitStatusSignaled(status: c_int) bool {
    const term_sig = status & 0x7f;
    return term_sig != 0 and term_sig != 0x7f;
}

fn waitStatusTermSig(status: c_int) c_longlong {
    return @intCast(status & 0x7f);
}

fn allocProcChild() ?*NurlProcChild {
    const raw = c.calloc(1, @sizeOf(NurlProcChild)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn procChildEmpty(err_kind: c_longlong) c_longlong {
    const child = allocProcChild() orelse return 0;
    child.* = .{
        .err_kind = err_kind,
        .last_io_err = 0,
        .exit_code = -1,
        .eof = 0,
        .waited = 0,
        .pid_or_0 = 0,
        .pid = 0,
        .fd_in = -1,
        .fd_out = -1,
        .scratch = null,
        .scratch_len = 0,
        .scratch_cap = 0,
        .line_buf = null,
        .line_len = 0,
        .line_cap = 0,
    };
    return @intCast(@intFromPtr(child));
}

fn procChildScratchReserve(child: *NurlProcChild, want: usize) bool {
    if (child.scratch_cap >= want) return true;
    var new_cap = if (child.scratch_cap == 0) @as(usize, 1024) else child.scratch_cap;
    while (new_cap < want) new_cap *= 2;
    const raw = c.realloc(child.scratch, new_cap) orelse return false;
    child.scratch = @ptrCast(raw);
    child.scratch_cap = new_cap;
    return true;
}

fn procChildLineReserve(child: *NurlProcChild, want: usize) bool {
    if (child.line_cap >= want + 1) return true;
    var new_cap = if (child.line_cap == 0) @as(usize, 256) else child.line_cap;
    while (new_cap < want + 1) new_cap *= 2;
    const raw = c.realloc(child.line_buf, new_cap) orelse return false;
    child.line_buf = @ptrCast(raw);
    child.line_cap = new_cap;
    return true;
}

fn procChildDrainLine(child: *NurlProcChild) bool {
    const scratch = child.scratch orelse return false;
    var i: usize = 0;
    while (i < child.scratch_len) : (i += 1) {
        if (scratch[i] != '\n') continue;
        var take = i;
        if (take > 0 and scratch[take - 1] == '\r') take -= 1;
        if (!procChildLineReserve(child, take)) return false;
        const line_buf = child.line_buf orelse return false;
        @memcpy(line_buf[0..take], scratch[0..take]);
        line_buf[take] = 0;
        child.line_len = take;
        const consume = i + 1;
        const rem = child.scratch_len - consume;
        if (rem != 0) {
            std.mem.copyForwards(u8, scratch[0..rem], scratch[consume .. consume + rem]);
        }
        child.scratch_len = rem;
        return true;
    }
    return false;
}

fn procChildHandle(handle: c_longlong) ?*NurlProcChild {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn tcpPrefixHandle(handle: c_longlong) ?*NurlTcpPrefix {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn sqliteDbHandle(handle: c_longlong) ?*NurlSqliteDb {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn sqliteStmtHandle(handle: c_longlong) ?*NurlSqliteStmt {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn sqliteSetErrmsg(db: *NurlSqliteDb) void {
    if (!runtime_features.have_sqlite3) return;
    if (db.errmsg) |prev| c.free(prev);
    const msg = if (db.db) |raw| sqlite.sqlite3_errmsg(raw) else null;
    db.errmsg = if (msg) |text| dupZ(text) else null;
}

fn sqliteFreeBoundTexts(stmt: *NurlSqliteStmt) void {
    if (stmt.bound_texts) |items| {
        var i: usize = 0;
        while (i < stmt.bound_text_count) : (i += 1) {
            if (items[i]) |text| c.free(text);
        }
        c.free(@ptrCast(items));
    }
    stmt.bound_texts = null;
    stmt.bound_text_count = 0;
    stmt.bound_text_cap = 0;
}

fn sqliteRememberBoundText(stmt: *NurlSqliteStmt, text: [*:0]u8) bool {
    if (stmt.bound_text_count == stmt.bound_text_cap) {
        const new_cap: usize = if (stmt.bound_text_cap == 0) 4 else stmt.bound_text_cap * 2;
        const bytes = new_cap * @sizeOf(?[*:0]u8);
        const resized = if (stmt.bound_texts) |existing|
            c.realloc(@ptrCast(existing), bytes)
        else
            c.malloc(bytes);
        if (resized == null) return false;
        stmt.bound_texts = @ptrCast(@alignCast(resized));
        stmt.bound_text_cap = new_cap;
    }
    stmt.bound_texts.?[stmt.bound_text_count] = text;
    stmt.bound_text_count += 1;
    return true;
}

fn httpBufAppend(buf: *NurlHttpBuf, src: [*]const u8, n: usize) bool {
    if (buf.len + n + 1 > buf.cap) {
        var new_cap: usize = if (buf.cap != 0) buf.cap else 256;
        while (new_cap < buf.len + n + 1) new_cap *= 2;
        const resized = if (buf.data) |existing|
            c.realloc(existing, new_cap)
        else
            c.malloc(new_cap);
        if (resized == null) return false;
        buf.data = @ptrCast(@alignCast(resized));
        buf.cap = new_cap;
    }
    const data = buf.data.?;
    @memcpy(data[buf.len .. buf.len + n], src[0..n]);
    buf.len += n;
    data[buf.len] = 0;
    return true;
}

fn httpMapErr(rc: curl.CURLcode) c_longlong {
    if (!runtime_features.have_libcurl or builtin.os.tag == .windows or builtin.os.tag == .wasi) return nurl_http_err_other;
    return switch (rc) {
        curl.CURLE_OK => nurl_http_err_ok,
        curl.CURLE_COULDNT_RESOLVE_HOST => nurl_http_err_dns,
        curl.CURLE_COULDNT_CONNECT => nurl_http_err_connect,
        curl.CURLE_OPERATION_TIMEDOUT => nurl_http_err_timeout,
        curl.CURLE_SSL_CONNECT_ERROR, curl.CURLE_PEER_FAILED_VERIFICATION => nurl_http_err_tls,
        curl.CURLE_URL_MALFORMAT, curl.CURLE_UNSUPPORTED_PROTOCOL => nurl_http_err_invalid,
        else => nurl_http_err_other,
    };
}

fn httpHeaderPush(hdrs: *NurlHttpHeaderBuf, name: [*:0]u8, value: [*:0]u8) bool {
    if (hdrs.len + 1 > hdrs.cap) {
        const new_cap: usize = if (hdrs.cap != 0) hdrs.cap * 2 else 8;
        const bytes = new_cap * @sizeOf(NurlHttpHeader);
        const resized = if (hdrs.items) |existing|
            c.realloc(existing, bytes)
        else
            c.malloc(bytes);
        if (resized == null) return false;
        hdrs.items = @ptrCast(@alignCast(resized));
        hdrs.cap = new_cap;
    }
    hdrs.items.?[hdrs.len] = .{ .name = name, .value = value };
    hdrs.len += 1;
    return true;
}

fn httpHeaderBufFree(hdrs: *NurlHttpHeaderBuf) void {
    if (hdrs.items) |items| {
        var i: usize = 0;
        while (i < hdrs.len) : (i += 1) {
            if (items[i].name) |name| c.free(name);
            if (items[i].value) |value| c.free(value);
        }
        c.free(@ptrCast(items));
    }
    hdrs.* = .{ .items = null, .len = 0, .cap = 0 };
}

fn httpHeaderBufClear(hdrs: *NurlHttpHeaderBuf) void {
    if (hdrs.items) |items| {
        var i: usize = 0;
        while (i < hdrs.len) : (i += 1) {
            if (items[i].name) |name| c.free(name);
            if (items[i].value) |value| c.free(value);
        }
    }
    hdrs.len = 0;
}

fn httpBuildSlist(blob: ?[*:0]const u8) ?*curl.struct_curl_slist {
    if (!runtime_features.have_libcurl or builtin.os.tag == .windows or builtin.os.tag == .wasi) return null;
    const raw = blob orelse return null;
    if (raw[0] == 0) return null;

    var list: ?*curl.struct_curl_slist = null;
    var p: [*:0]const u8 = raw;
    while (p[0] != 0) {
        var q: [*:0]const u8 = p;
        while (q[0] != 0 and q[0] != '\n') : (q += 1) {}
        var n: usize = @intFromPtr(q) - @intFromPtr(p);
        while (n > 0 and p[n - 1] == '\r') n -= 1;
        if (n > 0) {
            var has_colon = false;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                if (p[i] == ':') {
                    has_colon = true;
                    break;
                }
            }
            if (has_colon) {
                const line = c.malloc(n + 1) orelse break;
                const line_bytes: [*]u8 = @ptrCast(line);
                @memcpy(line_bytes[0..n], p[0..n]);
                line_bytes[n] = 0;
                const next = curl.curl_slist_append(list, @ptrCast(line_bytes));
                c.free(line);
                if (next != null) list = next;
            }
        }
        if (q[0] == 0) break;
        p = q + 1;
    }
    return list;
}

var g_cgs: [max_cgs]?*NurlCG = .{null} ** max_cgs;
var g_cg_count: c_int = 0;
var g_lexers: [max_lex]?*NurlLex = .{null} ** max_lex;
var g_lex_count: c_int = 0;
var g_symtabs: [max_symtabs]?*NurlSymTab = .{null} ** max_symtabs;
var g_symtab_count: c_int = 0;
var g_last_type: [*:0]const u8 = "i64";
var g_last_type_owned = false;
var g_last_parsed_float: f64 = 0.0;
var g_csv_row_n_cells: c_longlong = 0;
var g_csv_row_next_pos: c_longlong = 0;
var g_csv_n_rows: c_longlong = 0;
var g_csv_n_header: c_longlong = 0;
var g_csv_n_cells: c_longlong = 0;
var g_log_level: c_longlong = 1;
var g_stdin_eof_flag = false;
var g_outbuf: ?[*]u8 = null;
var g_outbuf_len: usize = 0;
var g_signal_listener: ?*volatile NurlTcpPrefix = null;
var g_outbuf_mode = false;
threadlocal var g_panic_top: ?*NurlPanicFrame = null;
threadlocal var g_panic_last_msg: ?[*:0]u8 = null;

const outbuf_size = 8 * 1024 * 1024;
const c_eof: c_int = -1;

fn getCg(handle: c_longlong) *NurlCG {
    const idx: c_int = @intCast(handle - 1);
    if (idx < 0 or idx >= g_cg_count or g_cgs[@intCast(idx)] == null) {
        std.debug.print("nurlc: invalid cg handle\n", .{});
        std.process.exit(1);
    }
    return g_cgs[@intCast(idx)].?;
}

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

pub export fn nurl_sym_new() c_longlong {
    if (g_symtab_count >= max_symtabs) {
        fatalRuntime("nurlc: too many symtabs\n");
    }
    const raw = c.calloc(1, @sizeOf(NurlSymTab)) orelse fatalRuntime("nurlc: too many symtabs\n");
    const tab: *NurlSymTab = @ptrCast(@alignCast(raw));
    tab.* = .{
        .entries = null,
        .count = 0,
        .cap = 0,
        .depth = 0,
    };
    const idx: c_int = g_symtab_count;
    g_symtabs[@intCast(idx)] = tab;
    g_symtab_count += 1;
    return idx + 1;
}

pub export fn nurl_sym_def(handle: c_longlong, name: ?[*:0]const u8, ty: ?[*:0]const u8) void {
    const tab = getSymTab(handle);
    const sym_name = name orelse "";
    const sym_ty = ty orelse "";
    if (tab.count >= max_syms) {
        fatalRuntime("nurlc: symbol table full\n");
    }
    ensureSymCap(tab, tab.count + 1);
    const name_copy = dupZ(sym_name) orelse fatalRuntime("nurlc: symbol table full\n");
    const ty_copy = dupZ(sym_ty) orelse {
        c.free(name_copy);
        fatalRuntime("nurlc: symbol table full\n");
    };
    tab.entries.?[tab.count] = .{
        .depth = tab.depth,
        .name = name_copy,
        .ty = ty_copy,
    };
    tab.count += 1;
}

pub export fn nurl_sym_get(handle: c_longlong, name: ?[*:0]const u8) ?[*:0]u8 {
    const tab = getSymTab(handle);
    const query = std.mem.span(name orelse "");
    var idx = tab.count;
    while (idx > 0) {
        idx -= 1;
        const entry = tab.entries.?[idx];
        if (std.mem.eql(u8, std.mem.span(entry.name), query)) {
            return dupZ(entry.ty);
        }
    }
    return dupSliceZ("");
}

pub export fn nurl_sym_push(handle: c_longlong) void {
    getSymTab(handle).depth += 1;
}

pub export fn nurl_sym_pop(handle: c_longlong) void {
    const tab = getSymTab(handle);
    while (tab.count > 0) {
        const entry = tab.entries.?[tab.count - 1];
        if (entry.depth != tab.depth) break;
        c.free(entry.name);
        c.free(entry.ty);
        tab.count -= 1;
    }
    if (tab.depth > 0) tab.depth -= 1;
}

pub export fn nurl_lex_new(src_ptr: ?[*:0]const u8, filename_ptr: ?[*:0]const u8) c_longlong {
    if (g_lex_count >= max_lex) {
        fatalRuntime("nurlc: too many lexers\n");
    }
    const raw = c.calloc(1, @sizeOf(NurlLex)) orelse fatalRuntime("nurlc: too many lexers\n");
    const lx: *NurlLex = @ptrCast(@alignCast(raw));
    lx.* = .{
        .src = dupZ(src_ptr orelse "") orelse fatalRuntime("nurlc: out of memory\n"),
        .filename = dupZ(filename_ptr orelse "") orelse fatalRuntime("nurlc: out of memory\n"),
        .pos = 0,
        .len = 0,
        .line = 1,
        .cur = emptyToken(),
        .peek = emptyToken(),
        .peek_valid = false,
        .peek2 = emptyToken(),
        .peek2_valid = false,
        .peek3 = emptyToken(),
        .peek3_valid = false,
        .peek4 = emptyToken(),
        .peek4_valid = false,
    };
    lx.len = @intCast(std.mem.len(lx.src));
    lx.cur = lexNextTok(lx);

    const idx = g_lex_count;
    g_lexers[@intCast(idx)] = lx;
    g_lex_count += 1;
    return idx + 1;
}

pub export fn nurl_lex_type(handle: c_longlong) c_longlong {
    return getLex(handle).cur.type;
}

pub export fn nurl_lex_val(handle: c_longlong) ?[*:0]u8 {
    return dupZ(getLex(handle).cur.val orelse "");
}

pub export fn nurl_lex_inum(handle: c_longlong) c_longlong {
    return getLex(handle).cur.inum;
}

pub export fn nurl_lex_fnum(handle: c_longlong) f64 {
    return getLex(handle).cur.fnum;
}

pub export fn nurl_lex_line(handle: c_longlong) c_longlong {
    return getLex(handle).cur.line;
}

pub export fn nurl_lex_filename(handle: c_longlong) ?[*:0]u8 {
    return dupZ(getLex(handle).filename);
}

pub export fn nurl_lex_advance(handle: c_longlong) void {
    const lx = getLex(handle);
    freeToken(&lx.cur);
    if (lx.peek_valid) {
        lx.cur = lx.peek;
        if (lx.peek2_valid) {
            lx.peek = lx.peek2;
            if (lx.peek3_valid) {
                lx.peek2 = lx.peek3;
                if (lx.peek4_valid) {
                    lx.peek3 = lx.peek4;
                    lx.peek4_valid = false;
                } else {
                    lx.peek3_valid = false;
                }
            } else {
                lx.peek2_valid = false;
            }
        } else {
            lx.peek_valid = false;
        }
    } else {
        lx.cur = lexNextTok(lx);
    }
}

pub export fn nurl_lex_cur_start(handle: c_longlong) c_longlong {
    return getLex(handle).cur.start_pos;
}

pub export fn nurl_lex_col(handle: c_longlong) c_longlong {
    const lx = getLex(handle);
    var pos = lx.cur.start_pos;
    if (pos < 0) pos = 0;
    if (pos > lx.len) pos = lx.len;
    var col: c_int = 1;
    const src = std.mem.span(lx.src);
    while (pos > 0 and src[@intCast(pos - 1)] != '\n') {
        pos -= 1;
        col += 1;
    }
    return col;
}

pub export fn nurl_lex_line_text(handle: c_longlong) ?[*:0]u8 {
    const lx = getLex(handle);
    const src = std.mem.span(lx.src);
    var pos = lx.cur.start_pos;
    if (pos < 0) pos = 0;
    if (pos > lx.len) pos = lx.len;

    var line_start = pos;
    while (line_start > 0 and src[@intCast(line_start - 1)] != '\n') line_start -= 1;

    var line_end = pos;
    while (line_end < lx.len and src[@intCast(line_end)] != '\n') line_end += 1;
    if (line_end > line_start and src[@intCast(line_end - 1)] == '\r') line_end -= 1;

    const count: usize = @intCast(line_end - line_start);
    const raw = c.malloc(count + 1) orelse fatalRuntime("nurlc: out of memory\n");
    const out: [*]u8 = @ptrCast(raw);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const cur = src[@as(usize, @intCast(line_start)) + i];
        out[i] = if (cur == '\t') ' ' else cur;
    }
    out[count] = 0;
    return @ptrCast(out);
}

pub export fn nurl_diag_caret(col: c_longlong) ?[*:0]u8 {
    var pad = if (col > 0) col - 1 else 0;
    if (pad > 4096) pad = 4096;
    const raw = c.malloc(@as(usize, @intCast(pad + 2))) orelse fatalRuntime("nurlc: out of memory\n");
    const out: [*]u8 = @ptrCast(raw);
    var i: usize = 0;
    while (i < @as(usize, @intCast(pad))) : (i += 1) out[i] = ' ';
    out[@intCast(pad)] = '^';
    out[@intCast(pad + 1)] = 0;
    return @ptrCast(out);
}

pub export fn nurl_lex_src_slice(handle: c_longlong, start: c_longlong, len: c_longlong) ?[*:0]u8 {
    const lx = getLex(handle);
    const src = std.mem.span(lx.src);
    const src_len: c_longlong = lx.len;
    var clamped_start = start;
    var clamped_len = len;
    if (clamped_start < 0) clamped_start = 0;
    if (clamped_start > src_len) clamped_start = src_len;
    if (clamped_len < 0) clamped_len = 0;
    const avail = src_len - clamped_start;
    if (clamped_len > avail) clamped_len = avail;
    return dupSliceZ(src[@intCast(clamped_start)..@intCast(clamped_start + clamped_len)]);
}

pub export fn nurl_lex_set_pos(handle: c_longlong, pos: c_longlong) void {
    const lx = getLex(handle);
    freeToken(&lx.cur);
    if (lx.peek_valid) {
        freeToken(&lx.peek);
        lx.peek_valid = false;
    }
    if (lx.peek2_valid) {
        freeToken(&lx.peek2);
        lx.peek2_valid = false;
    }
    if (lx.peek3_valid) {
        freeToken(&lx.peek3);
        lx.peek3_valid = false;
    }
    if (lx.peek4_valid) {
        freeToken(&lx.peek4);
        lx.peek4_valid = false;
    }

    var clamped_pos = pos;
    if (clamped_pos < 0) clamped_pos = 0;
    if (clamped_pos > lx.len) clamped_pos = lx.len;
    lx.pos = @intCast(clamped_pos);
    lx.line = 1;
    const src = std.mem.span(lx.src);
    var i: c_int = 0;
    while (i < lx.pos and i < lx.len) : (i += 1) {
        if (src[@intCast(i)] == '\n') lx.line += 1;
    }
    lx.cur = lexNextTok(lx);
}

pub export fn nurl_lex_peek_type(handle: c_longlong) c_longlong {
    const lx = getLex(handle);
    if (!lx.peek_valid) {
        lx.peek = lexNextTok(lx);
        lx.peek_valid = true;
    }
    return lx.peek.type;
}

pub export fn nurl_lex_peek2_type(handle: c_longlong) c_longlong {
    const lx = getLex(handle);
    if (!lx.peek_valid) {
        lx.peek = lexNextTok(lx);
        lx.peek_valid = true;
    }
    if (!lx.peek2_valid) {
        lx.peek2 = lexNextTok(lx);
        lx.peek2_valid = true;
    }
    return lx.peek2.type;
}

pub export fn nurl_lex_peek3_type(handle: c_longlong) c_longlong {
    const lx = getLex(handle);
    if (!lx.peek_valid) {
        lx.peek = lexNextTok(lx);
        lx.peek_valid = true;
    }
    if (!lx.peek2_valid) {
        lx.peek2 = lexNextTok(lx);
        lx.peek2_valid = true;
    }
    if (!lx.peek3_valid) {
        lx.peek3 = lexNextTok(lx);
        lx.peek3_valid = true;
    }
    return lx.peek3.type;
}

pub export fn nurl_lex_peek4_type(handle: c_longlong) c_longlong {
    const lx = getLex(handle);
    if (!lx.peek_valid) {
        lx.peek = lexNextTok(lx);
        lx.peek_valid = true;
    }
    if (!lx.peek2_valid) {
        lx.peek2 = lexNextTok(lx);
        lx.peek2_valid = true;
    }
    if (!lx.peek3_valid) {
        lx.peek3 = lexNextTok(lx);
        lx.peek3_valid = true;
    }
    if (!lx.peek4_valid) {
        lx.peek4 = lexNextTok(lx);
        lx.peek4_valid = true;
    }
    return lx.peek4.type;
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

fn nurl_proc_run_impl(
    cmd: ?[*:0]const u8,
    argv_buf: ?[*:0]const u8,
    argc: c_longlong,
    stdin_blob: ?[*:0]const u8,
) callconv(.c) c_longlong {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
        return procEmptyResult(nurl_proc_err_other);
    }

    const result = allocProcResult() orelse return 0;
    result.* = .{
        .exit_code = 0,
        .err_kind = nurl_proc_err_ok,
        .stdout_buf = dupSliceZ(""),
        .stdout_len = 0,
        .stderr_buf = dupSliceZ(""),
        .stderr_len = 0,
    };

    const cmd_ptr = cmd orelse {
        result.err_kind = nurl_proc_err_notfound;
        return @intCast(@intFromPtr(result));
    };
    if (cmd_ptr[0] == 0) {
        result.err_kind = nurl_proc_err_notfound;
        return @intCast(@intFromPtr(result));
    }

    const arg_count: usize = if (argc < 0) 0 else @intCast(argc);
    const argv_user: ?[*]const ?[*:0]const u8 = if (arg_count == 0 or argv_buf == null)
        null
    else
        @ptrCast(@alignCast(argv_buf.?));
    const full_raw = c.malloc((arg_count + 2) * @sizeOf(?[*:0]const u8)) orelse {
        result.err_kind = nurl_proc_err_other;
        return @intCast(@intFromPtr(result));
    };
    defer c.free(full_raw);
    const full: [*]?[*:0]const u8 = @ptrCast(@alignCast(full_raw));
    full[0] = cmd_ptr;
    var arg_index: usize = 0;
    while (arg_index < arg_count) : (arg_index += 1) {
        full[arg_index + 1] = if (argv_user) |user| user[arg_index] orelse "" else "";
    }
    full[arg_count + 1] = null;

    var sin_p: [2]c.fd_t = .{ -1, -1 };
    var sout_p: [2]c.fd_t = .{ -1, -1 };
    var serr_p: [2]c.fd_t = .{ -1, -1 };
    var err_p: [2]c.fd_t = .{ -1, -1 };

    if (c.pipe(&sin_p) != 0 or c.pipe(&sout_p) != 0 or c.pipe(&serr_p) != 0 or c.pipe(&err_p) != 0) {
        procClosePair(&sin_p);
        procClosePair(&sout_p);
        procClosePair(&serr_p);
        procClosePair(&err_p);
        result.err_kind = nurl_proc_err_io;
        return @intCast(@intFromPtr(result));
    }

    const fd_flags = c.fcntl(err_p[1], c.F.GETFD, @as(usize, 0));
    if (fd_flags != -1) _ = c.fcntl(err_p[1], c.F.SETFD, @as(c_uint, @intCast(fd_flags | c.FD_CLOEXEC)));

    const pid_raw = c.fork();
    if (pid_raw < 0) {
        procClosePair(&sin_p);
        procClosePair(&sout_p);
        procClosePair(&serr_p);
        procClosePair(&err_p);
        result.err_kind = nurl_proc_err_io;
        return @intCast(@intFromPtr(result));
    }

    if (pid_raw == 0) {
        if (sin_p[0] != 0) _ = c.dup2(sin_p[0], 0);
        if (sout_p[1] != 1) _ = c.dup2(sout_p[1], 1);
        if (serr_p[1] != 2) _ = c.dup2(serr_p[1], 2);
        _ = posix.close(sin_p[0]);
        _ = posix.close(sin_p[1]);
        _ = posix.close(sout_p[0]);
        _ = posix.close(sout_p[1]);
        _ = posix.close(serr_p[0]);
        _ = posix.close(serr_p[1]);
        _ = posix.close(err_p[0]);
        _ = execvp(cmd_ptr, @ptrCast(full));
        var child_errno: c_int = c._errno().*;
        _ = c.write(err_p[1], @ptrCast(&child_errno), @sizeOf(c_int));
        c._exit(127);
    }

    _ = posix.close(sin_p[0]);
    sin_p[0] = -1;
    _ = posix.close(sout_p[1]);
    sout_p[1] = -1;
    _ = posix.close(serr_p[1]);
    serr_p[1] = -1;
    _ = posix.close(err_p[1]);
    err_p[1] = -1;

    const nonblock_flag: c_uint = @bitCast(c.O{ .NONBLOCK = true });
    var fl = c.fcntl(sout_p[0], c.F.GETFL, @as(usize, 0));
    if (fl != -1) _ = c.fcntl(sout_p[0], c.F.SETFL, @as(c_uint, @intCast(fl)) | nonblock_flag);
    fl = c.fcntl(serr_p[0], c.F.GETFL, @as(usize, 0));
    if (fl != -1) _ = c.fcntl(serr_p[0], c.F.SETFL, @as(c_uint, @intCast(fl)) | nonblock_flag);

    const old_pipe = signal(@intFromEnum(c.SIG.PIPE), 1);
    const stdin_slice = std.mem.span(stdin_blob orelse "");
    if (stdin_slice.len != 0) {
        var off: usize = 0;
        while (off < stdin_slice.len) {
            const wrote = c.write(sin_p[1], stdin_slice.ptr + off, stdin_slice.len - off);
            if (wrote < 0) {
                if (c.errno(-1) == .INTR) continue;
                break;
            }
            off += @intCast(wrote);
        }
    }
    _ = posix.close(sin_p[1]);
    sin_p[1] = -1;
    _ = signal(@intFromEnum(c.SIG.PIPE), old_pipe);

    var out_buf = NurlProcBuf{};
    var err_buf = NurlProcBuf{};
    var tmp: [4096]u8 = undefined;
    var sout_open = true;
    var serr_open = true;
    var io_err = false;

    while (sout_open or serr_open) {
        var pfds: [2]c.pollfd = undefined;
        var n_fds: usize = 0;
        if (sout_open) {
            pfds[n_fds] = .{
                .fd = sout_p[0],
                .events = c.POLL.IN,
                .revents = 0,
            };
            n_fds += 1;
        }
        if (serr_open) {
            pfds[n_fds] = .{
                .fd = serr_p[0],
                .events = c.POLL.IN,
                .revents = 0,
            };
            n_fds += 1;
        }

        var pr: c_int = undefined;
        while (true) {
            pr = c.poll(pfds[0..].ptr, @intCast(n_fds), -1);
            if (pr >= 0 or c.errno(-1) != .INTR) break;
        }
        if (pr < 0) {
            io_err = true;
            break;
        }

        var fd_index: usize = 0;
        while (fd_index < n_fds) : (fd_index += 1) {
            const fd = pfds[fd_index].fd;
            const target = if (fd == sout_p[0]) &out_buf else &err_buf;
            const open_flag = if (fd == sout_p[0]) &sout_open else &serr_open;
            if (pfds[fd_index].revents == 0) continue;

            var got_eof = false;
            while (true) {
                const rd = c.read(fd, &tmp, tmp.len);
                if (rd > 0) {
                    if (!procBufAppend(target, tmp[0..@intCast(rd)])) {
                        io_err = true;
                        got_eof = true;
                        break;
                    }
                } else if (rd == 0) {
                    got_eof = true;
                    break;
                } else {
                    const err = c.errno(-1);
                    if (err == .INTR) continue;
                    if (err == .AGAIN) break;
                    io_err = true;
                    got_eof = true;
                    break;
                }
            }

            if (got_eof or (pfds[fd_index].revents & (c.POLL.HUP | c.POLL.ERR)) != 0) {
                while (true) {
                    const rd = c.read(fd, &tmp, tmp.len);
                    if (rd > 0) {
                        if (!procBufAppend(target, tmp[0..@intCast(rd)])) {
                            io_err = true;
                            break;
                        }
                    } else break;
                }
                open_flag.* = false;
            }
        }
    }

    _ = posix.close(sout_p[0]);
    sout_p[0] = -1;
    _ = posix.close(serr_p[0]);
    serr_p[0] = -1;

    var child_errno: c_int = 0;
    var got_errno_bytes: usize = 0;
    while (true) {
        const rd = c.read(err_p[0], @as([*]u8, @ptrCast(&child_errno)) + got_errno_bytes, @sizeOf(c_int) - got_errno_bytes);
        if (rd > 0) {
            got_errno_bytes += @intCast(rd);
            if (got_errno_bytes >= @sizeOf(c_int)) break;
        } else if (rd == 0) {
            break;
        } else {
            if (c.errno(-1) == .INTR) continue;
            break;
        }
    }
    _ = posix.close(err_p[0]);
    err_p[0] = -1;

    var status: c_int = 0;
    var waited_pid: c.pid_t = undefined;
    while (true) {
        waited_pid = c.waitpid(@intCast(pid_raw), &status, 0);
        if (waited_pid >= 0 or c.errno(-1) != .INTR) break;
    }
    if (waited_pid < 0) io_err = true;

    if (child_errno != 0) {
        result.exit_code = -1;
        result.err_kind = if (child_errno == @intFromEnum(c.E.NOENT))
            nurl_proc_err_notfound
        else
            nurl_proc_err_exec_failed;
    } else if (io_err) {
        result.exit_code = -1;
        result.err_kind = nurl_proc_err_io;
    } else if (waitStatusExited(status)) {
        result.exit_code = waitStatusExitCode(status);
        result.err_kind = nurl_proc_err_ok;
    } else if (waitStatusSignaled(status)) {
        result.exit_code = 128 + waitStatusTermSig(status);
        result.err_kind = nurl_proc_err_ok;
    } else {
        result.exit_code = -1;
        result.err_kind = nurl_proc_err_other;
    }

    c.free(result.stdout_buf);
    c.free(result.stderr_buf);
    result.stdout_buf = procBufOwnedOrEmpty(&out_buf);
    result.stdout_len = @intCast(out_buf.len);
    result.stderr_buf = procBufOwnedOrEmpty(&err_buf);
    result.stderr_len = @intCast(err_buf.len);
    return @intCast(@intFromPtr(result));
}

fn nurl_proc_exit_code_impl(handle: c_longlong) callconv(.c) c_longlong {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.exit_code else -1;
}

fn nurl_proc_err_kind_impl(handle: c_longlong) callconv(.c) c_longlong {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.err_kind else nurl_proc_err_other;
}

fn nurl_proc_stdout_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.stdout_buf orelse "" else "";
}

fn nurl_proc_stderr_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.stderr_buf orelse "" else "";
}

fn nurl_proc_stdout_len_impl(handle: c_longlong) callconv(.c) c_longlong {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.stdout_len else 0;
}

fn nurl_proc_stderr_len_impl(handle: c_longlong) callconv(.c) c_longlong {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    return if (result) |value| value.stderr_len else 0;
}

fn nurl_proc_free_impl(handle: c_longlong) callconv(.c) void {
    const result: ?*NurlProcResult = if (handle == 0) null else @ptrFromInt(@as(usize, @intCast(handle)));
    if (result) |value| {
        if (value.stdout_buf) |buf| c.free(buf);
        if (value.stderr_buf) |buf| c.free(buf);
        c.free(value);
    }
}

comptime {
    if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        @export(&nurl_proc_run_impl, .{ .name = "nurl_proc_run" });
        @export(&nurl_proc_exit_code_impl, .{ .name = "nurl_proc_exit_code" });
        @export(&nurl_proc_err_kind_impl, .{ .name = "nurl_proc_err_kind" });
        @export(&nurl_proc_stdout_impl, .{ .name = "nurl_proc_stdout" });
        @export(&nurl_proc_stderr_impl, .{ .name = "nurl_proc_stderr" });
        @export(&nurl_proc_stdout_len_impl, .{ .name = "nurl_proc_stdout_len" });
        @export(&nurl_proc_stderr_len_impl, .{ .name = "nurl_proc_stderr_len" });
        @export(&nurl_proc_free_impl, .{ .name = "nurl_proc_free" });
    }
}

fn nurl_proc_spawn_impl(
    cmd: ?[*:0]const u8,
    argv_buf: ?[*:0]const u8,
    argc: c_longlong,
) callconv(.c) c_longlong {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) {
        return procChildEmpty(nurl_proc_err_other);
    }

    const child = allocProcChild() orelse return 0;
    child.* = .{
        .err_kind = nurl_proc_err_ok,
        .last_io_err = 0,
        .exit_code = -1,
        .eof = 0,
        .waited = 0,
        .pid_or_0 = 0,
        .pid = 0,
        .fd_in = -1,
        .fd_out = -1,
        .scratch = null,
        .scratch_len = 0,
        .scratch_cap = 0,
        .line_buf = null,
        .line_len = 0,
        .line_cap = 0,
    };

    const cmd_ptr = cmd orelse {
        child.err_kind = nurl_proc_err_notfound;
        return @intCast(@intFromPtr(child));
    };
    if (cmd_ptr[0] == 0) {
        child.err_kind = nurl_proc_err_notfound;
        return @intCast(@intFromPtr(child));
    }

    const arg_count: usize = if (argc < 0) 0 else @intCast(argc);
    const argv_user: ?[*]const ?[*:0]const u8 = if (arg_count == 0 or argv_buf == null)
        null
    else
        @ptrCast(@alignCast(argv_buf.?));

    var sin_p: [2]c.fd_t = .{ -1, -1 };
    var sout_p: [2]c.fd_t = .{ -1, -1 };
    var err_p: [2]c.fd_t = .{ -1, -1 };

    if (c.pipe(&sin_p) != 0 or c.pipe(&sout_p) != 0 or c.pipe(&err_p) != 0) {
        procClosePair(&sin_p);
        procClosePair(&sout_p);
        procClosePair(&err_p);
        child.err_kind = nurl_proc_err_io;
        child.last_io_err = c._errno().*;
        return @intCast(@intFromPtr(child));
    }

    const fd_flags = c.fcntl(err_p[1], c.F.GETFD, @as(usize, 0));
    if (fd_flags != -1) _ = c.fcntl(err_p[1], c.F.SETFD, @as(c_uint, @intCast(fd_flags | c.FD_CLOEXEC)));

    const full_raw = c.malloc((arg_count + 2) * @sizeOf(?[*:0]const u8)) orelse {
        procClosePair(&sin_p);
        procClosePair(&sout_p);
        procClosePair(&err_p);
        child.err_kind = nurl_proc_err_other;
        return @intCast(@intFromPtr(child));
    };
    defer c.free(full_raw);
    const full: [*]?[*:0]const u8 = @ptrCast(@alignCast(full_raw));
    full[0] = cmd_ptr;
    var arg_index: usize = 0;
    while (arg_index < arg_count) : (arg_index += 1) {
        full[arg_index + 1] = if (argv_user) |user| user[arg_index] orelse "" else "";
    }
    full[arg_count + 1] = null;

    const pid_raw = c.fork();
    if (pid_raw < 0) {
        procClosePair(&sin_p);
        procClosePair(&sout_p);
        procClosePair(&err_p);
        child.err_kind = nurl_proc_err_io;
        child.last_io_err = c._errno().*;
        return @intCast(@intFromPtr(child));
    }

    if (pid_raw == 0) {
        if (sin_p[0] != 0) _ = c.dup2(sin_p[0], 0);
        if (sout_p[1] != 1) _ = c.dup2(sout_p[1], 1);
        _ = posix.close(sin_p[0]);
        _ = posix.close(sin_p[1]);
        _ = posix.close(sout_p[0]);
        _ = posix.close(sout_p[1]);
        _ = posix.close(err_p[0]);
        _ = execvp(cmd_ptr, @ptrCast(full));
        var child_errno: c_int = c._errno().*;
        _ = c.write(err_p[1], @ptrCast(&child_errno), @sizeOf(c_int));
        c._exit(127);
    }

    _ = posix.close(sin_p[0]);
    sin_p[0] = -1;
    _ = posix.close(sout_p[1]);
    sout_p[1] = -1;
    _ = posix.close(err_p[1]);
    err_p[1] = -1;

    var child_errno: c_int = 0;
    var got_errno_bytes: usize = 0;
    while (true) {
        const rd = c.read(err_p[0], @as([*]u8, @ptrCast(&child_errno)) + got_errno_bytes, @sizeOf(c_int) - got_errno_bytes);
        if (rd > 0) {
            got_errno_bytes += @intCast(rd);
            if (got_errno_bytes >= @sizeOf(c_int)) break;
        } else if (rd == 0) {
            break;
        } else {
            if (c.errno(-1) == .INTR) continue;
            break;
        }
    }
    _ = posix.close(err_p[0]);
    err_p[0] = -1;

    if (child_errno != 0) {
        _ = posix.close(sin_p[1]);
        _ = posix.close(sout_p[0]);
        var status: c_int = 0;
        _ = c.waitpid(@intCast(pid_raw), &status, 0);
        child.err_kind = if (child_errno == @intFromEnum(c.E.NOENT))
            nurl_proc_err_notfound
        else
            nurl_proc_err_exec_failed;
        child.last_io_err = child_errno;
        return @intCast(@intFromPtr(child));
    }

    const nonblock_flag: c_uint = @bitCast(c.O{ .NONBLOCK = true });
    const fl = c.fcntl(sout_p[0], c.F.GETFL, @as(usize, 0));
    if (fl != -1) _ = c.fcntl(sout_p[0], c.F.SETFL, @as(c_uint, @intCast(fl)) | nonblock_flag);

    child.pid = @intCast(pid_raw);
    child.pid_or_0 = @intCast(pid_raw);
    child.fd_in = sin_p[1];
    child.fd_out = sout_p[0];
    return @intCast(@intFromPtr(child));
}

fn nurl_proc_spawn_write_impl(handle: c_longlong, buf: ?[*:0]const u8, n: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle) orelse return -1;
    if (child.fd_in < 0 or buf == null or n <= 0) return 0;

    const old_pipe = signal(@intFromEnum(c.SIG.PIPE), 1);
    defer _ = signal(@intFromEnum(c.SIG.PIPE), old_pipe);

    var total: c_longlong = 0;
    while (total < n) {
        const wrote = c.write(child.fd_in, buf.? + @as(usize, @intCast(total)), @intCast(n - total));
        if (wrote < 0) {
            if (c.errno(-1) == .INTR) continue;
            child.last_io_err = c._errno().*;
            return -1;
        }
        if (wrote == 0) break;
        total += @intCast(wrote);
    }
    return total;
}

fn nurl_proc_spawn_close_stdin_impl(handle: c_longlong) callconv(.c) void {
    const child = procChildHandle(handle) orelse return;
    if (child.fd_in >= 0) {
        _ = posix.close(child.fd_in);
        child.fd_in = -1;
    }
}

fn nurl_proc_spawn_read_line_impl(handle: c_longlong, timeout_ms: c_longlong) callconv(.c) ?[*:0]const u8 {
    const child = procChildHandle(handle) orelse return "";
    child.line_len = 0;
    if (child.line_buf) |line_buf| line_buf[0] = 0;

    if (procChildDrainLine(child)) {
        return if (child.line_buf) |line_buf| @ptrCast(line_buf) else "";
    }

    if (child.fd_out < 0) {
        child.eof = 1;
        return "";
    }

    var chunk: [4096]u8 = undefined;
    while (true) {
        var pfds = [1]c.pollfd{.{
            .fd = child.fd_out,
            .events = c.POLL.IN,
            .revents = 0,
        }};
        const wait_for: c_int = if (timeout_ms > 0) @intCast(timeout_ms) else -1;
        var pr: c_int = undefined;
        while (true) {
            pr = c.poll(&pfds, 1, wait_for);
            if (pr >= 0 or c.errno(-1) != .INTR) break;
        }
        if (pr == 0) return "";
        if (pr < 0) {
            child.err_kind = nurl_proc_err_io;
            child.last_io_err = c._errno().*;
            return "";
        }

        if ((pfds[0].revents & c.POLL.IN) != 0) {
            while (true) {
                const rd = c.read(child.fd_out, &chunk, chunk.len);
                if (rd > 0) {
                    if (!procChildScratchReserve(child, child.scratch_len + @as(usize, @intCast(rd)))) {
                        child.err_kind = nurl_proc_err_other;
                        return "";
                    }
                    const scratch = child.scratch orelse return "";
                    @memcpy(scratch[child.scratch_len .. child.scratch_len + @as(usize, @intCast(rd))], chunk[0..@intCast(rd)]);
                    child.scratch_len += @intCast(rd);
                } else if (rd == 0) {
                    _ = posix.close(child.fd_out);
                    child.fd_out = -1;
                    child.eof = 1;
                    if (procChildDrainLine(child)) {
                        return if (child.line_buf) |line_buf| @ptrCast(line_buf) else "";
                    }
                    if (child.scratch_len > 0) {
                        if (!procChildLineReserve(child, child.scratch_len)) return "";
                        const line_buf = child.line_buf orelse return "";
                        const scratch = child.scratch orelse return "";
                        @memcpy(line_buf[0..child.scratch_len], scratch[0..child.scratch_len]);
                        line_buf[child.scratch_len] = 0;
                        child.line_len = child.scratch_len;
                        child.scratch_len = 0;
                        return @ptrCast(line_buf);
                    }
                    return "";
                } else {
                    const err = c.errno(-1);
                    if (err == .INTR) continue;
                    if (err == .AGAIN) break;
                    child.err_kind = nurl_proc_err_io;
                    child.last_io_err = c._errno().*;
                    return "";
                }
            }
            if (procChildDrainLine(child)) {
                return if (child.line_buf) |line_buf| @ptrCast(line_buf) else "";
            }
        }

        if ((pfds[0].revents & (c.POLL.HUP | c.POLL.ERR)) != 0) {
            _ = posix.close(child.fd_out);
            child.fd_out = -1;
            child.eof = 1;
            if (procChildDrainLine(child)) {
                return if (child.line_buf) |line_buf| @ptrCast(line_buf) else "";
            }
            if (child.scratch_len > 0) {
                if (!procChildLineReserve(child, child.scratch_len)) return "";
                const line_buf = child.line_buf orelse return "";
                const scratch = child.scratch orelse return "";
                @memcpy(line_buf[0..child.scratch_len], scratch[0..child.scratch_len]);
                line_buf[child.scratch_len] = 0;
                child.line_len = child.scratch_len;
                child.scratch_len = 0;
                return @ptrCast(line_buf);
            }
            return "";
        }
    }
}

fn nurl_proc_spawn_wait_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle) orelse return -1;
    if (child.waited != 0) return child.exit_code;
    if (child.pid_or_0 <= 0) return -1;

    var status: c_int = 0;
    var waited_pid: c.pid_t = undefined;
    while (true) {
        waited_pid = c.waitpid(child.pid, &status, 0);
        if (waited_pid >= 0 or c.errno(-1) != .INTR) break;
    }
    if (waited_pid < 0) {
        child.last_io_err = c._errno().*;
        return -1;
    }

    if (waitStatusExited(status)) {
        child.exit_code = waitStatusExitCode(status);
    } else if (waitStatusSignaled(status)) {
        child.exit_code = 128 + waitStatusTermSig(status);
    } else {
        child.exit_code = -1;
    }
    child.waited = 1;
    return child.exit_code;
}

fn nurl_proc_spawn_kill_impl(handle: c_longlong, sig: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle) orelse return -1;
    if (child.pid_or_0 <= 0) return -1;

    const signo: c.SIG = if (sig > 0) @enumFromInt(@as(c_uint, @intCast(sig))) else c.SIG.TERM;
    if (c.kill(child.pid, signo) < 0) {
        child.last_io_err = c._errno().*;
        return -1;
    }
    return 0;
}

fn nurl_proc_spawn_err_kind_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle);
    return if (child) |value| value.err_kind else nurl_proc_err_other;
}

fn nurl_proc_spawn_pid_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle);
    return if (child) |value| value.pid_or_0 else 0;
}

fn nurl_proc_spawn_read_line_len_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle);
    return if (child) |value| @intCast(value.line_len) else 0;
}

fn nurl_proc_spawn_eof_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle);
    return if (child) |value| value.eof else 1;
}

fn nurl_proc_spawn_last_io_err_impl(handle: c_longlong) callconv(.c) c_longlong {
    const child = procChildHandle(handle);
    return if (child) |value| value.last_io_err else 0;
}

fn nurl_proc_spawn_free_impl(handle: c_longlong) callconv(.c) void {
    const child = procChildHandle(handle) orelse return;
    if (child.fd_in >= 0) _ = posix.close(child.fd_in);
    if (child.fd_out >= 0) _ = posix.close(child.fd_out);

    if (child.pid_or_0 > 0 and child.waited == 0) {
        _ = c.kill(child.pid, c.SIG.TERM);
        var status: c_int = 0;
        var i: usize = 0;
        while (i < 50) : (i += 1) {
            const waited_pid = c.waitpid(child.pid, &status, c.W.NOHANG);
            if (waited_pid == child.pid) {
                child.waited = 1;
                break;
            }
            if (waited_pid < 0) break;
            var ts = c.timespec{ .sec = 0, .nsec = 10 * 1000 * 1000 };
            while (c.nanosleep(&ts, &ts) != 0 and c._errno().* == @intFromEnum(c.E.INTR)) {}
        }
        if (child.waited == 0) {
            _ = c.kill(child.pid, c.SIG.KILL);
            _ = c.waitpid(child.pid, &status, 0);
        }
    }

    if (child.scratch) |scratch| c.free(scratch);
    if (child.line_buf) |line_buf| c.free(line_buf);
    c.free(child);
}

comptime {
    if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        @export(&nurl_proc_spawn_impl, .{ .name = "nurl_proc_spawn" });
        @export(&nurl_proc_spawn_write_impl, .{ .name = "nurl_proc_spawn_write" });
        @export(&nurl_proc_spawn_close_stdin_impl, .{ .name = "nurl_proc_spawn_close_stdin" });
        @export(&nurl_proc_spawn_read_line_impl, .{ .name = "nurl_proc_spawn_read_line" });
        @export(&nurl_proc_spawn_wait_impl, .{ .name = "nurl_proc_spawn_wait" });
        @export(&nurl_proc_spawn_kill_impl, .{ .name = "nurl_proc_spawn_kill" });
        @export(&nurl_proc_spawn_err_kind_impl, .{ .name = "nurl_proc_spawn_err_kind" });
        @export(&nurl_proc_spawn_pid_impl, .{ .name = "nurl_proc_spawn_pid" });
        @export(&nurl_proc_spawn_read_line_len_impl, .{ .name = "nurl_proc_spawn_read_line_len" });
        @export(&nurl_proc_spawn_eof_impl, .{ .name = "nurl_proc_spawn_eof" });
        @export(&nurl_proc_spawn_last_io_err_impl, .{ .name = "nurl_proc_spawn_last_io_err" });
        @export(&nurl_proc_spawn_free_impl, .{ .name = "nurl_proc_spawn_free" });
    }
}

fn nurlSignalPosixHandler(sig: c.SIG) callconv(.c) void {
    _ = sig;
    const listener = g_signal_listener orelse return;
    if (listener.fd != nurl_invalid_sock) {
        _ = c.close(listener.fd);
        listener.fd = nurl_invalid_sock;
    }
}

fn nurl_tcp_shutdown_impl(handle: c_longlong) callconv(.c) void {
    const tcp = tcpPrefixHandle(handle) orelse return;
    if (tcp.fd != nurl_invalid_sock) {
        _ = c.shutdown(tcp.fd, c.SHUT.RDWR);
        _ = posix.close(tcp.fd);
        tcp.fd = nurl_invalid_sock;
    }
}

fn nurl_tcp_err_kind_impl(handle: c_longlong) callconv(.c) c_longlong {
    const tcp = tcpPrefixHandle(handle);
    return if (tcp) |value| value.err_kind else nurl_net_err_other;
}

fn nurl_tcp_peer_addr_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    const tcp = tcpPrefixHandle(handle) orelse return "";
    return tcp.peer orelse "";
}

fn nurl_tcp_set_timeout_impl(handle: c_longlong, ms: c_longlong) callconv(.c) void {
    const tcp = tcpPrefixHandle(handle) orelse return;
    if (tcp.fd == nurl_invalid_sock) return;

    var tv = c.timeval{
        .sec = if (ms > 0) @intCast(@divTrunc(ms, 1000)) else 0,
        .usec = if (ms > 0) @intCast(@mod(ms, 1000) * 1000) else 0,
    };
    _ = c.setsockopt(tcp.fd, c.SOL.SOCKET, c.SO.RCVTIMEO, @ptrCast(&tv), @sizeOf(c.timeval));
    _ = c.setsockopt(tcp.fd, c.SOL.SOCKET, c.SO.SNDTIMEO, @ptrCast(&tv), @sizeOf(c.timeval));
}

fn nurl_signal_install_shutdown_impl(listener_handle: c_longlong) callconv(.c) void {
    g_signal_listener = if (listener_handle == 0) null else @ptrFromInt(@as(usize, @intCast(listener_handle)));
    var sa = std.mem.zeroes(c.Sigaction);
    sa.handler.handler = nurlSignalPosixHandler;
    _ = c.sigemptyset(&sa.mask);
    sa.flags = 0;
    _ = c.sigaction(c.SIG.INT, &sa, null);
    _ = c.sigaction(c.SIG.TERM, &sa, null);
}

fn nurl_signal_trigger_shutdown_impl() callconv(.c) void {
    const listener = g_signal_listener orelse return;
    if (listener.fd != nurl_invalid_sock) {
        _ = c.close(listener.fd);
        listener.fd = nurl_invalid_sock;
    }
}

comptime {
    if (builtin.os.tag != .windows and builtin.os.tag != .wasi) {
        @export(&nurl_tcp_shutdown_impl, .{ .name = "nurl_tcp_shutdown" });
        @export(&nurl_tcp_err_kind_impl, .{ .name = "nurl_tcp_err_kind" });
        @export(&nurl_tcp_peer_addr_impl, .{ .name = "nurl_tcp_peer_addr" });
        @export(&nurl_tcp_set_timeout_impl, .{ .name = "nurl_tcp_set_timeout" });
        @export(&nurl_signal_install_shutdown_impl, .{ .name = "nurl_signal_install_shutdown" });
        @export(&nurl_signal_trigger_shutdown_impl, .{ .name = "nurl_signal_trigger_shutdown" });
    }
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

pub export fn nurl_gzip_compress(
    dst_ptr: ?[*]u8,
    dst_len_ptr: ?*c_longlong,
    src_ptr: ?[*]u8,
    src_len: c_longlong,
    level: c_int,
) c_int {
    if (!runtime_features.have_zlib) return nurl_gzip_err_unsupported;
    const dst = dst_ptr orelse return zlib.Z_BUF_ERROR;
    const dst_len = dst_len_ptr orelse return zlib.Z_BUF_ERROR;
    const src = src_ptr orelse return zlib.Z_BUF_ERROR;

    var stream = std.mem.zeroes(zlib.z_stream);
    stream.next_in = @ptrCast(src);
    stream.avail_in = @intCast(src_len);
    stream.next_out = @ptrCast(dst);
    stream.avail_out = @intCast(dst_len.*);

    var rc = zlib.deflateInit2_(
        &stream,
        level,
        zlib.Z_DEFLATED,
        15 + 16,
        8,
        zlib.Z_DEFAULT_STRATEGY,
        zlib.ZLIB_VERSION,
        @sizeOf(zlib.z_stream),
    );
    if (rc != zlib.Z_OK) return rc;

    rc = zlib.deflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) {
        _ = zlib.deflateEnd(&stream);
        return if (rc == zlib.Z_OK) zlib.Z_BUF_ERROR else rc;
    }

    dst_len.* = @intCast(stream.total_out);
    return zlib.deflateEnd(&stream);
}

pub export fn nurl_gzip_decompress(
    dst_ptr: ?[*]u8,
    dst_len_ptr: ?*c_longlong,
    src_ptr: ?[*]u8,
    src_len: c_longlong,
) c_int {
    if (!runtime_features.have_zlib) return nurl_gzip_err_unsupported;
    const dst = dst_ptr orelse return zlib.Z_BUF_ERROR;
    const dst_len = dst_len_ptr orelse return zlib.Z_BUF_ERROR;
    const src = src_ptr orelse return zlib.Z_BUF_ERROR;

    var stream = std.mem.zeroes(zlib.z_stream);
    stream.next_in = @ptrCast(src);
    stream.avail_in = @intCast(src_len);
    stream.next_out = @ptrCast(dst);
    stream.avail_out = @intCast(dst_len.*);

    var rc = zlib.inflateInit2_(
        &stream,
        15 + 32,
        zlib.ZLIB_VERSION,
        @sizeOf(zlib.z_stream),
    );
    if (rc != zlib.Z_OK) return rc;

    rc = zlib.inflate(&stream, zlib.Z_FINISH);
    if (rc != zlib.Z_STREAM_END) {
        _ = zlib.inflateEnd(&stream);
        return if (rc == zlib.Z_OK) zlib.Z_BUF_ERROR else rc;
    }

    dst_len.* = @intCast(stream.total_out);
    return zlib.inflateEnd(&stream);
}

pub export fn nurl_sqlite_open(path: ?[*:0]const u8) c_longlong {
    const raw = c.calloc(1, @sizeOf(NurlSqliteDb)) orelse return 0;
    const db: *NurlSqliteDb = @ptrCast(@alignCast(raw));
    db.* = .{
        .db = null,
        .err_kind = nurl_sqlite_err_ok,
        .errmsg = null,
    };

    if (!runtime_features.have_sqlite3) {
        db.err_kind = nurl_sqlite_err_unsupported;
        return @intCast(@intFromPtr(db));
    }

    var sqlite_db: ?*sqlite.sqlite3 = null;
    const rc = sqlite.sqlite3_open(path orelse ":memory:", &sqlite_db);
    db.db = sqlite_db;
    if (rc != sqlite.SQLITE_OK) {
        db.err_kind = if (rc != 0) rc else 1;
        sqliteSetErrmsg(db);
    }
    return @intCast(@intFromPtr(db));
}

pub export fn nurl_sqlite_close(handle: c_longlong) void {
    const db = sqliteDbHandle(handle) orelse return;
    if (runtime_features.have_sqlite3) {
        if (db.db) |raw| _ = sqlite.sqlite3_close(raw);
    }
    if (db.errmsg) |msg| c.free(msg);
    c.free(db);
}

pub export fn nurl_sqlite_err_kind(handle: c_longlong) c_longlong {
    const db = sqliteDbHandle(handle) orelse return nurl_sqlite_err_unsupported;
    return db.err_kind;
}

pub export fn nurl_sqlite_errmsg(handle: c_longlong) ?[*:0]const u8 {
    const db = sqliteDbHandle(handle) orelse return "";
    return db.errmsg orelse "";
}

pub export fn nurl_sqlite_exec(handle: c_longlong, sql: ?[*:0]const u8) c_longlong {
    const db = sqliteDbHandle(handle) orelse return -1;
    if (!runtime_features.have_sqlite3 or db.db == null) {
        db.err_kind = nurl_sqlite_err_unsupported;
        return -1;
    }

    var err: [*c]u8 = null;
    const rc = sqlite.sqlite3_exec(db.db, sql orelse "", null, null, &err);
    if (rc != sqlite.SQLITE_OK) {
        db.err_kind = rc;
        if (db.errmsg) |prev| c.free(prev);
        db.errmsg = if (err != null) dupZ(@ptrCast(err)) else dupZ("sqlite_exec failed");
        if (err != null) sqlite.sqlite3_free(err);
        return -1;
    }

    db.err_kind = nurl_sqlite_err_ok;
    return sqlite.sqlite3_changes(db.db);
}

pub export fn nurl_sqlite_prepare(handle: c_longlong, sql: ?[*:0]const u8) c_longlong {
    const db = sqliteDbHandle(handle) orelse return 0;
    const raw = c.calloc(1, @sizeOf(NurlSqliteStmt)) orelse return 0;
    const stmt: *NurlSqliteStmt = @ptrCast(@alignCast(raw));
    stmt.* = .{
        .stmt = null,
        .err_kind = nurl_sqlite_err_ok,
        .text_buf = null,
        .bound_texts = null,
        .bound_text_count = 0,
        .bound_text_cap = 0,
    };

    if (!runtime_features.have_sqlite3 or db.db == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return @intCast(@intFromPtr(stmt));
    }

    const rc = sqlite.sqlite3_prepare_v2(db.db, sql orelse "", -1, &stmt.stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        stmt.err_kind = rc;
        db.err_kind = rc;
        sqliteSetErrmsg(db);
    }
    return @intCast(@intFromPtr(stmt));
}

pub export fn nurl_sqlite_stmt_err_kind(handle: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    return stmt.err_kind;
}

pub export fn nurl_sqlite_bind_int(handle: c_longlong, idx: c_longlong, val: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const rc = sqlite.sqlite3_bind_int64(stmt.stmt, @intCast(idx), @intCast(val));
    stmt.err_kind = if (rc == sqlite.SQLITE_OK) nurl_sqlite_err_ok else rc;
    return stmt.err_kind;
}

pub export fn nurl_sqlite_bind_text(handle: c_longlong, idx: c_longlong, val: ?[*:0]const u8) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const owned = dupZ(val orelse "") orelse {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    };
    if (!sqliteRememberBoundText(stmt, owned)) {
        c.free(owned);
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const rc = sqlite.sqlite3_bind_text(stmt.stmt, @intCast(idx), owned, -1, null);
    stmt.err_kind = if (rc == sqlite.SQLITE_OK) nurl_sqlite_err_ok else rc;
    return stmt.err_kind;
}

pub export fn nurl_sqlite_bind_null(handle: c_longlong, idx: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const rc = sqlite.sqlite3_bind_null(stmt.stmt, @intCast(idx));
    stmt.err_kind = if (rc == sqlite.SQLITE_OK) nurl_sqlite_err_ok else rc;
    return stmt.err_kind;
}

pub export fn nurl_sqlite_step(handle: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const rc = sqlite.sqlite3_step(stmt.stmt);
    if (rc == sqlite.SQLITE_ROW) {
        stmt.err_kind = nurl_sqlite_err_ok;
        return nurl_sqlite_err_row;
    }
    if (rc == sqlite.SQLITE_DONE) {
        stmt.err_kind = nurl_sqlite_err_ok;
        return nurl_sqlite_err_done;
    }
    stmt.err_kind = rc;
    return rc;
}

pub export fn nurl_sqlite_column_count(handle: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return 0;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) return 0;
    return sqlite.sqlite3_column_count(stmt.stmt);
}

pub export fn nurl_sqlite_column_type(handle: c_longlong, idx: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return 5;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) return 5;
    return sqlite.sqlite3_column_type(stmt.stmt, @intCast(idx));
}

pub export fn nurl_sqlite_column_int(handle: c_longlong, idx: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return 0;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) return 0;
    return @intCast(sqlite.sqlite3_column_int64(stmt.stmt, @intCast(idx)));
}

pub export fn nurl_sqlite_column_text(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    const stmt = sqliteStmtHandle(handle) orelse return "";
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) return "";
    const raw = sqlite.sqlite3_column_text(stmt.stmt, @intCast(idx));
    if (stmt.text_buf) |prev| c.free(prev);
    stmt.text_buf = if (raw) |text| dupZ(@ptrCast(text)) else dupZ("");
    return stmt.text_buf orelse "";
}

pub export fn nurl_sqlite_finalize(handle: c_longlong) void {
    const stmt = sqliteStmtHandle(handle) orelse return;
    if (runtime_features.have_sqlite3) {
        if (stmt.stmt) |raw| _ = sqlite.sqlite3_finalize(raw);
    }
    if (stmt.text_buf) |buf| c.free(buf);
    sqliteFreeBoundTexts(stmt);
    c.free(stmt);
}

pub export fn nurl_sqlite_reset(handle: c_longlong) c_longlong {
    const stmt = sqliteStmtHandle(handle) orelse return nurl_sqlite_err_unsupported;
    if (!runtime_features.have_sqlite3 or stmt.stmt == null) {
        stmt.err_kind = nurl_sqlite_err_unsupported;
        return stmt.err_kind;
    }
    const rc = sqlite.sqlite3_reset(stmt.stmt);
    if (rc == sqlite.SQLITE_OK) {
        _ = sqlite.sqlite3_clear_bindings(stmt.stmt);
        sqliteFreeBoundTexts(stmt);
    }
    stmt.err_kind = if (rc == sqlite.SQLITE_OK) nurl_sqlite_err_ok else rc;
    return stmt.err_kind;
}

fn nurlHttpWriteBody(ptr: [*c]u8, size: usize, nmemb: usize, user: ?*anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const buf: *NurlHttpBuf = @ptrCast(@alignCast(user orelse return 0));
    const src: [*]const u8 = @ptrCast(ptr);
    if (!httpBufAppend(buf, src, total)) return 0;
    return total;
}

fn nurlHttpWriteHeader(ptr: [*c]u8, size: usize, nmemb: usize, user: ?*anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const hdrs: *NurlHttpHeaderBuf = @ptrCast(@alignCast(user orelse return 0));
    const line: [*]u8 = @ptrCast(ptr);
    var n = total;
    while (n > 0 and (line[n - 1] == '\n' or line[n - 1] == '\r')) n -= 1;
    if (n == 0) return total;

    var colon_idx: ?usize = null;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (line[i] == ':') {
            colon_idx = i;
            break;
        }
    }
    const name_len = colon_idx orelse return total;
    var val_off = name_len + 1;
    while (val_off < n and (line[val_off] == ' ' or line[val_off] == '\t')) val_off += 1;
    const val_len = n - val_off;

    const name = c.malloc(name_len + 1) orelse return 0;
    const value = c.malloc(val_len + 1) orelse {
        c.free(name);
        return 0;
    };
    const name_bytes: [*]u8 = @ptrCast(name);
    const value_bytes: [*]u8 = @ptrCast(value);
    @memcpy(name_bytes[0..name_len], line[0..name_len]);
    @memcpy(value_bytes[0..val_len], line[val_off .. val_off + val_len]);
    name_bytes[name_len] = 0;
    value_bytes[val_len] = 0;
    if (!httpHeaderPush(hdrs, @ptrCast(name_bytes), @ptrCast(value_bytes))) {
        c.free(name);
        c.free(value);
        return 0;
    }
    return total;
}

fn nurlHttpStreamWriteBody(ptr: [*c]u8, size: usize, nmemb: usize, user: ?*anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const stream: *NurlHttpStream = @ptrCast(@alignCast(user orelse return 0));
    if (stream.status == 0 and stream.easy != null) {
        var http_code: c_long = 0;
        _ = curl.curl_easy_getinfo(stream.easy, curl.CURLINFO_RESPONSE_CODE, &http_code);
        stream.status = http_code;
    }
    stream.headers_done = 1;
    const src: [*]const u8 = @ptrCast(ptr);
    if (!httpBufAppend(&stream.body_buf, src, total)) return 0;
    return total;
}

fn nurlHttpStreamWriteHeader(ptr: [*c]u8, size: usize, nmemb: usize, user: ?*anyopaque) callconv(.c) usize {
    const total = size * nmemb;
    const stream: *NurlHttpStream = @ptrCast(@alignCast(user orelse return 0));
    const line: [*]u8 = @ptrCast(ptr);
    var n = total;
    while (n > 0 and (line[n - 1] == '\n' or line[n - 1] == '\r')) n -= 1;
    if (n == 0) {
        var http_code: c_long = 0;
        if (stream.easy != null) _ = curl.curl_easy_getinfo(stream.easy, curl.CURLINFO_RESPONSE_CODE, &http_code);
        if (http_code >= 100 and http_code < 200) {
            httpHeaderBufClear(&stream.hdr_buf);
        } else {
            stream.headers_done = 1;
            stream.status = http_code;
        }
        return total;
    }

    var colon_idx: ?usize = null;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (line[i] == ':') {
            colon_idx = i;
            break;
        }
    }
    const name_len = colon_idx orelse return total;
    var val_off = name_len + 1;
    while (val_off < n and (line[val_off] == ' ' or line[val_off] == '\t')) val_off += 1;
    const val_len = n - val_off;

    const name = c.malloc(name_len + 1) orelse return 0;
    const value = c.malloc(val_len + 1) orelse {
        c.free(name);
        return 0;
    };
    const name_bytes: [*]u8 = @ptrCast(name);
    const value_bytes: [*]u8 = @ptrCast(value);
    @memcpy(name_bytes[0..name_len], line[0..name_len]);
    @memcpy(value_bytes[0..val_len], line[val_off .. val_off + val_len]);
    name_bytes[name_len] = 0;
    value_bytes[val_len] = 0;
    if (!httpHeaderPush(&stream.hdr_buf, @ptrCast(name_bytes), @ptrCast(value_bytes))) {
        c.free(name);
        c.free(value);
        return 0;
    }
    return total;
}

fn httpStreamHandle(handle: c_longlong) ?*NurlHttpStream {
    if (handle == 0 or !runtime_features.have_libcurl or builtin.os.tag == .windows or builtin.os.tag == .wasi) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn httpStreamCaptureDone(stream: *NurlHttpStream) void {
    if (stream.multi == null or stream.easy == null) return;
    var msgs_left: c_int = 0;
    while (true) {
        const msg = curl.curl_multi_info_read(stream.multi, &msgs_left) orelse break;
        if (msg[0].msg == curl.CURLMSG_DONE) {
            var http_code: c_long = 0;
            _ = curl.curl_easy_getinfo(stream.easy, curl.CURLINFO_RESPONSE_CODE, &http_code);
            stream.status = http_code;
            stream.err_kind = httpMapErr(msg[0].data.result);
        }
    }
}

pub export fn nurl_http_perform_full_to(
    url: ?[*:0]const u8,
    method: ?[*:0]const u8,
    body: ?[*:0]const u8,
    headers_blob: ?[*:0]const u8,
    timeout_ms: c_longlong,
    connect_timeout_ms: c_longlong,
) c_longlong {
    if (!runtime_features.have_libcurl or builtin.os.tag == .windows or builtin.os.tag == .wasi) return 0;

    const raw = c.calloc(1, @sizeOf(NurlHttpResponse)) orelse return 0;
    const resp: *NurlHttpResponse = @ptrCast(@alignCast(raw));
    resp.* = .{
        .status = 0,
        .err_kind = nurl_http_err_ok,
        .header_count = 0,
        .headers = null,
        .body = null,
        .body_len = 0,
    };

    if (url == null or url.?[0] == 0) {
        resp.err_kind = nurl_http_err_invalid;
        resp.body = dupSliceZ("");
        return @intCast(@intFromPtr(resp));
    }

    const total_timeout: c_long = @intCast(if (timeout_ms > 0) timeout_ms else 30000);
    const connect_timeout: c_long = @intCast(if (connect_timeout_ms > 0) connect_timeout_ms else 10000);

    const easy = curl.curl_easy_init() orelse {
        resp.err_kind = nurl_http_err_other;
        resp.body = dupSliceZ("");
        return @intCast(@intFromPtr(resp));
    };
    defer curl.curl_easy_cleanup(easy);

    var body_buf = NurlHttpBuf{ .data = null, .len = 0, .cap = 0 };
    var hdr_buf = NurlHttpHeaderBuf{ .items = null, .len = 0, .cap = 0 };
    errdefer {
        if (body_buf.data) |buf| c.free(buf);
        httpHeaderBufFree(&hdr_buf);
    }

    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_URL, url.?);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_NOSIGNAL, @as(c_long, 1));
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_TIMEOUT_MS, total_timeout);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_CONNECTTIMEOUT_MS, connect_timeout);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_WRITEFUNCTION, &nurlHttpWriteBody);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_WRITEDATA, &body_buf);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_HEADERFUNCTION, &nurlHttpWriteHeader);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_HEADERDATA, &hdr_buf);
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_USERAGENT, "nurl-http/0.1");
    _ = curl.curl_easy_setopt(easy, curl.CURLOPT_ACCEPT_ENCODING, "");

    const req_headers = httpBuildSlist(headers_blob);
    defer if (req_headers != null) curl.curl_slist_free_all(req_headers);
    if (req_headers != null) _ = curl.curl_easy_setopt(easy, curl.CURLOPT_HTTPHEADER, req_headers);

    const m = method orelse "GET";
    if (std.mem.eql(u8, std.mem.span(m), "POST")) {
        _ = curl.curl_easy_setopt(easy, curl.CURLOPT_POST, @as(c_long, 1));
        _ = curl.curl_easy_setopt(easy, curl.CURLOPT_POSTFIELDS, body orelse "");
        _ = curl.curl_easy_setopt(easy, curl.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(std.mem.len(body orelse ""))));
    } else if (std.mem.eql(u8, std.mem.span(m), "PUT") or
        std.mem.eql(u8, std.mem.span(m), "DELETE") or
        std.mem.eql(u8, std.mem.span(m), "PATCH"))
    {
        _ = curl.curl_easy_setopt(easy, curl.CURLOPT_CUSTOMREQUEST, m);
        if (body != null and body.?[0] != 0) {
            _ = curl.curl_easy_setopt(easy, curl.CURLOPT_POSTFIELDS, body.?);
            _ = curl.curl_easy_setopt(easy, curl.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(std.mem.len(body.?))));
        }
    }

    const rc = curl.curl_easy_perform(easy);
    if (rc != curl.CURLE_OK) {
        resp.err_kind = httpMapErr(rc);
    } else {
        var http_code: c_long = 0;
        _ = curl.curl_easy_getinfo(easy, curl.CURLINFO_RESPONSE_CODE, &http_code);
        resp.status = http_code;
    }

    if (body_buf.data) |buf| {
        resp.body = buf;
        resp.body_len = @intCast(body_buf.len);
    } else {
        resp.body = dupSliceZ("");
        resp.body_len = 0;
    }
    resp.headers = hdr_buf.items;
    resp.header_count = @intCast(hdr_buf.len);
    return @intCast(@intFromPtr(resp));
}

pub export fn nurl_http_perform_full(
    url: ?[*:0]const u8,
    method: ?[*:0]const u8,
    body: ?[*:0]const u8,
    headers_blob: ?[*:0]const u8,
) c_longlong {
    return nurl_http_perform_full_to(url, method, body, headers_blob, 30000, 10000);
}

pub export fn nurl_http_stream_open_to(
    method: ?[*:0]const u8,
    url: ?[*:0]const u8,
    body: ?[*:0]const u8,
    headers_blob: ?[*:0]const u8,
    timeout_ms: c_longlong,
    connect_timeout_ms: c_longlong,
) c_longlong {
    if (!runtime_features.have_libcurl or builtin.os.tag == .windows or builtin.os.tag == .wasi) return 0;

    const raw = c.calloc(1, @sizeOf(NurlHttpStream)) orelse return 0;
    const stream: *NurlHttpStream = @ptrCast(@alignCast(raw));
    stream.* = .{
        .multi = curl.curl_multi_init(),
        .easy = curl.curl_easy_init(),
        .req_headers = null,
        .body_buf = .{ .data = null, .len = 0, .cap = 0 },
        .hdr_buf = .{ .items = null, .len = 0, .cap = 0 },
        .headers_done = 0,
        .still_running = 0,
        .finished = 0,
        .status = 0,
        .err_kind = nurl_http_err_ok,
    };

    if (stream.multi == null or stream.easy == null) {
        stream.err_kind = nurl_http_err_other;
        stream.finished = 1;
        return @intCast(@intFromPtr(stream));
    }

    const total_timeout: c_long = @intCast(if (timeout_ms > 0) timeout_ms else 30000);
    const connect_timeout: c_long = @intCast(if (connect_timeout_ms > 0) connect_timeout_ms else 10000);

    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_URL, url orelse "");
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_NOSIGNAL, @as(c_long, 1));
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_TIMEOUT_MS, total_timeout);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_CONNECTTIMEOUT_MS, connect_timeout);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_WRITEFUNCTION, &nurlHttpStreamWriteBody);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_WRITEDATA, stream);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_HEADERFUNCTION, &nurlHttpStreamWriteHeader);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_HEADERDATA, stream);
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_USERAGENT, "nurl-http/0.1");
    _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_ACCEPT_ENCODING, "");

    stream.req_headers = httpBuildSlist(headers_blob);
    if (stream.req_headers != null) {
        _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_HTTPHEADER, stream.req_headers);
    }

    const m = method orelse "GET";
    if (std.mem.eql(u8, std.mem.span(m), "POST")) {
        _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_POST, @as(c_long, 1));
        _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_POSTFIELDS, body orelse "");
        _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(std.mem.len(body orelse ""))));
    } else if (!std.mem.eql(u8, std.mem.span(m), "GET")) {
        _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_CUSTOMREQUEST, m);
        if (body != null and body.?[0] != 0) {
            _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_POSTFIELDS, body.?);
            _ = curl.curl_easy_setopt(stream.easy, curl.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(std.mem.len(body.?))));
        }
    }

    const mrc = curl.curl_multi_add_handle(stream.multi, stream.easy);
    if (mrc != curl.CURLM_OK) {
        stream.err_kind = nurl_http_err_other;
        stream.finished = 1;
        return @intCast(@intFromPtr(stream));
    }
    stream.still_running = 1;
    return @intCast(@intFromPtr(stream));
}

pub export fn nurl_http_stream_next(handle: c_longlong) ?[*:0]u8 {
    const stream = httpStreamHandle(handle) orelse return null;
    while (stream.body_buf.len == 0 and stream.finished == 0) {
        var still: c_int = 0;
        const mrc = curl.curl_multi_perform(stream.multi, &still);
        if (mrc != curl.CURLM_OK) {
            stream.err_kind = nurl_http_err_other;
            stream.finished = 1;
            break;
        }
        stream.still_running = still;
        if (still == 0) {
            httpStreamCaptureDone(stream);
            stream.finished = 1;
            break;
        }
        var numfds: c_int = 0;
        _ = curl.curl_multi_wait(stream.multi, null, 0, 100, &numfds);
    }
    if (stream.body_buf.len == 0) return null;
    const out = stream.body_buf.data;
    stream.body_buf.data = null;
    stream.body_buf.len = 0;
    stream.body_buf.cap = 0;
    return out;
}

pub export fn nurl_http_stream_status(handle: c_longlong) c_longlong {
    const stream = httpStreamHandle(handle) orelse return 0;
    return stream.status;
}

pub export fn nurl_http_stream_err_kind(handle: c_longlong) c_longlong {
    const stream = httpStreamHandle(handle) orelse return nurl_http_err_other;
    return stream.err_kind;
}

pub export fn nurl_http_stream_pump_headers(handle: c_longlong) c_longlong {
    const stream = httpStreamHandle(handle) orelse return 0;
    while (stream.headers_done == 0 and stream.finished == 0) {
        var still: c_int = 0;
        const mrc = curl.curl_multi_perform(stream.multi, &still);
        if (mrc != curl.CURLM_OK) {
            stream.err_kind = nurl_http_err_other;
            stream.finished = 1;
            break;
        }
        stream.still_running = still;
        if (still == 0) {
            httpStreamCaptureDone(stream);
            stream.finished = 1;
            break;
        }
        var numfds: c_int = 0;
        _ = curl.curl_multi_wait(stream.multi, null, 0, 100, &numfds);
    }
    return stream.status;
}

pub export fn nurl_http_stream_header_count(handle: c_longlong) c_longlong {
    const stream = httpStreamHandle(handle) orelse return 0;
    return @intCast(stream.hdr_buf.len);
}

pub export fn nurl_http_stream_header_name(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    const stream = httpStreamHandle(handle) orelse return "";
    if (idx < 0 or @as(usize, @intCast(idx)) >= stream.hdr_buf.len) return "";
    return stream.hdr_buf.items.?[@intCast(idx)].name orelse "";
}

pub export fn nurl_http_stream_header_value(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    const stream = httpStreamHandle(handle) orelse return "";
    if (idx < 0 or @as(usize, @intCast(idx)) >= stream.hdr_buf.len) return "";
    return stream.hdr_buf.items.?[@intCast(idx)].value orelse "";
}

pub export fn nurl_http_stream_close(handle: c_longlong) void {
    const stream = httpStreamHandle(handle) orelse return;
    if (stream.multi != null and stream.easy != null) {
        _ = curl.curl_multi_remove_handle(stream.multi, stream.easy);
    }
    if (stream.easy != null) curl.curl_easy_cleanup(stream.easy);
    if (stream.multi != null) _ = curl.curl_multi_cleanup(stream.multi);
    if (stream.req_headers != null) curl.curl_slist_free_all(stream.req_headers);
    httpHeaderBufFree(&stream.hdr_buf);
    if (stream.body_buf.data) |buf| c.free(buf);
    c.free(stream);
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

pub export fn nurl_csv_filter_float_gt_and_str_contains(
    content: ?[*]const u8,
    escape_buf: ?[*]const u8,
    flat_cells: ?[*]const c_longlong,
    row_starts: ?[*]c_longlong,
    row_lens: ?[*]c_longlong,
    n_rows: c_longlong,
    col_f: c_longlong,
    threshold: f64,
    col_s: c_longlong,
    needle: ?[*:0]const u8,
    nlen: c_longlong,
) c_longlong {
    if (col_f < 0 or col_s < 0 or n_rows <= 0) return 0;
    const raw = content orelse return 0;
    const cells = flat_cells orelse return 0;
    const starts = row_starts orelse return 0;
    const lens = row_lens orelse return 0;
    const needle_ptr = needle orelse return 0;
    if (nlen <= 0) return 0;
    const needle_slice = needle_ptr[0..@intCast(nlen)];

    var w: c_longlong = 0;
    var r: c_longlong = 0;
    while (r < n_rows) : (r += 1) {
        const row_first = starts[@intCast(r)];
        const row_count = lens[@intCast(r)];
        if (col_f >= row_count or col_s >= row_count) continue;

        const float_idx = row_first + col_f;
        const float_off = cells[@intCast(float_idx * 2)];
        const float_len = cells[@intCast(float_idx * 2 + 1)];
        if (float_len <= 0) continue;
        const float_ptr = csvCellPtr(raw, escape_buf, float_off) orelse continue;
        if (!(parseFloatRangeFast(float_ptr[0..@intCast(float_len)]) > threshold)) continue;

        const str_idx = row_first + col_s;
        const str_off = cells[@intCast(str_idx * 2)];
        const str_len = cells[@intCast(str_idx * 2 + 1)];
        if (str_len < nlen) continue;
        const str_ptr = csvCellPtr(raw, escape_buf, str_off) orelse continue;
        if (!csvCellContains(str_ptr, str_len, needle_slice)) continue;

        starts[@intCast(w)] = row_first;
        lens[@intCast(w)] = row_count;
        w += 1;
    }
    return w;
}

pub export fn nurl_csv_filter_typed_float_gt(
    typed_floats: ?[*]const f64,
    row_starts: ?[*]c_longlong,
    row_lens: ?[*]c_longlong,
    n_rows: c_longlong,
    threshold: f64,
) c_longlong {
    if (n_rows <= 0) return 0;
    const typed = typed_floats orelse return 0;
    const starts = row_starts orelse return 0;
    const lens = row_lens orelse return 0;

    var w: c_longlong = 0;
    var r: c_longlong = 0;
    while (r < n_rows) : (r += 1) {
        if (typed[@intCast(r)] > threshold) {
            starts[@intCast(w)] = starts[@intCast(r)];
            lens[@intCast(w)] = lens[@intCast(r)];
            w += 1;
        }
    }
    return w;
}

pub export fn nurl_csv_filter_float_gt(
    content: ?[*]const u8,
    escape_buf: ?[*]const u8,
    flat_cells: ?[*]const c_longlong,
    row_starts: ?[*]c_longlong,
    row_lens: ?[*]c_longlong,
    n_rows: c_longlong,
    col: c_longlong,
    threshold: f64,
) c_longlong {
    if (col < 0 or n_rows <= 0) return 0;
    const raw = content orelse return 0;
    const cells = flat_cells orelse return 0;
    const starts = row_starts orelse return 0;
    const lens = row_lens orelse return 0;

    var w: c_longlong = 0;
    var r: c_longlong = 0;
    while (r < n_rows) : (r += 1) {
        const row_first = starts[@intCast(r)];
        const row_count = lens[@intCast(r)];
        if (col >= row_count) continue;
        const cell_idx = row_first + col;
        const off = cells[@intCast(cell_idx * 2)];
        const len = cells[@intCast(cell_idx * 2 + 1)];
        if (len <= 0) continue;
        const src = csvCellPtr(raw, escape_buf, off) orelse continue;
        if (!(parseFloatRangeFast(src[0..@intCast(len)]) > threshold)) continue;
        starts[@intCast(w)] = row_first;
        lens[@intCast(w)] = row_count;
        w += 1;
    }
    return w;
}

pub export fn nurl_csv_filter_str_contains(
    content: ?[*]const u8,
    escape_buf: ?[*]const u8,
    flat_cells: ?[*]const c_longlong,
    row_starts: ?[*]c_longlong,
    row_lens: ?[*]c_longlong,
    n_rows: c_longlong,
    col: c_longlong,
    needle: ?[*:0]const u8,
    nlen: c_longlong,
) c_longlong {
    if (col < 0 or n_rows <= 0) return 0;
    const raw = content orelse return 0;
    const cells = flat_cells orelse return 0;
    const starts = row_starts orelse return 0;
    const lens = row_lens orelse return 0;
    const needle_ptr = needle orelse return n_rows;
    if (nlen <= 0) return n_rows;
    const needle_slice = needle_ptr[0..@intCast(nlen)];

    var w: c_longlong = 0;
    var r: c_longlong = 0;
    while (r < n_rows) : (r += 1) {
        const row_first = starts[@intCast(r)];
        const row_count = lens[@intCast(r)];
        if (col >= row_count) continue;
        const cell_idx = row_first + col;
        const off = cells[@intCast(cell_idx * 2)];
        const len = cells[@intCast(cell_idx * 2 + 1)];
        if (len < nlen) continue;
        const src = csvCellPtr(raw, escape_buf, off) orelse continue;
        if (!csvCellContains(src, len, needle_slice)) continue;
        starts[@intCast(w)] = row_first;
        lens[@intCast(w)] = row_count;
        w += 1;
    }
    return w;
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

pub export fn nurl_csv_n_rows_out() c_longlong {
    return g_csv_n_rows;
}

pub export fn nurl_csv_n_header_out() c_longlong {
    return g_csv_n_header;
}

pub export fn nurl_csv_n_cells_out() c_longlong {
    return g_csv_n_cells;
}

pub export fn nurl_csv_parse_arena(
    content: ?[*]const u8,
    clen: c_longlong,
    delim: c_longlong,
    flat_cells: ?[*]c_longlong,
    flat_cap: c_longlong,
    row_starts: ?[*]c_longlong,
    row_lens: ?[*]c_longlong,
    row_cap: c_longlong,
    header_cells: ?[*]c_longlong,
    header_cap: c_longlong,
) c_longlong {
    g_csv_n_rows = 0;
    g_csv_n_header = 0;
    g_csv_n_cells = 0;

    const raw = content orelse return 0;
    if (clen <= 0) return 0;
    if (flat_cap < 0 or row_cap < 0 or header_cap < 0) return -1;

    const body_pairs = flat_cells orelse return -1;
    const body_rows = row_starts orelse return -1;
    const body_lens = row_lens orelse return -1;
    const headers = header_cells orelse return -1;

    const d = asciiByte(delim) orelse return -1;
    const slice = raw[0..@intCast(clen)];

    var pos: usize = 0;
    var first_row = true;
    var n_cells: c_longlong = 0;
    var n_rows: c_longlong = 0;
    var n_hdr: c_longlong = 0;

    while (pos < slice.len) {
        const row_first_cell: c_longlong = @divTrunc(n_cells, 2);
        var row_n_cells: c_longlong = 0;
        var row_done = false;

        while (!row_done) {
            const field_start = pos;
            while (pos < slice.len) : (pos += 1) {
                const ch = slice[pos];
                if (ch == d or ch == '\n' or ch == '\r') break;
            }

            const cell_len: c_longlong = @intCast(pos - field_start);
            if (first_row) {
                if (n_hdr + 2 > header_cap) return -1;
                headers[@intCast(n_hdr)] = @intCast(field_start);
                headers[@intCast(n_hdr + 1)] = cell_len;
                n_hdr += 2;
            } else {
                if (n_cells + 2 > flat_cap) return -1;
                body_pairs[@intCast(n_cells)] = @intCast(field_start);
                body_pairs[@intCast(n_cells + 1)] = cell_len;
                n_cells += 2;
            }
            row_n_cells += 1;

            if (pos >= slice.len) {
                row_done = true;
                break;
            }

            const ch = slice[pos];
            if (ch == d) {
                pos += 1;
                continue;
            }

            pos += 1;
            if (ch == '\r' and pos < slice.len and slice[pos] == '\n') pos += 1;
            row_done = true;
        }

        const last_len = if (first_row)
            headers[@intCast(n_hdr - 1)]
        else
            body_pairs[@intCast(n_cells - 1)];
        const phantom = row_n_cells == 1 and last_len == 0 and pos >= slice.len;
        if (phantom) {
            if (first_row) n_hdr -= 2 else n_cells -= 2;
            continue;
        }

        if (first_row) {
            first_row = false;
            continue;
        }

        if (n_rows >= row_cap) return -1;
        body_rows[@intCast(n_rows)] = row_first_cell;
        body_lens[@intCast(n_rows)] = row_n_cells;
        n_rows += 1;
    }

    g_csv_n_rows = n_rows;
    g_csv_n_header = @divTrunc(n_hdr, 2);
    g_csv_n_cells = @divTrunc(n_cells, 2);
    return 0;
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
