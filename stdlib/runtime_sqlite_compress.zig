const std = @import("std");
const runtime_features = @import("runtime_features_generated.zig");

const zlib = if (runtime_features.have_zlib) @cImport({
    @cInclude("zlib.h");
}) else struct {};
const sqlite = if (runtime_features.have_sqlite3) @cImport({
    @cInclude("sqlite3.h");
}) else struct {};

const c = std.c;

const nurl_gzip_err_unsupported: c_int = -98;
const nurl_sqlite_err_ok: c_longlong = 0;
const nurl_sqlite_err_row: c_longlong = 100;
const nurl_sqlite_err_done: c_longlong = 101;
const nurl_sqlite_err_unsupported: c_longlong = 99;

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

fn dupZ(src: [*:0]const u8) ?[*:0]u8 {
    const len = std.mem.len(src);
    const raw = c.malloc(len + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(raw);
    @memcpy(buf[0..len], src[0..len]);
    buf[len] = 0;
    return @ptrCast(buf);
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
