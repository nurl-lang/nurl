// nurl-mcp — a local MCP (Model Context Protocol) server for the NURL
// toolchain. The LLM-facing counterpart of nurl-lsp: where nurl-lsp serves
// editors over LSP, nurl-mcp serves an LLM agent over MCP so it can drive the
// *locally installed* compiler — build, run, type-check, format NURL, and read
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
// that spawned this server talks to it. A network (`--http`) transport with
// token auth is intentionally deferred to a later version.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/posix.nu`

// ── Temp-file plumbing ──────────────────────────────────────────────
//
// Inline `source` is written to a unique temp .nu so the file-oriented
// compiler can read it. `nm_input_temp` records whether the resolved path is
// such a temp (so we delete it afterward) vs. a user-supplied `path` (left
// untouched). Single-threaded stdio server ⇒ the global is race-free.

: ~ i nm_input_temp 0
: ~ i nm_seq 0

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
    = nm_input_temp 0
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
                T → { = nm_input_temp 1 ^ @ ?String { T tmp } }
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
            : i temp nm_input_temp
            : !Output ProcessErr r ( process_run1 `nurlc` ( string_data p ) )
            ? != temp 0 { ( nm_unlink ( string_data p ) ) } {}
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
            : i temp nm_input_temp
            : String outp ( nm_tmp_path `-bin` )
            : !Output ProcessErr r ( process_run2 `nurl` ( string_data p ) ( string_data outp ) )
            ? != temp 0 { ( nm_unlink ( string_data p ) ) } {}
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
            : i temp nm_input_temp
            : String outp ( nm_tmp_path `-bin` )
            : !Output ProcessErr br ( process_run2 `nurl` ( string_data p ) ( string_data outp ) )
            ? != temp 0 { ( nm_unlink ( string_data p ) ) } {}
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

@ build_tools_list → ( Vec Json ) {
    : ( Vec Json ) tools ( vec_new [Json] )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_build`
    `Compile NURL (inline "source" or a "path") with the local toolchain; reports success or compiler diagnostics. Does not run the program.`
    ( nm_schema_src_path ) ) )
    ( vec_push [Json] tools ( mcp_tool_descriptor `nurl_run`
    `Compile AND run NURL with the local toolchain; returns the program's exit code, stdout, and stderr.`
    ( nm_schema_src_path ) ) )
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
    ^ tools
}

@ dispatch_tool s name Json args → Json {
    ? != ( nurl_str_eq name `nurl_build` ) 0 { ^ ( nm_tool_build args ) } {}
    ? != ( nurl_str_eq name `nurl_run` ) 0 { ^ ( nm_tool_run args ) } {}
    ? != ( nurl_str_eq name `nurl_check` ) 0 { ^ ( nm_tool_check args ) } {}
    ? != ( nurl_str_eq name `nurl_fmt` ) 0 { ^ ( nm_tool_fmt args ) } {}
    ? != ( nurl_str_eq name `nurl_list_stdlib` ) 0 { ^ ( nm_tool_list_stdlib args ) } {}
    ? != ( nurl_str_eq name `nurl_read_stdlib` ) 0 { ^ ( nm_tool_read_stdlib args ) } {}
    ^ ( mcp_tool_result_error `unknown tool` )
}

// ── JSON-RPC method handlers (shape from examples/mcp_echo_server.nu) ─

@ handle_initialize Json id → v {
    : Json result ( mcp_initialize_result `nurl-mcp` `0.1.0` )
    ( mcp_send_message ( mcp_response_result id result ) )
}

@ handle_ping Json id → v {
    : Json empty ( json_obj_new )
    ( mcp_send_message ( mcp_response_result id empty ) )
}

@ handle_tools_list Json id → v {
    : ( Vec Json ) tools ( build_tools_list )
    : Json result ( mcp_tools_list_result tools )
    ( mcp_send_message ( mcp_response_result id result ) )
}

@ handle_tools_call Json id Json params → v {
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
            ( mcp_send_message ( mcp_response_result id result ) )
        }
        F → {
            ( mcp_send_message
            ( mcp_response_error id mcp_err_invalid_params
            `tools/call requires a "name" parameter` ) )
        }
    }
}

@ handle_unknown_method Json id s method → v {
    : i mlen ( nurl_str_len method )
    : String msg ( string_with_cap + 32 mlen )
    ( string_push_str msg `unknown method: ` )
    ( string_push_str msg method )
    ( mcp_send_message
    ( mcp_response_error id mcp_err_method_not_found ( string_data msg ) ) )
    ( string_free msg )
}

@ handle Json req → v {
    : ?Json method_j ( json_obj_get req `method` )
    ?? method_j {
        T mv → {
            : s method ( json_str_data mv )
            : ?Json id_opt ( json_obj_get req `id` )
            ?? id_opt {
                T id → {
                    ? != ( nurl_str_eq method `initialize` ) 0 {
                        ( handle_initialize id )
                    } {
                        ? != ( nurl_str_eq method `ping` ) 0 {
                            ( handle_ping id )
                        } {
                            ? != ( nurl_str_eq method `tools/list` ) 0 {
                                ( handle_tools_list id )
                            } {
                                ? != ( nurl_str_eq method `tools/call` ) 0 {
                                    : ?Json params_j ( json_obj_get req `params` )
                                    : Json params ?? params_j {
                                        T pv → ( json_clone pv )
                                        F → ( json_obj_new )
                                    }
                                    ( handle_tools_call id params )
                                    ( json_free params )
                                } {
                                    ( handle_unknown_method id method )
                                } } } }
                }
                F → {
                    ? != ( nurl_str_eq method `notifications/initialized` ) 0 {
                        ( mcp_log `client initialized` )
                    } {}
                }
            }
        }
        F → {
            ( mcp_log `request without method, ignoring` )
        }
    }
}

@ main → i {
    ( mcp_log `nurl-mcp 0.1.0 ready (stdio)` )
    : ~ b running T
    ~ running {
        : ?Json msg ( mcp_read_request )
        ?? msg {
            T req → {
                ( handle req )
                ( json_free req )
            }
            F → {
                = running F
            }
        }
    }
    ( mcp_log `bye` )
    ^ 0
}
