// nurl-mcp — a local MCP (Model Context Protocol) server for the NURL
// toolchain. The LLM-facing counterpart of nurl-lsp: where nurl-lsp serves
// editors over LSP, nurl-mcp serves an LLM agent over MCP so it can drive the
// *locally installed* compiler — build, run, type-check, format NURL, compile
// it to wasm32-wasi (via the wasmbuilder package, no build service), and read
// the installed standard library — against the host's real filesystem.
//
// Transport: newline-delimited JSON-RPC 2.0 over stdin/stdout (the transport
// every MCP client supports). Logs go to stderr; stdout is protocol-only.
// Wire it into an MCP client by pointing its `command` at the built binary,
// e.g.  `claude mcp add nurl -- nurl-mcp`.
//
// The build/run/check/fmt tools shell out to `nurl` / `nurlc` / `nurlfmt`
// (found on $PATH — the installed toolchain shims export $NURL_STDLIB so the
// compiler resolves stdlib imports). Running NURL is full code execution
// (libc FFI, no sandbox); over stdio that is safe because only the process
// that spawned this server talks to it. The `--http` transport serves the
// MCP Streamable-HTTP protocol via the stdlib facade (`ext/mcp_http.nu`:
// POST single/batch, GET SSE probe, Mcp-Session-Id echo, DELETE, CORS)
// with bearer-token auth layered on top; nurl_run stays off over HTTP
// unless --allow-run is given.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/mcp_search.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/std/encode.nu`
$ `deps/wasmbuilder/src/build.nu`

// ── Policy (set once in main, read by the dispatcher) ───────────────
//
// g_read_only : 1 ⇒ expose only the read/analysis tools (check, fmt,
//               list_stdlib, read_stdlib) — no build, no run.
// g_run_allowed : 1 ⇒ nurl_run is available. Defaults to 1 over stdio
//               (only the spawning process can reach the server); over
//               HTTP it is 0 unless --allow-run is passed, because run
//               is unsandboxed code execution.
// g_token     : non-empty ⇒ HTTP requests must carry
//               `Authorization: Bearer <g_token>`.
: ~ i g_read_only 0
: ~ i g_run_allowed 1
: ~ s g_token ``

// ── Version ─────────────────────────────────────────────────────────
//
// Single source of truth for the server version. Keep this in sync with
// `version` in nurl.toml on every release — the banners and the MCP
// `initialize` result both read it here, so there is exactly one string
// to bump (previously the banners drifted to a stale 0.2.0 while the
// handshake reported 0.4.0).

@ nm_version → s { ^ `0.5.0` }

// Log a startup banner "nurl-mcp <version> <suffix>" through mcp_log,
// building the line from the single-source version so the banners can
// never drift from the handshake version again.
@ nm_log_banner s suffix → v {
    : String b ( string_from `nurl-mcp ` )
    ( string_push_str b ( nm_version ) )
    ( string_push_char b 32 )
    ( string_push_str b suffix )
    ( mcp_log ( string_data b ) )
    ( string_free b )
}

// ── Temp-file plumbing ──────────────────────────────────────────────
//
// Inline `source` is written to a unique temp .nu so the file-oriented
// compiler can read it. `nm_input_temp` records whether the resolved path is
// such a temp (so we delete it afterward) vs. a user-supplied `path` (left
// untouched). Single-threaded stdio server ⇒ the global is race-free.

: ~ i nm_seq 0

// A resolved input path is a temp we own iff it sits under the
// "<tmpdir>/nurl-mcp-" prefix nm_tmp_path mints. Path-based (not a shared
// mutable flag) so it stays correct if requests are ever served on
// concurrent fibers.
@ nm_is_temp s path → b {
    : String dir ( env_var_or `TMPDIR` `/tmp` )
    : String pref ( string_from ( string_data dir ) )
    ( string_push_str pref `/nurl-mcp-` )
    : b r ? != ( nurl_str_starts path ( string_data pref ) ) 0 T F
    ( string_free dir )
    ( string_free pref )
    ^ r
}

@ nm_tmp_path s suffix → String {
    : String dir ( env_var_or `TMPDIR` `/tmp` )
    : String p ( string_with_cap 96 )
    ( string_push_str p ( string_data dir ) )
    ( string_push_str p `/nurl-mcp-` )
    ( string_push_int p ( getpid ) )
    ( string_push_str p `-` )
    ( string_push_int p nm_seq )
    ( string_push_str p suffix )
    = nm_seq + nm_seq 1
    ( string_free dir )
    ^ p
}

@ nm_unlink s path → v {
    : !Output ProcessErr r ( process_run2 `rm` `-f` path )
    ?? r {
        T o → ( output_free o )
        F e → {}
    }
}

// Remove a build's artifacts: the binary `base` and the `base.ll` IR that the
// build driver leaves beside it.
@ nm_unlink_artifacts s base → v {
    ( nm_unlink base )
    : String ll ( string_from base )
    ( string_push_str ll `.ll` )
    ( nm_unlink ( string_data ll ) )
    ( string_free ll )
}

