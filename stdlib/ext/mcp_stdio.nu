// stdlib/ext/mcp_stdio.nu — MCP (Model Context Protocol) client over
// stdio. Many MCP servers (filesystem, git, Postgres, …) ship as
// command-line programs that speak newline-delimited JSON-RPC on
// stdin/stdout — this module spawns one as a child process and drives
// it through `tools/list`, `tools/call`, etc. Symmetric counterpart to
// `mcp_client.nu` (HTTP transport) so a NURL host can consume any MCP
// server regardless of how it was packaged.
//
// Layered on:
//
//   stdlib/std/process.nu  → process_spawn / proc_read_line / proc_write_line
//   stdlib/ext/json.nu     → json_stringify / json_parse / json_obj_get/set
//
// Wire format — one request per line, one response per line. The MCP
// stdio spec (`MCP §3.1 — stdio transport`) requires:
//   * each JSON-RPC message followed by a single '\n'
//   * no embedded newlines in the message itself
//   * stderr is for diagnostics, NOT JSON-RPC traffic
// `json_stringify` already escapes embedded '\n' as `\n`, so writing
// `( json_stringify req ) + '\n'` is conformant.
//
// API:
//
//   ( mcp_stdio_spawn s cmd ( Vec s ) args )       → ! McpStdioClient McpStdioErr
//   ( mcp_stdio_spawn0 s cmd )                     → ! McpStdioClient McpStdioErr
//   ( mcp_stdio_spawn1 s cmd s a0 )                → ! McpStdioClient McpStdioErr
//   ( mcp_stdio_spawn2 s cmd s a0 s a1 )           → ! McpStdioClient McpStdioErr
//
//   ( mcp_stdio_call McpStdioClient c s method ? Json params i timeout_ms )
//                                                  → ! Json McpStdioErr
//
//   ( mcp_stdio_initialize  McpStdioClient c s name s ver ) → ! Json McpStdioErr
//   ( mcp_stdio_ping        McpStdioClient c )              → ! Json McpStdioErr
//   ( mcp_stdio_tools_list  McpStdioClient c )              → ! ( Vec Json ) McpStdioErr
//   ( mcp_stdio_tools_call  McpStdioClient c s name Json args )
//                                                  → ! Json McpStdioErr
//   ( mcp_stdio_prompts_list   McpStdioClient c )  → ! ( Vec Json ) McpStdioErr
//   ( mcp_stdio_resources_list McpStdioClient c )  → ! ( Vec Json ) McpStdioErr
//
//   ( mcp_stdio_response_is_error      Json r ) → b
//   ( mcp_stdio_response_error_code    Json r ) → i
//   ( mcp_stdio_response_error_message Json r ) → s
//
//   ( mcp_stdio_free McpStdioClient c )            → v
//   ( mcp_stdio_err_name McpStdioErr e )           → s
//
// Memory model — single-owner, LLM-friendly:
//
//   * `mcp_stdio_spawn` returns an OWNED McpStdioClient that wraps the
//     child handle. Caller MUST `mcp_stdio_free` exactly once on the
//     Ok arm. Free reaps the child (SIGTERM then SIGKILL fallback).
//   * `params` / `args` Json values are CONSUMED by the call.
//   * `mcp_stdio_call` returns the full JSON-RPC response on success;
//     server-reported `error` envelopes ARE the Ok arm — distinguish
//     via `mcp_stdio_response_is_error`. McpStdioErr covers transport,
//     framing, JSON-shape, and timeout failures.
//   * Per-call timeout is in MILLISECONDS; <= 0 means block forever.
//     The convenience wrappers default to 30 seconds.

