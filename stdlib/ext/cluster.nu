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
//          caller frees with json_free. Uses retry_default.
//   ( call_remote_with Node n s fn_id Json args RetryPolicy pol )
//                                                      → !Json ClusterErr
//        — as above with an explicit backoff/retry policy.
//   ( call_remote_cb … RetryPolicy pol CircuitBreaker cb )
//                                                      → !Json ClusterErr
//        — guarded by a breaker; ClCircuitOpen when open (args still
//          consumed). Records success/failure on the breaker.
//
// ── Resilience API ───────────────────────────────────────────────────
//
//   ( retry_default ) / ( retry_none )                → RetryPolicy
//   ( retry_new max base_ms max_ms mult_pct jitter )  → RetryPolicy
//   ( retry_backoff_ms RetryPolicy pol i attempt )    → i  (no jitter)
//   ( cb_new i threshold i cooldown_ms )              → CircuitBreaker
//   ( cb_free / cb_allow / cb_record_success /
//     cb_record_failure / cb_is_open / cb_fails )

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/trace.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/msgpack.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

// ── Errors ───────────────────────────────────────────────────────────

: | ClusterErr {
    ClNet  // transport connect / I/O failure
    ClTimeout  // request budget exceeded
    ClNoSuchFn  // remote has no handler registered under that fn_id
    ClBadResp  // malformed / unexpected response envelope
    ClRemote  // remote handler returned an error
    ClSerialize  // local (de)serialization failure
    ClCircuitOpen  // breaker open — call short-circuited, never sent
}

@ cluster_err_name ClusterErr e → s {
    ^ ?? e {
        ClNet → `ClNet`
        ClTimeout → `ClTimeout`
        ClNoSuchFn → `ClNoSuchFn`
        ClBadResp → `ClBadResp`
        ClRemote → `ClRemote`
        ClSerialize → `ClSerialize`
        ClCircuitOpen → `ClCircuitOpen`
    }
}