// Resolve a tool's input to a .nu file path (owned String) the compiler can
// read. Prefers an explicit `path`; otherwise writes inline `source` to a
// temp file. Returns None when neither argument is present.
@ nm_input_path Json args → ?String {
    : ?Json pj ( json_obj_get args `path` )
    ?? pj {
        T pv → { ^ @ ?String { T ( string_from ( json_str_data pv ) ) } }
        F → {}
    }
    : ?Json sj ( json_obj_get args `source` )
    ?? sj {
        T sv → {
            : String tmp ( nm_tmp_path `.nu` )
            : !v IoErr wr ( write_file ( string_data tmp ) ( json_str_data sv ) )
            ?? wr {
                T → { ^ @ ?String { T tmp } }
                F e → { ( string_free tmp ) ^ @ ?String { F } }
            }
        }
        F → {}
    }
    ^ @ ?String { F }
}

// ── Result-shaping helpers ──────────────────────────────────────────

// Turn a non-zero-exit Output into an MCP error result carrying the exit code
// and captured diagnostics. `with_stdout` folds stdout in too (the build
// driver prints some diagnostics there; the front-end check prints IR there,
// so check passes F).
@ nm_fail_from_output s prefix Output o b with_stdout → Json {
    : String msg ( string_with_cap 256 )
    ( string_push_str msg prefix )
    ( string_push_str msg ` (exit ` )
    ( string_push_int msg ( output_exit_code o ) )
    ( string_push_str msg `)` )
    ? > ( output_stderr_len o ) 0 {
        ( string_push_str msg `\n` )
        ( string_push_str msg ( output_stderr o ) )
    } {}
    ? & with_stdout > ( output_stdout_len o ) 0 {
        ( string_push_str msg `\n` )
        ( string_push_str msg ( output_stdout o ) )
    } {}
    : Json j ( mcp_tool_result_error ( string_data msg ) )
    ( string_free msg )
    ^ j
}

@ nm_proc_err ProcessErr e → Json {
    : String m ( string_from `could not launch the NURL toolchain: ` )
    ( string_push_str m ( process_err_name e ) )
    ( string_push_str m ` — is "nurl"/"nurlc"/"nurlfmt" on $PATH? (install via tools/install-toolchain.sh)` )
    : Json j ( mcp_tool_result_error ( string_data m ) )
    ( string_free m )
    ^ j
}

@ nm_missing_input → Json {
    ^ ( mcp_tool_result_error `provide "source" (inline NURL) or "path" (a .nu file)` )
}

// ── Tool: nurl_check (front-end type + borrow check, no binary) ──────

@ nm_tool_check Json args → Json {
    : ?String po ( nm_input_path args )
    ?? po {
        T p → {
            : !Output ProcessErr r ( process_run1 `nurlc` ( string_data p ) )
            ? ( nm_is_temp ( string_data p ) ) { ( nm_unlink ( string_data p ) ) } {}
            ( string_free p )
            ?? r {
                T o → {
                    ? ( output_success o ) {
                        ( output_free o )
                        ^ ( mcp_tool_result_text `OK — type-checks and passes the borrow checker.` )
                    } {
                        : Json j ( nm_fail_from_output `type / borrow check failed` o F )
                        ( output_free o )
                        ^ j
                    }
                }
                F e → { ^ ( nm_proc_err e ) }
            }
        }
        F → {}
    }
    ^ ( nm_missing_input )
}

// ── Tool: nurl_build (compile to a binary, do not run) ──────────────

@ nm_tool_build Json args → Json {
    : ?String po ( nm_input_path args )
    ?? po {
        T p → {
            : String outp ( nm_tmp_path `-bin` )
            : !Output ProcessErr r ( process_run2 `nurl` ( string_data p ) ( string_data outp ) )
            ? ( nm_is_temp ( string_data p ) ) { ( nm_unlink ( string_data p ) ) } {}
            ( string_free p )
            ( nm_unlink_artifacts ( string_data outp ) )
            ( string_free outp )
            ?? r {
                T o → {
                    ? ( output_success o ) {
                        ( output_free o )
                        ^ ( mcp_tool_result_text `OK — compiled successfully.` )
                    } {
                        : Json j ( nm_fail_from_output `build failed` o T )
                        ( output_free o )
                        ^ j
                    }
                }
                F e → { ^ ( nm_proc_err e ) }
            }
        }
        F → {}
    }
    ^ ( nm_missing_input )
}

