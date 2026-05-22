const std = @import("std");
const builtin = @import("builtin");
const runtime_features = @import("runtime_features_generated.zig");

const c = std.c;

const have_posix_tcp = builtin.os.tag != .windows and builtin.os.tag != .wasi;
const have_posix_openssl = runtime_features.have_openssl and have_posix_tcp;
const net = if (have_posix_tcp) @cImport({
    @cInclude("sys/socket.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
}) else struct {};
const openssl = if (have_posix_openssl) @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
}) else struct {};
const pthread = if (have_posix_openssl) @cImport({
    @cInclude("pthread.h");
}) else struct {};

const posix = if (builtin.os.tag == .windows) struct {} else struct {
    extern "c" fn close(fd: c.fd_t) c_int;
};

const NurlTcpPrefix = extern struct {
    fd: c.fd_t,
    err_kind: c_longlong,
    kind: c_int,
    peer: ?[*:0]u8,
};

const NurlSniEntry = if (have_posix_openssl) extern struct {
    hostname: ?[*:0]u8,
    ctx: ?*openssl.SSL_CTX,
} else struct {};

const NurlTcp = if (have_posix_openssl) extern struct {
    fd: c.fd_t,
    err_kind: c_longlong,
    kind: c_int,
    peer: ?[*:0]u8,
    ssl_ctx: ?*openssl.SSL_CTX,
    ssl: ?*openssl.SSL,
    alpn_wire: ?[*]u8,
    alpn_wire_len: usize,
    sni_entries: ?[*]NurlSniEntry,
    sni_count: usize,
    sni_cap: usize,
    tls_lock: pthread.pthread_mutex_t,
    tls_lock_init: c_int,
} else extern struct {
    fd: c.fd_t,
    err_kind: c_longlong,
    kind: c_int,
    peer: ?[*:0]u8,
};

const nurl_net_err_ok: c_longlong = 0;
const nurl_net_err_bind: c_longlong = 1;
const nurl_net_err_addrinuse: c_longlong = 2;
const nurl_net_err_accept: c_longlong = 3;
const nurl_net_err_read: c_longlong = 4;
const nurl_net_err_write: c_longlong = 5;
const nurl_net_err_closed: c_longlong = 6;
const nurl_net_err_timeout: c_longlong = 7;
const nurl_net_err_other: c_longlong = 8;
const nurl_net_err_tls_ctx_init: c_longlong = 9;
const nurl_net_err_tls_cert_load: c_longlong = 10;
const nurl_net_err_tls_key_load: c_longlong = 11;
const nurl_net_err_tls_handshake: c_longlong = 12;
const nurl_invalid_sock: c.fd_t = -1;

var g_signal_listener: ?*volatile NurlTcpPrefix = null;

fn dupZ(src: [*:0]const u8) ?[*:0]u8 {
    const len = std.mem.len(src);
    const raw = c.malloc(len + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..len], src[0..len]);
    buf[len] = 0;
    return @ptrCast(buf);
}

