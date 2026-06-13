// stdlib/ext/cluster.nu — minimal RPC for distributed NURL.
//
// **Phase 1 MVP** of the distributed-computing track (TODO §7.1). One
// coordinator, NO consensus, NO discovery — the smallest thing that
// proves the idea on top of machinery NURL already has (ext/http for the
// transport, ext/json for serialization). Everything here is pure NURL.
//
// Design decisions (TODO §7.3), locked 2026-06-13:
//
//   * `call_remote` is a MOVE: the caller's local `args` value is
//     CONSUMED — serialized onto the wire and freed. "Move to another
//     address space." The result comes back as a fresh owned value.
//   * Dispatch is a RUNTIME REGISTRY keyed by `fn_id` (no compile-time
//     stub codegen), mirroring the ext/mcp dispatch-closure model.
//
// Wire protocol (JSON over HTTP/1.1 POST to `/__rpc`):
//
//   request   { "fn": "<name>", "args": <any json> }
//   response  { "ok": true,  "result": <any json> }
//          or { "ok": false, "error":  "<message>" }
//
// Delivery semantics: at-least-once. `call_remote` retries transient
// transport failures (connect / dns / timeout / other) up to
// `__cluster_max_attempts` times. Exactly-once and backoff are Phase 2.
//
// ── Server API ───────────────────────────────────────────────────────
//
//   ( registry_new )                                  → Registry
//   ( registry_free Registry r )                      → v
//   ( registry_register Registry r s name handler )   → v
//        handler :: ( @ !Json ClusterErr Json )
//        — receives a BORROWED args Json (do NOT free it), returns an
//          OWNED Json on success or a ClusterErr on failure.
//   ( registry_count Registry r )                     → i
//   ( rpc_dispatch Registry r Json req )              → Json
//        — pure: maps a request envelope to an owned response envelope.
//          Network-free, so the whole dispatch path is unit-testable.
//   ( registry_handler Registry r )                   → ( @ HttpResponse HttpRequest )
//        — wraps the registry as an HTTP handler for http_server /
//          http2_server. Captures the registry by reference.
//   ( cluster_serve s host i port Registry r )        → !v NetErr
//        — convenience: bind + async accept loop serving the registry.
//
// ── Client API ───────────────────────────────────────────────────────
//
//   ( node_new s host i port )                        → Node
//   ( call_remote Node n s fn_id Json args )          → !Json ClusterErr
//        — MOVE: consumes `args`. Ok arm is a fresh owned Json the
//          caller frees with json_free.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

// ── Errors ───────────────────────────────────────────────────────────

: | ClusterErr {
    ClNet         // transport connect / I/O failure
    ClTimeout     // request budget exceeded
    ClNoSuchFn    // remote has no handler registered under that fn_id
    ClBadResp     // malformed / unexpected response envelope
    ClRemote      // remote handler returned an error
    ClSerialize   // local (de)serialization failure
}

@ cluster_err_name ClusterErr e → s {
    ^ ?? e {
        ClNet → `ClNet`
        ClTimeout → `ClTimeout`
        ClNoSuchFn → `ClNoSuchFn`
        ClBadResp → `ClBadResp`
        ClRemote → `ClRemote`
        ClSerialize → `ClSerialize`
    }
}

@ __cluster_map_http HttpErr e → ClusterErr {
    ^ ?? e {
        HttpTimeout → @ ClusterErr { ClTimeout }
        HttpConnect → @ ClusterErr { ClNet }
        HttpTls → @ ClusterErr { ClNet }
        HttpDns → @ ClusterErr { ClNet }
        HttpInvalidUrl → @ ClusterErr { ClNet }
        HttpOther → @ ClusterErr { ClNet }
    }
}

// ── Registry ─────────────────────────────────────────────────────────
//
// A registered handler lives in a heap RpcImpl so the Vec can hold a
// stable cell; the public Registry just owns the Vec of pointer-wrappers
// (same shape as http_router's Route → RouteImpl).

: RpcImpl {
    String name
    ( @ !Json ClusterErr Json ) handler
}

: RpcEntry { s ctl }

: Registry { ( Vec RpcEntry ) entries }

@ registry_new → Registry {
    ^ @ Registry { ( vec_new [RpcEntry] ) }
}

