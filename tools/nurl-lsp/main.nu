// tools/nurl-lsp/main.nu — NURL Language Server.
//
// Stdio JSON-RPC server. Phases shipped so far:
//   1. Protocol lifecycle (initialize / initialized / shutdown / exit).
//   2. Document tracking + compile-driven diagnostics.
//      * textDocument/didOpen / didChange / didClose
//      * On every store-or-update, write the buffer to a temp file,
//        run `build/nurlc` against it, parse stderr GCC-style lines
//        (`file:line:col: msg` and `... warning: msg`), and emit a
//        `textDocument/publishDiagnostics` notification per URI.
//   3. textDocument/definition (go-to-def).
//      * Lightweight per-line decl scanner indexes top-level @-fns,
//        struct/enum types + variants, and global `:` consts.
//      * Transitively walks `$`-imports starting from each didOpen
//        file so cross-file jumps land in the right place.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/json.nu`
$ `tools/nurl-lsp/jsonrpc.nu`

: ~ b g_shutdown_received F
: ~ b g_exit_requested F

// nurl_sym table doubling as a URI → text store. Key = LSP document
// URI (e.g. `file:///path/to/x.nu`); value = raw file content. nurl_sym
// copies both, so callers can free their inputs.
: ~ i g_docs 0

// name → "uri\tline" decl index, populated by the per-line scanner.
// Same-name collisions across files survive only as the last write —
// good enough for the MVP; namespacing improves this in a later
// iteration.
: ~ i g_defs 0

// Set of absolute filesystem paths already indexed in this session,
// for dedup during transitive `$`-import walks. Value is "1" for any
// member key.
: ~ i g_indexed 0

// Workspace root absolute path (no trailing slash). Captured from
// initialize.params.rootUri / .rootPath. Used to resolve relative
// `$`-import paths to absolute files.
: ~ i g_workspace_root_set 0

// Counter for unique temp-file names within a single server run. Per-
// pid is enough — we don't expect concurrent LSP sessions sharing a
// /tmp.
: ~ i g_tmp_counter 0

@ __build_capabilities → Json {
    : Json caps ( json_obj_new )
    // Full document sync: every didChange carries the whole buffer.
    ( json_obj_set caps `textDocumentSync` ( json_int 1 ) )
    ( json_obj_set caps `definitionProvider` ( json_bool T ) )
    ^ caps
}

@ __build_server_info → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit `nurl-lsp` ) )
    ( json_obj_set info `version` ( json_str_lit `0.4.1` ) )
    ^ info
}

@ __make_response Json id Json result → Json {
    : Json env ( json_obj_new )
    ( json_obj_set env `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set env `id` id )
    ( json_obj_set env `result` result )
    ^ env
}

@ __make_error Json id i code s msg → Json {
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int code ) )
    ( json_obj_set err `message` ( json_str_lit msg ) )
    : Json env ( json_obj_new )
    ( json_obj_set env `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set env `id` id )
    ( json_obj_set env `error` err )
    ^ env
}