fn dupSliceZ(src: []const u8) ?[*:0]u8 {
    const raw = c.malloc(src.len + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return @ptrCast(buf);
}

fn tcpPrefixHandle(handle: c_longlong) ?*NurlTcpPrefix {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn tcpHandle(handle: c_longlong) ?*NurlTcp {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

fn tcpAllocHandle(kind: c_int) ?*NurlTcp {
    const raw = c.calloc(1, @sizeOf(NurlTcp)) orelse return null;
    const tcp: *NurlTcp = @ptrCast(@alignCast(raw));
    tcp.fd = nurl_invalid_sock;
    tcp.err_kind = nurl_net_err_other;
    tcp.kind = kind;
    tcp.peer = null;
    return tcp;
}

fn netMapErrno(err_no: c_int, default_kind: c_longlong) c_longlong {
    if (err_no == @intFromEnum(c.E.AGAIN)) return nurl_net_err_timeout;
    if (@hasField(c.E, "WOULDBLOCK")) {
        const would_block = @intFromEnum(@field(c.E, "WOULDBLOCK"));
        if (would_block != @intFromEnum(c.E.AGAIN) and err_no == would_block) return nurl_net_err_timeout;
    }
    if (err_no == @intFromEnum(c.E.TIMEDOUT)) return nurl_net_err_timeout;
    if (err_no == @intFromEnum(c.E.ADDRINUSE)) return nurl_net_err_addrinuse;
    if (err_no == @intFromEnum(c.E.PIPE) or
        err_no == @intFromEnum(c.E.CONNRESET) or
        err_no == @intFromEnum(c.E.NOTCONN))
    {
        return nurl_net_err_closed;
    }
    return default_kind;
}

fn netFormatPeer(sa: *const net.sockaddr_in) ?[*:0]u8 {
    var ip_buf: [64]u8 = undefined;
    const ip_ptr = net.inet_ntop(c.AF.INET, @constCast(&sa.sin_addr), &ip_buf, ip_buf.len) orelse return dupSliceZ("");
    const ip = std.mem.span(ip_ptr);
    var peer_buf: [32]u8 = undefined;
    const peer = std.fmt.bufPrint(&peer_buf, "{s}:{d}", .{ ip, net.ntohs(sa.sin_port) }) catch return dupSliceZ("");
    return dupSliceZ(peer);
}

fn alpnPack(spec: ?[*:0]const u8, out_len: *usize) ?[*]u8 {
    out_len.* = 0;
    const raw = spec orelse return null;
    const text = std.mem.span(raw);
    if (text.len == 0) return null;

    const alloc = c.malloc(text.len + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(alloc);
    var written: usize = 0;

    var i: usize = 0;
    while (i < text.len) {
        while (i < text.len and text[i] == ' ') : (i += 1) {}
        if (i >= text.len) break;
        const start = i;
        while (i < text.len and text[i] != ' ') : (i += 1) {}
        const tok = text[start..i];
        if (tok.len == 0 or tok.len > 255) {
            c.free(alloc);
            return null;
        }
        buf[written] = @intCast(tok.len);
        written += 1;
        @memcpy(buf[written .. written + tok.len], tok);
        written += tok.len;
    }

    if (written == 0) {
        c.free(alloc);
        return null;
    }
    out_len.* = written;
    return buf;
}

fn tlsBuildCtx(tcp: ?*NurlTcp, cert_path: ?[*:0]const u8, key_path: ?[*:0]const u8) ?*openssl.SSL_CTX {
    if (!have_posix_openssl) return null;
    const cert = cert_path orelse {
        if (tcp) |value| value.err_kind = nurl_net_err_tls_cert_load;
        return null;
    };
    const key = key_path orelse {
        if (tcp) |value| value.err_kind = nurl_net_err_tls_key_load;
        return null;
    };

    const ctx = openssl.SSL_CTX_new(openssl.TLS_server_method()) orelse {
        if (tcp) |value| value.err_kind = nurl_net_err_tls_ctx_init;
        return null;
    };
    _ = openssl.SSL_CTX_set_min_proto_version(ctx, openssl.TLS1_2_VERSION);
    if (openssl.SSL_CTX_use_certificate_chain_file(ctx, cert) != 1) {
        openssl.SSL_CTX_free(ctx);
        if (tcp) |value| value.err_kind = nurl_net_err_tls_cert_load;
        return null;
    }
    if (openssl.SSL_CTX_use_PrivateKey_file(ctx, key, openssl.SSL_FILETYPE_PEM) != 1) {
        openssl.SSL_CTX_free(ctx);
        if (tcp) |value| value.err_kind = nurl_net_err_tls_key_load;
        return null;
    }
    if (openssl.SSL_CTX_check_private_key(ctx) != 1) {
        openssl.SSL_CTX_free(ctx);
        if (tcp) |value| value.err_kind = nurl_net_err_tls_key_load;
        return null;
    }
    return ctx;
}

fn tlsLockEnsure(tcp: *NurlTcp) void {
    if (!have_posix_openssl) return;
    if (tcp.tls_lock_init != 0) return;
    _ = pthread.pthread_mutex_init(&tcp.tls_lock, null);
    tcp.tls_lock_init = 1;
}

fn tlsLock(tcp: *NurlTcp) void {
    if (!have_posix_openssl) return;
    if (tcp.tls_lock_init == 0) return;
    _ = pthread.pthread_mutex_lock(&tcp.tls_lock);
}

fn tlsUnlock(tcp: *NurlTcp) void {
    if (!have_posix_openssl) return;
    if (tcp.tls_lock_init == 0) return;
    _ = pthread.pthread_mutex_unlock(&tcp.tls_lock);
}

fn hostnameIeq(a: ?[*:0]const u8, b: ?[*:0]const u8) bool {
    const lhs = a orelse return false;
    const rhs = b orelse return false;
    const a_bytes = std.mem.span(lhs);
    const b_bytes = std.mem.span(rhs);
    if (a_bytes.len != b_bytes.len) return false;
    var i: usize = 0;
    while (i < a_bytes.len) : (i += 1) {
        var ca = a_bytes[i];
        var cb = b_bytes[i];
        if (ca >= 'A' and ca <= 'Z') ca += 32;
        if (cb >= 'A' and cb <= 'Z') cb += 32;
        if (ca != cb) return false;
    }
    return true;
}

fn tlsInstallSniCallback(ctx: ?*openssl.SSL_CTX, tcp: *NurlTcp) void {
    if (!have_posix_openssl) return;
    if (ctx == null) return;
    _ = openssl.SSL_CTX_callback_ctrl(
        ctx,
        openssl.SSL_CTRL_SET_TLSEXT_SERVERNAME_CB,
        @ptrCast(&nurlTcpSniSelectCb),
    );
    _ = openssl.SSL_CTX_set_tlsext_servername_arg(ctx, tcp);
}

fn nurlTcpAlpnSelectCb(
    ssl: ?*openssl.SSL,
    out: [*c]?*const u8,
    outlen: [*c]u8,
    in: [*c]const u8,
    inlen: c_uint,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    _ = ssl;
    const tcp: *NurlTcp = @ptrCast(@alignCast(arg orelse return openssl.SSL_TLSEXT_ERR_NOACK));
    const wire = tcp.alpn_wire orelse return openssl.SSL_TLSEXT_ERR_NOACK;
    if (tcp.alpn_wire_len == 0) return openssl.SSL_TLSEXT_ERR_NOACK;

    const rv = openssl.SSL_select_next_proto(
        @ptrCast(out),
        @ptrCast(outlen),
        wire,
        @intCast(tcp.alpn_wire_len),
        in,
        inlen,
    );
    if (rv == openssl.OPENSSL_NPN_NEGOTIATED) return openssl.SSL_TLSEXT_ERR_OK;
    return openssl.SSL_TLSEXT_ERR_NOACK;
}

fn nurlTcpSniSelectCb(ssl: ?*openssl.SSL, al: [*c]c_int, arg: ?*anyopaque) callconv(.c) c_int {
    _ = al;
    if (!have_posix_openssl) return openssl.SSL_TLSEXT_ERR_OK;
    const tcp: *NurlTcp = @ptrCast(@alignCast(arg orelse return openssl.SSL_TLSEXT_ERR_OK));
    const server_name = openssl.SSL_get_servername(ssl, openssl.TLSEXT_NAMETYPE_host_name);
    if (server_name == null) return openssl.SSL_TLSEXT_ERR_OK;

    tlsLock(tcp);
    defer tlsUnlock(tcp);
    const entries_ptr = tcp.sni_entries orelse return openssl.SSL_TLSEXT_ERR_OK;
    const entries = entries_ptr[0..tcp.sni_count];
    for (entries) |entry| {
        if (hostnameIeq(entry.hostname, server_name)) {
            _ = openssl.SSL_set_SSL_CTX(ssl, entry.ctx);
            break;
        }
    }
    return openssl.SSL_TLSEXT_ERR_OK;
}

fn nurlSignalPosixHandler(sig: c.SIG) callconv(.c) void {
    _ = sig;
    const listener = g_signal_listener orelse return;
    if (listener.fd != nurl_invalid_sock) {
        _ = c.close(listener.fd);
        listener.fd = nurl_invalid_sock;
    }
}

fn nurl_tcp_listen_impl(host: ?[*:0]const u8, port: c_longlong, backlog: c_longlong) callconv(.c) c_longlong {
    const tcp = tcpAllocHandle(0) orelse return 0;
    if (port <= 0 or port > 65535) {
        tcp.err_kind = nurl_net_err_bind;
        return @intCast(@intFromPtr(tcp));
    }

    const effective_backlog: c_uint = @intCast(if (backlog <= 0) @as(c_longlong, 16) else backlog);
    const fd = c.socket(c.AF.INET, c.SOCK.STREAM, 0);
    if (fd == nurl_invalid_sock) {
        tcp.err_kind = nurl_net_err_bind;
        return @intCast(@intFromPtr(tcp));
    }

    var on: c_int = 1;
    _ = c.setsockopt(fd, c.SOL.SOCKET, c.SO.REUSEADDR, @ptrCast(&on), @sizeOf(c_int));

    var sa = std.mem.zeroes(net.sockaddr_in);
    if (@hasField(net.sockaddr_in, "sin_len")) sa.sin_len = @sizeOf(net.sockaddr_in);
    sa.sin_family = c.AF.INET;
    sa.sin_port = net.htons(@as(c_ushort, @intCast(port)));
    if (host == null or host.?[0] == 0) {
        sa.sin_addr = .{ .s_addr = net.htonl(net.INADDR_ANY) };
    } else if (net.inet_pton(c.AF.INET, host.?, &sa.sin_addr) != 1) {
        _ = posix.close(fd);
        tcp.err_kind = nurl_net_err_bind;
        return @intCast(@intFromPtr(tcp));
    }

    if (c.bind(fd, @ptrCast(&sa), @intCast(@sizeOf(net.sockaddr_in))) != 0) {
        tcp.err_kind = netMapErrno(c._errno().*, nurl_net_err_bind);
        _ = posix.close(fd);
        return @intCast(@intFromPtr(tcp));
    }
    if (c.listen(fd, effective_backlog) != 0) {
        tcp.err_kind = netMapErrno(c._errno().*, nurl_net_err_bind);
        _ = posix.close(fd);
        return @intCast(@intFromPtr(tcp));
    }

    tcp.fd = fd;
    tcp.err_kind = nurl_net_err_ok;
    return @intCast(@intFromPtr(tcp));
}

fn nurl_tcp_listen_tls_impl(
    host: ?[*:0]const u8,
    port: c_longlong,
    backlog: c_longlong,
    cert_path: ?[*:0]const u8,
    key_path: ?[*:0]const u8,
) callconv(.c) c_longlong {
    if (!have_posix_openssl) {
        const tcp = tcpAllocHandle(0) orelse return 0;
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return @intCast(@intFromPtr(tcp));
    }

    const handle = nurl_tcp_listen_impl(host, port, backlog);
    const tcp = tcpHandle(handle) orelse return handle;
    if (tcp.err_kind != nurl_net_err_ok) return handle;

    const ctx = tlsBuildCtx(tcp, cert_path, key_path) orelse {
        _ = posix.close(tcp.fd);
        tcp.fd = nurl_invalid_sock;
        return handle;
    };
    tcp.ssl_ctx = ctx;
    return handle;
}

fn nurl_tcp_listen_tls_alpn_impl(
    host: ?[*:0]const u8,
    port: c_longlong,
    backlog: c_longlong,
    cert_path: ?[*:0]const u8,
    key_path: ?[*:0]const u8,
    alpn_protocols: ?[*:0]const u8,
) callconv(.c) c_longlong {
    const handle = nurl_tcp_listen_tls_impl(host, port, backlog, cert_path, key_path);
    if (!have_posix_openssl) return handle;

    const tcp = tcpHandle(handle) orelse return handle;
    if (tcp.err_kind != nurl_net_err_ok or tcp.ssl_ctx == null) return handle;

    var wire_len: usize = 0;
    const wire = alpnPack(alpn_protocols, &wire_len) orelse return handle;
    if (wire_len == 0) {
        c.free(wire);
        return handle;
    }

    tcp.alpn_wire = wire;
    tcp.alpn_wire_len = wire_len;
    openssl.SSL_CTX_set_alpn_select_cb(tcp.ssl_ctx.?, nurlTcpAlpnSelectCb, tcp);
    return handle;
}

fn nurl_tcp_tls_add_sni_impl(
    handle: c_longlong,
    hostname: ?[*:0]const u8,
    cert_path: ?[*:0]const u8,
    key_path: ?[*:0]const u8,
) callconv(.c) c_longlong {
    const tcp = tcpHandle(handle) orelse return nurl_net_err_other;
    if (!have_posix_openssl) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }
    if (tcp.ssl_ctx == null) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }
    if (hostname == null or hostname.?[0] == 0) {
        tcp.err_kind = nurl_net_err_other;
        return nurl_net_err_other;
    }

    const ctx = tlsBuildCtx(tcp, cert_path, key_path) orelse return tcp.err_kind;
    tlsLockEnsure(tcp);
    tlsLock(tcp);
    defer tlsUnlock(tcp);

    if (tcp.sni_entries) |entries_ptr| {
        const entries = entries_ptr[0..tcp.sni_count];
        for (entries) |*entry| {
            if (hostnameIeq(entry.hostname, hostname)) {
                if (entry.ctx) |old| openssl.SSL_CTX_free(old);
                entry.ctx = ctx;
                tlsInstallSniCallback(tcp.ssl_ctx, tcp);
                tcp.err_kind = nurl_net_err_ok;
                return nurl_net_err_ok;
            }
        }
    }

    if (tcp.sni_count == tcp.sni_cap) {
        const new_cap: usize = if (tcp.sni_cap != 0) tcp.sni_cap * 2 else 4;
        const grown = c.realloc(tcp.sni_entries, new_cap * @sizeOf(NurlSniEntry)) orelse {
            openssl.SSL_CTX_free(ctx);
            tcp.err_kind = nurl_net_err_other;
            return nurl_net_err_other;
        };
        tcp.sni_entries = @ptrCast(@alignCast(grown));
        tcp.sni_cap = new_cap;
    }

    const hostname_copy = dupZ(hostname.?) orelse {
        openssl.SSL_CTX_free(ctx);
        tcp.err_kind = nurl_net_err_other;
        return nurl_net_err_other;
    };
    const entries = tcp.sni_entries.?;
    entries[tcp.sni_count] = .{ .hostname = hostname_copy, .ctx = ctx };
    tcp.sni_count += 1;
    tlsInstallSniCallback(tcp.ssl_ctx, tcp);
    tcp.err_kind = nurl_net_err_ok;
    return nurl_net_err_ok;
}

fn nurl_tcp_tls_reload_impl(
    handle: c_longlong,
    hostname: ?[*:0]const u8,
    cert_path: ?[*:0]const u8,
    key_path: ?[*:0]const u8,
) callconv(.c) c_longlong {
    const tcp = tcpHandle(handle) orelse return nurl_net_err_other;
    if (!have_posix_openssl) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }
    if (tcp.ssl_ctx == null) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }

    const new_ctx = tlsBuildCtx(tcp, cert_path, key_path) orelse return tcp.err_kind;
    tlsLockEnsure(tcp);
    tlsLock(tcp);
    defer tlsUnlock(tcp);

    if (hostname == null or hostname.?[0] == 0) {
        const old = tcp.ssl_ctx;
        tcp.ssl_ctx = new_ctx;
        if (tcp.alpn_wire != null and tcp.alpn_wire_len > 0) {
            openssl.SSL_CTX_set_alpn_select_cb(new_ctx, nurlTcpAlpnSelectCb, tcp);
        }
        if (tcp.sni_count > 0) tlsInstallSniCallback(new_ctx, tcp);
        if (old) |ctx| openssl.SSL_CTX_free(ctx);
        tcp.err_kind = nurl_net_err_ok;
        return nurl_net_err_ok;
    }

    if (tcp.sni_entries) |entries_ptr| {
        const entries = entries_ptr[0..tcp.sni_count];
        for (entries) |*entry| {
            if (hostnameIeq(entry.hostname, hostname)) {
                if (entry.ctx) |old| openssl.SSL_CTX_free(old);
                entry.ctx = new_ctx;
                tcp.err_kind = nurl_net_err_ok;
                return nurl_net_err_ok;
            }
        }
    }

    openssl.SSL_CTX_free(new_ctx);
    tcp.err_kind = nurl_net_err_other;
    return nurl_net_err_other;
}