@ __rpc_entry_free RpcEntry e → v {
    : *RpcImpl impl # *RpcImpl . e ctl
    ( string_free . impl name )
    // The closure value is a by-value { fn_ptr, env_ptr } pair; only the
    // env is heap-allocated (NULL for capture-less lambdas) and closures
    // have no auto-drop, so release it here (router/recover convention).
    : ( @ !Json ClusterErr Json ) h . impl handler
    ( nurl_free # s # *u h 1 )
    ( nurl_free # s impl )
}

@ registry_free Registry r → v {
    ( vec_free_with [RpcEntry] . r entries
    \ RpcEntry e → v { ( __rpc_entry_free e ) } )
}

@ registry_register Registry r s name ( @ !Json ClusterErr Json ) handler → v {
    : *RpcImpl impl # *RpcImpl ( nurl_alloc Z RpcImpl )
    = . impl name ( string_from name )
    = . impl handler handler
    : RpcEntry e @ RpcEntry { # s impl }
    ( vec_push [RpcEntry] . r entries e )
}

@ registry_count Registry r → i {
    ^ ( vec_len [RpcEntry] . r entries )
}

// Linear scan for a handler by name → index, or -1 if absent.
@ __registry_find Registry r s name → i {
    : i n ( vec_len [RpcEntry] . r entries )
    : ~ i found - 0 1
    : ~ b done F
    : ~ i k 0
    ~ & ! done < k n {
        : ?RpcEntry ek ( vec_get [RpcEntry] . r entries k )
        ?? ek {
            T e → {
                : *RpcImpl impl # *RpcImpl . e ctl
                ? != 0 ( nurl_str_eq ( string_data . impl name ) name ) {
                    = found k
                    = done T
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

@ __registry_handler_at Registry r i idx → ( @ !Json ClusterErr Json ) {
    // Unreachable fallback (callers gate on __registry_find ≥ 0); kept so
    // the None arm typechecks without an `^` inside the match.
    : ( @ !Json ClusterErr Json ) miss \ Json a → !Json ClusterErr {
        ^ @ !Json ClusterErr { F @ ClusterErr { ClNoSuchFn } }
    }
    : ?RpcEntry ek ( vec_get [RpcEntry] . r entries idx )
    ^ ?? ek {
        T e → {
            : *RpcImpl impl # *RpcImpl . e ctl
            . impl handler
        }
        F → miss
    }
}

// ── Envelope builders ────────────────────────────────────────────────

@ __rpc_ok_env Json result → Json {
    : Json env ( json_obj_new )
    ( json_obj_set env `ok` ( json_bool T ) )
    ( json_obj_set env `result` result )   // MOVES result into env
    ^ env
}

@ __rpc_err_env s msg → Json {
    : Json env ( json_obj_new )
    ( json_obj_set env `ok` ( json_bool F ) )
    ( json_obj_set env `error` ( json_str_lit msg ) )
    ^ env
}

// Call a handler with a BORROWED args Json and wrap its outcome into an
// owned response envelope.
@ __rpc_invoke ( @ !Json ClusterErr Json ) h Json args → Json {
    : !Json ClusterErr rr ( h args )
    ^ ?? rr {
        T result → ( __rpc_ok_env result )
        F e → {
            : ClusterErr ce # ClusterErr e
            ( __rpc_err_env ( cluster_err_name ce ) )
        }
    }
}

// ── Dispatch (pure, network-free) ────────────────────────────────────

@ rpc_dispatch Registry r Json req → Json {
    : ?Json fnj ( json_obj_get req `fn` )      // borrow
    ^ ?? fnj {
        T fj → {
            : s name ( json_as_str fj )
            : i idx ( __registry_find r name )
            ? < idx 0 {
                ( __rpc_err_env `no such fn` )
            } {
                : ( @ !Json ClusterErr Json ) h ( __registry_handler_at r idx )
                : ?Json argsj ( json_obj_get req `args` )   // borrow
                ?? argsj {
                    T a → ( __rpc_invoke h a )
                    F → {
                        : Json a ( json_null )
                        : Json env ( __rpc_invoke h a )
                        ( json_free a )
                        env
                    }
                }
            }
        }
        F → ( __rpc_err_env `missing fn field` )
    }
}

// ── HTTP glue ────────────────────────────────────────────────────────

@ registry_handler Registry r → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : String bs ( bytes_to_str . req body )
        : !Json JsonError pr ( json_parse ( string_data bs ) )
        : HttpResponse resp ?? pr {
            T reqj → {
                : Json env ( rpc_dispatch r reqj )
                ( json_free reqj )
                : HttpResponse rp ( response_json 200 env )
                ( json_free env )
                rp
            }
            F _ → {
                : Json env ( __rpc_err_env `bad request json` )
                : HttpResponse rp ( response_json 400 env )
                ( json_free env )
                rp
            }
        }
        ( string_free bs )
        ^ resp
    }
}

@ __cluster_accept_loop TcpListener listener Registry r → v {
    : ( @ HttpResponse HttpRequest ) h ( registry_handler r )
    : HttpServer srv ( server_new listener h )
    : !v NetErr rr ( server_run srv )
    ?? rr { T _ → {} F _ → {} }
}

@ cluster_serve s host i port Registry r → !v NetErr {
    : !TcpListener NetErr lr ( tcp_listen host port )
    ^ ?? lr {
        T listener → {
            ( __cluster_accept_loop listener r )
            ( tcp_close_listener listener )
            @ !v NetErr { T 0 }
        }
        F e → @ !v NetErr { F # NetErr e }
    }
}

// ── Client ───────────────────────────────────────────────────────────

: Node {
    String host
    i port
}

@ node_new s host i port → Node {
    ^ @ Node { ( string_from host ) port }
}

@ node_free Node n → v {
    ( string_free . n host )
}

// Per-call total / connect budgets (ms) and retry cap.
@ __cluster_timeout_ms → i { ^ 30000 }
@ __cluster_connect_ms → i { ^ 5000 }
@ __cluster_max_attempts → i { ^ 3 }

@ __node_url Node n → String {
    : String u ( string_from `http://` )
    ( string_push_str u ( string_data . n host ) )
    ( string_push_char u 58 )              // ':'
    ( string_push_int u . n port )
    ( string_push_str u `/__rpc` )
    ^ u
}

// Pull a fresh owned `result` Json out of a borrowed response envelope
// by round-tripping through text (no detach primitive on Json yet).
@ __rpc_extract_result Json env → !Json ClusterErr {
    : ?Json okj ( json_obj_get env `ok` )      // borrow
    : b ok ?? okj { T b → ( json_bool_val b ) F → F }
    ? ! ok {
        ^ @ !Json ClusterErr { F @ ClusterErr { ClRemote } }
    } {}
    : ?Json resj ( json_obj_get env `result` )  // borrow
    ^ ?? resj {
        T rb → {
            : String rs ( json_stringify rb )
            : !Json JsonError rp ( json_parse ( string_data rs ) )
            ( string_free rs )
            ?? rp {
                T owned → @ !Json ClusterErr { T owned }
                F _ → @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
            }
        }
        F → @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
    }
}

// One transport attempt. `body` is BORROWED (reused across retries).
@ __rpc_attempt s url s body → !Json ClusterErr {
    : !Response HttpErr rr ( http_request_to `POST` url body
    `Content-Type: application/json\r\n`
    ( __cluster_timeout_ms ) ( __cluster_connect_ms ) )
    ^ ?? rr {
        T resp → {
            : i st ( http_status resp )
            ? != st 200 {
                ( response_free resp )
                @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
            } {
                : !Json JsonError pr ( json_parse ( http_body_str resp ) )
                : !Json ClusterErr out ?? pr {
                    T env → {
                        : !Json ClusterErr r2 ( __rpc_extract_result env )
                        ( json_free env )
                        r2
                    }
                    F _ → @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
                }
                ( response_free resp )
                out
            }
        }
        F e → {
            // Map to a ClusterErr; call_remote's loop decides whether to
            // retry (ClNet / ClTimeout) or give up (others).
            : HttpErr he # HttpErr e
            @ !Json ClusterErr { F ( __cluster_map_http he ) }
        }
    }
}

@ call_remote Node n s fn_id Json args → !Json ClusterErr {
    // Build + serialize the request envelope; this MOVES `args` (it is
    // consumed into `req`, then `req` is freed once on the wire).
    : Json req ( json_obj_new )
    ( json_obj_set req `fn` ( json_str_lit fn_id ) )
    ( json_obj_set req `args` args )
    : String body ( json_stringify req )
    ( json_free req )

    : String url ( __node_url n )

    // at-least-once: retry transient failures up to the attempt cap.
    : i max ( __cluster_max_attempts )
    : ~ i k 0
    : ~ b done F
    : ~ ClusterErr last @ ClusterErr { ClNet }
    : ~ Json result ( json_null )
    : ~ b have_result F
    ~ & ! done < k max {
        : !Json ClusterErr ar ( __rpc_attempt ( string_data url ) ( string_data body ) )
        ?? ar {
            T r → {
                = result r
                = have_result T
                = done T
            }
            F e → {
                : ClusterErr ce # ClusterErr e
                = last ce
                // Only ClNet / ClTimeout are worth another attempt;
                // ClBadResp / ClRemote are terminal.
                : b retry ?? ce { ClNet → T ClTimeout → T _ → F }
                ? ! retry { = done T } {}
            }
        }
        = k + k 1
    }

    ( string_free url )
    ( string_free body )

    ? have_result {
        ^ @ !Json ClusterErr { T result }
    } {}
    ^ @ !Json ClusterErr { F last }
}
