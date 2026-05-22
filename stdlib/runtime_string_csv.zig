const std = @import("std");

const c = std.c;

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

var g_last_parsed_float: f64 = 0.0;
var g_csv_row_n_cells: c_longlong = 0;
var g_csv_row_next_pos: c_longlong = 0;
var g_csv_n_rows: c_longlong = 0;
var g_csv_n_header: c_longlong = 0;
var g_csv_n_cells: c_longlong = 0;

fn setErrno(err: c.E) void {
    c._errno().* = @intFromEnum(err);
}

fn fatalRuntime(msg: [*:0]const u8) noreturn {
    std.debug.print("{s}", .{std.mem.span(msg)});
    std.process.exit(1);
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
    const out = std.fmt.bufPrint(&buf, "{d}", .{value}) catch fatalRuntime("nurlc: int format failed\n");
    return dupSliceZ(out);
}

pub export fn nurl_str_float(value: f64) ?[*:0]u8 {
    var buf: [128]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}", .{value}) catch fatalRuntime("nurlc: float format failed\n");
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