fn nurl_tcp_tls_require_client_cert_impl(
    handle: c_longlong,
    ca_bundle_path: ?[*:0]const u8,
    strict: c_longlong,
) callconv(.c) c_longlong {
    const tcp = tcpHandle(handle) orelse return nurl_net_err_other;
    if (!have_posix_openssl) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }
    if (tcp.ssl_ctx == null) {
        tcp.err_kind = nurl_net_err_tls_ctx_init;
        return nurl_net_err_tls_ctx_init;
    }
    const ca_path = ca_bundle_path orelse {
        tcp.err_kind = nurl_net_err_tls_cert_load;
        return nurl_net_err_tls_cert_load;
    };
    if (openssl.SSL_CTX_load_verify_locations(tcp.ssl_ctx, ca_path, null) != 1) {
        tcp.err_kind = nurl_net_err_tls_cert_load;
        return nurl_net_err_tls_cert_load;
    }
    var mode: c_int = openssl.SSL_VERIFY_PEER;
    if (strict != 0) mode |= openssl.SSL_VERIFY_FAIL_IF_NO_PEER_CERT;
    openssl.SSL_CTX_set_verify(tcp.ssl_ctx, mode, null);
    const list = openssl.SSL_load_client_CA_file(ca_path);
    if (list != null) openssl.SSL_CTX_set_client_CA_list(tcp.ssl_ctx, list);
    tcp.err_kind = nurl_net_err_ok;
    return nurl_net_err_ok;
}