// ── Tool: nurl_build_wasm (compile to wasm32-wasi, fully local) ──────
//
// Drives the wasmbuilder library in-process: nurlc → wasm32 IR rewrite →
// the toolchain's bundled zig cc. No build service, no network (a machine
// with no zig anywhere downloads it once — see the wasmbuilder README).
//
// Output shape:
//   * `out` argument given          → module written there, text summary
//   * `path` input, no `out`        → written next to the input as
//                                     <input minus .nu>.wasm
//   * inline `source`, no `out`     → JSON text with `wasm_base64`
//                                     (mirrors the playground MCP tool)
@ nm_tool_build_wasm Json args → Json {
    : ?String po ( nm_input_path args )
    ?? po {
        T p → {
            : b was_inline ( nm_is_temp ( string_data p ) )

            : ~ String outp ( string_new )
            : ?Json oj ( json_obj_get args `out` )
            ?? oj { T ov → { ( string_free outp ) = outp ( string_from ( json_str_data ov ) ) } F → {} }
            : ~ b b64_mode F
            ? == ( string_len outp ) 0 {
                ? was_inline {
                    = b64_mode T
                    ( string_free outp ) = outp ( nm_tmp_path `.wasm` )
                } {
                    ( string_free outp ) = outp ( string_from ( string_data p ) )
                    ? ( string_ends_with outp `.nu` ) {
                        : String t ( string_substr outp 0 - ( string_len outp ) 3 )
                        ( string_free outp ) = outp t
                    } {}
                    ( string_push_str outp `.wasm` )
                }
            } {}

            : ~ WbOpts wopts ( wb_opts_default )
            = . wopts opt `-O1`
            = . wopts quiet T
            : !v String r ( wb_build_file ( string_data p ) ( string_data outp ) wopts )
            ? was_inline { ( nm_unlink ( string_data p ) ) } {}
            ( string_free p )
            ?? r {
                T _ → {
                    : !i IoErr szr ( file_size ( string_data outp ) )
                    : i sz ?? szr { T sv → sv F _ → 0 }
                    ? b64_mode {
                        : !( Vec u ) IoErr br ( read_file_bytes ( string_data outp ) )
                        ( nm_unlink ( string_data outp ) )
                        ( string_free outp )
                        ?? br {
                            T bytes → {
                                : String b64 ( b64_encode_vec bytes )
                                ( vec_free [u] bytes )
                                : Json res ( json_obj_new )
                                ( json_obj_set res `status` ( json_str_lit `ok` ) )
                                ( json_obj_set res `wasm_bytes` ( json_int sz ) )
                                ( json_obj_set res `wasm_base64` ( json_str_lit ( string_data b64 ) ) )
                                ( string_free b64 )
                                : String body ( json_stringify res )
                                ( json_free res )
                                : Json j ( mcp_tool_result_text ( string_data body ) )
                                ( string_free body )
                                ^ j
                            }
                            F _ → { ^ ( mcp_tool_result_error `built module could not be read back` ) }
                        }
                    } {
                        : String msg ( string_from `OK — wrote ` )
                        ( string_push_str msg ( string_data outp ) )
                        ( string_push_str msg ` (` )
                        ( string_push_int msg sz )
                        ( string_push_str msg ` bytes of wasm32-wasi). Run it: wt run ` )
                        ( string_push_str msg ( string_data outp ) )
                        ( string_free outp )
                        : Json j ( mcp_tool_result_text ( string_data msg ) )
                        ( string_free msg )
                        ^ j
                    }
                }
                F e → {
                    ( string_free outp )
                    : Json j ( mcp_tool_result_error ( string_data e ) )
                    ( string_free e )
                    ^ j
                }
            }
        }
        F → {}
    }
    ^ ( nm_missing_input )
}

// ── Tool: nurl_run (compile then execute, capture output) ───────────

@ nm_run_result Output o → Json {
    : String body ( string_with_cap 256 )
    ( string_push_str body `[exit ` )
    ( string_push_int body ( output_exit_code o ) )
    ( string_push_str body `]\n` )
    ? > ( output_stdout_len o ) 0 { ( string_push_str body ( output_stdout o ) ) } {}
    ? > ( output_stderr_len o ) 0 {
        ( string_push_str body `\n[stderr]\n` )
        ( string_push_str body ( output_stderr o ) )
    } {}
    : Json j ( mcp_tool_result_text ( string_data body ) )
    ( string_free body )
    ^ j
}

@ nm_tool_run Json args → Json {
    : ?String po ( nm_input_path args )
    ?? po {
        T p → {
            : String outp ( nm_tmp_path `-bin` )
            : !Output ProcessErr br ( process_run2 `nurl` ( string_data p ) ( string_data outp ) )
            ? ( nm_is_temp ( string_data p ) ) { ( nm_unlink ( string_data p ) ) } {}
            ( string_free p )
            ?? br {
                T bo → {
                    ? ! ( output_success bo ) {
                        : Json j ( nm_fail_from_output `build failed` bo T )
                        ( output_free bo )
                        ( nm_unlink_artifacts ( string_data outp ) )
                        ( string_free outp )
                        ^ j
                    } {}
                    ( output_free bo )
                    : !Output ProcessErr rr ( process_run0 ( string_data outp ) )
                    ( nm_unlink_artifacts ( string_data outp ) )
                    ( string_free outp )
                    ?? rr {
                        T ro → {
                            : Json j ( nm_run_result ro )
                            ( output_free ro )
                            ^ j
                        }
                        F e → { ^ ( nm_proc_err e ) }
                    }
                }
                F e → {
                    ( string_free outp )
                    ^ ( nm_proc_err e )
                }
            }
        }
        F → {}
    }
    ^ ( nm_missing_input )
}

