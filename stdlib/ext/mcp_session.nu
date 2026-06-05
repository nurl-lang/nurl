// stdlib/ext/mcp_session.nu — stateful MCP session core + reverse RPC
//
// The pieces an MCP "Streamable HTTP" server needs beyond the
// stateless request/response path in `mcp_http.nu`:
//
//   1. A SESSION STORE keyed by the opaque `Mcp-Session-Id` the server
//      hands a client on `initialize`. Each session owns an outbound
//      NOTIFICATION QUEUE (server→client messages waiting to be flushed
//      over the client's SSE channel) and the bookkeeping for
//      server→client (reverse) RPC.
//
//   2. REVERSE RPC correlation — `sampling/createMessage` and friends.
//      The server issues a JSON-RPC *request* (with an id it allocates)
//      into the session's outbound queue; it rides the SSE stream to the
//      client; the client POSTs back a JSON-RPC *response* carrying that
//      id; the server matches it to the pending request and the original
//      caller collects the result.
//
//   3. The wire builders the transport layers on top of: an SSE event
//      frame, and the `sampling/createMessage` request envelope.
//
// This module is pure data structures + JSON — no sockets — so it is
// fully unit-testable. `mcp_http.nu` wires it to the HTTP transport.
//
// Ownership: the store owns every session and every queued / pending /
// resolved Json. `mcp_session_store_free` releases all of it. Functions
// that take a Json (push_notify, begin_rpc params, resolve_rpc) CONSUME
// it; functions that return a Json (drain_notify elements, take_result)
// transfer ownership to the caller.
//
//   ( mcp_session_store_new )                       → McpSessionStore
//   ( mcp_session_create store )                    → String  new id (owned)
//   ( mcp_session_valid store sid )                 → b
//   ( mcp_session_count store )                     → i
//   ( mcp_session_touch store sid now )             → b   stamp last_ms
//   ( mcp_session_delete store sid )                → b
//   ( mcp_session_push_notify store sid msg )       → b   CONSUMES msg
//   ( mcp_session_drain_notify store sid )          → ( Vec Json )  owned
//   ( mcp_session_begin_rpc store sid method params ) → i  request id, CONSUMES params
//   ( mcp_session_request_sampling store sid msgs system max_tokens ) → i
//   ( mcp_session_is_pending store sid id )         → b
//   ( mcp_session_resolve_rpc store sid response )  → b   CONSUMES response
//   ( mcp_session_take_result store sid id )        → ? Json  owned
//   ( mcp_session_store_free store )                → v
//
//   ( mcp_sse_frame event data )                    → String  borrows data
//   ( mcp_sampling_message role text )              → Json
//   ( mcp_sampling_params msgs system max_tokens )  → Json   CONSUMES msgs
//   ( mcp_sampling_request id msgs system max_tokens ) → Json full envelope

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: McpSession {
    String id
    i created_ms
    i last_ms
    i next_rpc_id           // server→client request id allocator (1-based)
    ( Vec Json ) notify     // outbound queue (notifications + reverse-RPC requests)
    ( Vec i ) pending_ids   // reverse-RPC request ids awaiting a response
    ( Vec Json ) results    // inbound reverse-RPC responses, matched by their "id"
}

: McpSessionStore { ( Vec McpSession ) sessions }

// ── Store / lifecycle ─────────────────────────────────────────────────

@ mcp_session_store_new → McpSessionStore {
    ^ @ McpSessionStore { ( vec_new [McpSession] ) }
}

@ __mcp_session_find McpSessionStore store s sid → i {
    : i n ( vec_len [McpSession] . store sessions )
    : ~ i k 0
    : ~ i res -1
    ~ < k n {
        : ?McpSession so ( vec_get [McpSession] . store sessions k )
        ?? so {
            T se → {
                ? == 1 ( nurl_str_eq ( string_data . se id ) sid ) { = res k = k n } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ res
}

@ mcp_session_create McpSessionStore store → String {
    // 32 hex chars of CSPRNG output — collision-free for any realistic
    // server lifetime, and opaque per the MCP spec.
    : String id ( rand_hex_str 16 )
    : String ret ( string_from ( string_data id ) )
    : i now ( now_ms )
    : McpSession se @ McpSession {
        id now now 1
        ( vec_new [Json] ) ( vec_new [i] ) ( vec_new [Json] )
    }
    ( vec_push [McpSession] . store sessions se )
    ^ ret
}

@ mcp_session_valid McpSessionStore store s sid → b {
    ^ >= ( __mcp_session_find store sid ) 0
}

@ mcp_session_count McpSessionStore store → i {
    ^ ( vec_len [McpSession] . store sessions )
}

@ mcp_session_touch McpSessionStore store s sid i now → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            = . se last_ms now
            ( vec_set [McpSession] . store sessions idx se )
            ^ T
        }
        F → { ^ F }
    }
}

