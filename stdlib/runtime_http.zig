const std = @import("std");
const builtin = @import("builtin");
const runtime_features = @import("runtime_features_generated.zig");

const c = std.c;
const have_windows_http = builtin.os.tag == .windows;
const have_libcurl_runtime = runtime_features.have_libcurl and builtin.os.tag != .windows and builtin.os.tag != .wasi;
const curl = if (have_libcurl_runtime) @cImport({
    @cInclude("curl/curl.h");
}) else struct {};
const winhttp = if (have_windows_http) @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("winhttp.h");
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

const NurlHttpStream = if (have_libcurl_runtime) struct {
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

fn httpBufReserve(buf: *NurlHttpBuf, need: usize) bool {
    if (need <= buf.cap) return true;
    var new_cap: usize = if (buf.cap != 0) buf.cap else 256;
    while (new_cap < need) new_cap *= 2;
    const resized = if (buf.data) |existing|
        c.realloc(existing, new_cap)
    else
        c.malloc(new_cap);
    if (resized == null) return false;
    buf.data = @ptrCast(@alignCast(resized));
    buf.cap = new_cap;
    return true;
}

fn httpBufAppend(buf: *NurlHttpBuf, src: [*]const u8, n: usize) bool {
    if (!httpBufReserve(buf, buf.len + n + 1)) return false;
    const data = buf.data.?;
    @memcpy(data[buf.len .. buf.len + n], src[0..n]);
    buf.len += n;
    data[buf.len] = 0;
    return true;
}

fn httpAllocResponse() ?*NurlHttpResponse {
    const raw = c.calloc(1, @sizeOf(NurlHttpResponse)) orelse return null;
    const resp: *NurlHttpResponse = @ptrCast(@alignCast(raw));
    resp.* = .{
        .status = 0,
        .err_kind = nurl_http_err_ok,
        .header_count = 0,
        .headers = null,
        .body = dupSliceZ(""),
        .body_len = 0,
    };
    return resp;
}

fn httpStubResponse(err_kind: c_longlong) c_longlong {
    const resp = httpAllocResponse() orelse return 0;
    resp.err_kind = err_kind;
    return @intCast(@intFromPtr(resp));
}

fn httpMapErr(rc: curl.CURLcode) c_longlong {
    if (!have_libcurl_runtime) return nurl_http_err_other;
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

const windows_http = if (have_windows_http) struct {
    const auto_length = std.math.maxInt(winhttp.DWORD);

    fn utf8ToWide(src: ?[*:0]const u8) ?[*:0]u16 {
        const text = src orelse return null;
        const needed = winhttp.MultiByteToWideChar(winhttp.CP_UTF8, 0, text, -1, null, 0);
        if (needed <= 0) return null;
        const raw = c.malloc(@as(usize, @intCast(needed)) * @sizeOf(u16)) orelse return null;
        const wide: [*]u16 = @ptrCast(@alignCast(raw));
        if (winhttp.MultiByteToWideChar(winhttp.CP_UTF8, 0, text, -1, @ptrCast(wide), needed) <= 0) {
            c.free(raw);
            return null;
        }
        return @ptrCast(wide);
    }

    fn wideToUtf8N(src: [*]const u16, len: usize) ?[*:0]u8 {
        if (len == 0) return dupSliceZ("");
        const needed = winhttp.WideCharToMultiByte(winhttp.CP_UTF8, 0, @ptrCast(src), @intCast(len), null, 0, null, null);
        if (needed <= 0) return dupSliceZ("");
        const raw = c.malloc(@as(usize, @intCast(needed)) + 1) orelse return dupSliceZ("");
        const bytes: [*]u8 = @ptrCast(raw);
        _ = winhttp.WideCharToMultiByte(winhttp.CP_UTF8, 0, @ptrCast(src), @intCast(len), @ptrCast(bytes), needed, null, null);
        bytes[@intCast(needed)] = 0;
        return @ptrCast(bytes);
    }

    fn mapErr(err_no: winhttp.DWORD) c_longlong {
        return switch (err_no) {
            winhttp.ERROR_WINHTTP_NAME_NOT_RESOLVED => nurl_http_err_dns,
            winhttp.ERROR_WINHTTP_CANNOT_CONNECT => nurl_http_err_connect,
            winhttp.ERROR_WINHTTP_TIMEOUT => nurl_http_err_timeout,
            winhttp.ERROR_WINHTTP_SECURE_FAILURE => nurl_http_err_tls,
            winhttp.ERROR_WINHTTP_INVALID_URL,
            winhttp.ERROR_WINHTTP_UNRECOGNIZED_SCHEME,
            => nurl_http_err_invalid,
            else => nurl_http_err_other,
        };
    }

    fn appendHeader(hdrs: *NurlHttpHeaderBuf, line: [*]const u16, len_in: usize) void {
        var n = len_in;
        while (n > 0 and (line[n - 1] == '\n' or line[n - 1] == '\r')) n -= 1;
        if (n == 0) return;

        var colon_idx: ?usize = null;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (line[i] == ':') {
                colon_idx = i;
                break;
            }
        }
        const name_len = colon_idx orelse return;
        var val_off = name_len + 1;
        while (val_off < n and (line[val_off] == ' ' or line[val_off] == '\t')) val_off += 1;
        const val_len = n - val_off;

        const name = wideToUtf8N(line, name_len) orelse return;
        const value = wideToUtf8N(line + val_off, val_len) orelse {
            c.free(name);
            return;
        };
        if (!httpHeaderPush(hdrs, name, value)) {
            c.free(name);
            c.free(value);
        }
    }

    fn perform(
        url: ?[*:0]const u8,
        method: ?[*:0]const u8,
        body: ?[*:0]const u8,
        headers_blob: ?[*:0]const u8,
        timeout_ms: c_longlong,
        connect_timeout_ms: c_longlong,
    ) c_longlong {
        const resp = httpAllocResponse() orelse return 0;
        if (url == null or url.?[0] == 0) {
            resp.err_kind = nurl_http_err_invalid;
            return @intCast(@intFromPtr(resp));
        }

        const total_timeout: c_int = @intCast(if (timeout_ms > 0) timeout_ms else 30000);
        const connect_timeout: c_int = @intCast(if (connect_timeout_ms > 0) connect_timeout_ms else 10000);

        const wurl = utf8ToWide(url) orelse {
            resp.err_kind = nurl_http_err_invalid;
            return @intCast(@intFromPtr(resp));
        };
        defer c.free(wurl);

        var uc: winhttp.URL_COMPONENTSW = std.mem.zeroes(winhttp.URL_COMPONENTSW);
        uc.dwStructSize = @sizeOf(winhttp.URL_COMPONENTSW);
        uc.dwSchemeLength = auto_length;
        uc.dwHostNameLength = auto_length;
        uc.dwUrlPathLength = auto_length;
        uc.dwExtraInfoLength = auto_length;
        if (winhttp.WinHttpCrackUrl(@ptrCast(wurl), 0, 0, &uc) == 0 or uc.dwHostNameLength == 0) {
            resp.err_kind = nurl_http_err_invalid;
            return @intCast(@intFromPtr(resp));
        }

        const host_len: usize = @intCast(uc.dwHostNameLength);
        const host_raw = c.malloc((host_len + 1) * @sizeOf(u16)) orelse {
            resp.err_kind = nurl_http_err_other;
            return @intCast(@intFromPtr(resp));
        };
        defer c.free(host_raw);
        const host: [*]u16 = @ptrCast(@alignCast(host_raw));
        const host_src: [*]const u16 = @ptrCast(uc.lpszHostName);
        @memcpy(host[0..host_len], host_src[0..host_len]);
        host[host_len] = 0;

        const url_path_len: usize = @intCast(uc.dwUrlPathLength);
        const extra_len: usize = @intCast(uc.dwExtraInfoLength);
        const path_len = url_path_len + extra_len;
        const path_raw = c.malloc((path_len + 2) * @sizeOf(u16)) orelse {
            resp.err_kind = nurl_http_err_other;
            return @intCast(@intFromPtr(resp));
        };
        defer c.free(path_raw);
        const path: [*]u16 = @ptrCast(@alignCast(path_raw));
        if (path_len == 0) {
            path[0] = '/';
            path[1] = 0;
        } else {
            const path_src: [*]const u16 = @ptrCast(uc.lpszUrlPath);
            @memcpy(path[0..url_path_len], path_src[0..url_path_len]);
            if (extra_len > 0) {
                const extra_src: [*]const u16 = @ptrCast(uc.lpszExtraInfo);
                @memcpy(path[url_path_len..path_len], extra_src[0..extra_len]);
            }
            path[path_len] = 0;
        }
        const is_https = uc.nScheme == winhttp.INTERNET_SCHEME_HTTPS;

        const user_agent = utf8ToWide("nurl-http/0.1") orelse {
            resp.err_kind = nurl_http_err_other;
            return @intCast(@intFromPtr(resp));
        };
        defer c.free(user_agent);

        const h_session = winhttp.WinHttpOpen(
            @ptrCast(user_agent),
            winhttp.WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            null,
            null,
            0,
        ) orelse {
            resp.err_kind = mapErr(winhttp.GetLastError());
            return @intCast(@intFromPtr(resp));
        };
        defer _ = winhttp.WinHttpCloseHandle(h_session);
        _ = winhttp.WinHttpSetTimeouts(h_session, connect_timeout, connect_timeout, total_timeout, total_timeout);

        const h_conn = winhttp.WinHttpConnect(h_session, @ptrCast(host), uc.nPort, 0) orelse {
            resp.err_kind = mapErr(winhttp.GetLastError());
            return @intCast(@intFromPtr(resp));
        };
        defer _ = winhttp.WinHttpCloseHandle(h_conn);

        const wmethod = utf8ToWide(method orelse "GET") orelse {
            resp.err_kind = nurl_http_err_other;
            return @intCast(@intFromPtr(resp));
        };
        defer c.free(wmethod);

        const req_flags: winhttp.DWORD = if (is_https) winhttp.WINHTTP_FLAG_SECURE else 0;
        const h_req = winhttp.WinHttpOpenRequest(
            h_conn,
            @ptrCast(wmethod),
            @ptrCast(path),
            null,
            null,
            null,
            req_flags,
        ) orelse {
            resp.err_kind = mapErr(winhttp.GetLastError());
            return @intCast(@intFromPtr(resp));
        };
        defer _ = winhttp.WinHttpCloseHandle(h_req);

        var redirect_policy: winhttp.DWORD = winhttp.WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
        _ = winhttp.WinHttpSetOption(h_req, winhttp.WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy, @sizeOf(winhttp.DWORD));

        if (headers_blob != null and headers_blob.?[0] != 0) {
            if (utf8ToWide(headers_blob)) |wide_headers| {
                defer c.free(wide_headers);
                _ = winhttp.WinHttpAddRequestHeaders(
                    h_req,
                    @ptrCast(wide_headers),
                    std.math.maxInt(winhttp.DWORD),
                    @as(winhttp.DWORD, @intCast(winhttp.WINHTTP_ADDREQ_FLAG_ADD)) |
                        @as(winhttp.DWORD, @bitCast(winhttp.WINHTTP_ADDREQ_FLAG_REPLACE)),
                );
            }
        }

        const method_text = std.mem.span(method orelse "GET");
        const body_allowed =
            std.mem.eql(u8, method_text, "POST") or
            std.mem.eql(u8, method_text, "PUT") or
            std.mem.eql(u8, method_text, "DELETE") or
            std.mem.eql(u8, method_text, "PATCH");
        const body_len: winhttp.DWORD = if (body_allowed and body != null) @intCast(std.mem.len(body.?)) else 0;
        const body_ptr = if (body_len != 0 and body != null)
            @as(?*anyopaque, @ptrCast(@constCast(body.?)))
        else
            winhttp.WINHTTP_NO_REQUEST_DATA;

        var ok = winhttp.WinHttpSendRequest(
            h_req,
            null,
            0,
            body_ptr,
            body_len,
            body_len,
            0,
        );
        if (ok != 0) ok = winhttp.WinHttpReceiveResponse(h_req, null);
        if (ok == 0) {
            resp.err_kind = mapErr(winhttp.GetLastError());
            return @intCast(@intFromPtr(resp));
        }

        var status_code: winhttp.DWORD = 0;
        var status_size: winhttp.DWORD = @sizeOf(winhttp.DWORD);
        _ = winhttp.WinHttpQueryHeaders(
            h_req,
            winhttp.WINHTTP_QUERY_STATUS_CODE | winhttp.WINHTTP_QUERY_FLAG_NUMBER,
            null,
            &status_code,
            &status_size,
            null,
        );
        resp.status = @intCast(status_code);

        var hdr_buf = NurlHttpHeaderBuf{ .items = null, .len = 0, .cap = 0 };
        var hdr_bytes: winhttp.DWORD = 0;
        _ = winhttp.WinHttpQueryHeaders(
            h_req,
            winhttp.WINHTTP_QUERY_RAW_HEADERS_CRLF,
            null,
            null,
            &hdr_bytes,
            null,
        );
        if (winhttp.GetLastError() == winhttp.ERROR_INSUFFICIENT_BUFFER and hdr_bytes > 0) {
            const hdr_raw = c.malloc(hdr_bytes);
            if (hdr_raw != null) {
                defer c.free(hdr_raw);
                if (winhttp.WinHttpQueryHeaders(
                    h_req,
                    winhttp.WINHTTP_QUERY_RAW_HEADERS_CRLF,
                    null,
                    hdr_raw,
                    &hdr_bytes,
                    null,
                ) != 0) {
                    const hdrs: [*]const u16 = @ptrCast(@alignCast(hdr_raw));
                    var wn: usize = @intCast(hdr_bytes / @sizeOf(u16));
                    if (wn > 0 and hdrs[wn - 1] == 0) wn -= 1;
                    var i: usize = 0;
                    while (i < wn) {
                        var j = i;
                        while (j < wn and hdrs[j] != '\n') : (j += 1) {}
                        var end = j;
                        if (end > i and hdrs[end - 1] == '\r') end -= 1;
                        appendHeader(&hdr_buf, hdrs + i, end - i);
                        i = j + 1;
                    }
                }
            }
        }

        var body_buf = NurlHttpBuf{ .data = null, .len = 0, .cap = 0 };
        while (true) {
            var avail: winhttp.DWORD = 0;
            if (winhttp.WinHttpQueryDataAvailable(h_req, &avail) == 0 or avail == 0) break;
            if (!httpBufReserve(&body_buf, body_buf.len + @as(usize, @intCast(avail)) + 1)) break;
            var got: winhttp.DWORD = 0;
            if (winhttp.WinHttpReadData(h_req, body_buf.data.? + body_buf.len, avail, &got) == 0 or got == 0) break;
            body_buf.len += @intCast(got);
            body_buf.data.?[body_buf.len] = 0;
        }

        if (resp.body) |body_text| c.free(body_text);
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
} else struct {};

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
    if (have_windows_http) {
        return windows_http.perform(url, method, body, headers_blob, timeout_ms, connect_timeout_ms);
    }
    if (!have_libcurl_runtime) return httpStubResponse(nurl_http_err_other);

    const resp = httpAllocResponse() orelse return 0;

    if (url == null or url.?[0] == 0) {
        resp.err_kind = nurl_http_err_invalid;
        return @intCast(@intFromPtr(resp));
    }

    const total_timeout: c_long = @intCast(if (timeout_ms > 0) timeout_ms else 30000);
    const connect_timeout: c_long = @intCast(if (connect_timeout_ms > 0) connect_timeout_ms else 10000);

    const easy = curl.curl_easy_init() orelse {
        resp.err_kind = nurl_http_err_other;
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
        if (resp.body) |body_text| c.free(body_text);
        resp.body = buf;
        resp.body_len = @intCast(body_buf.len);
    } else {
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
    if (!have_libcurl_runtime) return 0;

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
    if (!have_libcurl_runtime) return null;
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
    if (!have_libcurl_runtime) return 0;
    const stream = httpStreamHandle(handle) orelse return 0;
    return stream.status;
}

pub export fn nurl_http_stream_err_kind(handle: c_longlong) c_longlong {
    if (!have_libcurl_runtime) return nurl_http_err_other;
    const stream = httpStreamHandle(handle) orelse return nurl_http_err_other;
    return stream.err_kind;
}

pub export fn nurl_http_stream_pump_headers(handle: c_longlong) c_longlong {
    if (!have_libcurl_runtime) return 0;
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
    if (!have_libcurl_runtime) return 0;
    const stream = httpStreamHandle(handle) orelse return 0;
    return @intCast(stream.hdr_buf.len);
}

pub export fn nurl_http_stream_header_name(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    if (!have_libcurl_runtime) return "";
    const stream = httpStreamHandle(handle) orelse return "";
    if (idx < 0 or @as(usize, @intCast(idx)) >= stream.hdr_buf.len) return "";
    return stream.hdr_buf.items.?[@intCast(idx)].name orelse "";
}

pub export fn nurl_http_stream_header_value(handle: c_longlong, idx: c_longlong) ?[*:0]const u8 {
    if (!have_libcurl_runtime) return "";
    const stream = httpStreamHandle(handle) orelse return "";
    if (idx < 0 or @as(usize, @intCast(idx)) >= stream.hdr_buf.len) return "";
    return stream.hdr_buf.items.?[@intCast(idx)].value orelse "";
}

pub export fn nurl_http_stream_close(handle: c_longlong) void {
    if (!have_libcurl_runtime) return;
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
