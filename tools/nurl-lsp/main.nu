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

// Counter for unique temp-file names within a single server run. Per-
// pid is enough — we don't expect concurrent LSP sessions sharing a
// /tmp.
: ~ i g_tmp_counter 0

@ __build_capabilities → Json {
    : Json caps ( json_obj_new )
    // Full document sync: every didChange carries the whole buffer.
    ( json_obj_set caps `textDocumentSync` ( json_int 1 ) )
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

// ── Request / notification dispatch ────────────────────────────────

@ __handle_initialize Json id → v {
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
                        ( __handle_initialize id )
                    } {
                        ? ( nurl_str_eq method `shutdown` ) {
                            ( __handle_shutdown id )
                        } {
                            ( __handle_unknown_request id method )
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