fn nurl_tcp_accept_impl(listener_handle: c_longlong) callconv(.c) c_longlong {
    const listener = tcpHandle(listener_handle);
    const conn = tcpAllocHandle(1) orelse return 0;
    if (listener == null or listener.?.fd == nurl_invalid_sock or listener.?.kind != 0) {
        conn.err_kind = nurl_net_err_accept;
        return @intCast(@intFromPtr(conn));
    }

    var peer = std.mem.zeroes(net.sockaddr_in);
    var peer_len: net.socklen_t = @intCast(@sizeOf(net.sockaddr_in));
    const fd = c.accept(listener.?.fd, @ptrCast(&peer), &peer_len);
    if (fd == nurl_invalid_sock) {
        conn.err_kind = netMapErrno(c._errno().*, nurl_net_err_accept);
        return @intCast(@intFromPtr(conn));
    }

    conn.fd = fd;
    conn.err_kind = nurl_net_err_ok;
    conn.peer = netFormatPeer(&peer);

    if (comptime have_posix_openssl) {
        if (listener.?.ssl_ctx) |ssl_ctx| {
            const ssl = openssl.SSL_new(ssl_ctx);
            if (ssl == null) {
                _ = posix.close(conn.fd);
                conn.fd = nurl_invalid_sock;
                conn.err_kind = nurl_net_err_tls_handshake;
                return @intCast(@intFromPtr(conn));
            }
            if (openssl.SSL_set_fd(ssl, @intCast(conn.fd)) != 1) {
                openssl.SSL_free(ssl);
                _ = posix.close(conn.fd);
                conn.fd = nurl_invalid_sock;
                conn.err_kind = nurl_net_err_tls_handshake;
                return @intCast(@intFromPtr(conn));
            }
            if (openssl.SSL_accept(ssl) != 1) {
                openssl.SSL_free(ssl);
                _ = posix.close(conn.fd);
                conn.fd = nurl_invalid_sock;
                conn.err_kind = nurl_net_err_tls_handshake;
                return @intCast(@intFromPtr(conn));
            }
            conn.ssl = ssl;
        }
    }

    return @intCast(@intFromPtr(conn));
}

