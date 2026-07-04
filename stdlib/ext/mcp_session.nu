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
//   ( mcp_session_drain_frames store sid )          → ( Vec String ) owned id-tagged SSE frames
//   ( mcp_session_replay store sid last_event_id )  → ( Vec String ) owned, backlog frames id > last_event_id
//   ( mcp_session_backlog_cap )                     → i   replay backlog bound (64)
//   ( mcp_session_subscribe store sid uri )         → b
//   ( mcp_session_unsubscribe store sid uri )       → b
//   ( mcp_session_is_subscribed store sid uri )     → b
//   ( mcp_session_notify_resource_updated store uri ) → i   sessions notified
//   ( mcp_resource_updated_notification uri )       → Json  notification msg
//   ( mcp_session_begin_rpc store sid method params ) → i  request id, CONSUMES params
//   ( mcp_session_request_sampling store sid msgs system max_tokens ) → i
//   ( mcp_session_is_pending store sid id )         → b
//   ( mcp_session_resolve_rpc store sid response )  → b   CONSUMES response
//   ( mcp_session_take_result store sid id )        → ? Json  owned
//   ( mcp_session_store_free store )                → v
//
//   ( mcp_sse_frame event data )                    → String  borrows data
//   ( mcp_sse_frame_id id event data )              → String  borrows data
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
    i next_rpc_id  // server→client request id allocator (1-based)
    i next_event_id  // SSE event-id allocator (1-based, assigned at drain)
    ( Vec Json ) notify  // outbound queue (notifications + reverse-RPC requests)
    ( Vec i ) pending_ids  // reverse-RPC request ids awaiting a response
    ( Vec Json ) results  // inbound reverse-RPC responses, matched by their "id"
    ( Vec String ) subscriptions  // resource URIs this session subscribed to
    ( Vec i ) backlog_ids  // event ids of the retained replay backlog (parallel)
    ( Vec String ) backlog_frames  // rendered id-tagged SSE frames for replay
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

// Hard cap on concurrent sessions. `initialize` is unauthenticated, so an
// abusive client could otherwise mint sessions without bound — each owns a
// String id plus four Vecs — and exhaust memory. At the cap a fresh
// `initialize` evicts the least-recently-active session (smallest
// `last_ms`) so a flood of new sessions can't push out genuinely-active
// clients ahead of idle ones. `last_ms` is stamped at creation and kept
// fresh by `mcp_session_touch`; sized for a local / loopback MCP server.
@ mcp_session_max → i { ^ 4096 }

// Drop the least-recently-active session to make room. Caller guarantees a
// non-empty store. Frees the evicted session's owned Json / String state.
@ __mcp_session_evict_lru McpSessionStore store → v {
    : i n ( vec_len [McpSession] . store sessions )
    ? > n 0 {
        : ~ i victim 0
        : ~ i oldest 0
        : ~ b have F
        : ~ i k 0
        ~ < k n {
            : ?McpSession so ( vec_get [McpSession] . store sessions k )
            ?? so {
                T se → {
                    ? | ! have < . se last_ms oldest
                    { = oldest . se last_ms = victim k = have T } {}
                }
                F → {}
            }
            = k + k 1
        }
        : ?McpSession vo ( vec_get [McpSession] . store sessions victim )
        ?? vo { T se → ( __mcp_session_free se ) F → {} }
        ( vec_remove [McpSession] . store sessions victim )
    } {}
}