$ `stdlib/std/process.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── McpStdioClient ──────────────────────────────────────────────────

: McpStdioClient {
    ProcChild child
    i default_timeout_ms
}

// ── McpStdioErr ─────────────────────────────────────────────────────

: | McpStdioErr {
    McpStdioSpawn  // child failed to start (cmd missing, fork/exec err)
    McpStdioIo  // pipe write/read failure mid-conversation
    McpStdioTimeout  // no response inside the call's deadline
    McpStdioEof  // child closed its stdout (server crash / clean exit)
    McpStdioJson  // server replied with non-JSON / malformed JSON
    McpStdioProtocol  // missing jsonrpc/id/result/error envelope fields
    McpStdioOther
}

@ mcp_stdio_err_name McpStdioErr e → s {
    ^ ?? e {
        McpStdioSpawn → `McpStdioSpawn`
        McpStdioIo → `McpStdioIo`
        McpStdioTimeout → `McpStdioTimeout`
        McpStdioEof → `McpStdioEof`
        McpStdioJson → `McpStdioJson`
        McpStdioProtocol → `McpStdioProtocol`
        McpStdioOther → `McpStdioOther`
    }
}

@ __mcp_stdio_proc_to_err ProcessErr pe → McpStdioErr {
    ^ ?? pe {
        ProcessNotFound → @ McpStdioErr { McpStdioSpawn }
        ProcessExecFailed → @ McpStdioErr { McpStdioSpawn }
        ProcessIo → @ McpStdioErr { McpStdioIo }
        ProcessOther → @ McpStdioErr { McpStdioOther }
    }
}

// ── Spawn ───────────────────────────────────────────────────────────

@ mcp_stdio_spawn s cmd ( Vec s ) args → !McpStdioClient McpStdioErr {
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ?? res {
        T child → {
            : McpStdioClient cli @ McpStdioClient { child 30000 }
            ^ @ !McpStdioClient McpStdioErr { T cli }
        }
        F pe → {
            : McpStdioErr me ( __mcp_stdio_proc_to_err pe )
            ^ @ !McpStdioClient McpStdioErr { F me }
        }
    }
}

@ mcp_stdio_spawn0 s cmd → !McpStdioClient McpStdioErr {
    : ( Vec s ) av ( vec_new [s] )
    : !McpStdioClient McpStdioErr r ( mcp_stdio_spawn cmd av )
    ( vec_free [s] av )
    ^ r
}

@ mcp_stdio_spawn1 s cmd s a0 → !McpStdioClient McpStdioErr {
    : ( Vec s ) av ( vec_with_cap [s] 1 )
    ( vec_push [s] av a0 )
    : !McpStdioClient McpStdioErr r ( mcp_stdio_spawn cmd av )
    ( vec_free [s] av )
    ^ r
}

@ mcp_stdio_spawn2 s cmd s a0 s a1 → !McpStdioClient McpStdioErr {
    : ( Vec s ) av ( vec_with_cap [s] 2 )
    ( vec_push [s] av a0 )
    ( vec_push [s] av a1 )
    : !McpStdioClient McpStdioErr r ( mcp_stdio_spawn cmd av )
    ( vec_free [s] av )
    ^ r
}

@ mcp_stdio_free McpStdioClient c → v {
    ( proc_free . c child )
}

// ── Envelope construction ───────────────────────────────────────────

@ __mcp_stdio_envelope i id s method ? Json params → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_int id ) )
    ( json_obj_set out `method` ( json_str_lit method ) )
    ?? params {
        T p → ( json_obj_set out `params` p )
        F _ → {}
    }
    ^ out
}

// ── Single round-trip ───────────────────────────────────────────────

@ mcp_stdio_call McpStdioClient c s method ? Json params i timeout_ms → !Json McpStdioErr {
    // Millisecond clock as the JSON-RPC id — round-trips for one call,
    // human-readable in logs. Collisions matter only if a single client
    // fires more than one call inside the same millisecond AND the server
    // pipelines responses out of order; not a realistic MCP pattern.
    : i id ( now_ms )
    : i to ? > timeout_ms 0 timeout_ms . c default_timeout_ms

    // Build & write the request line.
    : Json req ( __mcp_stdio_envelope id method params )
    : String body ( json_stringify req )
    ( json_free req )
    : i wn ( proc_write_line . c child ( string_data body ) )
    ( string_free body )
    ? < wn 0 {
        // A failed write almost always means the child exited and
        // closed its stdin read-end (EPIPE). Disambiguate: if its
        // stdout is also at EOF the server is simply gone (McpStdioEof,
        // same as a write that lands then reads EOF); otherwise it is a
        // genuine transient pipe fault (McpStdioIo).
        //
        // proc_eof's flag is set lazily — it goes true only once a
        // `read(2)` has observed zero bytes. At write-fail time we have
        // not read from the child's stdout yet, so the flag is still
        // false even when the child has actually died. Force an EOF
        // observation here by attempting a short read probe: if the
        // child is gone the kernel returns 0 immediately (POLLHUP +
        // read → 0), the eof flag flips to true, and we land on
        // McpStdioEof. A genuinely-alive-but-broken-stdin pipe (the
        // McpStdioIo case proper) returns EAGAIN inside the timeout
        // window and the flag stays false.
        //
        // Why this used to flake: `false` exits before our write
        // arrives at the kernel ~50% of runs. The write-succeeded
        // path always read EOF and reported McpStdioEof; the write-
        // failed path skipped the EOF probe and reported McpStdioIo.
        // Probing here collapses both into McpStdioEof for dead
        // servers, which is what callers actually want.
        : ?String drop ( proc_read_line . c child 50 )
        ?? drop {
            T s → ( string_free s )
            F _ → {}
        }
        ? ( proc_eof . c child ) {
            ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioEof } }
        } {
            ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioIo } }
        }
    } {}

    // Read response lines until we find one whose `id` matches our request.
    // MCP servers may interleave server→client notifications (no `id`
    // field) or unrelated notifications — skip those without erroring.
    // Practical loop bound: 64 frames per call. Most servers reply directly.
    : ~ i tries 64
    ~ > tries 0 {
        = tries - tries 1
        : ?String line_o ( proc_read_line . c child to )
        ?? line_o {
            T line → {
                : !Json JsonError pj ( json_parse ( string_data line ) )
                ( string_free line )
                ?? pj {
                    T j → {
                        // Match on id field. Only return when ids align so we
                        // don't surface a stale notification for the wrong call.
                        : ?Json idj ( json_obj_get j `id` )
                        ?? idj {
                            T idjv → {
                                : ?i idn ( json_num_as_i idjv )
                                ?? idn {
                                    T n → {
                                        ? == n id {
                                            ^ @ !Json McpStdioErr { T j }
                                        } {
                                            // Different id — skip and keep reading.
                                            ( json_free j )
                                        }
                                    }
                                    F _ → ( json_free j )
                                }
                            }
                            F _ → {
                                // No id ⇒ server-initiated notification. Drop it.
                                ( json_free j )
                            }
                        }
                    }
                    F _ → {
                        // Malformed line. Surface as a JSON error rather than try
                        // to recover — MCP servers must emit one valid JSON object
                        // per line.
                        ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioJson } }
                    }
                }
            }
            F _ → {
                // None ⇒ either timeout or EOF on stdout. proc_eof tells us which.
                ? ( proc_eof . c child ) {
                    ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioEof } }
                } {
                    ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioTimeout } }
                }
            }
        }
    }
    ^ @ !Json McpStdioErr { F @ McpStdioErr { McpStdioProtocol } }
}

// ── Convenience wrappers ────────────────────────────────────────────

@ mcp_stdio_initialize McpStdioClient c s client_name s client_version → !Json McpStdioErr {
    : Json caps ( json_obj_new )
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit client_name ) )
    ( json_obj_set info `version` ( json_str_lit client_version ) )
    : Json params ( json_obj_new )
    // Handshake-era revision — `initialize` IS the legacy path; the
    // modern (2026-07-28) revision has no handshake, see
    // mcp_stdio_discover.
    ( json_obj_set params `protocolVersion` ( json_str_lit ( mcp_protocol_version_initialize ) ) )
    ( json_obj_set params `capabilities` caps )
    ( json_obj_set params `clientInfo` info )
    ^ ( mcp_stdio_call c `initialize` @ ?Json { T params } 0 )
}

// server/discover (2026-07-28) — ALSO the stdio backward-compat probe:
// a dual-era client SHOULD send this first; a DiscoverResult (or a
// recognized modern error like -32022) identifies a modern server,
// anything else (e.g. -32601 method not found) identifies a legacy
// server → fall back to mcp_stdio_initialize.
@ mcp_stdio_discover McpStdioClient c s client_name s client_version → !Json McpStdioErr {
    : Json params ( json_obj_new )
    ( json_obj_set params `_meta` ( mcp_client_meta client_name client_version ) )
    ^ ( mcp_stdio_call c `server/discover` @ ?Json { T params } 0 )
}

@ mcp_stdio_ping McpStdioClient c → !Json McpStdioErr {
    ^ ( mcp_stdio_call c `ping` @ ?Json { F } 0 )
}

@ __mcp_stdio_extract_array Json r s field → ( Vec Json ) {
    : ( Vec Json ) out ( vec_new [Json] )
    : ?Json result ( json_obj_get r `result` )
    ?? result {
        T res → {
            : ?Json arr_o ( json_obj_get res field )
            ?? arr_o {
                T arr → {
                    ( json_arr_each arr \ Json el → v {
                        ( vec_push [Json] out ( json_clone el ) )
                    } )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ mcp_stdio_tools_list McpStdioClient c → !( Vec Json ) McpStdioErr {
    : !Json McpStdioErr r ( mcp_stdio_call c `tools/list` @ ?Json { F } 0 )
    ?? r {
        T resp → {
            : ( Vec Json ) tools ( __mcp_stdio_extract_array resp `tools` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpStdioErr { T tools }
        }
        F e → ^ @ !( Vec Json ) McpStdioErr { F e }
    }
}

@ mcp_stdio_prompts_list McpStdioClient c → !( Vec Json ) McpStdioErr {
    : !Json McpStdioErr r ( mcp_stdio_call c `prompts/list` @ ?Json { F } 0 )
    ?? r {
        T resp → {
            : ( Vec Json ) ps ( __mcp_stdio_extract_array resp `prompts` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpStdioErr { T ps }
        }
        F e → ^ @ !( Vec Json ) McpStdioErr { F e }
    }
}

@ mcp_stdio_resources_list McpStdioClient c → !( Vec Json ) McpStdioErr {
    : !Json McpStdioErr r ( mcp_stdio_call c `resources/list` @ ?Json { F } 0 )
    ?? r {
        T resp → {
            : ( Vec Json ) rs ( __mcp_stdio_extract_array resp `resources` )
            ( json_free resp )
            ^ @ !( Vec Json ) McpStdioErr { T rs }
        }
        F e → ^ @ !( Vec Json ) McpStdioErr { F e }
    }
}

@ mcp_stdio_tools_call McpStdioClient c s name Json args → !Json McpStdioErr {
    : Json params ( json_obj_new )
    ( json_obj_set params `name` ( json_str_lit name ) )
    ( json_obj_set params `arguments` args )
    ^ ( mcp_stdio_call c `tools/call` @ ?Json { T params } 0 )
}

// ── Response inspection ─────────────────────────────────────────────

@ mcp_stdio_response_is_error Json r → b {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T _ → ^ T
        F _ → ^ F
    }
}

@ mcp_stdio_response_error_code Json r → i {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T err → {
            : ?Json codeo ( json_obj_get err `code` )
            ?? codeo {
                T j → {
                    : ?i n ( json_num_as_i j )
                    ?? n {
                        T x → { ^ x }
                        F _ → { ^ 0 }
                    }
                }
                F _ → { ^ 0 }
            }
        }
        F _ → { ^ 0 }
    }
    ^ 0
}

@ mcp_stdio_response_error_message Json r → s {
    : ?Json e ( json_obj_get r `error` )
    ?? e {
        T err → {
            : ?Json m ( json_obj_get err `message` )
            ?? m {
                T j → ^ ( json_str_data j )
                F _ → ^ ``
            }
        }
        F _ → ^ ``
    }
    ^ ``
}