fn nurl_tcp_peer_cert_subject_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    const tcp = tcpHandle(handle) orelse return dupSliceZ("") orelse "";
    if (!have_posix_openssl) return dupSliceZ("") orelse "";
    const ssl = tcp.ssl orelse return dupSliceZ("") orelse "";
    const cert = openssl.SSL_get_peer_certificate(ssl) orelse return dupSliceZ("") orelse "";
    defer openssl.X509_free(cert);

    const subject = openssl.X509_get_subject_name(cert) orelse return dupSliceZ("") orelse "";
    const line = openssl.X509_NAME_oneline(subject, null, 0);
    if (line == null) return dupSliceZ("") orelse "";
    defer openssl.CRYPTO_free(line, "runtime_tcp_tls.zig", 0);
    return dupZ(line) orelse dupSliceZ("") orelse "";
}

fn nurl_tcp_alpn_selected_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    const tcp = tcpHandle(handle) orelse return dupSliceZ("") orelse "";
    if (!have_posix_openssl) return dupSliceZ("") orelse "";
    const ssl = tcp.ssl orelse return dupSliceZ("") orelse "";

    var data: [*c]const u8 = null;
    var len: c_uint = 0;
    openssl.SSL_get0_alpn_selected(ssl, @ptrCast(&data), &len);
    if (data == null or len == 0) return dupSliceZ("") orelse "";
    return dupSliceZ(data[0..len]) orelse dupSliceZ("") orelse "";
}