@ mcp_session_create McpSessionStore store → String {
    // Bound the store before adding — evict the LRU session at the cap.
    ? >= ( vec_len [McpSession] . store sessions ) ( mcp_session_max ) {
        ( __mcp_session_evict_lru store )
    } {}
    // 32 hex chars of CSPRNG output — collision-free for any realistic
    // server lifetime, and opaque per the MCP spec.
    : String id ( rand_hex_str 16 )
    : String ret ( string_from ( string_data id ) )
    : i now ( now_ms )
    : McpSession se @ McpSession {
        id now now 1 1
        ( vec_new [Json] ) ( vec_new [i] ) ( vec_new [Json] )
        ( vec_new [String] )
        ( vec_new [i] ) ( vec_new [String] )
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
    ( vec_free_with [String] . se subscriptions \ String s → v { ( string_free s ) } )
    ( vec_free [i] . se backlog_ids )
    ( vec_free_with [String] . se backlog_frames \ String s → v { ( string_free s ) } )
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

// ── SSE event ids + replay backlog ────────────────────────────────────
//
// Each outbound event delivered over SSE carries a MONOTONIC per-session
// event id (integer, starting at 1). Ids are assigned in queue order at
// drain time by `mcp_session_drain_frames`, which renders each queued
// message as an id-tagged SSE `message` frame (`mcp_sse_frame_id`) and
// retains a copy of the frame in a bounded per-session replay backlog.
// The backlog holds the LAST `mcp_session_backlog_cap` (64) delivered
// events; older ones are evicted oldest-first.
//
// `mcp_session_replay` gives a reconnecting client (`Last-Event-ID`
// header) the retained frames with id > last_event_id. BEST-EFFORT
// semantics: if last_event_id is current (or the session is unknown) the
// result is empty; if last_event_id is so old that the backlog has
// already evicted past it, everything still held is returned — a client
// can therefore see a gap after a long disconnect, but never a stall.

// Bound on retained delivered events per session (replay window).
@ mcp_session_backlog_cap → i { ^ 64 }

// Drain the queue as id-tagged SSE `message` frames (owned Strings, in
// queue order), assigning fresh monotonic event ids and archiving a copy
// of every frame in the session's replay backlog (bounded, oldest-first
// eviction). Unknown session → empty Vec.
@ mcp_session_drain_frames McpSessionStore store s sid → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ out } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : ~ i next . se next_event_id
            : i n ( vec_len [Json] . se notify )
            : ~ i k 0
            ~ < k n {
                : ?Json e ( vec_get [Json] . se notify k )
                ?? e {
                    T j → {
                        : String f ( mcp_sse_frame_id next `message` j )
                        ( json_free j )
                        ( vec_push [i] . se backlog_ids next )
                        ( vec_push [String] . se backlog_frames ( string_from ( string_data f ) ) )
                        ( vec_push [String] out f )
                        = next + next 1
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_clear [Json] . se notify )
            // Evict beyond the cap, oldest first.
            ~ > ( vec_len [String] . se backlog_frames ) ( mcp_session_backlog_cap ) {
                : ?String victim ( vec_get [String] . se backlog_frames 0 )
                ?? victim { T s → ( string_free s ) F → {} }
                ( vec_remove [String] . se backlog_frames 0 )
                ( vec_remove [i] . se backlog_ids 0 )
            }
            // Vec pushes ride the heap-stable ctl; the id allocator is a
            // scalar field, so write the struct copy back.
            = . se next_event_id next
            ( vec_set [McpSession] . store sessions idx se )
        }
        F → {}
    }
    ^ out
}

// Replay backlog frames with event id > last_event_id (owned copies, in
// id order). Empty when the id is current or the session unknown; when
// last_event_id predates the retained window (already evicted) every
// frame still held is returned — see the best-effort note above.
@ mcp_session_replay McpSessionStore store s sid i last_event_id → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ out } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : i n ( vec_len [String] . se backlog_frames )
            : ~ i k 0
            ~ < k n {
                : i eid ?? ( vec_get [i] . se backlog_ids k ) { T x → x F → 0 }
                ? > eid last_event_id {
                    : ?String fo ( vec_get [String] . se backlog_frames k )
                    ?? fo {
                        T f → ( vec_push [String] out ( string_from ( string_data f ) ) )
                        F → {}
                    }
                } {}
                = k + k 1
            }
        }
        F → {}
    }
    ^ out
}

// ── Resource subscriptions (spec §6.5) ────────────────────────────────
//
// A session may subscribe to individual resource URIs; when the server
// observes a change it calls `mcp_session_notify_resource_updated`, which
// enqueues a `notifications/resources/updated` message onto every
// subscribed session's outbound queue (delivered over the SSE stream by
// the existing drain path). Subscription URIs are owned String copies.