@ __mcp_session_free McpSession se → v {
    ( string_free . se id )
    ( vec_free_with [Json] . se notify \ Json j → v { ( json_free j ) } )
    ( vec_free [i] . se pending_ids )
    ( vec_free_with [Json] . se results \ Json j → v { ( json_free j ) } )
}

@ mcp_session_delete McpSessionStore store s sid → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → { ( __mcp_session_free se ) }
        F → {}
    }
    ( vec_remove [McpSession] . store sessions idx )
    ^ T
}

// ── Outbound notification queue ───────────────────────────────────────

@ mcp_session_push_notify McpSessionStore store s sid Json msg → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ( json_free msg ) ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            // Push rides the session's Vec ctl (heap-stable), so it
            // persists through the struct copy without a vec_set.
            ( vec_push [Json] . se notify msg )
            ^ T
        }
        F → { ( json_free msg ) ^ F }
    }
}

// Move every queued message into a fresh owned Vec and clear the queue.
@ mcp_session_drain_notify McpSessionStore store s sid → ( Vec Json ) {
    : ( Vec Json ) out ( vec_new [Json] )
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ out } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : i n ( vec_len [Json] . se notify )
            : ~ i k 0
            ~ < k n {
                : ?Json e ( vec_get [Json] . se notify k )
                ?? e { T j → ( vec_push [Json] out j ) F → {} }
                = k + k 1
            }
            // vec_clear drops the length without freeing elements — they
            // now live solely in `out`.
            ( vec_clear [Json] . se notify )
        }
        F → {}
    }
    ^ out
}

// ── Reverse RPC (server → client) ─────────────────────────────────────

@ __mcp_rpc_envelope i id s method Json params → Json {
    : Json out ( json_obj_new )
    ( json_obj_set out `jsonrpc` ( json_str_lit `2.0` ) )
    ( json_obj_set out `id` ( json_int id ) )
    ( json_obj_set out `method` ( json_str_lit method ) )
    ( json_obj_set out `params` params )
    ^ out
}

// Allocate a request id, enqueue a JSON-RPC request for the client, and
// mark it pending. Returns the id (or -1 if the session is unknown,
// freeing params). CONSUMES params.
@ mcp_session_begin_rpc McpSessionStore store s sid s method Json params → i {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ( json_free params ) ^ -1 } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : i id . se next_rpc_id
            : Json env ( __mcp_rpc_envelope id method params )
            ( vec_push [Json] . se notify env )
            ( vec_push [i] . se pending_ids id )
            = . se next_rpc_id + id 1
            ( vec_set [McpSession] . store sessions idx se )
            ^ id
        }
        F → { ( json_free params ) ^ -1 }
    }
}

@ mcp_session_request_sampling McpSessionStore store s sid ( Vec Json ) messages s system i max_tokens → i {
    : Json params ( mcp_sampling_params messages system max_tokens )
    ^ ( mcp_session_begin_rpc store sid `sampling/createMessage` params )
}

@ __mcp_pending_index ( Vec i ) ids i id → i {
    : i n ( vec_len [i] ids )
    : ~ i k 0
    : ~ i res -1
    ~ < k n {
        : i v ?? ( vec_get [i] ids k ) { T x → x F → -1 }
        ? == v id { = res k = k n } {}
        = k + k 1
    }
    ^ res
}

@ mcp_session_is_pending McpSessionStore store s sid i id → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → { ^ >= ( __mcp_pending_index . se pending_ids id ) 0 }
        F → { ^ F }
    }
}