// ── Tool: nurl_fmt (canonical formatting via nurlfmt) ───────────────

@ nm_tool_fmt Json args → Json {
    : ?Json sj ( json_obj_get args `source` )
    ?? sj {
        T sv → {
            : ( Vec s ) a ( vec_new [s] )
            ( vec_push [s] a `--stdin` )
            : !Output ProcessErr r ( process_run `nurlfmt` a ( json_str_data sv ) )
            ( vec_free [s] a )
            ?? r {
                T o → {
                    ? ( output_success o ) {
                        : Json j ( mcp_tool_result_text ( output_stdout o ) )
                        ( output_free o )
                        ^ j
                    } {
                        : Json j ( nm_fail_from_output `format failed` o F )
                        ( output_free o )
                        ^ j
                    }
                }
                F e → { ^ ( nm_proc_err e ) }
            }
        }
        F → {}
    }
    : ?Json pj ( json_obj_get args `path` )
    ?? pj {
        T pv → {
            : !Output ProcessErr r ( process_run1 `nurlfmt` ( json_str_data pv ) )
            ?? r {
                T o → {
                    ? ( output_success o ) {
                        : Json j ( mcp_tool_result_text ( output_stdout o ) )
                        ( output_free o )
                        ^ j
                    } {
                        : Json j ( nm_fail_from_output `format failed` o F )
                        ( output_free o )
                        ^ j
                    }
                }
                F e → { ^ ( nm_proc_err e ) }
            }
        }
        F → {}
    }
    ^ ( nm_missing_input )
}

// ── Tool: nurl_list_stdlib ──────────────────────────────────────────

@ nm_tool_list_stdlib Json args → Json {
    : String root ( env_var_or `NURL_STDLIB` `` )
    ? == ( string_len root ) 0 {
        ( string_free root )
        ^ ( mcp_tool_result_error `NURL_STDLIB is not set — run via the installed toolchain shims, or export it manually` )
    } {}
    : !Output ProcessErr r ( process_run3 `find` ( string_data root ) `-name` `*.nu` )
    ( string_free root )
    ?? r {
        T o → {
            ? ( output_success o ) {
                : Json j ( mcp_tool_result_text ( output_stdout o ) )
                ( output_free o )
                ^ j
            } {
                : Json j ( nm_fail_from_output `listing failed` o T )
                ( output_free o )
                ^ j
            }
        }
        F e → { ^ ( nm_proc_err e ) }
    }
    ^ ( mcp_tool_result_error `internal` )
}

// ── Tool: nurl_read_stdlib ──────────────────────────────────────────

@ nm_has_dotdot s p → b {
    : i n ( nurl_str_len p )
    ? < n 2 { ^ F } {}
    : ~ i i 0
    ~ < i - n 1 {
        ? & == ( nurl_str_get p i ) 46 == ( nurl_str_get p + i 1 ) 46 { ^ T } {}
        = i + i 1
    }
    ^ F
}

@ nm_tool_read_stdlib Json args → Json {
    : ?Json nj ( json_obj_get args `name` )
    ?? nj {
        T nv → {
            : s name ( json_str_data nv )
            ? ( nm_has_dotdot name ) {
                ^ ( mcp_tool_result_error `invalid name: must not contain ".."` )
            } {}
            : String root ( env_var_or `NURL_STDLIB` `` )
            ? == ( string_len root ) 0 {
                ( string_free root )
                ^ ( mcp_tool_result_error `NURL_STDLIB is not set` )
            } {}
            : String full ( string_with_cap 160 )
            ? != ( nurl_str_starts name `/` ) 0 {
                ( string_push_str full name )
            } {
                ( string_push_str full ( string_data root ) )
                ( string_push_str full `/` )
                ( string_push_str full name )
            }
            ? == ( nurl_str_starts ( string_data full ) ( string_data root ) ) 0 {
                ( string_free full )
                ( string_free root )
                ^ ( mcp_tool_result_error `path escapes the stdlib root` )
            } {}
            : !String IoErr rd ( read_file ( string_data full ) )
            ( string_free full )
            ( string_free root )
            ?? rd {
                T contents → {
                    : Json j ( mcp_tool_result_text ( string_data contents ) )
                    ( string_free contents )
                    ^ j
                }
                F e → { ^ ( mcp_tool_result_error `could not read that stdlib file` ) }
            }
        }
        F → {}
    }
    ^ ( mcp_tool_result_error `provide a "name" (path under the stdlib root, e.g. core/string.nu)` )
}

