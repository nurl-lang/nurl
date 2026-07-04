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
//   4. textDocument/rename.
//      * References sweep + declaration site, mapped to a
//        WorkspaceEdit; invalid targets / names → -32602.

$ `stdlib/core/string.nu`
$ `stdlib/core/symtab.nu`
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

// Newline-separated list of every document URI opened this session.
// g_docs is a sym map (not enumerable), so this parallel roster lets
// textDocument/references sweep all open buffers. Append-once (deduped
// in __track_doc_uri); didClose entries linger harmlessly — the sweep
// reads g_docs[uri] and skips a missing/empty body.
: ~ i g_doc_uris 0

// name → "uri\tline\tkind" decl index, populated by the per-line
// scanner. `kind` is the LSP SymbolKind integer: 12=Function,
// 23=Struct, 10=Enum, 22=EnumMember, 14=Constant. Same-name
// collisions across files survive only as the last write — good
// enough for the MVP; namespacing improves this in a later iteration.
: ~ i g_defs 0

// uri → TSV of (name, line, kind) triplets — one entry per decl
// found in that URI, in source order. Used by textDocument/
// documentSymbol so the editor outline view is a single sym_get
// + parse instead of scanning the file again.
: ~ i g_defs_by_uri 0

// Dual-purpose name-set + TSV iterator. Keys:
//   name → "1"   — membership marker for O(1) dedup
//   :list → tab-separated unique names — drives completion enumeration
// Two roles in one handle so iteration and existence both fit in
// the same sym table without inventing a second one.
: ~ i g_all_names 0

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
    ( json_obj_set caps `referencesProvider` ( json_bool T ) )
    ( json_obj_set caps `renameProvider` ( json_bool T ) )
    ( json_obj_set caps `documentSymbolProvider` ( json_bool T ) )
    ( json_obj_set caps `hoverProvider` ( json_bool T ) )
    // Completion: no trigger characters — VS Code invokes completion
    // on every keystroke by default. resolveProvider:false because we
    // pack everything (label, kind, detail) into the initial response.
    : Json comp ( json_obj_new )
    ( json_obj_set comp `resolveProvider` ( json_bool F ) )
    ( json_obj_set comp `triggerCharacters` ( json_arr_new ) )
    ( json_obj_set caps `completionProvider` comp )
    ( json_obj_set caps `documentFormattingProvider` ( json_bool T ) )
    ( json_obj_set caps `workspaceSymbolProvider` ( json_bool T ) )
    ( json_obj_set caps `foldingRangeProvider` ( json_bool T ) )
    ^ caps
}

@ __build_server_info → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit `nurl-lsp` ) )
    ( json_obj_set info `version` ( json_str_lit `0.7.0` ) )
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

