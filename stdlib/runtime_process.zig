const std = @import("std");
const builtin = @import("builtin");

const c = std.c;

extern "c" fn execvp(file: [*:0]const u8, argv: [*c]?[*:0]const u8) c_int;
extern "c" fn signal(sig: c_int, handler: usize) usize;

const posix = if (builtin.os.tag == .windows) struct {} else struct {
    extern "c" fn close(fd: c.fd_t) c_int;
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

const nurl_proc_err_ok: c_longlong = 0;
const nurl_proc_err_notfound: c_longlong = 1;
const nurl_proc_err_exec_failed: c_longlong = 2;
const nurl_proc_err_io: c_longlong = 3;
const nurl_proc_err_other: c_longlong = 4;

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
        @export(&nurl_proc_run_impl, .{ .name = "nurl_proc_run" });
        @export(&nurl_proc_exit_code_impl, .{ .name = "nurl_proc_exit_code" });
        @export(&nurl_proc_err_kind_impl, .{ .name = "nurl_proc_err_kind" });
        @export(&nurl_proc_stdout_impl, .{ .name = "nurl_proc_stdout" });
        @export(&nurl_proc_stderr_impl, .{ .name = "nurl_proc_stderr" });
        @export(&nurl_proc_stdout_len_impl, .{ .name = "nurl_proc_stdout_len" });
        @export(&nurl_proc_stderr_len_impl, .{ .name = "nurl_proc_stderr_len" });
        @export(&nurl_proc_free_impl, .{ .name = "nurl_proc_free" });

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