// ── Tool descriptors ────────────────────────────────────────────────

// ── Tools: nurl_api + nurl_grep (shared engine: stdlib/ext/mcp_search) ─
//
// The value locally: an agent reading whole modules through
// nurl_read_stdlib pays ext/csv.nu's 63 KB for a "what csv functions
// exist" question — the declaration view is ~11 KB and a query returns
// just the matching blocks. The registry search rides along: "is there
// a package for X" works from any editor with only MCP tools.

@ nm_stdlib_root → String {
    ^ ( env_var_or `NURL_STDLIB` `` )
}

@ nm_tool_api Json args → Json {
    : String root ( nm_stdlib_root )
    ? == ( string_len root ) 0 {
        ( string_free root )
        ^ ( mcp_tool_result_error `NURL_STDLIB is not set — run via the installed toolchain shims, or export it manually` )
    } {}
    : ~ s module ``
    ?? ( json_obj_get args `module` ) {
        T mj → { ? ( json_is_str mj ) { = module ( json_as_str mj ) } {} }
        F _ → {}
    }
    : ~ s query ``
    ?? ( json_obj_get args `query` ) {
        T qj → { ? ( json_is_str qj ) { = query ( json_as_str qj ) } {} }
        F _ → {}
    }
    ? > ( nurl_str_len module ) 0 {
        ? ( nm_has_dotdot module ) {
            ( string_free root )
            ^ ( mcp_tool_result_error `bad 'module'` )
        } {}
        : String md ( msearch_api_module ( string_data root ) module )
        ( string_free root )
        ? == ( string_len md ) 0 {
            ( string_free md )
            ^ ( mcp_tool_result_error `module not found — 'module' is a path from nurl_list_stdlib, e.g. ext/csv.nu` )
        } {}
        : Json r ( mcp_tool_result_text ( string_data md ) )
        ( string_free md )
        ^ r
    } {}
    ? == ( nurl_str_len query ) 0 {
        ( string_free root )
        ^ ( mcp_tool_result_error `pass 'module' (a nurl_list_stdlib path, e.g. ext/csv.nu) or 'query' (search terms)` )
    } {}
    // No local examples corpus in an installed toolchain → "" skips it;
    // the registry fallback + exact-name footer still apply.
    : String rb ( msearch_default_registry )
    : String text ( msearch_api_query ( string_data root ) `` ( string_data rb ) query )
    ( string_free rb ) ( string_free root )
    : Json r ( mcp_tool_result_text ( string_data text ) )
    ( string_free text )
    ^ r
}

@ nm_tool_grep Json args → Json {
    : ~ s pattern ``
    ?? ( json_obj_get args `pattern` ) {
        T pj → { ? ( json_is_str pj ) { = pattern ( json_as_str pj ) } {} }
        F _ → {}
    }
    ? == ( nurl_str_len pattern ) 0 {
        ^ ( mcp_tool_result_error `missing 'pattern'` )
    } {}
    : ~ b word F
    ?? ( json_obj_get args `word` ) {
        T wj → { ? ( json_is_bool wj ) { = word ( json_as_bool wj ) } {} }
        F _ → {}
    }
    : ~ s where_s `all`
    ?? ( json_obj_get args `where` ) {
        T wj → { ? ( json_is_str wj ) { = where_s ( json_as_str wj ) } {} }
        F _ → {}
    }
    : b all != 0 ( nurl_str_eq where_s `all` )
    : b w_stdlib | all >= ( nurl_str_find where_s `stdlib` ) 0
    : b w_packages | all >= ( nurl_str_find where_s `package` ) 0
    : ~ String root ( string_new )
    ? w_stdlib {
        ( string_free root )
        = root ( nm_stdlib_root )
    } {}
    : ~ String rb ( string_new )
    ? w_packages {
        ( string_free rb )
        = rb ( msearch_default_registry )
    } {}
    : String text ( msearch_grep pattern word ( string_data root ) `` `` ( string_data rb ) )
    ( string_free root ) ( string_free rb )
    : Json r ( mcp_tool_result_text ( string_data text ) )
    ( string_free text )
    ^ r
}

@ nm_schema_api → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( nm_prop props `module` `Render ONE installed-stdlib module's API surface (signatures, doc comments, full type definitions — no function bodies). A nurl_list_stdlib path, e.g. 'ext/csv.nu'.` )
    ( nm_prop props `query` `Search every installed-stdlib module's declarations: space-separated terms, ALL must occur (case-insensitive) in a declaration's signature + doc comment + module path. Zero hits widen to the package registry; an exact package-name term is noted regardless. Ignored when 'module' is set.` )
    ( json_obj_set schema `properties` props )
    ^ schema
}

