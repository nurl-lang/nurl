// mcp_stdio_basic.nu — exercises stdlib/ext/mcp_stdio.nu.
//
// Trick: `cat` echoes every line we write back unchanged. Because
// mcp_stdio_call only matches the JSON-RPC `id` field, cat's echo of
// our request looks like a valid response — the test uses that for an
// offline round-trip without needing a real MCP server. We then probe
// the test fields of the echoed payload to confirm the wire was framed
// correctly.
//
// Coverage:
//   1. mcp_stdio_spawn0 + cat echo of an `initialize` request
//   2. error mapping: spawn nonexistent command  → McpStdioSpawn
//   3. error mapping: spawn `false` (exits 0)    → McpStdioEof
//      (also asserts mcp_stdio_call's eof-vs-timeout discrimination)

$ `stdlib/ext/mcp_stdio.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`

@ println s line → v {
    ( nurl_print line )
    ( nurl_print `\n` )
}

@ kv s label s val → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print val )
    ( nurl_print `\n` )
}

@ pr_str_field Json j s key → v {
    : ?Json fo ( json_obj_get j key )
    ?? fo {
        T fv → {
            ? ( json_is_str fv ) {
                ( kv key ( json_str_data fv ) )
            } {
                ( kv key ( json_type_name fv ) )
            }
        }
        F _ → ( kv key `<missing>` )
    }
}

@ has_id Json j → b {
    : ?Json idj ( json_obj_get j `id` )
    ?? idj {
        T _ → ^ T
        F _ → ^ F
    }
}

@ main → i {
    // ── 1. Echo round-trip via cat. ───────────────────────────────────
    : !McpStdioClient McpStdioErr s1 ( mcp_stdio_spawn0 `cat` )
    ?? s1 {
        T cli → {
            ( println `=== cat echo ===` )
            // initialize is a real MCP method; cat will echo our request
            // verbatim. mcp_stdio_call only checks `id` matches, so it
            // happily returns the echoed object — we then probe its fields.
            : !Json McpStdioErr resp ( mcp_stdio_initialize cli `nurl_test` `1.0` )
            ?? resp {
                T j → {
                    ( pr_str_field j `jsonrpc` )
                    ( pr_str_field j `method` )
                    ( kv `has_id` ? ( has_id j ) `T` `F` )
                    ( json_free j )
                }
                F e → ( kv `init_err` ( mcp_stdio_err_name e ) )
            }
            ( mcp_stdio_free cli )
        }
        F e → ( kv `cat_spawn_err` ( mcp_stdio_err_name e ) )
    }

    // ── 2. Missing command. ──────────────────────────────────────────
    : !McpStdioClient McpStdioErr s2 ( mcp_stdio_spawn0 `nurl_does_not_exist_xyz_42` )
    ?? s2 {
        T cli → {
            ( println `unexpected_spawn_ok` )
            ( mcp_stdio_free cli )
        }
        F e → ( kv `missing` ( mcp_stdio_err_name e ) )
    }

    // ── 3. Server exits immediately → EOF on first read. ─────────────
    : !McpStdioClient McpStdioErr s3 ( mcp_stdio_spawn0 `false` )
    ?? s3 {
        T cli → {
            : !Json McpStdioErr r ( mcp_stdio_ping cli )
            ?? r {
                T j → { ( println `unexpected_pong` ) ( json_free j ) }
                F e → ( kv `dead_server` ( mcp_stdio_err_name e ) )
            }
            ( mcp_stdio_free cli )
        }
        F e → ( kv `false_spawn` ( mcp_stdio_err_name e ) )
    }

    ^ 0
}