fn nurl_tcp_read_impl(handle: c_longlong, buf: ?[*:0]const u8, n: c_longlong) callconv(.c) c_longlong {
    const tcp = tcpHandle(handle) orelse return -1;
    if (tcp.fd == nurl_invalid_sock) {
        tcp.err_kind = nurl_net_err_closed;
        return -1;
    }
    if (n <= 0) return 0;
    if (buf == null) {
        tcp.err_kind = nurl_net_err_read;
        return -1;
    }

    if (comptime have_posix_openssl) {
        if (tcp.ssl) |ssl| {
            const max_chunk: c_int = @intCast(@min(n, @as(c_longlong, 0x40000000)));
            const rd = openssl.SSL_read(ssl, @ptrCast(@constCast(buf.?)), max_chunk);
            if (rd > 0) {
                tcp.err_kind = nurl_net_err_ok;
                return rd;
            }
            const ssl_err = openssl.SSL_get_error(ssl, rd);
            if (ssl_err == openssl.SSL_ERROR_ZERO_RETURN) return 0;
            if (ssl_err == openssl.SSL_ERROR_WANT_READ or ssl_err == openssl.SSL_ERROR_WANT_WRITE) {
                tcp.err_kind = nurl_net_err_timeout;
                return -1;
            }
            tcp.err_kind = nurl_net_err_read;
            return -1;
        }
    }

    var rd: isize = 0;
    while (true) {
        rd = c.recv(tcp.fd, @ptrCast(@constCast(buf.?)), @intCast(n), 0);
        if (rd >= 0 or c._errno().* != @intFromEnum(c.E.INTR)) break;
    }
    if (rd > 0) {
        tcp.err_kind = nurl_net_err_ok;
        return @intCast(rd);
    }
    if (rd == 0) return 0;

    tcp.err_kind = netMapErrno(c._errno().*, nurl_net_err_read);
    return -1;
}