// Which ClusterErrs are worth another attempt — transport failures only.
// ClBadResp / ClRemote / ClNoSuchFn / ClSerialize are deterministic and
// retrying them just wastes round-trips.
@ cluster_err_retryable ClusterErr e → b {
    ^ ?? e {
        ClNet → T
        ClTimeout → T
        _ → F
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
    ( json_obj_set env `result` result )  // MOVES result into env
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
    : ?Json fnj ( json_obj_get req `fn` )  // borrow
    ^ ?? fnj {
        T fj → {
            : s name ( json_as_str fj )
            : i idx ( __registry_find r name )
            ? < idx 0 {
                ( __rpc_err_env `no such fn` )
            } {
                : ( @ !Json ClusterErr Json ) h ( __registry_handler_at r idx )
                : ?Json argsj ( json_obj_get req `args` )  // borrow
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

// Does the request carry a msgpack Content-Type?
@ __req_is_msgpack HttpRequest req → b {
    : ?String ct ( header_get . req headers `Content-Type` )
    : ~ b mp F
    ?? ct {
        T cs → { = mp ( string_contains cs `msgpack` ) ( string_free cs ) }
        F cs → { ( string_free cs ) }
    }
    ^ mp
}

// Decode the request body as Json per its Content-Type. None on failure.
@ __req_decode b mp HttpRequest req → ?Json {
    ? mp {
        : !Json MsgpackErr d ( msgpack_decode . req body )
        ^ ?? d { T j → @ ?Json { T j } F _ → @ ?Json { F # Json 0 } }
    } {}
    : String bs ( bytes_to_str . req body )
    : !Json JsonError d ( json_parse ( string_data bs ) )
    ( string_free bs )
    ^ ?? d { T j → @ ?Json { T j } F _ → @ ?Json { F # Json 0 } }
}

// Build a response carrying `env` in the negotiated wire format.
@ __resp_send b mp i status Json env → HttpResponse {
    ? mp {
        : HttpResponse r ( response_new status )
        : !( Vec u ) MsgpackErr enc ( msgpack_encode env )
        ?? enc {
            T body → { ( response_set_body_bytes r body ) ( vec_free [u] body ) }
            F _ → {}
        }
        ( response_set_header r `Content-Type` `application/msgpack` )
        ^ r
    } {}
    ^ ( response_json status env )
}

// Adopt an incoming W3C traceparent (if present) as the current trace, so
// any call the handler makes propagates the same trace id.
@ __apply_incoming_trace HttpRequest req → v {
    : ?String tph ( header_get . req headers `traceparent` )
    ?? tph {
        T h → {
            : TraceParsed p ( traceparent_parse ( string_data h ) )
            ( string_free h )
            ? != 0 . p ok { ( trace_set . p trace . p span ) } {}
        }
        F h → { ( string_free h ) }
    }
}

@ registry_handler Registry r → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        // Save + adopt the incoming trace context; restore it after dispatch
        // so the worker fiber's trace state doesn't leak between requests.
        : i __st ( trace_current_trace )
        : i __ss ( trace_current_span )
        ( __apply_incoming_trace req )
        : b mp ( __req_is_msgpack req )
        : ?Json reqj ( __req_decode mp req )
        : HttpResponse resp ?? reqj {
            T rj → {
                : Json env ( rpc_dispatch r rj )
                ( json_free rj )
                : HttpResponse rp ( __resp_send mp 200 env )
                ( json_free env )
                rp
            }
            F → {
                : Json env ( __rpc_err_env `bad request` )
                : HttpResponse rp ( __resp_send mp 400 env )
                ( json_free env )
                rp
            }
        }
        ( trace_set __st __ss )
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

// ── Retry policy (exponential backoff + jitter) ──────────────────────
//
// Controls call_remote_with's retry loop. Delays grow geometrically:
// base · (multiplier_pct/100)^k, capped at max_delay_ms. `jitter` adds
// full-jitter (uniform [0, delay]) to spread thundering-herd retries.
// Only transport errors (cluster_err_retryable) are retried.

: RetryPolicy {
    i max_attempts  // total tries incl. the first (clamped ≥ 1)
    i base_delay_ms  // delay before the 1st retry
    i max_delay_ms  // cap on any single backoff
    i multiplier_pct  // geometric growth per retry, percent (200 = ×2)
    b jitter  // full-jitter the slept delay
}

@ retry_new i max_attempts i base_delay_ms i max_delay_ms i multiplier_pct b jitter → RetryPolicy {
    ^ @ RetryPolicy { max_attempts base_delay_ms max_delay_ms multiplier_pct jitter }
}

// Sensible default: 3 tries, 100ms → 200ms backoff, capped 5s, jittered.
@ retry_default → RetryPolicy {
    ^ @ RetryPolicy { 3 100 5000 200 T }
}

// A single attempt, no backoff — for callers that want fail-fast.
@ retry_none → RetryPolicy {
    ^ @ RetryPolicy { 1 0 0 200 F }
}

@ __grow_delay i d RetryPolicy pol → i {
    : i nd / * d . pol multiplier_pct 100
    ? > nd . pol max_delay_ms { ^ . pol max_delay_ms } {}
    ^ nd
}

// Deterministic backoff (no jitter) for the delay BEFORE retry `attempt`
// (0-based). Exposed so callers/tests can reason about timing.
@ retry_backoff_ms RetryPolicy pol i attempt → i {
    : ~ i d . pol base_delay_ms
    : ~ i k 0
    ~ < k attempt {
        = d ( __grow_delay d pol )
        = k + k 1
    }
    ^ d
}

@ __jitter i delay → i {
    ? <= delay 0 { ^ 0 } {}
    : Rng g ( rng_seed ( monotonic_ns ) )
    : i j ( rng_below g + delay 1 )
    ( rng_free g )
    ^ j
}

// ── Circuit breaker ──────────────────────────────────────────────────
//
// Per-endpoint failure gate. After `threshold` consecutive failures the
// breaker OPENS and cb_allow returns F (fail fast) until `cooldown_ms`
// elapses, after which it goes HALF-OPEN (one probe allowed). A probe
// success closes it; a probe failure re-opens it. State lives in a heap
// cell so every holder of the CircuitBreaker shares one counter.

: CbImpl {
    i threshold
    i cooldown_ms
    i fails
    i opened_at_ns  // -1 when closed
}

: CircuitBreaker { s ctl }

@ cb_new i threshold i cooldown_ms → CircuitBreaker {
    : *CbImpl impl # *CbImpl ( nurl_alloc Z CbImpl )
    = . impl threshold threshold
    = . impl cooldown_ms cooldown_ms
    = . impl fails 0
    = . impl opened_at_ns - 0 1
    ^ @ CircuitBreaker { # s impl }
}

@ cb_free CircuitBreaker cb → v {
    ( nurl_free . cb ctl )
}

// True if a call may proceed: closed, or open-but-cooled-down (half-open).
@ cb_allow CircuitBreaker cb → b {
    : *CbImpl impl # *CbImpl . cb ctl
    ? < . impl opened_at_ns 0 { ^ T } {}
    : i elapsed_ms / - ( monotonic_ns ) . impl opened_at_ns 1000000
    ^ >= elapsed_ms . impl cooldown_ms
}

@ cb_record_success CircuitBreaker cb → v {
    : *CbImpl impl # *CbImpl . cb ctl
    = . impl fails 0
    = . impl opened_at_ns - 0 1
}

@ cb_record_failure CircuitBreaker cb → v {
    : *CbImpl impl # *CbImpl . cb ctl
    = . impl fails + . impl fails 1
    ? >= . impl fails . impl threshold {
        = . impl opened_at_ns ( monotonic_ns )
    } {}
}

// Introspection (tests / metrics): consecutive failure count + open flag.
@ cb_fails CircuitBreaker cb → i {
    : *CbImpl impl # *CbImpl . cb ctl
    ^ . impl fails
}

@ cb_is_open CircuitBreaker cb → b {
    : *CbImpl impl # *CbImpl . cb ctl
    ^ >= . impl opened_at_ns 0
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

// Per-call total / connect budgets (ms). Retry cadence is the caller's
// RetryPolicy (see call_remote_with / retry_default).
@ __cluster_timeout_ms → i { ^ 30000 }

@ __cluster_connect_ms → i { ^ 5000 }

@ __node_url Node n → String {
    : String u ( string_from `http://` )
    ( string_push_str u ( string_data . n host ) )
    ( string_push_char u 58 )  // ':'
    ( string_push_int u . n port )
    ( string_push_str u `/__rpc` )
    ^ u
}

// Pull a fresh owned `result` Json out of a borrowed response envelope
// by round-tripping through text (no detach primitive on Json yet).
@ __rpc_extract_result Json env → !Json ClusterErr {
    : ?Json okj ( json_obj_get env `ok` )  // borrow
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

// ── Wire format ──────────────────────────────────────────────────────
//
// JSON (text) by default; msgpack (binary) when opted in. Process-wide —
// set once at startup before issuing calls. Only the CLIENT opts in: the
// server auto-detects each request's Content-Type and replies in kind, so
// a msgpack client and a JSON client can share one server.
: ~ i g_cluster_wire 0

@ cluster_use_msgpack b on → v { = g_cluster_wire ? on 1 0 }

@ cluster_wire_is_msgpack → b { ^ != g_cluster_wire 0 }

// Build the request headers blob: Content-Type, plus a W3C `traceparent`
// carrying the current trace id (a fresh child span per call) when a trace
// is active — so a fan-out's hops share one trace id for log correlation.
@ __rpc_headers s content_type → String {
    : String h ( string_from `Content-Type: ` )
    ( string_push_str h content_type )
    ( string_push_str h `\r\n` )
    ? ( trace_active ) {
        ( string_push_str h `traceparent: ` )
        : String tp ( traceparent_format ( trace_current_trace ) ( trace_new_span ) )
        ( string_push_str h ( string_data tp ) )
        ( string_free tp )
        ( string_push_str h `\r\n` )
    } {}
    ^ h
}

@ __rpc_send_json s url s body → !Response HttpErr {
    : String hdr ( __rpc_headers `application/json` )
    : !Response HttpErr r ( http_request_to `POST` url body ( string_data hdr )
    ( __cluster_timeout_ms ) ( __cluster_connect_ms ) )
    ( string_free hdr )
    ^ r
}

@ __rpc_send_mp s url Json req → !Response HttpErr {
    : !( Vec u ) MsgpackErr enc ( msgpack_encode req )
    ^ ?? enc {
        T body → {
            : String hdr ( __rpc_headers `application/msgpack` )
            : !Response HttpErr r2 ( http_request_bytes_to `POST` url body
            ( string_data hdr ) ( __cluster_timeout_ms ) ( __cluster_connect_ms ) )
            ( string_free hdr )
            ( vec_free [u] body )
            r2
        }
        F _ → @ !Response HttpErr { F @ HttpErr { HttpOther } }
    }
}

// Decode a response body as Json per the wire format. None on failure.
@ __rpc_decode_resp b mp Response resp → ?Json {
    ? mp {
        : ( Vec u ) bb ( http_body_bytes resp )
        : !Json MsgpackErr d ( msgpack_decode bb )
        ( vec_free [u] bb )
        ^ ?? d { T j → @ ?Json { T j } F _ → @ ?Json { F # Json 0 } }
    } {}
    : !Json JsonError d ( json_parse ( http_body_str resp ) )
    ^ ?? d { T j → @ ?Json { T j } F _ → @ ?Json { F # Json 0 } }
}

// One transport attempt. `req` is BORROWED (re-serialized per retry).
@ __rpc_attempt s url Json req → !Json ClusterErr {
    : b mp ( cluster_wire_is_msgpack )
    : String jbody ? mp ( string_new ) ( json_stringify req )
    : ~ ! Response HttpErr rr @ !Response HttpErr { F @ HttpErr { HttpOther } }
    ? mp { = rr ( __rpc_send_mp url req ) }
    { = rr ( __rpc_send_json url ( string_data jbody ) ) }
    ( string_free jbody )
    ^ ?? rr {
        T resp → {
            : i st ( http_status resp )
            ? != st 200 {
                ( response_free resp )
                @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
            } {
                : ?Json envo ( __rpc_decode_resp mp resp )
                : !Json ClusterErr out ?? envo {
                    T env → {
                        : !Json ClusterErr r2 ( __rpc_extract_result env )
                        ( json_free env )
                        r2
                    }
                    F → @ !Json ClusterErr { F @ ClusterErr { ClBadResp } }
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

// Full RPC with an explicit RetryPolicy. MOVES `args`. Retries transient
// transport errors (cluster_err_retryable) with exponential backoff +
// optional jitter between attempts; terminal errors stop immediately.
@ call_remote_with Node n s fn_id Json args RetryPolicy pol → !Json ClusterErr {
    // Build + serialize the request envelope; this MOVES `args` (it is
    // consumed into `req`, then `req` is freed once on the wire).
    : Json req ( json_obj_new )
    ( json_obj_set req `fn` ( json_str_lit fn_id ) )
    ( json_obj_set req `args` args )

    : String url ( __node_url n )

    : i max ? > . pol max_attempts 1 . pol max_attempts 1
    : ~ i k 0
    : ~ b done F
    : ~ ClusterErr last @ ClusterErr { ClNet }
    : ~ Json result ( json_null )
    : ~ b have_result F
    : ~ i delay . pol base_delay_ms
    ~ & ! done < k max {
        : !Json ClusterErr ar ( __rpc_attempt ( string_data url ) req )
        ?? ar {
            T r → {
                = result r
                = have_result T
                = done T
            }
            F e → {
                : ClusterErr ce # ClusterErr e
                = last ce
                ? ! ( cluster_err_retryable ce ) {
                    = done T
                } {
                    // Backoff before the next attempt (if any remain).
                    ? < + k 1 max {
                        : i d ? . pol jitter ( __jitter delay ) delay
                        ( sleep_ms d )
                        = delay ( __grow_delay delay pol )
                    } {}
                }
            }
        }
        = k + k 1
    }

    ( string_free url )
    ( json_free req )

    ? have_result {
        ^ @ !Json ClusterErr { T result }
    } {}
    ^ @ !Json ClusterErr { F last }
}

// Convenience: call_remote_with the default retry policy. MOVES `args`.
@ call_remote Node n s fn_id Json args → !Json ClusterErr {
    ^ ( call_remote_with n fn_id args ( retry_default ) )
}

// call_remote_with guarded by a CircuitBreaker. When the breaker is open
// (and not yet cooled down) the call short-circuits with ClCircuitOpen —
// but still CONSUMES `args` to honour the move contract. Otherwise the
// breaker records the outcome (success closes it, failure trips it).
@ call_remote_cb Node n s fn_id Json args RetryPolicy pol CircuitBreaker cb → !Json ClusterErr {
    ? ! ( cb_allow cb ) {
        ( json_free args )
        ^ @ !Json ClusterErr { F @ ClusterErr { ClCircuitOpen } }
    } {}
    : !Json ClusterErr r ( call_remote_with n fn_id args pol )
    ?? r {
        T result → {
            ( cb_record_success cb )
            ^ @ !Json ClusterErr { T result }
        }
        F e → {
            ( cb_record_failure cb )
            ^ @ !Json ClusterErr { F # ClusterErr e }
        }
    }
}
