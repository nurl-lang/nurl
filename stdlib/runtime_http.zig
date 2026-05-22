const std = @import("std");
const builtin = @import("builtin");
const runtime_features = @import("runtime_features_generated.zig");

const c = std.c;
const curl = if (runtime_features.have_libcurl and builtin.os.tag != .windows and builtin.os.tag != .wasi) @cImport({
    @cInclude("curl/curl.h");
}) else struct {};

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

const nurl_http_err_ok: c_longlong = 0;
const nurl_http_err_connect: c_longlong = 1;
const nurl_http_err_timeout: c_longlong = 2;
const nurl_http_err_tls: c_longlong = 3;
const nurl_http_err_dns: c_longlong = 4;
const nurl_http_err_invalid: c_longlong = 5;
const nurl_http_err_other: c_longlong = 6;

fn dupSliceZ(src: []const u8) ?[*:0]u8 {
    const raw = c.malloc(src.len + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return @ptrCast(buf);
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

fn httpResponseHandle(handle: c_longlong) ?*NurlHttpResponse {
    if (handle == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(handle)));
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

pub export fn nurl_http_response_status(handle: c_longlong) c_longlong {
    const resp = httpResponseHandle(handle) orelse return 0;
    return resp.status;
}

pub export fn nurl_http_response_err_kind(handle: c_longlong) c_longlong {
    const resp = httpResponseHandle(handle) orelse return nurl_http_err_other;
    return resp.err_kind;
}

pub export fn nurl_http_response_body(handle: c_longlong) ?[*:0]const u8 {
    const resp = httpResponseHandle(handle) orelse return "";
    return resp.body orelse "";
}

pub export fn nurl_http_response_body_len(handle: c_longlong) c_longlong {
    const resp = httpResponseHandle(handle) orelse return 0;
    return resp.body_len;
}

pub export fn nurl_http_response_header_count(handle: c_longlong) c_longlong {
    const resp = httpResponseHandle(handle) orelse return 0;
    return resp.header_count;
}

pub export fn nurl_http_response_header_name(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    const resp = httpResponseHandle(handle) orelse return "";
    if (idx < 0 or idx >= resp.header_count or resp.headers == null) return "";
    return resp.headers.?[@intCast(idx)].name orelse "";
}

pub export fn nurl_http_response_header_value(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    const resp = httpResponseHandle(handle) orelse return "";
    if (idx < 0 or idx >= resp.header_count or resp.headers == null) return "";
    return resp.headers.?[@intCast(idx)].value orelse "";
}

pub export fn nurl_http_response_free(handle: c_longlong) void {
    const resp = httpResponseHandle(handle) orelse return;
    if (resp.headers) |headers| {
        var i: usize = 0;
        while (i < @as(usize, @intCast(resp.header_count))) : (i += 1) {
            if (headers[i].name) |name| c.free(name);
            if (headers[i].value) |value| c.free(value);
        }
        c.free(@ptrCast(headers));
    }
    if (resp.body) |body| c.free(body);
    c.free(resp);
}