fn nurl_tcp_write_impl(handle: c_longlong, buf: ?[*:0]const u8, n: c_longlong) callconv(.c) c_longlong {
    const tcp = tcpHandle(handle) orelse return -1;
    if (tcp.fd == nurl_invalid_sock) {
        tcp.err_kind = nurl_net_err_closed;
        return -1;
    }
    if (n <= 0) return 0;
    if (buf == null) {
        tcp.err_kind = nurl_net_err_write;
        return -1;
    }

    if (comptime have_posix_openssl) {
        if (tcp.ssl) |ssl| {
            var total: c_longlong = 0;
            while (total < n) {
                const want = n - total;
                const chunk: c_int = @intCast(@min(want, @as(c_longlong, 0x40000000)));
                const wn = openssl.SSL_write(ssl, buf.? + @as(usize, @intCast(total)), chunk);
                if (wn <= 0) {
                    tcp.err_kind = nurl_net_err_write;
                    return -1;
                }
                total += wn;
            }
            tcp.err_kind = nurl_net_err_ok;
            return total;
        }
    }

    const send_flags: c_int = if (@hasDecl(c.MSG, "NOSIGNAL")) c.MSG.NOSIGNAL else 0;
    var total: c_longlong = 0;
    while (total < n) {
        var wn: isize = 0;
        while (true) {
            wn = c.send(tcp.fd, buf.? + @as(usize, @intCast(total)), @intCast(n - total), send_flags);
            if (wn >= 0 or c._errno().* != @intFromEnum(c.E.INTR)) break;
        }
        if (wn <= 0) {
            tcp.err_kind = netMapErrno(c._errno().*, nurl_net_err_write);
            return -1;
        }
        total += @intCast(wn);
    }
    tcp.err_kind = nurl_net_err_ok;
    return total;
}