@ nm_schema_grep → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( nm_prop props `pattern` `Case-insensitive substring to find; results are path:line: text, boundary-clean matches ranked first. For short acronyms (under ~5 chars) pass word=true.` )
    ( nm_prop props `where` `Scope: 'stdlib' (installed), 'packages' (registry name+description), or 'all' (default).` )
    ( nm_prop props `word` `true = only word-boundary lines (adjacent byte not a letter; underscore and digits count as boundaries).` )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `pattern` ) )
    ( json_obj_set schema `properties` props )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ nm_prop Json props s name s desc → v {
    : Json p ( json_obj_new )
    ( json_obj_set p `type` ( json_str_lit `string` ) )
    ( json_obj_set p `description` ( json_str_lit desc ) )
    ( json_obj_set props name p )
}

@ nm_schema_src_path → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( nm_prop props `source` `Inline NURL source. Provide this OR "path".` )
    ( nm_prop props `path` `Path to a .nu file on the host. Provide this OR "source".` )
    ( json_obj_set schema `properties` props )
    ^ schema
}

@ nm_schema_name → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    : Json props ( json_obj_new )
    ( nm_prop props `name` `Path under the stdlib root, e.g. "core/string.nu".` )
    ( json_obj_set schema `properties` props )
    : Json req ( json_arr_new )
    ( json_arr_push req ( json_str_lit `name` ) )
    ( json_obj_set schema `required` req )
    ^ schema
}

@ nm_schema_empty → Json {
    : Json schema ( json_obj_new )
    ( json_obj_set schema `type` ( json_str_lit `object` ) )
    ^ schema
}

// Policy predicates (read the globals set in main).
@ nm_build_ok → b { ^ ? == g_read_only 0 T F }

@ nm_run_ok → b { ^ ? & == g_read_only 0 != g_run_allowed 0 T F }