@ __parse_diag_line s line → ?Json {
    : i n ( nurl_str_len line )
    // Must contain at least two ':' separators; brute-force scan.
    : i lc1 ( __index_of_byte line 0 n 58 )  // first ':'
    ? < lc1 0 { ^ @ ?Json { F } } {}
    : i lc2 ( __index_of_byte line + lc1 1 n 58 )
    ? < lc2 0 { ^ @ ?Json { F } } {}
    : i lc3 ( __index_of_byte line + lc2 1 n 58 )
    ? < lc3 0 { ^ @ ?Json { F } } {}

    // Line and column must parse as decimal ints.
    : String ls ( __substr line + lc1 1 lc2 )
    : !i ParseErr lr ( string_to_int ls )
    ( string_free ls )
    : ~ i ln 0
    : b ok_ln ?? lr { T n → { = ln n T } F _ → F }
    ? ! ok_ln { ^ @ ?Json { F } } {}

    : String cs ( __substr line + lc2 1 lc3 )
    : !i ParseErr cr ( string_to_int cs )
    ( string_free cs )
    : ~ i cn 0
    : b ok_cn ?? cr { T n → { = cn n T } F _ → F }
    ? ! ok_cn { ^ @ ?Json { F } } {}

    // Message starts after the third ':' plus a space (skip leading
    // whitespace defensively).
    : ~ i mstart + lc3 1
    ~ & < mstart n | == ( nurl_str_get line mstart ) 32 == ( nurl_str_get line mstart ) 9 {
        = mstart + mstart 1
    }
    : String msg_s ( __substr line mstart n )

    : ~ i severity 1
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

    // `--lint` enables the unused-binding / unused-private-function
    // warnings; they ride out on stderr in the same `file:line:col:
    // warning:` shape the diag parser already understands.
    : ( Vec s ) nc_args ( vec_with_cap [s] 2 )
    ( vec_push [s] nc_args `--lint` )
    ( vec_push [s] nc_args ( string_data tmp ) )
    : !Output ProcessErr pr ( process_run `build/nurlc` nc_args `` )
    ( vec_free [s] nc_args )
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

// LSP SymbolKind values used by this server:
//   12 = Function   23 = Struct   10 = Enum   22 = EnumMember
//   14 = Constant
@ __register_def s name s uri i line i kind → v {
    // g_defs entry: "uri\tline\tkind"
    : String val ( string_with_cap 64 )
    ( string_push_str val uri )
    ( string_push_char val 9 )
    ( string_push_str val ( nurl_str_int line ) )
    ( string_push_char val 9 )
    ( string_push_str val ( nurl_str_int kind ) )
    ( nurl_sym_def g_defs name ( string_data val ) )
    ( string_free val )

    // g_defs_by_uri entry: append "name\tline\tkind" triplet to the
    // existing TSV (or seed it). Same-line idempotence isn't worth the
    // bookkeeping — a re-index of an already-indexed URI is gated by
    // __index_uri clearing g_indexed[path] first, so a fresh listing
    // starts from an empty slot anyway.
    : s prev ( nurl_sym_get g_defs_by_uri uri )
    : String acc ( string_with_cap + ( nurl_str_len prev ) 64 )
    ? > ( nurl_str_len prev ) 0 {
        ( string_push_str acc prev )
        ( string_push_char acc 9 )
    } {}
    ( string_push_str acc name )
    ( string_push_char acc 9 )
    ( string_push_str acc ( nurl_str_int line ) )
    ( string_push_char acc 9 )
    ( string_push_str acc ( nurl_str_int kind ) )
    ( nurl_sym_def g_defs_by_uri uri ( string_data acc ) )
    ( string_free acc )

    // First-time-seen → append to the all-names TSV. Skipped on
    // duplicates so the iterator stays linear-bounded by distinct
    // names rather than register-call count.
    : s seen ( nurl_sym_get g_all_names name )
    ? == 0 ( nurl_str_len seen ) {
        ( nurl_sym_def g_all_names name `1` )
        : s prev_list ( nurl_sym_get g_all_names `:list` )
        : String list_acc ( string_with_cap + ( nurl_str_len prev_list ) + 8 ( nurl_str_len name ) )
        ? > ( nurl_str_len prev_list ) 0 {
            ( string_push_str list_acc prev_list )
            ( string_push_char list_acc 9 )
        } {}
        ( string_push_str list_acc name )
        ( nurl_sym_def g_all_names `:list` ( string_data list_acc ) )
        ( string_free list_acc )
    } {}
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
    : ~ i depth 0  // {} brace depth
    : ~ i in_string 0  // 1 while inside `…` backtick string
    : ~ i in_comment 0  // 1 while inside // line comment
    : ~ i at_line_start 1
    ~ < pos n {
        : i c ( nurl_str_get content pos )
        ? != in_string 0 {
            ? == c 96 { = in_string 0 } {}
            ? == c 10 { = line + line 1 = at_line_start 1 } {}
            = pos + pos 1
        } {
            ? != in_comment 0 {
                ? == c 10 { = in_comment 0 = line + line 1 = at_line_start 1 } {}
                = pos + pos 1
            } {
                ? == c 96 { = in_string 1 = pos + pos 1 = at_line_start 0 } {
                    ? & == c 47 & < + pos 1 n == ( nurl_str_get content + pos 1 ) 47 {
                        = in_comment 1
                        = pos + pos 2
                    } {
                        ? == c 123 { = depth + depth 1 = pos + pos 1 = at_line_start 0 } {
                            ? == c 125 { = depth - depth 1 = pos + pos 1 = at_line_start 0 } {
                                ? == c 10 { = line + line 1 = at_line_start 1 = pos + pos 1 } {
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
                                                    // `@ name` — fn decl (SymbolKind 12 Function)
                                                    : i ai ( __skip_ws content + p 1 n )
                                                    : i ae ( __scan_ident content ai n )
                                                    ? > ae ai {
                                                        : String nm ( __substr content ai ae )
                                                        ( __register_def ( string_data nm ) uri line 12 )
                                                        ( string_free nm )
                                                    } {}
                                                } {
                                                    ? == c2 58 {
                                                        // `:` — either struct, enum, or const.
                                                        : ~ i cp ( __skip_ws content + p 1 n )
                                                        // Optional `~`
                                                        ? & < cp n == ( nurl_str_get content cp ) 126 {
                                                            = cp ( __skip_ws content + cp 1 n )
                                                        } {}
                                                        ? < cp n {
                                                            : i c3 ( nurl_str_get content cp )
                                                            ? == c3 124 {
                                                                // `: | Name { variants }` enum (SymbolKind 10)
                                                                : i ep ( __skip_ws content + cp 1 n )
                                                                : i ee ( __scan_ident content ep n )
                                                                ? > ee ep {
                                                                    : String nm ( __substr content ep ee )
                                                                    ( __register_def ( string_data nm ) uri line 10 )
                                                                    ( string_free nm )
                                                                    // Walk the body for variant names.
                                                                    : i bb ( __skip_ws content ee n )
                                                                    ? & < bb n == ( nurl_str_get content bb ) 123 {
                                                                        : ~ i wp + bb 1
                                                                        : ~ i body_depth 1
                                                                        : ~ i body_line line
                                                                        ~ & < wp n > body_depth 0 {
                                                                            : i wc ( nurl_str_get content wp )
                                                                            ? == wc 123 { = body_depth + body_depth 1 = wp + wp 1 } {
                                                                                ? == wc 125 { = body_depth - body_depth 1 = wp + wp 1 } {
                                                                                    ? == wc 10 { = body_line + body_line 1 = wp + wp 1 } {
                                                                                        ? ( __is_space wc ) { = wp + wp 1 } {
                                                                                            : i ve ( __scan_ident content wp n )
                                                                                            ? > ve wp {
                                                                                                : String vn ( __substr content wp ve )
                                                                                                // SymbolKind 22 EnumMember
                                                                                                ( __register_def ( string_data vn ) uri body_line 22 )
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
                                                                        // const: `: TYPE NAME ...` (SymbolKind 14)
                                                                        : i np ( __skip_ws content ne n )
                                                                        : i ke ( __scan_ident content np n )
                                                                        ? > ke np {
                                                                            : String nm ( __substr content np ke )
                                                                            ( __register_def ( string_data nm ) uri line 14 )
                                                                            ( string_free nm )
                                                                        } {}
                                                                    } {
                                                                        // struct: `: Name { ... }` (SymbolKind 23)
                                                                        ( __register_def ( string_data tok ) uri line 23 )
                                                                    }
                                                                    ( string_free tok )
                                                                } {}
                                                            }
                                                        } {}
                                                    } {
                                                        ? == c2 38 {
                                                            // `& \`lib\` @ name` FFI (SymbolKind 12 Function)
                                                            : i ap ( __index_of_byte content + p 1 n 64 )
                                                            ? >= ap 0 {
                                                                : i nm_s ( __skip_ws content + ap 1 n )
                                                                : i nm_e ( __scan_ident content nm_s n )
                                                                ? > nm_e nm_s {
                                                                    : String nm ( __substr content nm_s nm_e )
                                                                    ( __register_def ( string_data nm ) uri line 12 )
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
                        ? == c 36 { = prev_was_dollar 1 = pos + pos 1 } {
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

// Best-effort read for the indexer / hover paths: the compiler's
// `nurl_read_file` calls `exit(1)` on a missing file (a missing import
// is fatal to a COMPILE, but must never be fatal to the language
// server — e.g. a package whose registry deps under `deps/` aren't
// installed yet). Probe with `file_exists` first; return "" on a miss
// so the existing `nurl_str_len > 0` guards skip it gracefully.
@ __read_if_exists s path → s {
    ? ( file_exists path ) { ^ ( nurl_read_file path ) } {}
    ^ ``
}

// Index one absolute path. Reads the file, marks it indexed, scans
// for top-level decls, and recurses into its imports. Dedup via
// g_indexed so cycles + diamonds visit each file once.
@ __index_path s abs_path → v {
    : s marker ( nurl_sym_get g_indexed abs_path )
    ? == 0 ( nurl_str_len marker ) {
        ( nurl_sym_def g_indexed abs_path `1` )
        : s content ( __read_if_exists abs_path )
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
    // flag first; imports remain cached. Also reset the TSV slot so
    // re-indexing replaces rather than appends — otherwise outline
    // entries would double on every keystroke.
    ( nurl_sym_def g_indexed ( string_data path ) `` )
    ( nurl_sym_def g_defs_by_uri uri `` )
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
    // Unused-import warnings arrive from `nurlc --lint` itself (it
    // attributes every decl to its defining file and tracks which file
    // references what), so no LSP-side text heuristic is layered on
    // top — one source of truth, no duplicate diagnostics.
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
                        ( __track_doc_uri uri )
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
    ? >= pos n { ^ @ ?String { F } } {}
    : i c ( nurl_str_get content pos )
    ? == c 10 { ^ @ ?String { F } } {}
    ? ! ( __is_ident_byte c ) { ^ @ ?String { F } } {}
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
    : ~ Json result ( json_null )
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
                                                                    // line ends at the next tab (kind follows) or at EOS
                                                                    : i tab2 ( __index_of_byte defs_val + tab 1 n 9 )
                                                                    : i line_end ? >= tab2 0 tab2 n
                                                                    : String line_str ( __substr defs_val + tab 1 line_end )
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

// ── Document outline (textDocument/documentSymbol) ──────────────
//
// Reads the precomputed g_defs_by_uri TSV ("name\tline\tkind" triplets,
// one per top-level decl in source order) and emits a flat
// SymbolInformation[] array. We pick the flat form over the recursive
// DocumentSymbol[] because (a) NURL's decls are uniformly top-level,
// (b) flat SymbolInformation has been supported by every LSP client
// since the protocol's first revision, and (c) the editor's outline
// renders both identically for a single-file structure.

@ __build_symbol_information s name s uri i line i kind → Json {
    : Json range ( json_obj_new )
    // Convert compiler 1-based to LSP 0-based.
    : i lz - line 1
    ( json_obj_set range `start` ( __build_position lz 0 ) )
    ( json_obj_set range `end` ( __build_position lz 0 ) )
    : Json loc ( json_obj_new )
    ( json_obj_set loc `uri` ( json_str_lit uri ) )
    ( json_obj_set loc `range` range )
    : Json sym ( json_obj_new )
    ( json_obj_set sym `name` ( json_str_lit name ) )
    ( json_obj_set sym `kind` ( json_int kind ) )
    ( json_obj_set sym `location` loc )
    ^ sym
}

@ __handle_document_symbol Json id Json params → v {
    : Json result ( json_arr_new )
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        : s tsv ( nurl_sym_get g_defs_by_uri uri )
        : i n ( nurl_str_len tsv )
        : ~ i pos 0
        ~ < pos n {
            // Each triplet = name \t line \t kind separated by tabs;
            // triplets in the TSV are also tab-separated. Read three
            // tab-delimited fields, build a SymbolInformation, append.
            : i t1 ( __index_of_byte tsv pos n 9 )
            ? < t1 0 { = pos n } {
                : i t2 ( __index_of_byte tsv + t1 1 n 9 )
                ? < t2 0 { = pos n } {
                    : i t3 ( __index_of_byte tsv + t2 1 n 9 )
                    : i end ? >= t3 0 t3 n
                    : String name ( __substr tsv pos t1 )
                    : String line_s ( __substr tsv + t1 1 t2 )
                    : String kind_s ( __substr tsv + t2 1 end )
                    : !i ParseErr lr ( string_to_int line_s )
                    : !i ParseErr kr ( string_to_int kind_s )
                    ?? lr {
                        T ln → {
                            ?? kr {
                                T kn → {
                                    : Json sym ( __build_symbol_information ( string_data name ) uri ln kn )
                                    ( json_arr_push result sym )
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    ( string_free name )
                    ( string_free line_s )
                    ( string_free kind_s )
                    = pos ? >= t3 0 + t3 1 n
                }
            }
        }
    } {}
    : Json resp ( __make_response id result )
    ( write_message resp )
    ( json_free resp )
}

// ── Hover (textDocument/hover) ───────────────────────────────────
//
// Same token-at-cursor + g_defs lookup as go-to-def, but the
// response carries a Markdown popup with the decl kind, the
// signature line from the source, and the file:line location. The
// signature is pulled live from the def-file via nurl_read_file
// (cheap; the file was already indexed once on didOpen so the OS
// page cache is warm).

@ __kind_label i kind → s {
    ? == kind 12 { ^ `function` } {}
    ? == kind 23 { ^ `struct` } {}
    ? == kind 10 { ^ `enum` } {}
    ? == kind 22 { ^ `enum variant` } {}
    ? == kind 14 { ^ `constant` } {}
    ^ `symbol`
}

// Extract the LSP-spec line `line0` (0-based) from `content`. Returns
// the line with any leading whitespace and the trailing newline
// stripped, so the result drops cleanly into a fenced code block.
@ __extract_source_line s content i line0 → String {
    : i n ( nurl_str_len content )
    : ~ i pos 0
    : ~ i cur 0
    ~ & < pos n < cur line0 {
        ? == ( nurl_str_get content pos ) 10 { = cur + cur 1 } {}
        = pos + pos 1
    }
    // Trim leading spaces / tabs.
    ~ & < pos n | == ( nurl_str_get content pos ) 32 == ( nurl_str_get content pos ) 9 {
        = pos + pos 1
    }
    : ~ i ep pos
    ~ & < ep n != ( nurl_str_get content ep ) 10 {
        = ep + ep 1
    }
    // Also trim trailing \r if present (CRLF files).
    ? & > ep pos == ( nurl_str_get content - ep 1 ) 13 { = ep - ep 1 } {}
    ^ ( __substr content pos ep )
}

// Find the basename slot in `path` (everything after the last '/').
// Returns an OWNED String. For `file:///x/y/lib.nu` the caller should
// __uri_to_path first.
@ __basename s path → String {
    : i n ( nurl_str_len path )
    : ~ i last - 0 1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get path k ) 47 { = last k } {}
        = k + k 1
    }
    : i start ? >= last 0 + last 1 0
    ^ ( __substr path start n )
}

@ __handle_hover Json id Json params → v {
    : ~ Json result ( json_null )
    : s uri ( __extract_uri params )
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
                                                                : i dn ( nurl_str_len defs_val )
                                                                : i t1 ( __index_of_byte defs_val 0 dn 9 )
                                                                : i t2 ( __index_of_byte defs_val + t1 1 dn 9 )
                                                                ? & >= t1 0 >= t2 0 {
                                                                    : String def_uri ( __substr defs_val 0 t1 )
                                                                    : String line_s ( __substr defs_val + t1 1 t2 )
                                                                    : String kind_s ( __substr defs_val + t2 1 dn )
                                                                    : !i ParseErr lr ( string_to_int line_s )
                                                                    : !i ParseErr kr ( string_to_int kind_s )
                                                                    ?? lr {
                                                                        T def_line → {
                                                                            ?? kr {
                                                                                T def_kind → {
                                                                                    // Read def-file content, pull the
                                                                                    // signature line, format Markdown.
                                                                                    : String def_path ( __uri_to_path ( string_data def_uri ) )
                                                                                    : s def_content ( __read_if_exists ( string_data def_path ) )
                                                                                    : String sig ( __extract_source_line def_content - def_line 1 )
                                                                                    : String base ( __basename ( string_data def_path ) )

                                                                                    // Build Markdown popup. Backtick (96)
                                                                                    // and newline (10) added via
                                                                                    // string_push_char because backticks
                                                                                    // delimit NURL string literals.
                                                                                    : String md ( string_with_cap 256 )
                                                                                    ( string_push_str md `**` )
                                                                                    ( string_push_str md ( __kind_label def_kind ) )
                                                                                    ( string_push_str md `** ` )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_str md ( string_data name ) )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_str md `nurl` )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_str md ( string_data sig ) )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_char md 10 )
                                                                                    ( string_push_str md `*Defined in ` )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_str md ( string_data base ) )
                                                                                    ( string_push_char md 58 )
                                                                                    ( string_push_str md ( nurl_str_int def_line ) )
                                                                                    ( string_push_char md 96 )
                                                                                    ( string_push_char md 42 )

                                                                                    : Json contents ( json_obj_new )
                                                                                    ( json_obj_set contents `kind` ( json_str_lit `markdown` ) )
                                                                                    ( json_obj_set contents `value` ( json_str_lit ( string_data md ) ) )
                                                                                    : Json hov ( json_obj_new )
                                                                                    ( json_obj_set hov `contents` contents )
                                                                                    = result hov

                                                                                    ( string_free def_path )
                                                                                    ( string_free sig )
                                                                                    ( string_free base )
                                                                                    ( string_free md )
                                                                                }
                                                                                F _ → {}
                                                                            }
                                                                        }
                                                                        F _ → {}
                                                                    }
                                                                    ( string_free def_uri )
                                                                    ( string_free line_s )
                                                                    ( string_free kind_s )
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

// ── Completion (textDocument/completion) ────────────────────────
//
// Returns every known symbol whose name starts with the IDENT-prefix
// immediately to the left of the cursor (or every symbol when the
// cursor is at an ident boundary). The editor filters further on its
// side as the user keeps typing.
//
// CompletionItemKind differs from SymbolKind despite the close
// resemblance — both enums are part of the LSP spec but the integer
// values aren't aligned. `__completion_kind` maps SymbolKind →
// CompletionItemKind for the five kinds we emit.

@ __completion_kind i symbol_kind → i {
    ? == symbol_kind 12 { ^ 3 } {}  // Function
    ? == symbol_kind 23 { ^ 22 } {}  // Struct
    ? == symbol_kind 10 { ^ 13 } {}  // Enum
    ? == symbol_kind 22 { ^ 20 } {}  // EnumMember
    ? == symbol_kind 14 { ^ 21 } {}  // Constant
    ^ 1  // Text fallback
}

// Extract the IDENT-prefix immediately left of `(line, col)`.
// Returns "" when the cursor is on whitespace or after a non-ident
// byte — the LSP client treats an empty prefix as "show everything".
@ __prefix_at s content i line i col → String {
    : i n ( nurl_str_len content )
    : ~ i pos 0
    : ~ i cur_line 0
    ~ & < pos n < cur_line line {
        ? == ( nurl_str_get content pos ) 10 { = cur_line + cur_line 1 } {}
        = pos + pos 1
    }
    : i line_start pos
    : ~ i k 0
    ~ & & < pos n != ( nurl_str_get content pos ) 10 < k col {
        = pos + pos 1
        = k + k 1
    }
    : ~ i lo pos
    ~ & > lo line_start ( __is_ident_byte ( nurl_str_get content - lo 1 ) ) {
        = lo - lo 1
    }
    ^ ( __substr content lo pos )
}

@ __starts_with s str s prefix → b {
    : i np ( nurl_str_len prefix )
    ? == np 0 { ^ T } {}
    : i ns ( nurl_str_len str )
    ? > np ns { ^ F } {}
    : ~ i k 0
    ~ < k np {
        ? != ( nurl_str_get str k ) ( nurl_str_get prefix k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ __build_completion_item s name s uri i line i symbol_kind → Json {
    : Json item ( json_obj_new )
    ( json_obj_set item `label` ( json_str_lit name ) )
    ( json_obj_set item `kind` ( json_int ( __completion_kind symbol_kind ) ) )
    : String path ( __uri_to_path uri )
    : String base ( __basename ( string_data path ) )
    : String detail ( string_with_cap 64 )
    ( string_push_str detail ( __kind_label symbol_kind ) )
    ( string_push_str detail ` (` )
    ( string_push_str detail ( string_data base ) )
    ( string_push_char detail 58 )
    ( string_push_str detail ( nurl_str_int line ) )
    ( string_push_char detail 41 )
    ( json_obj_set item `detail` ( json_str_lit ( string_data detail ) ) )
    ( string_free path )
    ( string_free base )
    ( string_free detail )
    ^ item
}

@ __handle_completion Json id Json params → v {
    : Json items ( json_arr_new )
    : s uri ( __extract_uri params )
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
                                                : String prefix ( __prefix_at content ln cn )
                                                : s tsv ( nurl_sym_get g_all_names `:list` )
                                                : i nt ( nurl_str_len tsv )
                                                : ~ i tpos 0
                                                ~ < tpos nt {
                                                    : i tend ( __index_of_byte tsv tpos nt 9 )
                                                    : i sep ? >= tend 0 tend nt
                                                    : String name ( __substr tsv tpos sep )
                                                    ? ( __starts_with ( string_data name ) ( string_data prefix ) ) {
                                                        : s defs_val ( nurl_sym_get g_defs ( string_data name ) )
                                                        ? > ( nurl_str_len defs_val ) 0 {
                                                            : i dn ( nurl_str_len defs_val )
                                                            : i t1 ( __index_of_byte defs_val 0 dn 9 )
                                                            : i t2 ( __index_of_byte defs_val + t1 1 dn 9 )
                                                            ? & >= t1 0 >= t2 0 {
                                                                : String def_uri ( __substr defs_val 0 t1 )
                                                                : String line_s ( __substr defs_val + t1 1 t2 )
                                                                : String kind_s ( __substr defs_val + t2 1 dn )
                                                                : !i ParseErr lr ( string_to_int line_s )
                                                                : !i ParseErr kr ( string_to_int kind_s )
                                                                ?? lr {
                                                                    T def_line → {
                                                                        ?? kr {
                                                                            T def_kind → {
                                                                                : Json it ( __build_completion_item ( string_data name ) ( string_data def_uri ) def_line def_kind )
                                                                                ( json_arr_push items it )
                                                                            }
                                                                            F _ → {}
                                                                        }
                                                                    }
                                                                    F _ → {}
                                                                }
                                                                ( string_free def_uri )
                                                                ( string_free line_s )
                                                                ( string_free kind_s )
                                                            } {}
                                                        } {}
                                                    } {}
                                                    ( string_free name )
                                                    = tpos ? >= tend 0 + tend 1 nt
                                                }
                                                ( string_free prefix )
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
    // CompletionList envelope. isIncomplete=false tells the editor
    // the full set is already in `items`, no need to retrigger.
    : Json clist ( json_obj_new )
    ( json_obj_set clist `isIncomplete` ( json_bool F ) )
    ( json_obj_set clist `items` items )
    : Json resp ( __make_response id clist )
    ( write_message resp )
    ( json_free resp )
}

// ── Formatting (textDocument/formatting) ─────────────────────────
//
// Pipes the current buffer through `build/nurlfmt --stdin` and
// returns a single TextEdit covering the whole document. The
// `--stdin` mode is the project-canonical entry point — same code
// path as `git diff | nurlfmt --stdin --check` in CI.
//
// LSP TextEdit range semantics: `start` inclusive, `end` exclusive.
// To replace the whole document we point `end` at the position
// immediately past the last character — line N+1, char 0 — which
// VS Code interprets as "everything up to the end of file".

@ __count_lines s content → i {
    : i n ( nurl_str_len content )
    : ~ i k 0
    : ~ i lines 0
    ~ < k n {
        ? == ( nurl_str_get content k ) 10 { = lines + lines 1 } {}
        = k + k 1
    }
    ^ lines
}

@ __handle_formatting Json id Json params → v {
    : Json edits ( json_arr_new )
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        : s content ( nurl_sym_get g_docs uri )
        ? > ( nurl_str_len content ) 0 {
            // Call nurlfmt --stdin; feed the buffer via process_run's
            // stdin_str parameter. nurlfmt: 1 arg = `--stdin`.
            : ( Vec s ) args ( vec_with_cap [s] 1 )
            ( vec_push [s] args `--stdin` )
            : !Output ProcessErr pr ( process_run `build/nurlfmt` args content )
            ( vec_free [s] args )
            ?? pr {
                F _ → {}
                T out → {
                    ? ( output_success out ) {
                        : s formatted ( output_stdout out )
                        // Build a single TextEdit covering the full
                        // document. end-of-file position = (linecount, 0).
                        : i nl ( __count_lines content )
                        : Json range ( json_obj_new )
                        ( json_obj_set range `start` ( __build_position 0 0 ) )
                        ( json_obj_set range `end` ( __build_position nl 0 ) )
                        : Json edit ( json_obj_new )
                        ( json_obj_set edit `range` range )
                        ( json_obj_set edit `newText` ( json_str_lit formatted ) )
                        ( json_arr_push edits edit )
                    } {}
                    ( output_free out )
                }
            }
        } {}
    } {}
    : Json resp ( __make_response id edits )
    ( write_message resp )
    ( json_free resp )
}

// ── Workspace symbol search (workspace/symbol) ───────────────────
//
// `Ctrl+T` in VS Code / `Cmd+T` on macOS: fuzzy-search across every
// known top-level symbol in the workspace + transitive imports.
// Empty query returns the full set so the user can browse; non-empty
// queries filter by case-insensitive substring match.

@ __byte_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// Case-insensitive substring search. Empty `needle` matches anything.
@ __ci_contains s hay s needle → b {
    : i nn ( nurl_str_len needle )
    ? == nn 0 { ^ T } {}
    : i nh ( nurl_str_len hay )
    ? > nn nh { ^ F } {}
    : i limit + - nh nn 1
    : ~ i i 0
    ~ < i limit {
        : ~ b match T
        : ~ i j 0
        ~ & match < j nn {
            : i hc ( __byte_lower ( nurl_str_get hay + i j ) )
            : i nc ( __byte_lower ( nurl_str_get needle j ) )
            ? != hc nc { = match F } {}
            = j + j 1
        }
        ? match { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ __handle_workspace_symbol Json id Json params → v {
    : Json items ( json_arr_new )
    // Extract `query` (a JSON string). Spec says it's always present.
    : ?Json q_o ( json_obj_get params `query` )
    : ~ s query ``
    ?? q_o {
        T qj → = query ( json_str_data qj )
        F _ → {}
    }
    : s tsv ( nurl_sym_get g_all_names `:list` )
    : i nt ( nurl_str_len tsv )
    : ~ i tpos 0
    ~ < tpos nt {
        : i tend ( __index_of_byte tsv tpos nt 9 )
        : i sep ? >= tend 0 tend nt
        : String name ( __substr tsv tpos sep )
        ? ( __ci_contains ( string_data name ) query ) {
            : s defs_val ( nurl_sym_get g_defs ( string_data name ) )
            ? > ( nurl_str_len defs_val ) 0 {
                : i dn ( nurl_str_len defs_val )
                : i t1 ( __index_of_byte defs_val 0 dn 9 )
                : i t2 ( __index_of_byte defs_val + t1 1 dn 9 )
                ? & >= t1 0 >= t2 0 {
                    : String def_uri ( __substr defs_val 0 t1 )
                    : String line_s ( __substr defs_val + t1 1 t2 )
                    : String kind_s ( __substr defs_val + t2 1 dn )
                    : !i ParseErr lr ( string_to_int line_s )
                    : !i ParseErr kr ( string_to_int kind_s )
                    ?? lr {
                        T def_line → {
                            ?? kr {
                                T def_kind → {
                                    : Json sym ( __build_symbol_information ( string_data name ) ( string_data def_uri ) def_line def_kind )
                                    ( json_arr_push items sym )
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    ( string_free def_uri )
                    ( string_free line_s )
                    ( string_free kind_s )
                } {}
            } {}
        } {}
        ( string_free name )
        = tpos ? >= tend 0 + tend 1 nt
    }
    : Json resp ( __make_response id items )
    ( write_message resp )
    ( json_free resp )
}

// ── Folding ranges (textDocument/foldingRange) ───────────────────
//
// Char-by-char walker that pairs `{ … }` blocks and emits a
// FoldingRange per multi-line pair. Comments (`//`) and backtick
// strings are skipped so braces inside them don't confuse the
// matcher. Stack of open-line numbers kept in a Vec[i] — vec_push
// on `{`, vec_pop on `}`. Single-line blocks (`{ a b }` on one row)
// are filtered out so the editor doesn't list useless one-row folds.
//
// LSP FoldingRange semantics: startLine + endLine are inclusive,
// both fold-targets. We emit endLine = (close-row - 1) so the
// closing `}` stays visible after the fold collapses.

@ __handle_folding_range Json id Json params → v {
    : Json ranges ( json_arr_new )
    : s uri ( __extract_uri params )
    ? > ( nurl_str_len uri ) 0 {
        : s content ( nurl_sym_get g_docs uri )
        : i n ( nurl_str_len content )
        : ( Vec i ) stack ( vec_new [i] )
        : ~ i pos 0
        : ~ i line 0
        : ~ i in_string 0
        : ~ i in_comment 0
        ~ < pos n {
            : i c ( nurl_str_get content pos )
            ? != in_string 0 {
                ? == c 96 { = in_string 0 } {}
                ? == c 10 { = line + line 1 } {}
                = pos + pos 1
            } {
                ? != in_comment 0 {
                    ? == c 10 { = in_comment 0 = line + line 1 } {}
                    = pos + pos 1
                } {
                    ? == c 96 { = in_string 1 = pos + pos 1 } {
                        ? & == c 47 & < + pos 1 n == ( nurl_str_get content + pos 1 ) 47 {
                            = in_comment 1
                            = pos + pos 2
                        } {
                            ? == c 123 {
                                ( vec_push [i] stack line )
                                = pos + pos 1
                            } {
                                ? == c 125 {
                                    : ?i op ( vec_pop [i] stack )
                                    ?? op {
                                        T open_line → {
                                            ? > line open_line {
                                                : Json r ( json_obj_new )
                                                ( json_obj_set r `startLine` ( json_int open_line ) )
                                                ( json_obj_set r `endLine` ( json_int - line 1 ) )
                                                ( json_arr_push ranges r )
                                            } {}
                                        }
                                        F _ → {}
                                    }
                                    = pos + pos 1
                                } {
                                    ? == c 10 { = line + line 1 } {}
                                    = pos + pos 1
                                }
                            }
                        }
                    }
                }
            }
        }
        ( vec_free [i] stack )
    } {}
    : Json resp ( __make_response id ranges )
    ( write_message resp )
    ( json_free resp )
}

// ── References (textDocument/references) ────────────────────────────
//
// Sweeps every OPEN document (g_doc_uris) for whole-word identifier
// matches of the symbol under the cursor and returns them as LSP
// Locations. Limited to open buffers — files indexed only for go-to-
// definition are not re-read here — which covers the common
// multi-file editing session. `context.includeDeclaration` is ignored:
// the declaration token is itself an identifier occurrence, so it is
// always included.

// Compare content[st .. st+len) to `name` byte-for-byte (no alloc).
@ __slice_eq s content i st i len s name → b {
    ? != len ( nurl_str_len name ) { ^ F } {}
    : ~ i k 0
    : ~ b eq T
    ~ & < k len eq {
        ? != ( nurl_str_get content + st k ) ( nurl_str_get name k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}

// Append a Location for every whole-word occurrence of `name` in one
// document's content, skipping strings + comments. Positions are
// emitted 0-based (LSP coordinates) directly.
@ __collect_refs_in_doc s uri s content s name Json out → v {
    : i n ( nurl_str_len content )
    : ~ i pos 0
    : ~ i line 0
    : ~ i line_start 0
    : ~ i in_str 0
    : ~ i in_com 0
    ~ < pos n {
        : i c ( nurl_str_get content pos )
        ? == c 10 { = line + line 1 = pos + pos 1 = line_start pos = in_com 0 } {
            ? != in_str 0 {
                ? == c 96 { = in_str 0 } {}
                = pos + pos 1
            } {
                ? != in_com 0 { = pos + pos 1 } {
                    ? == c 96 { = in_str 1 = pos + pos 1 } {
                        ? & & == c 47 < + pos 1 n == ( nurl_str_get content + pos 1 ) 47 {
                            = in_com 1 = pos + pos 2
                        } {
                            ? ( __is_ident_start c ) {
                                : i st pos
                                ~ & < pos n ( __is_ident_byte ( nurl_str_get content pos ) ) { = pos + pos 1 }
                                : i len - pos st
                                ? ( __slice_eq content st len name ) {
                                    : i scol - st line_start
                                    : Json range ( json_obj_new )
                                    ( json_obj_set range `start` ( __build_position line scol ) )
                                    ( json_obj_set range `end` ( __build_position line + scol len ) )
                                    : Json loc ( json_obj_new )
                                    ( json_obj_set loc `uri` ( json_str_lit uri ) )
                                    ( json_obj_set loc `range` range )
                                    ( json_arr_push out loc )
                                } {}
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

// Sweep every open document for references to `name`, appending to `out`.
@ __refs_all_docs s name Json out → v {
    : s list ( nurl_sym_get g_doc_uris `list` )
    : i n ( nurl_str_len list )
    : ~ i pos 0
    ~ < pos n {
        : i nl ( __index_of_byte list pos n 10 )
        : i end ? < nl 0 n nl
        : String duri ( __substr list pos end )
        : s dc ( nurl_sym_get g_docs ( string_data duri ) )
        ? > ( nurl_str_len dc ) 0 { ( __collect_refs_in_doc ( string_data duri ) dc name out ) } {}
        ( string_free duri )
        = pos ? < nl 0 n + nl 1
    }
}

@ __handle_references Json id Json params → v {
    : s uri ( __extract_uri params )
    : Json result ( json_arr_new )
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
                                                            ( __refs_all_docs ( string_data name ) result )
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

// ── Rename (textDocument/rename) ────────────────────────────────────
//
// Rename = references + the declaration site, mapped to TextEdits.
// Reuses the references scanner (__collect_refs_in_doc): every
// Location it produces has its range cloned into a TextEdit
// {range, newText}. The sweep covers the same scope as
// textDocument/references (every open document); additionally, when
// g_defs knows the declaring file and that file is NOT an open
// buffer, it is read from disk and swept too, so the declaration is
// always part of the WorkspaceEdit.
//
// Invalid targets are rejected with JSON-RPC error -32602:
//   * position not on an identifier (whitespace / punctuation /
//     numeric literal),
//   * identifier under the cursor is a reserved word,
//   * newName not shaped [A-Za-z_][A-Za-z0-9_]*,
//   * newName collides with a reserved word.

// Is `name` lexically a valid NURL identifier?
@ __valid_ident s name → b {
    : i n ( nurl_str_len name )
    ? == n 0 { ^ F } {}
    ? ! ( __is_ident_start ( nurl_str_get name 0 ) ) { ^ F } {}
    : ~ i k 1
    ~ < k n {
        ? ! ( __is_ident_byte ( nurl_str_get name k ) ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Reserved words rename must never produce or target: the
// single-token type keywords plus named types and the literal /
// decl keywords the lexer treats specially.
@ __is_reserved_word s name → b {
    ? ( __is_type_kw name ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `String` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `Vec` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `T` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `F` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `pub` ) { ^ T } {}
    ^ F
}

// Run the references scanner over one document and clone every
// Location's range into a TextEdit under `changes[uri]`. No-op when
// the doc has no matches (no empty arrays in the WorkspaceEdit).
@ __rename_edits_for_doc s uri s content s name s new_name Json changes → v {
    : Json locs ( json_arr_new )
    ( __collect_refs_in_doc uri content name locs )
    : i nl ( json_arr_len locs )
    ? > nl 0 {
        : Json edits ( json_arr_new )
        : ~ i k 0
        ~ < k nl {
            : ?Json lo ( json_arr_get locs k )
            ?? lo {
                T loc → {
                    : ?Json ro ( json_obj_get loc `range` )
                    ?? ro {
                        T range_j → {
                            : Json edit ( json_obj_new )
                            ( json_obj_set edit `range` ( json_clone range_j ) )
                            ( json_obj_set edit `newText` ( json_str_lit new_name ) )
                            ( json_arr_push edits edit )
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = k + k 1
        }
        ( json_obj_set changes uri edits )
    } {}
    ( json_free locs )
}

// Sweep the same scope as textDocument/references (every open doc),
// then the g_defs declaration file when it isn't an open buffer —
// closed / never-opened decl files are read from disk so the
// declaration site is always covered.
@ __rename_all_docs s name s new_name Json changes → v {
    : s list ( nurl_sym_get g_doc_uris `list` )
    : i n ( nurl_str_len list )
    : ~ i pos 0
    ~ < pos n {
        : i nl ( __index_of_byte list pos n 10 )
        : i end ? < nl 0 n nl
        : String duri ( __substr list pos end )
        : s dc ( nurl_sym_get g_docs ( string_data duri ) )
        ? > ( nurl_str_len dc ) 0 { ( __rename_edits_for_doc ( string_data duri ) dc name new_name changes ) } {}
        ( string_free duri )
        = pos ? < nl 0 n + nl 1
    }
    : s defs_val ( nurl_sym_get g_defs name )
    ? > ( nurl_str_len defs_val ) 0 {
        : i dn ( nurl_str_len defs_val )
        : i t1 ( __index_of_byte defs_val 0 dn 9 )
        ? >= t1 0 {
            : String def_uri ( __substr defs_val 0 t1 )
            : s open_body ( nurl_sym_get g_docs ( string_data def_uri ) )
            ? == 0 ( nurl_str_len open_body ) {
                : String def_path ( __uri_to_path ( string_data def_uri ) )
                : s def_content ( __read_if_exists ( string_data def_path ) )
                ? > ( nurl_str_len def_content ) 0 {
                    ( __rename_edits_for_doc ( string_data def_uri ) def_content name new_name changes )
                } {}
                ( string_free def_path )
            } {}
            ( string_free def_uri )
        } {}
    } {}
}

@ __handle_rename Json id Json params → v {
    : s uri ( __extract_uri params )
    : ~ s new_name ``
    : ?Json nn_o ( json_obj_get params `newName` )
    ?? nn_o {
        T nj → = new_name ( json_str_data nj )
        F _ → {}
    }
    // Position extraction (same envelope walk as references).
    : ~ i p_line 0
    : ~ i p_col 0
    : ~ b have_pos F
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
                                        T cn → { = p_line ln = p_col cn = have_pos T }
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

    : ~ s err_msg ``
    : ~ b have_err F
    : Json changes ( json_obj_new )
    ? ! ( __valid_ident new_name ) {
        = err_msg `rename rejected: newName is not a valid NURL identifier ([A-Za-z_][A-Za-z0-9_]*)`
        = have_err T
    } {
        ? ( __is_reserved_word new_name ) {
            = err_msg `rename rejected: newName collides with a NURL type keyword or reserved word`
            = have_err T
        } {
            : s content ( nurl_sym_get g_docs uri )
            ? | ! have_pos == ( nurl_str_len content ) 0 {
                = err_msg `rename rejected: document not open or position missing`
                = have_err T
            } {
                : ?String tk ( __token_at content p_line p_col )
                ?? tk {
                    F _ → {
                        = err_msg `rename rejected: no identifier at the given position (keyword, literal, or whitespace)`
                        = have_err T
                    }
                    T name → {
                        ? ! ( __is_ident_start ( string_get name 0 ) ) {
                            = err_msg `rename rejected: position is on a numeric literal, not an identifier`
                            = have_err T
                        } {
                            ? ( __is_reserved_word ( string_data name ) ) {
                                = err_msg `rename rejected: cannot rename a NURL type keyword or reserved word`
                                = have_err T
                            } {
                                ( __rename_all_docs ( string_data name ) new_name changes )
                            }
                        }
                        ( string_free name )
                    }
                }
            }
        }
    }
    ? have_err {
        ( json_free changes )
        : Json resp ( __make_error id - 0 32602 err_msg )
        ( write_message resp )
        ( json_free resp )
    } {
        : Json we ( json_obj_new )
        ( json_obj_set we `changes` changes )
        : Json resp ( __make_response id we )
        ( write_message resp )
        ( json_free resp )
    }
}

// ── Open-document roster (for the references sweep) ─────────────────

// True when `uri` already appears as a full line in the newline-
// separated roster.
@ __uri_in_list s list s uri → b {
    : i n ( nurl_str_len list )
    : ~ i pos 0
    : ~ b found F
    ~ & < pos n ! found {
        : i nl ( __index_of_byte list pos n 10 )
        : i end ? < nl 0 n nl
        ? ( __slice_eq list pos - end pos uri ) { = found T } {}
        = pos ? < nl 0 n + nl 1
    }
    ^ found
}

@ __track_doc_uri s uri → v {
    : s cur ( nurl_sym_get g_doc_uris `list` )
    ? ( __uri_in_list cur uri ) {} {
        : String acc ( string_with_cap + + ( nurl_str_len cur ) ( nurl_str_len uri ) 1 )
        ? > ( nurl_str_len cur ) 0 { ( string_push_str acc cur ) ( string_push_char acc 10 ) } {}
        ( string_push_str acc uri )
        ( nurl_sym_def g_doc_uris `list` ( string_data acc ) )
        ( string_free acc )
    }
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
                                ? ( nurl_str_eq method `textDocument/documentSymbol` ) {
                                    : ?Json params_o ( json_obj_get msg `params` )
                                    ?? params_o {
                                        T params_j → ( __handle_document_symbol id params_j )
                                        F _ → {
                                            : Json resp ( __make_response id ( json_arr_new ) )
                                            ( write_message resp )
                                            ( json_free resp )
                                        }
                                    }
                                } {
                                    ? ( nurl_str_eq method `textDocument/hover` ) {
                                        : ?Json params_o ( json_obj_get msg `params` )
                                        ?? params_o {
                                            T params_j → ( __handle_hover id params_j )
                                            F _ → {
                                                : Json resp ( __make_response id ( json_null ) )
                                                ( write_message resp )
                                                ( json_free resp )
                                            }
                                        }
                                    } {
                                        ? ( nurl_str_eq method `textDocument/completion` ) {
                                            : ?Json params_o ( json_obj_get msg `params` )
                                            ?? params_o {
                                                T params_j → ( __handle_completion id params_j )
                                                F _ → {
                                                    : Json resp ( __make_response id ( json_arr_new ) )
                                                    ( write_message resp )
                                                    ( json_free resp )
                                                }
                                            }
                                        } {
                                            ? ( nurl_str_eq method `textDocument/formatting` ) {
                                                : ?Json params_o ( json_obj_get msg `params` )
                                                ?? params_o {
                                                    T params_j → ( __handle_formatting id params_j )
                                                    F _ → {
                                                        : Json resp ( __make_response id ( json_arr_new ) )
                                                        ( write_message resp )
                                                        ( json_free resp )
                                                    }
                                                }
                                            } {
                                                ? ( nurl_str_eq method `workspace/symbol` ) {
                                                    : ?Json params_o ( json_obj_get msg `params` )
                                                    ?? params_o {
                                                        T params_j → ( __handle_workspace_symbol id params_j )
                                                        F _ → {
                                                            : Json resp ( __make_response id ( json_arr_new ) )
                                                            ( write_message resp )
                                                            ( json_free resp )
                                                        }
                                                    }
                                                } {
                                                    ? ( nurl_str_eq method `textDocument/foldingRange` ) {
                                                        : ?Json params_o ( json_obj_get msg `params` )
                                                        ?? params_o {
                                                            T params_j → ( __handle_folding_range id params_j )
                                                            F _ → {
                                                                : Json resp ( __make_response id ( json_arr_new ) )
                                                                ( write_message resp )
                                                                ( json_free resp )
                                                            }
                                                        }
                                                    } {
                                                        ? ( nurl_str_eq method `textDocument/references` ) {
                                                            : ?Json params_o ( json_obj_get msg `params` )
                                                            ?? params_o {
                                                                T params_j → ( __handle_references id params_j )
                                                                F _ → {
                                                                    : Json resp ( __make_response id ( json_arr_new ) )
                                                                    ( write_message resp )
                                                                    ( json_free resp )
                                                                }
                                                            }
                                                        } {
                                                            ? ( nurl_str_eq method `textDocument/rename` ) {
                                                                : ?Json params_o ( json_obj_get msg `params` )
                                                                ?? params_o {
                                                                    T params_j → ( __handle_rename id params_j )
                                                                    F _ → {
                                                                        : Json resp ( __make_error id - 0 32602 `rename rejected: missing params` )
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
                                            }
                                        }
                                    }
                                }
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
    = g_doc_uris ( nurl_sym_new )
    = g_defs ( nurl_sym_new )
    = g_defs_by_uri ( nurl_sym_new )
    = g_all_names ( nurl_sym_new )
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