fn nurl_tcp_close_impl(handle: c_longlong) callconv(.c) void {
    const tcp = tcpHandle(handle) orelse return;
    if (comptime have_posix_openssl) {
        if (tcp.ssl) |ssl| {
            _ = openssl.SSL_shutdown(ssl);
            openssl.SSL_free(ssl);
            tcp.ssl = null;
        }
        if (tcp.ssl_ctx) |ssl_ctx| {
            openssl.SSL_CTX_free(ssl_ctx);
            tcp.ssl_ctx = null;
        }
        if (tcp.alpn_wire) |wire| {
            c.free(wire);
            tcp.alpn_wire = null;
            tcp.alpn_wire_len = 0;
        }
        if (tcp.sni_entries) |entries_ptr| {
            const entries = entries_ptr[0..tcp.sni_count];
            for (entries) |entry| {
                if (entry.hostname) |hostname| c.free(hostname);
                if (entry.ctx) |ssl_ctx| openssl.SSL_CTX_free(ssl_ctx);
            }
            c.free(entries_ptr);
            tcp.sni_entries = null;
            tcp.sni_count = 0;
            tcp.sni_cap = 0;
        }
        if (tcp.tls_lock_init != 0) {
            _ = pthread.pthread_mutex_destroy(&tcp.tls_lock);
            tcp.tls_lock_init = 0;
        }
    }
    if (tcp.fd != nurl_invalid_sock) {
        _ = posix.close(tcp.fd);
        tcp.fd = nurl_invalid_sock;
    }
    if (tcp.peer) |peer| c.free(peer);
    c.free(tcp);
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

fn nurl_tcp_listen_stub_impl(host: ?[*:0]const u8, port: c_longlong, backlog: c_longlong) callconv(.c) c_longlong {
    _ = host;
    _ = port;
    _ = backlog;
    return 0;
}

fn nurl_tcp_listen_tls_stub_impl(
    host: ?[*:0]const u8,
    port: c_longlong,
    backlog: c_longlong,
    cert_path: ?[*:0]const u8,
    key_path: ?[*:0]const u8,
) callconv(.c) c_longlong {
    _ = host;
    _ = port;
    _ = backlog;
    _ = cert_path;
    _ = key_path;
    return 0;
}

fn nurl_tcp_accept_stub_impl(listener_handle: c_longlong) callconv(.c) c_longlong {
    _ = listener_handle;
    return 0;
}

fn nurl_tcp_read_stub_impl(handle: c_longlong, buf: ?[*:0]const u8, n: c_longlong) callconv(.c) c_longlong {
    _ = handle;
    _ = buf;
    _ = n;
    return -1;
}

fn nurl_tcp_write_stub_impl(handle: c_longlong, buf: ?[*:0]const u8, n: c_longlong) callconv(.c) c_longlong {
    _ = handle;
    _ = buf;
    _ = n;
    return -1;
}

fn nurl_tcp_close_stub_impl(handle: c_longlong) callconv(.c) void {
    _ = handle;
}

fn nurl_tcp_shutdown_stub_impl(handle: c_longlong) callconv(.c) void {
    _ = handle;
}

fn nurl_tcp_err_kind_stub_impl(handle: c_longlong) callconv(.c) c_longlong {
    _ = handle;
    return nurl_net_err_other;
}

fn nurl_tcp_peer_addr_stub_impl(handle: c_longlong) callconv(.c) ?[*:0]const u8 {
    _ = handle;
    return "";
}

fn nurl_tcp_set_timeout_stub_impl(handle: c_longlong, ms: c_longlong) callconv(.c) void {
    _ = handle;
    _ = ms;
}

fn nurl_signal_install_shutdown_stub_impl(listener_handle: c_longlong) callconv(.c) void {
    _ = listener_handle;
}

fn nurl_signal_trigger_shutdown_stub_impl() callconv(.c) void {}

comptime {
    if (have_posix_tcp) {
        @export(&nurl_tcp_listen_impl, .{ .name = "nurl_tcp_listen" });
        @export(&nurl_tcp_listen_tls_impl, .{ .name = "nurl_tcp_listen_tls" });
        @export(&nurl_tcp_listen_tls_alpn_impl, .{ .name = "nurl_tcp_listen_tls_alpn" });
        @export(&nurl_tcp_tls_add_sni_impl, .{ .name = "nurl_tcp_tls_add_sni" });
        @export(&nurl_tcp_tls_reload_impl, .{ .name = "nurl_tcp_tls_reload" });
        @export(&nurl_tcp_tls_require_client_cert_impl, .{ .name = "nurl_tcp_tls_require_client_cert" });
        @export(&nurl_tcp_accept_impl, .{ .name = "nurl_tcp_accept" });
        @export(&nurl_tcp_peer_cert_subject_impl, .{ .name = "nurl_tcp_peer_cert_subject" });
        @export(&nurl_tcp_alpn_selected_impl, .{ .name = "nurl_tcp_alpn_selected" });
        @export(&nurl_tcp_read_impl, .{ .name = "nurl_tcp_read" });
        @export(&nurl_tcp_write_impl, .{ .name = "nurl_tcp_write" });
        @export(&nurl_tcp_close_impl, .{ .name = "nurl_tcp_close" });
        @export(&nurl_tcp_shutdown_impl, .{ .name = "nurl_tcp_shutdown" });
        @export(&nurl_tcp_err_kind_impl, .{ .name = "nurl_tcp_err_kind" });
        @export(&nurl_tcp_peer_addr_impl, .{ .name = "nurl_tcp_peer_addr" });
        @export(&nurl_tcp_set_timeout_impl, .{ .name = "nurl_tcp_set_timeout" });
        @export(&nurl_signal_install_shutdown_impl, .{ .name = "nurl_signal_install_shutdown" });
        @export(&nurl_signal_trigger_shutdown_impl, .{ .name = "nurl_signal_trigger_shutdown" });
    } else if (builtin.os.tag == .wasi) {
        @export(&nurl_tcp_listen_stub_impl, .{ .name = "nurl_tcp_listen" });
        @export(&nurl_tcp_listen_tls_stub_impl, .{ .name = "nurl_tcp_listen_tls" });
        @export(&nurl_tcp_accept_stub_impl, .{ .name = "nurl_tcp_accept" });
        @export(&nurl_tcp_read_stub_impl, .{ .name = "nurl_tcp_read" });
        @export(&nurl_tcp_write_stub_impl, .{ .name = "nurl_tcp_write" });
        @export(&nurl_tcp_close_stub_impl, .{ .name = "nurl_tcp_close" });
        @export(&nurl_tcp_shutdown_stub_impl, .{ .name = "nurl_tcp_shutdown" });
        @export(&nurl_tcp_err_kind_stub_impl, .{ .name = "nurl_tcp_err_kind" });
        @export(&nurl_tcp_peer_addr_stub_impl, .{ .name = "nurl_tcp_peer_addr" });
        @export(&nurl_tcp_set_timeout_stub_impl, .{ .name = "nurl_tcp_set_timeout" });
        @export(&nurl_signal_install_shutdown_stub_impl, .{ .name = "nurl_signal_install_shutdown" });
        @export(&nurl_signal_trigger_shutdown_stub_impl, .{ .name = "nurl_signal_trigger_shutdown" });
    }
}