@ build_tools_list → ( Vec Json ) {
    : ( Vec Json ) tools ( vec_new [Json] )
    ? ( nm_build_ok ) {
        ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_build`
        `Compile NURL (inline "source" or a "path") with the local toolchain; reports success or compiler diagnostics. Does not run the program.`
        ( nm_schema_src_path ) ) )
    } {}
    ? ( nm_build_ok ) {
        ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_build_wasm`
        `Compile NURL (inline "source" or a "path") to a wasm32-wasi module, fully locally (no build service). Optional "out" = output path; a "path" input defaults to <input>.wasm next to it; inline "source" without "out" returns JSON with wasm_base64.`
        ( nm_schema_src_path ) ) )
    } {}
    ? ( nm_run_ok ) {
        ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_run`
        `Compile AND run NURL with the local toolchain; returns the program's exit code, stdout, and stderr.`
        ( nm_schema_src_path ) ) )
    } {}
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_check`
    `Front-end only: type-check and borrow-check NURL without producing a binary. Fast. Reports diagnostics.`
    ( nm_schema_src_path ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_fmt`
    `Format NURL to canonical form with nurlfmt; returns the formatted source.`
    ( nm_schema_src_path ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_list_stdlib`
    `List the .nu modules in the installed standard library (under $NURL_STDLIB).`
    ( nm_schema_empty ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_read_stdlib`
    `Read one module from the installed standard library by relative path.`
    ( nm_schema_name ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_api`
    `A stdlib module's API surface, or a search across all of them — strongly prefer this over nurl_read_stdlib (whole modules waste context; ext/csv.nu is 63 KB, its API surface 11 KB, one matching declaration ~0.3 KB). module='ext/csv.nu' renders signatures + doc comments + type definitions; query='csv quote' finds matching declarations. Zero hits widen to the package registry; an exact package-name term is footnoted regardless.`
    ( nm_schema_api ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_grep`
    `Case-insensitive search across the installed stdlib (path:line: text; word-boundary matches ranked first, in-word substring hits in a labeled tail) and the package registry (name + description) — "is there a package for X" works from any MCP-only editor. word=true for short acronyms.`
    ( nm_schema_grep ) ) )
    ^ tools
}

@ dispatch_tool s name Json args → Json {
    ? != ( nurl_str_eq name `nurl_build` ) 0 {
        ? ( nm_build_ok ) { ^ ( nm_tool_build args ) }
        { ^ ( mcp_tool_result_error `nurl_build is disabled (--read-only)` ) }
    } {}
    ? != ( nurl_str_eq name `nurl_build_wasm` ) 0 {
        ? ( nm_build_ok ) { ^ ( nm_tool_build_wasm args ) }
        { ^ ( mcp_tool_result_error `nurl_build_wasm is disabled (--read-only)` ) }
    } {}
    ? != ( nurl_str_eq name `nurl_run` ) 0 {
        ? ( nm_run_ok ) { ^ ( nm_tool_run args ) }
        { ^ ( mcp_tool_result_error `nurl_run is disabled — it is unsandboxed code execution; over HTTP pass --allow-run to enable it (and it is off entirely under --read-only)` ) }
    } {}
    ? != ( nurl_str_eq name `nurl_check` ) 0 { ^ ( nm_tool_check args ) } {}
    ? != ( nurl_str_eq name `nurl_fmt` ) 0 { ^ ( nm_tool_fmt args ) } {}
    ? != ( nurl_str_eq name `nurl_list_stdlib` ) 0 { ^ ( nm_tool_list_stdlib args ) } {}
    ? != ( nurl_str_eq name `nurl_read_stdlib` ) 0 { ^ ( nm_tool_read_stdlib args ) } {}
    ? != ( nurl_str_eq name `nurl_api` ) 0 { ^ ( nm_tool_api args ) } {}
    ? != ( nurl_str_eq name `nurl_grep` ) 0 { ^ ( nm_tool_grep args ) } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── JSON-RPC method handlers (return-style: shape from
// examples/mcp_echo_server_http.nu, used by both transports) ─────────

@ handle_initialize Json id → Json {
    : Json result ( mcp_initialize_result `nurl-mcp` ( nm_version ) )
    ^ ( mcp_response_result id result )
}

@ handle_ping Json id → Json {
    : Json empty ( json_obj_new )
    ^ ( mcp_response_result id empty )
}

@ handle_tools_list Json id → Json {
    : ( Vec Json ) tools ( build_tools_list )
    : Json result ( mcp_tools_list_result tools )
    ^ ( mcp_response_result id result )
}

@ handle_tools_call Json id Json params → Json {
    : ?Json name_j ( json_obj_get params `name` )
    ?? name_j {
        T nv → {
            : s name ( json_str_data nv )
            : ?Json args_j ( json_obj_get params `arguments` )
            : Json args ?? args_j {
                T av → ( json_clone av )
                F → ( json_obj_new )
            }
            : Json result ( dispatch_tool name args )
            ( json_free args )
            ^ ( mcp_response_result id result )
        }
        F → {
            ^ ( mcp_response_error id mcp_err_invalid_params
            `tools/call requires a "name" parameter` )
        }
    }
}

@ handle_unknown_method Json id s method → Json {
    : i mlen ( nurl_str_len method )
    : String msg ( string_with_cap + 32 mlen )
    ( string_push_str msg `unknown method: ` )
    ( string_push_str msg method )
    : Json err ( mcp_response_error id mcp_err_method_not_found ( string_data msg ) )
    ( string_free msg )
    ^ err
}

// Transport-agnostic dispatcher: request Json → Some(response) for a
// request, or None for a notification (the caller drops it / replies 202).
@ dispatch Json req → ?Json {
    : ?Json method_j ( json_obj_get req `method` )
    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )
            : ?Json id_opt ( json_obj_get req `id` )
            ?? id_opt {
                T id → {
                    ? != ( nurl_str_eq method `initialize` ) 0 {
                        ^ @ ?Json { T ( handle_initialize id ) }
                    } {}
                    ? != ( nurl_str_eq method `ping` ) 0 {
                        ^ @ ?Json { T ( handle_ping id ) }
                    } {}
                    ? != ( nurl_str_eq method `tools/list` ) 0 {
                        ^ @ ?Json { T ( handle_tools_list id ) }
                    } {}
                    ? != ( nurl_str_eq method `tools/call` ) 0 {
                        : ?Json params_j ( json_obj_get req `params` )
                        : Json params ?? params_j {
                            T pv → ( json_clone pv )
                            F → ( json_obj_new )
                        }
                        : Json out ( handle_tools_call id params )
                        ( json_free params )
                        ^ @ ?Json { T out }
                    } {}
                    ^ @ ?Json { T ( handle_unknown_method id method ) }
                }
                F → {
                    ? != ( nurl_str_eq method `notifications/initialized` ) 0 {
                        ( mcp_log `client initialized` )
                    } {}
                    ^ @ ?Json { F }
                }
            }
        }
        F → {
            ( mcp_log `request without method, ignoring` )
            ^ @ ?Json { F }
        }
    }
}

// ── stdio transport ─────────────────────────────────────────────────

@ stdio_loop → v {
    : ~ b running T
    ~ running {
        : ?Json msg ( mcp_read_request )
        ?? msg {
            T req → {
                : ?Json reply ( dispatch req )
                ( json_free req )
                ?? reply {
                    T resp → ( mcp_send_message resp )
                    F empty → ( json_free empty )
                }
            }
            F → { = running F }
        }
    }
}

// ── HTTP transport ───────────────────────────────────────────────────
//
// The wire protocol (POST single/batch, GET SSE probe, DELETE,
// Mcp-Session-Id echo, CORS + preflight) comes from the stdlib's
// Streamable-HTTP facade (`ext/mcp_http.nu` — the same plumbing
// swarm-mcp serves through); this file only layers bearer-token auth
// around it. CORS headers for the auth reject, matching the facade's.

@ nm_cors HttpResponse r → v {
    ( response_set_header r `Access-Control-Allow-Origin` `*` )
    ( response_set_header r `Access-Control-Allow-Headers` `Content-Type, Authorization, Mcp-Session-Id` )
    ( response_set_header r `Access-Control-Allow-Methods` `POST, GET, DELETE, OPTIONS` )
}

@ nm_authed HttpRequest req → b {
    ? == ( nurl_str_len g_token ) 0 { ^ T } {}
    : ?String av ( header_get . req headers `Authorization` )
    ?? av {
        T s → {
            : String expect ( string_from `Bearer ` )
            ( string_push_str expect g_token )
            : b ok ? != ( nurl_str_eq ( string_data s ) ( string_data expect ) ) 0 T F
            ( string_free expect )
            ( string_free s )
            ^ ok
        }
        F → { ^ F }
    }
    ^ F
}

@ nm_is_loopback s host → b {
    ? != ( nurl_str_eq host `127.0.0.1` ) 0 { ^ T } {}
    ? != ( nurl_str_eq host `::1` ) 0 { ^ T } {}
    ? != ( nurl_str_eq host `localhost` ) 0 { ^ T } {}
    ^ F
}

@ run_http s host i port → i {
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            // The facade handles the whole MCP wire protocol; auth wraps it.
            // OPTIONS bypasses auth (browser preflights carry no headers).
            : ( @ HttpResponse HttpRequest ) inner ( mcp_http_handler \ Json rq → ?Json { ^ ( dispatch rq ) } )
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                ? != ( nurl_str_eq ( string_data . req method ) `OPTIONS` ) 0 { ^ ( inner req ) } {}
                ? ! ( nm_authed req ) {
                    : HttpResponse r ( response_text 401 `Unauthorized\n` )
                    ( response_set_header r `WWW-Authenticate` `Bearer` )
                    ( nm_cors r )
                    ^ r
                } {}
                ^ ( inner req )
            }
            : HttpServer srv ( server_new listener h )
            : !v NetErr rr ( server_run srv )
            ( server_stop srv )
            ?? rr {
                T → { ^ 0 }
                F e → {
                    ( nurl_eprint `[mcp] server error: ` )
                    ( nurl_eprint ( net_err_name e ) )
                    ( nurl_eprint `\n` )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `[mcp] cannot bind ` )
            ( nurl_eprint host )
            ( nurl_eprint `: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
    ^ 1
}

@ main → i {
    : ArgParser p ( args_new `nurl-mcp` `Local MCP server for the NURL toolchain (stdio by default; --http to serve over HTTP).` )
    ( args_flag p `http` 0 `Serve over HTTP instead of stdio` )
    ( args_opt p `host` 0 `ADDR` `HTTP bind address (default 127.0.0.1)` )
    ( args_opt p `port` 0 `N` `HTTP port (default 8080)` )
    ( args_opt p `token` 0 `TOK` `Require "Authorization: Bearer TOK" on HTTP requests` )
    ( args_flag p `read-only` 0 `Expose only read/check/fmt tools (no build, no run)` )
    ( args_flag p `allow-run` 0 `Allow nurl_run over HTTP (off by default; stdio always allows it)` )
    : b ok ( args_parse_argv p )
    ? ! ok {
        : String u ( args_usage p )
        ( nurl_eprint ( string_data u ) )
        ( string_free u )
        ( args_free p )
        ^ 2
    } {}

    : b want_http ( args_present p `http` )
    : b read_only ( args_present p `read-only` )
    : b allow_run ( args_present p `allow-run` )
    : String host ( args_value_or p `host` `127.0.0.1` )
    : String ports ( args_value_or p `port` `8080` )
    : String token ( args_value_or p `token` `` )
    : i port ( nurl_str_to_int ( string_data ports ) )

    = g_read_only ? read_only 1 0
    ? want_http {
        = g_run_allowed ? & ! read_only allow_run 1 0
    } {
        = g_run_allowed ? read_only 0 1
    }
    = g_token ( string_data token )

    : ~ i rc 0
    ? want_http {
        ? & ! ( nm_is_loopback ( string_data host ) ) == ( string_len token ) 0 {
            ( nurl_eprint `[mcp] refusing to bind a non-loopback address without --token (HTTP build/run is unsandboxed code execution)\n` )
            = rc 2
        } {
            ? == ( string_len token ) 0 {
                ( mcp_log `WARNING: serving HTTP with no --token — any local client can drive the toolchain` )
            } {}
            ? ( nm_run_ok ) {
                ( nm_log_banner `ready (http) — nurl_run ENABLED` )
            } {
                ( nm_log_banner `ready (http) — nurl_run disabled (pass --allow-run to enable)` )
            }
            = rc ( run_http ( string_data host ) port )
        }
    } {
        ( nm_log_banner `ready (stdio)` )
        ( stdio_loop )
        ( mcp_log `bye` )
        = rc 0
    }

    ( args_free p )
    ( string_free host )
    ( string_free ports )
    ( string_free token )
    ^ rc
}
