const std = @import("std");

const c = std.c;

extern "c" fn atoll(nptr: [*:0]const u8) c_longlong;

const max_syms = 1_000_000;
const max_symtabs = 16;
const max_lex = 1024;
const max_cgs = 8;

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

const NurlCG = struct {
    reg: c_int,
    lbl: c_int,
};

var g_cgs: [max_cgs]?*NurlCG = .{null} ** max_cgs;
var g_cg_count: c_int = 0;
var g_lexers: [max_lex]?*NurlLex = .{null} ** max_lex;
var g_lex_count: c_int = 0;
var g_symtabs: [max_symtabs]?*NurlSymTab = .{null} ** max_symtabs;
var g_symtab_count: c_int = 0;
var g_last_type: [*:0]const u8 = "i64";
var g_last_type_owned = false;

fn fatalRuntime(msg: [*:0]const u8) noreturn {
    std.debug.print("{s}", .{std.mem.span(msg)});
    std.process.exit(1);
}

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

fn concatSlices(parts: []const []const u8) ?[*:0]u8 {
    var total: usize = 0;
    for (parts) |part| total += part.len;
    const raw = c.malloc(total + 1) orelse return null;
    const buf: [*]u8 = @ptrCast(raw);
    var cursor: usize = 0;
    for (parts) |part| {
        @memcpy(buf[cursor .. cursor + part.len], part);
        cursor += part.len;
    }
    buf[total] = 0;
    return @ptrCast(buf);
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

fn getCg(handle: c_longlong) *NurlCG {
    const idx: c_int = @intCast(handle - 1);
    if (idx < 0 or idx >= g_cg_count or g_cgs[@intCast(idx)] == null) {
        fatalRuntime("nurlc: invalid cg handle\n");
    }
    return g_cgs[@intCast(idx)].?;
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
        fatalRuntime("nurlc: too many codegen handles\n");
    }
    const raw = c.calloc(1, @sizeOf(NurlCG)) orelse fatalRuntime("nurlc: out of memory allocating cg handle\n");
    const cg: *NurlCG = @ptrCast(@alignCast(raw));
    const idx = g_cg_count;
    g_cgs[@intCast(idx)] = cg;
    g_cg_count += 1;
    return idx + 1;
}

pub export fn nurl_cg_reg(handle: c_longlong) ?[*:0]u8 {
    const cg = getCg(handle);
    var buf: [32]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{c}r{d}", .{ '%', cg.reg }) catch fatalRuntime("nurlc: cg reg format failed\n");
    cg.reg += 1;
    return dupSliceZ(out);
}

pub export fn nurl_cg_lbl(handle: c_longlong, hint: ?[*:0]const u8) ?[*:0]u8 {
    const cg = getCg(handle);
    const label_hint = hint orelse "";
    var buf: [256]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{s}_{d}", .{ std.mem.span(label_hint), cg.lbl }) catch fatalRuntime("nurlc: cg label format failed\n");
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
    const dup = dupZ(t orelse "") orelse fatalRuntime("nurlc: out of memory setting last type\n");
    if (g_last_type_owned) c.free(@constCast(g_last_type));
    g_last_type = dup;
    g_last_type_owned = true;
}