// Accept a client's JSON-RPC response to a reverse RPC. Stores it for
// the originating caller and clears the pending marker. CONSUMES the
// response. Returns F if the session is unknown or the response has no
// integer "id" (then the response is freed).
@ mcp_session_resolve_rpc McpSessionStore store s sid Json response → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ( json_free response ) ^ F } {}
    // json_obj_get returns a BORROW into `response` — never free it.
    : ?Json ido ( json_obj_get response `id` )
    : ~ i rid -1
    ?? ido { T j → { = rid ( json_as_int j ) } F → {} }
    ? < rid 0 { ( json_free response ) ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            ( vec_push [Json] . se results response )
            : i pi ( __mcp_pending_index . se pending_ids rid )
            ? >= pi 0 { ( vec_remove [i] . se pending_ids pi ) } {}
            ^ T
        }
        F → { ( json_free response ) ^ F }
    }
}

// Collect a resolved reverse-RPC response by id (owned), or None if it
// has not arrived yet.
@ mcp_session_take_result McpSessionStore store s sid i id → ?Json {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ @ ?Json { F # Json 0 } } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : i n ( vec_len [Json] . se results )
            : ~ i k 0
            : ~ i hit -1
            ~ < k n {
                : ?Json e ( vec_get [Json] . se results k )
                ?? e {
                    T j → {
                        : ?Json ido ( json_obj_get j `id` )
                        ?? ido { T jid → { ? == ( json_as_int jid ) id { = hit k } {} } F → {} }
                    }
                    F → {}
                }
                = k + k 1
            }
            ? < hit 0 { ^ @ ?Json { F # Json 0 } } {}
            ^ ( vec_remove [Json] . se results hit )
        }
        F → { ^ @ ?Json { F # Json 0 } }
    }
}

@ mcp_session_store_free McpSessionStore store → v {
    : i n ( vec_len [McpSession] . store sessions )
    : ~ i k 0
    ~ < k n {
        : ?McpSession so ( vec_get [McpSession] . store sessions k )
        ?? so { T se → ( __mcp_session_free se ) F → {} }
        = k + k 1
    }
    ( vec_free [McpSession] . store sessions )
}

// ── Wire builders ─────────────────────────────────────────────────────

// One SSE event frame: `event: <event>\r\ndata: <json>\r\n\r\n`. Borrows
// `data` (stringifies it); returns an owned String.
@ mcp_sse_frame s event Json data → String {
    : String payload ( json_stringify data )
    : String out ( string_with_cap + ( string_len payload ) + ( nurl_str_len event ) 24 )
    ( string_push_str out `event: ` )
    ( string_push_str out event )
    ( string_push_str out `\r\ndata: ` )
    ( string_push_str out ( string_data payload ) )
    ( string_push_str out `\r\n\r\n` )
    ( string_free payload )
    ^ out
}

// A single `sampling/createMessage` message object: {role, content}.
@ mcp_sampling_message s role s text → Json {
    : Json content ( json_obj_new )
    ( json_obj_set content `type` ( json_str_lit `text` ) )
    ( json_obj_set content `text` ( json_str_lit text ) )
    : Json out ( json_obj_new )
    ( json_obj_set out `role` ( json_str_lit role ) )
    ( json_obj_set out `content` content )
    ^ out
}

// Build a `sampling/createMessage` params object. CONSUMES `messages`
// (each element is moved into the params array).
@ mcp_sampling_params ( Vec Json ) messages s system i max_tokens → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [Json] messages )
    : ~ i k 0
    ~ < k n {
        : ?Json e ( vec_get [Json] messages k )
        ?? e { T j → ( json_arr_push arr j ) F → {} }
        = k + k 1
    }
    ( vec_free [Json] messages )
    : Json params ( json_obj_new )
    ( json_obj_set params `messages` arr )
    ? > ( nurl_str_len system ) 0 {
        ( json_obj_set params `systemPrompt` ( json_str_lit system ) )
    } {}
    ( json_obj_set params `maxTokens` ( json_int max_tokens ) )
    ^ params
}

// Full standalone `sampling/createMessage` request envelope with an
// explicit id (for callers not going through a session store).
@ mcp_sampling_request i id ( Vec Json ) messages s system i max_tokens → Json {
    : Json params ( mcp_sampling_params messages system max_tokens )
    ^ ( __mcp_rpc_envelope id `sampling/createMessage` params )
}