@ __mcp_sub_index ( Vec String ) subs s uri → i {
    : i n ( vec_len [String] subs )
    : ~ i k 0
    : ~ i res -1
    ~ < k n {
        : ?String so ( vec_get [String] subs k )
        ?? so {
            T s → { ? == 1 ( nurl_str_eq ( string_data s ) uri ) { = res k = k n } {} }
            F → {}
        }
        = k + k 1
    }
    ^ res
}

// Subscribe `sid` to `uri`. Idempotent: a duplicate URI is a no-op.
// Returns F if the session is unknown.
@ mcp_session_subscribe McpSessionStore store s sid s uri → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            // Subscriptions ride the heap-stable Vec ctl, so a push
            // persists through the struct copy without a vec_set.
            ? >= ( __mcp_sub_index . se subscriptions uri ) 0
            {}
            { ( vec_push [String] . se subscriptions ( string_from uri ) ) }
            ^ T
        }
        F → { ^ F }
    }
}

// Unsubscribe `sid` from `uri`. Returns T iff the URI was subscribed.
@ mcp_session_unsubscribe McpSessionStore store s sid s uri → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → {
            : i si ( __mcp_sub_index . se subscriptions uri )
            ? < si 0 { ^ F } {}
            : ?String victim ( vec_get [String] . se subscriptions si )
            ?? victim { T s → ( string_free s ) F → {} }
            ( vec_remove [String] . se subscriptions si )
            ^ T
        }
        F → { ^ F }
    }
}

@ mcp_session_is_subscribed McpSessionStore store s sid s uri → b {
    : i idx ( __mcp_session_find store sid )
    ? < idx 0 { ^ F } {}
    : ?McpSession so ( vec_get [McpSession] . store sessions idx )
    ?? so {
        T se → { ^ >= ( __mcp_sub_index . se subscriptions uri ) 0 }
        F → { ^ F }
    }
}

// Build the spec-shaped `notifications/resources/updated` message for a
// changed `uri` (no id — it is a notification, not a request).
@ mcp_resource_updated_notification s uri → Json {
    : Json params ( json_obj_new )
    ( json_obj_set params `uri` ( json_str_lit uri ) )
    ^ ( mcp_notification `notifications/resources/updated` params )
}

// Notify every session subscribed to `uri` that the resource changed.
// Enqueues one `notifications/resources/updated` per subscribed session.
// Returns the number of sessions notified.
@ mcp_session_notify_resource_updated McpSessionStore store s uri → i {
    : i n ( vec_len [McpSession] . store sessions )
    : ~ i k 0
    : ~ i count 0
    ~ < k n {
        : ?McpSession so ( vec_get [McpSession] . store sessions k )
        ?? so {
            T se → {
                ? >= ( __mcp_sub_index . se subscriptions uri ) 0 {
                    ( vec_push [Json] . se notify ( mcp_resource_updated_notification uri ) )
                    = count + count 1
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ count
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
            // Only accept a response whose id matches an OUTSTANDING
            // reverse-RPC request we actually issued. Without this gate a
            // client can POST unlimited responses carrying ids we never
            // sent — each piles into `results` unbounded (memory DoS), and
            // a forged result could be picked up by a later caller that
            // reuses the id. A non-pending id is dropped.
            : i pi ( __mcp_pending_index . se pending_ids rid )
            ? < pi 0 { ( json_free response ) ^ F } {}
            ( vec_remove [i] . se pending_ids pi )
            ( vec_push [Json] . se results response )
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

// Id-tagged sibling of `mcp_sse_frame`:
// `id: <id>\r\nevent: <event>\r\ndata: <json>\r\n\r\n`. Borrows `data`;
// returns an owned String. The id is what a client echoes back in a
// `Last-Event-ID` header to resume after a dropped connection.
@ mcp_sse_frame_id i id s event Json data → String {
    : String payload ( json_stringify data )
    : String out ( string_with_cap + ( string_len payload ) + ( nurl_str_len event ) 48 )
    ( string_push_str out `id: ` )
    ( string_push_int out id )
    ( string_push_str out `\r\nevent: ` )
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