@ __make_notification s method Json params → Json {
    : Json env ( json_obj_new )
    ( json_obj_set env `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set env `method` ( json_str_lit method ) )
    ( json_obj_set env `params` params )
    ^ env
}

// ── Diagnostic builders ─────────────────────────────────────────────
//
// LSP DiagnosticSeverity: 1=Error, 2=Warning, 3=Info, 4=Hint.
// We map the compiler's `warning:` prefix to Warning, everything else
// to Error.

@ __build_position i line i col → Json {
    : Json p ( json_obj_new )
    ( json_obj_set p `line` ( json_int line ) )
    ( json_obj_set p `character` ( json_int col ) )
    ^ p
}

@ __build_diagnostic i line i col i severity s msg → Json {
    // Single-character range — LSP requires both endpoints. The
    // compiler's caret points at one column; we emit a one-character
    // range so editors draw a single-glyph squiggle. Conversion:
    // compiler uses 1-based line/col, LSP uses 0-based.
    : i l0 - line 1
    : i c0 - col 1
    : Json d ( json_obj_new )
    : Json range ( json_obj_new )
    ( json_obj_set range `start` ( __build_position l0 c0 ) )
    ( json_obj_set range `end` ( __build_position l0 + c0 1 ) )
    ( json_obj_set d `range` range )
    ( json_obj_set d `severity` ( json_int severity ) )
    ( json_obj_set d `source` ( json_str_lit `nurl` ) )
    ( json_obj_set d `message` ( json_str_lit msg ) )
    ^ d
}

// ── Parse one diagnostic line ─────────────────────────────────────
//
// Input format (from nurlc's `die` / `warn`):
//   <path>:<line>:<col>: <msg>            (error)
//   <path>:<line>:<col>: warning: <msg>   (warning)
//
// Returns Some(Diagnostic-Json) on a successful parse, None for the
// follow-up "<source>" and "<pad>^" decoration lines or anything that
// doesn't match the prefix shape.

@ __parse_diag_line s line → ? Json {
    : i n ( nurl_str_len line )
    // Must contain at least two ':' separators; brute-force scan.
    : i lc1 ( __index_of_byte line 0 n 58 )    // first ':'
    ? < lc1 0 { ^ @ ?Json { F ( json_null ) } } {}
    : i lc2 ( __index_of_byte line + lc1 1 n 58 )
    ? < lc2 0 { ^ @ ?Json { F ( json_null ) } } {}
    : i lc3 ( __index_of_byte line + lc2 1 n 58 )
    ? < lc3 0 { ^ @ ?Json { F ( json_null ) } } {}

    // Line and column must parse as decimal ints.
    : String ls ( __substr line + lc1 1 lc2 )
    : !i ParseErr lr ( string_to_int ls )
    ( string_free ls )
    : i ln 0
    : b ok_ln ?? lr { T n → { = ln n  T } F _ → F }
    ? ! ok_ln { ^ @ ?Json { F ( json_null ) } } {}

    : String cs ( __substr line + lc2 1 lc3 )
    : !i ParseErr cr ( string_to_int cs )
    ( string_free cs )
    : i cn 0
    : b ok_cn ?? cr { T n → { = cn n  T } F _ → F }
    ? ! ok_cn { ^ @ ?Json { F ( json_null ) } } {}

    // Message starts after the third ':' plus a space (skip leading
    // whitespace defensively).
    : ~ i mstart + lc3 1
    ~ & < mstart n | == ( nurl_str_get line mstart ) 32 == ( nurl_str_get line mstart ) 9 {
        = mstart + mstart 1
    }
    : String msg_s ( __substr line mstart n )

    : i severity 1
    // Warning if the message text begins with "warning: ".
    ? & >= ( string_len msg_s ) 9 ( __string_starts_with msg_s `warning: ` ) {
        = severity 2
        // Strip the prefix from the surfaced message.
        : String stripped ( __substr ( string_data msg_s ) 9 ( string_len msg_s ) )
        ( string_free msg_s )
        : Json d ( __build_diagnostic ln cn severity ( string_data stripped ) )
        ( string_free stripped )
        ^ @ ?Json { T d }
    } {}

    : Json d ( __build_diagnostic ln cn severity ( string_data msg_s ) )
    ( string_free msg_s )
    ^ @ ?Json { T d }
}

// ── URI ↔ path conversion ────────────────────────────────────────
//
// LSP uses `file:///abs/path`. We strip the `file://` prefix to get
// an absolute filesystem path and prepend it back to build a URI.
// Non-file URIs (untitled:, etc.) round-trip as-is and won't index.

@ __uri_to_path s uri → String {
    : i n ( nurl_str_len uri )
    ? & >= n 7
      & == ( nurl_str_get uri 0 ) 102
      & == ( nurl_str_get uri 1 ) 105
      & == ( nurl_str_get uri 2 ) 108
      & == ( nurl_str_get uri 3 ) 101
      & == ( nurl_str_get uri 4 ) 58
      & == ( nurl_str_get uri 5 ) 47
        == ( nurl_str_get uri 6 ) 47
    {
        // Three slashes total: `file:///`. Skip the first two only,
        // keeping the third as the absolute-path leading slash.
        ^ ( __substr uri 7 n )
    } {}
    ^ ( string_from uri )
}

@ __path_to_uri s path → String {
    : String out ( string_with_cap + 7 ( nurl_str_len path ) )
    ( string_push_str out `file://` )
    ( string_push_str out path )
    ^ out
}

// ── Char-class predicates ───────────────────────────────────────

@ __is_ident_byte i c → b {
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ? == c 95 { ^ T } {}
    ^ F
}

@ __is_ident_start i c → b {
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 97 <= c 122 { ^ T } {}
    ? == c 95 { ^ T } {}
    ^ F
}

@ __is_space i c → b {
    | | | == c 32 == c 9 == c 13 == c 11
}

// ── Tiny string helpers (local-use only) ──────────────────────────

@ __index_of_byte s str i from i to i target → i {
    : ~ i k from
    ~ < k to {
        ? == ( nurl_str_get str k ) target { ^ k } {}
        = k + k 1
    }
    ^ - 0 1
}

@ __substr s str i from i to → String {
    : String out ( string_with_cap - to from )
    : ~ i k from
    ~ < k to {
        ( string_push_char out ( nurl_str_get str k ) )
        = k + k 1
    }
    ^ out
}

@ __string_starts_with String str s prefix → b {
    : i n ( nurl_str_len prefix )
    ? > n ( string_len str ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( string_get str k ) ( nurl_str_get prefix k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── Compile + collect diagnostics ─────────────────────────────────
//
// Writes `content` to a fresh temp file, invokes `build/nurlc <tmp>`,
// parses stderr line by line, returns a Json array of Diagnostics.
// `build/nurlc` is assumed to live relative to the LSP server's cwd
// (the editor typically opens it at the workspace root).

@ __compile_diagnostics s content → Json {
    = g_tmp_counter + g_tmp_counter 1
    : String tmp ( string_with_cap 64 )
    ( string_push_str tmp `/tmp/nurl-lsp-` )
    ( string_push_str tmp ( nurl_str_int g_tmp_counter ) )
    ( string_push_str tmp `.nu` )

    // Best-effort write. If this fails (out of /tmp space etc.) we
    // give up and surface an empty diagnostics array — the client
    // will keep last known errors but won't crash.
    : !v IoErr wr ( write_file ( string_data tmp ) content )
    ?? wr {
        T _ → {}
        F _ → {
            ( string_free tmp )
            ^ ( json_arr_new )
        }
    }

    : !Output ProcessErr pr ( process_run1 `build/nurlc` ( string_data tmp ) )
    : Json diags ( json_arr_new )
    ?? pr {
        F _ → { ( string_free tmp ) ^ diags }
        T out → {
            : s stderr_s ( output_stderr out )
            : i n ( nurl_str_len stderr_s )
            : ~ i pos 0
            ~ < pos n {
                : i nl ( __index_of_byte stderr_s pos n 10 )
                : i end ? < nl 0 n nl
                : String line ( __substr stderr_s pos end )
                : ?Json dr ( __parse_diag_line ( string_data line ) )
                ?? dr {
                    T d → ( json_arr_push diags d )
                    F _ → {}
                }
                ( string_free line )
                = pos ? < nl 0 n + nl 1
            }
            ( output_free out )
        }
    }

    // Remove temp file.
    : !v IoErr _rm ( file_delete ( string_data tmp ) )
    ?? _rm { T _ → {} F _ → {} }
    ( string_free tmp )
    ^ diags
}

// ── Decl scanner + index ──────────────────────────────────────────
//
// Line-oriented walk over the file content. Tracks brace depth so
// declarations inside struct bodies / fn bodies don't shadow the
// top-level scan. Recognises:
//   pub? @ name             → fn-decl
//   pub? : ~? Name { ...    → struct-decl (Name is IDENT)
//   pub? : | Name { ...     → enum-decl + every IDENT inside the body
//   pub? : ~? TYPE_KW NAME  → const-decl
//   & `lib` @ name          → FFI fn
//
// Each registered decl writes `g_defs[name] = "<uri>\t<line>"` (1-based
// line, matching the editor's view). Same-name collisions are
// last-write-wins for the MVP.

@ __register_def s name s uri i line → v {
    : String val ( string_with_cap 64 )
    ( string_push_str val uri )
    ( string_push_char val 9 )  // tab separator
    ( string_push_str val ( nurl_str_int line ) )
    ( nurl_sym_def g_defs name ( string_data val ) )
    ( string_free val )
}

// Skip leading whitespace; return new position.
@ __skip_ws s src i pos i n → i {
    : ~ i p pos
    ~ & < p n ( __is_space ( nurl_str_get src p ) ) {
        = p + p 1
    }
    ^ p
}

// Read an IDENT starting at pos. Returns its end position; the name
// itself is the slice [pos..end). Empty (end == pos) when the byte
// at pos isn't an ident-start.
@ __scan_ident s src i pos i n → i {
    ? >= pos n { ^ pos } {}
    : i first ( nurl_str_get src pos )
    ? ! ( __is_ident_start first ) { ^ pos } {}
    : ~ i p + pos 1
    ~ & < p n ( __is_ident_byte ( nurl_str_get src p ) ) {
        = p + p 1
    }
    ^ p
}

// Is `s` one of NURL's single-token type keywords? Used to
// distinguish `: TYPE_KW NAME val` (const) from `: NAME { ... }`
// (struct).
@ __is_type_kw s tok → b {
    ? != 0 ( nurl_str_eq tok `i` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `u` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `f` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `b` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `s` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `v` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `i8` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `i16` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `i32` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `u16` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `u32` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `u64` ) { ^ T } {}
    ? != 0 ( nurl_str_eq tok `f32` ) { ^ T } {}
    ^ F
}

// Scan `content` of `uri` and register every top-level decl in
// g_defs. The walker is character-oriented (not regex) so that
// brace-depth tracking + backtick strings + `//` comments interact
// correctly with decl boundaries.
@ __index_content s uri s content → v {
    : i n ( nurl_str_len content )
    : ~ i pos 0
    : ~ i line 1
    : ~ i depth 0       // {} brace depth
    : ~ i in_string 0   // 1 while inside `…` backtick string
    : ~ i in_comment 0  // 1 while inside // line comment
    : ~ i at_line_start 1
    ~ < pos n {
        : i c ( nurl_str_get content pos )
        ? != in_string 0 {
            ? == c 96 { = in_string 0 } {}
            ? == c 10 { = line + line 1  = at_line_start 1 } {}
            = pos + pos 1
        } {
            ? != in_comment 0 {
                ? == c 10 { = in_comment 0  = line + line 1  = at_line_start 1 } {}
                = pos + pos 1
            } {
                ? == c 96 { = in_string 1  = pos + pos 1  = at_line_start 0 } {
                    ? & == c 47 & < + pos 1 n == ( nurl_str_get content + pos 1 ) 47 {
                        = in_comment 1
                        = pos + pos 2
                    } {
                        ? == c 123 { = depth + depth 1  = pos + pos 1  = at_line_start 0 } {
                            ? == c 125 { = depth - depth 1  = pos + pos 1  = at_line_start 0 } {
                                ? == c 10 { = line + line 1  = at_line_start 1  = pos + pos 1 } {
                                    ? ( __is_space c ) { = pos + pos 1 } {
                                        // Non-whitespace, non-comment, non-string, top-level?
                                        ? & == depth 0 != at_line_start 0 {
                                            // Decl-start scan.
                                            : i sp ( __skip_ws content pos n )
                                            : ~ i p sp
                                            : ~ b pub_seen F
                                            // Optional `pub` keyword.
                                            : i ie ( __scan_ident content p n )
                                            ? > ie p {
                                                : String tok ( __substr content p ie )
                                                ? ( __string_starts_with tok `pub` ) {
                                                    ? == ie - ie p { = pub_seen T = p ( __skip_ws content ie n ) } {}
                                                } {}
                                                ( string_free tok )
                                            } {}
                                            // (pub-check above is robust only when token == "pub"; covered below.)
                                            ? < p n {
                                                : i c2 ( nurl_str_get content p )
                                                ? == c2 64 {
                                                    // `@ name` — fn decl
                                                    : i ai ( __skip_ws content + p 1 n )
                                                    : i ae ( __scan_ident content ai n )
                                                    ? > ae ai {
                                                        : String nm ( __substr content ai ae )
                                                        ( __register_def ( string_data nm ) uri line )
                                                        ( string_free nm )
                                                    } {}
                                                } {
                                                    ? == c2 58 {
                                                        // `:` — either struct, enum, or const.
                                                        : i cp ( __skip_ws content + p 1 n )
                                                        // Optional `~`
                                                        ? & < cp n == ( nurl_str_get content cp ) 126 {
                                                            = cp ( __skip_ws content + cp 1 n )
                                                        } {}
                                                        ? < cp n {
                                                            : i c3 ( nurl_str_get content cp )
                                                            ? == c3 124 {
                                                                // `: | Name { variants }` enum
                                                                : i ep ( __skip_ws content + cp 1 n )
                                                                : i ee ( __scan_ident content ep n )
                                                                ? > ee ep {
                                                                    : String nm ( __substr content ep ee )
                                                                    ( __register_def ( string_data nm ) uri line )
                                                                    ( string_free nm )
                                                                    // Walk the body for variant names.
                                                                    : i bb ( __skip_ws content ee n )
                                                                    ? & < bb n == ( nurl_str_get content bb ) 123 {
                                                                        : ~ i wp + bb 1
                                                                        : ~ i body_depth 1
                                                                        : ~ i body_line line
                                                                        ~ & < wp n > body_depth 0 {
                                                                            : i wc ( nurl_str_get content wp )
                                                                            ? == wc 123 { = body_depth + body_depth 1  = wp + wp 1 } {
                                                                                ? == wc 125 { = body_depth - body_depth 1  = wp + wp 1 } {
                                                                                    ? == wc 10 { = body_line + body_line 1  = wp + wp 1 } {
                                                                                        ? ( __is_space wc ) { = wp + wp 1 } {
                                                                                            : i ve ( __scan_ident content wp n )
                                                                                            ? > ve wp {
                                                                                                : String vn ( __substr content wp ve )
                                                                                                ( __register_def ( string_data vn ) uri body_line )
                                                                                                ( string_free vn )
                                                                                                = wp ve
                                                                                            } { = wp + wp 1 }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    } {}
                                                                } {}
                                                            } {
                                                                // `: IDENT …` — could be struct OR const.
                                                                : i ne ( __scan_ident content cp n )
                                                                ? > ne cp {
                                                                    : String tok ( __substr content cp ne )
                                                                    ? ( __is_type_kw ( string_data tok ) ) {
                                                                        // const: `: TYPE NAME ...`
                                                                        : i np ( __skip_ws content ne n )
                                                                        : i ke ( __scan_ident content np n )
                                                                        ? > ke np {
                                                                            : String nm ( __substr content np ke )
                                                                            ( __register_def ( string_data nm ) uri line )
                                                                            ( string_free nm )
                                                                        } {}
                                                                    } {
                                                                        // struct: `: Name { ... }`
                                                                        ( __register_def ( string_data tok ) uri line )
                                                                    }
                                                                    ( string_free tok )
                                                                } {}
                                                            }
                                                        } {}
                                                    } {
                                                        ? == c2 38 {
                                                            // `& \`lib\` @ name` FFI
                                                            : i ap ( __index_of_byte content + p 1 n 64 )
                                                            ? >= ap 0 {
                                                                : i nm_s ( __skip_ws content + ap 1 n )
                                                                : i nm_e ( __scan_ident content nm_s n )
                                                                ? > nm_e nm_s {
                                                                    : String nm ( __substr content nm_s nm_e )
                                                                    ( __register_def ( string_data nm ) uri line )
                                                                    ( string_free nm )
                                                                } {}
                                                            } {}
                                                        } {}
                                                    }
                                                }
                                            } {}
                                            = at_line_start 0
                                            = pos + pos 1
                                        } {
                                            = pos + pos 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Workspace + transitive import indexing ─────────────────────────

@ __set_workspace_root s root → v {
    ( nurl_sym_def g_indexed `:root` root )
    = g_workspace_root_set 1
}

@ __get_workspace_root → s {
    ^ ( nurl_sym_get g_indexed `:root` )
}

// Resolve a `$`-import path (e.g. `stdlib/core/string.nu`) against
// the workspace root. Strips a leading `./` (matches the compiler's
// `__norm_import_path` rule).
@ __resolve_import_path s rel → String {
    : i n ( nurl_str_len rel )
    : ~ i k 0
    ~ & >= n + k 2
      & == ( nurl_str_get rel k ) 46
        == ( nurl_str_get rel + k 1 ) 47
    { = k + k 2 }
    : String tail ( __substr rel k n )
    : s root ( __get_workspace_root )
    ? == 0 ( nurl_str_len root ) { ^ tail } {}
    : String out ( string_with_cap + + ( nurl_str_len root ) 1 ( nurl_str_len rel ) )
    ( string_push_str out root )
    ( string_push_char out 47 )
    ( string_push_str out ( string_data tail ) )
    ( string_free tail )
    ^ out
}

// Walk `content` and collect every `$ `path`` import as raw relative
// paths. Returns an OWNED Vec[String].
@ __collect_imports s content → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len content )
    : ~ i pos 0
    : ~ i in_string 0
    : ~ i in_comment 0
    : ~ i prev_was_dollar 0
    ~ < pos n {
        : i c ( nurl_str_get content pos )
        ? != in_string 0 {
            ? == c 96 { = in_string 0 } {}
            = pos + pos 1
        } {
            ? != in_comment 0 {
                ? == c 10 { = in_comment 0 } {}
                = pos + pos 1
            } {
                ? == c 96 {
                    ? != prev_was_dollar 0 {
                        // Capture path until matching backtick.
                        : ~ i ep + pos 1
                        ~ & < ep n != ( nurl_str_get content ep ) 96 {
                            = ep + ep 1
                        }
                        ? < ep n {
                            : String path ( __substr content + pos 1 ep )
                            ( vec_push [String] out path )
                            = pos + ep 1
                        } { = pos n }
                        = prev_was_dollar 0
                    } {
                        = in_string 1
                        = pos + pos 1
                    }
                } {
                    ? & == c 47 & < + pos 1 n == ( nurl_str_get content + pos 1 ) 47 {
                        = in_comment 1
                        = pos + pos 2
                        = prev_was_dollar 0
                    } {
                        ? == c 36 { = prev_was_dollar 1  = pos + pos 1 } {
                            ? ( __is_space c ) { = pos + pos 1 } {
                                = prev_was_dollar 0
                                = pos + pos 1
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// Index one absolute path. Reads the file, marks it indexed, scans
// for top-level decls, and recurses into its imports. Dedup via
// g_indexed so cycles + diamonds visit each file once.
@ __index_path s abs_path → v {
    : s marker ( nurl_sym_get g_indexed abs_path )
    ? == 0 ( nurl_str_len marker ) {
        ( nurl_sym_def g_indexed abs_path `1` )
        : s content ( nurl_read_file abs_path )
        ? > ( nurl_str_len content ) 0 {
            : String uri ( __path_to_uri abs_path )
            ( __index_content ( string_data uri ) content )
            ( string_free uri )
            : ( Vec String ) imports ( __collect_imports content )
            : i nimp ( vec_len [String] imports )
            : ~ i k 0
            ~ < k nimp {
                : ?String pk ( vec_get [String] imports k )
                ?? pk {
                    T pv → {
                        : String abs ( __resolve_import_path ( string_data pv ) )
                        ( __index_path ( string_data abs ) )
                        ( string_free abs )
                        ( string_free pv )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] imports )
        } {}
    } {}
}

// Index the given URI + its full import transitive closure. Resets
// dedup-set only for re-indexing of an already-known URI; new URIs
// are added incrementally.
@ __index_uri s uri → v {
    : String path ( __uri_to_path uri )
    // Force re-index of this file (didChange) by clearing its dedup
    // flag first; imports remain cached.
    ( nurl_sym_def g_indexed ( string_data path ) `` )
    ( __index_path ( string_data path ) )
    ( string_free path )
}

// ── Document state + handlers ─────────────────────────────────────

@ __publish_diagnostics s uri Json diags → v {
    : Json params ( json_obj_new )
    ( json_obj_set params `uri` ( json_str_lit uri ) )
    ( json_obj_set params `diagnostics` diags )
    : Json note ( __make_notification `textDocument/publishDiagnostics` params )
    ( write_message note )
    ( json_free note )
}

// Re-run diagnostics for `uri` using its current stored text. Called
// from didOpen / didChange after the store mutates.
@ __recompile_and_publish s uri → v {
    : s text ( nurl_sym_get g_docs uri )
    : Json diags ( __compile_diagnostics text )
    ( __publish_diagnostics uri diags )
}

// Extract `uri` from params.textDocument.uri. Returns "" on a
// malformed envelope.
@ __extract_uri Json params → s {
    : ?Json td ( json_obj_get params `textDocument` )
    ^ ?? td {
        T t → {
            : ?Json u ( json_obj_get t `uri` )
            ^ ?? u {
                T uj → ( json_str_data uj )
                F _ → ``
            }
        }
        F _ → ``
    }
}

@ __handle_did_open Json params → v {
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        : ?Json td ( json_obj_get params `textDocument` )
        ?? td {
            T t → {
                : ?Json txt ( json_obj_get t `text` )
                ?? txt {
                    T tj → {
                        ( nurl_sym_def g_docs uri ( json_str_data tj ) )
                        ( __index_uri uri )
                        ( __recompile_and_publish uri )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
    } {}
}

@ __handle_did_change Json params → v {
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        // Full-sync mode: params.contentChanges is a one-element array
        // whose [0].text is the entire new buffer. (Incremental sync
        // would deliver edit ranges; not enabled in v1.)
        : ?Json cc ( json_obj_get params `contentChanges` )
        ?? cc {
            T arr → {
                ? > ( json_arr_len arr ) 0 {
                    : ?Json e0 ( json_arr_get arr 0 )
                    ?? e0 {
                        T ej → {
                            : ?Json txt ( json_obj_get ej `text` )
                            ?? txt {
                                T tj → {
                                    ( nurl_sym_def g_docs uri ( json_str_data tj ) )
                                    ( __index_uri uri )
                                    ( __recompile_and_publish uri )
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
    } {}
}

@ __handle_did_close Json params → v {
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        // Clear stored content + clear client-side diagnostics.
        ( nurl_sym_def g_docs uri `` )
        ( __publish_diagnostics uri ( json_arr_new ) )
    } {}
}

// ── Position → IDENT-token ───────────────────────────────────────
//
// Given `(content, line, character)` (LSP coordinates: 0-based both
// axes), find the IDENT token under the cursor. Walks the file once
// to advance to the right line, then expands left + right on the
// ident-byte predicate. Returns None when the position falls on
// whitespace, punctuation, or past the end of file.

@ __token_at s content i line i col → ?String {
    : i n ( nurl_str_len content )
    // Advance to the start of `line`.
    : ~ i pos 0
    : ~ i cur_line 0
    ~ & < pos n < cur_line line {
        ? == ( nurl_str_get content pos ) 10 { = cur_line + cur_line 1 } {}
        = pos + pos 1
    }
    // pos is now at the start of `line`. Advance by `col` bytes,
    // stopping at newline.
    : i line_start pos
    : ~ i k 0
    ~ & & < pos n != ( nurl_str_get content pos ) 10 < k col {
        = pos + pos 1
        = k + k 1
    }
    ? >= pos n { ^ @ ?String { F ( string_new ) } } {}
    : i c ( nurl_str_get content pos )
    ? == c 10 { ^ @ ?String { F ( string_new ) } } {}
    ? ! ( __is_ident_byte c ) { ^ @ ?String { F ( string_new ) } } {}
    // Expand left.
    : ~ i lo pos
    ~ & > lo line_start ( __is_ident_byte ( nurl_str_get content - lo 1 ) ) {
        = lo - lo 1
    }
    // Expand right.
    : ~ i hi + pos 1
    ~ & < hi n ( __is_ident_byte ( nurl_str_get content hi ) ) {
        = hi + hi 1
    }
    ^ @ ?String { T ( __substr content lo hi ) }
}

// ── Definition handler ──────────────────────────────────────────
//
// `params.textDocument.uri` + `params.position.{line,character}`.
// Look up the IDENT under the cursor in the stored document, query
// g_defs, return an LSP Location. Null when there's no token or no
// match.

@ __handle_definition Json id Json params → v {
    : s uri ( __extract_uri params )
    : Json result ( json_null )
    ? > ( nurl_str_len uri ) 0 {
        : ?Json pos_o ( json_obj_get params `position` )
        ?? pos_o {
            T pos_j → {
                : ?Json ln_o ( json_obj_get pos_j `line` )
                : ?Json ch_o ( json_obj_get pos_j `character` )
                ?? ln_o {
                    T ln_j → {
                        ?? ch_o {
                            T ch_j → {
                                : ?i line_p ( json_num_as_i ln_j )
                                : ?i col_p ( json_num_as_i ch_j )
                                ?? line_p {
                                    T ln → {
                                        ?? col_p {
                                            T cn → {
                                                : s content ( nurl_sym_get g_docs uri )
                                                ? > ( nurl_str_len content ) 0 {
                                                    : ?String tk ( __token_at content ln cn )
                                                    ?? tk {
                                                        T name → {
                                                            : s defs_val ( nurl_sym_get g_defs ( string_data name ) )
                                                            ? > ( nurl_str_len defs_val ) 0 {
                                                                // value is "uri\tline"
                                                                : i n ( nurl_str_len defs_val )
                                                                : i tab ( __index_of_byte defs_val 0 n 9 )
                                                                ? >= tab 0 {
                                                                    : String def_uri ( __substr defs_val 0 tab )
                                                                    : String line_str ( __substr defs_val + tab 1 n )
                                                                    : !i ParseErr lr ( string_to_int line_str )
                                                                    ( string_free line_str )
                                                                    ?? lr {
                                                                        T def_line → {
                                                                            // Convert compiler 1-based line to LSP 0-based.
                                                                            : i lz - def_line 1
                                                                            : Json range ( json_obj_new )
                                                                            ( json_obj_set range `start` ( __build_position lz 0 ) )
                                                                            ( json_obj_set range `end` ( __build_position lz 0 ) )
                                                                            : Json loc ( json_obj_new )
                                                                            ( json_obj_set loc `uri` ( json_str_lit ( string_data def_uri ) ) )
                                                                            ( json_obj_set loc `range` range )
                                                                            = result loc
                                                                        }
                                                                        F _ → {}
                                                                    }
                                                                    ( string_free def_uri )
                                                                } {}
                                                            } {}
                                                            ( string_free name )
                                                        }
                                                        F _ → {}
                                                    }
                                                } {}
                                            }
                                            F _ → {}
                                        }
                                    }
                                    F _ → {}
                                }
                            }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
    } {}
    : Json resp ( __make_response id result )
    ( write_message resp )
    ( json_free resp )
}

// ── Request / notification dispatch ────────────────────────────────

@ __handle_initialize Json id Json params → v {
    // Capture rootUri / rootPath if the client sent one. Either field
    // is enough; rootUri is the modern form, rootPath is deprecated
    // but still seen from older clients.
    : ?Json ru ( json_obj_get params `rootUri` )
    ?? ru {
        T uj → {
            : String p ( __uri_to_path ( json_str_data uj ) )
            // Strip a trailing slash if present so resolve_import_path
            // can simply append `/<rel>`.
            : i ln ( string_len p )
            ? & > ln 0 == ( string_get p - ln 1 ) 47 {
                : String p2 ( __substr ( string_data p ) 0 - ln 1 )
                ( __set_workspace_root ( string_data p2 ) )
                ( string_free p2 )
            } {
                ( __set_workspace_root ( string_data p ) )
            }
            ( string_free p )
        }
        F _ → {
            : ?Json rp ( json_obj_get params `rootPath` )
            ?? rp {
                T sj → ( __set_workspace_root ( json_str_data sj ) )
                F _ → {}
            }
        }
    }

    : Json caps ( __build_capabilities )
    : Json info ( __build_server_info )
    : Json result ( json_obj_new )
    ( json_obj_set result `capabilities` caps )
    ( json_obj_set result `serverInfo` info )
    : Json resp ( __make_response id result )
    ( write_message resp )
    ( json_free resp )
}

@ __handle_shutdown Json id → v {
    = g_shutdown_received T
    : Json resp ( __make_response id ( json_null ) )
    ( write_message resp )
    ( json_free resp )
}

@ __handle_unknown_request Json id s method → v {
    : String msg ( string_with_cap 64 )
    ( string_push_str msg `method not found: ` )
    ( string_push_str msg method )
    : Json resp ( __make_error id - 0 32601 ( string_data msg ) )
    ( write_message resp )
    ( json_free resp )
    ( string_free msg )
}

@ __dispatch Json msg → v {
    : ?Json mo ( json_obj_get msg `method` )
    ?? mo {
        F _ → {}
        T method_j → {
            : s method ( json_str_data method_j )
            : ?Json id_o ( json_obj_get msg `id` )
            ?? id_o {
                T id_j → {
                    : Json id ( json_clone id_j )
                    ? ( nurl_str_eq method `initialize` ) {
                        : ?Json params_o ( json_obj_get msg `params` )
                        ?? params_o {
                            T params_j → ( __handle_initialize id params_j )
                            F _ → ( __handle_initialize id ( json_obj_new ) )
                        }
                    } {
                        ? ( nurl_str_eq method `shutdown` ) {
                            ( __handle_shutdown id )
                        } {
                            ? ( nurl_str_eq method `textDocument/definition` ) {
                                : ?Json params_o ( json_obj_get msg `params` )
                                ?? params_o {
                                    T params_j → ( __handle_definition id params_j )
                                    F _ → {
                                        : Json resp ( __make_response id ( json_null ) )
                                        ( write_message resp )
                                        ( json_free resp )
                                    }
                                }
                            } {
                                ( __handle_unknown_request id method )
                            }
                        }
                    }
                }
                F _ → {
                    // Notification — no response required.
                    ? ( nurl_str_eq method `exit` ) {
                        = g_exit_requested T
                    } {
                        ? ( nurl_str_eq method `initialized` ) {} {
                            : ?Json params_o ( json_obj_get msg `params` )
                            ?? params_o {
                                T params_j → {
                                    ? ( nurl_str_eq method `textDocument/didOpen` ) {
                                        ( __handle_did_open params_j )
                                    } {
                                        ? ( nurl_str_eq method `textDocument/didChange` ) {
                                            ( __handle_did_change params_j )
                                        } {
                                            ? ( nurl_str_eq method `textDocument/didClose` ) {
                                                ( __handle_did_close params_j )
                                            } {
                                                ( nurl_eprintln method )
                                            }
                                        }
                                    }
                                }
                                F _ → ( nurl_eprintln method )
                            }
                        }
                    }
                }
            }
        }
    }
}

@ main → i {
    = g_docs ( nurl_sym_new )
    = g_defs ( nurl_sym_new )
    = g_indexed ( nurl_sym_new )
    : ~ b done F
    ~ ! done {
        : ?Json mr ( read_message )
        ?? mr {
            F _ → { = done T }
            T msg → {
                ( __dispatch msg )
                ( json_free msg )
                ? g_exit_requested { = done T } {}
            }
        }
    }
    ? g_shutdown_received { ^ 0 } { ^ 1 }
}
