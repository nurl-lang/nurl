// stdlib/ext/mcp_tasks.nu — the `io.modelcontextprotocol/tasks` extension.
//
// The tasks extension lets a server answer a `tools/call` with an
// asynchronous TASK HANDLE instead of a final result: the client polls
// `tasks/get` until the task reaches a terminal status and then reads
// the real `CallToolResult` out of the task's `result` field. It is the
// right shape for expensive computations, batch jobs and anything that
// maps onto an external job API — work that would otherwise hold a
// JSON-RPC response open for minutes.
//
// Spec: https://tasks.extensions.modelcontextprotocol.io/specification/draft/tasks
//
// ── What this module is ─────────────────────────────────────────────
//
// A TASK STORE plus the wire shapes, capability negotiation and the
// three `tasks/*` request handlers. It is pure data structures + JSON —
// no sockets, no threads, no execution engine — so it is fully
// unit-testable and composes with either transport (`mcp_stdio.nu`,
// `mcp_http.nu`).
//
// This module does NOT run the work. NURL has no closure-in-struct
// support (see the note at the top of `mcp.nu`), and in practice a
// server that wants tasks already owns a job engine of its own. The
// division of labour is:
//
//   * this module owns the task RECORD — id, status, timestamps, TTL,
//     the stored result/error/inputRequests, and the wire encoding;
//   * the server owns the WORK — it decides which calls become tasks,
//     drives its own scheduler, and calls `mcp_task_complete` /
//     `mcp_task_fail` / `mcp_task_request_input` when state changes.
//
// A task carries an opaque `link` integer for exactly this: stash your
// own job id in it and look the job back up when a poll arrives.
//
// ── Capability negotiation ──────────────────────────────────────────
//
// Task creation is SERVER-DIRECTED. The client only signals that it can
// *handle* a task, per-request, in
// `params._meta["io.modelcontextprotocol/clientCapabilities"].extensions`;
// the server then decides per request whether to materialize one. Two
// hard rules from the spec, both enforced by helpers here:
//
//   * a server MUST NOT return `CreateTaskResult` to a client that did
//     not declare the extension ON THAT REQUEST — gate every call site
//     with `mcp_request_declares_tasks`;
//   * a non-declaring client issuing `tasks/get` / `tasks/update` /
//     `tasks/cancel` MUST get error -32003 —
//     `mcp_tasks_dispatch` does this for you.
//
// NOTE on -32003: the base 2026-07-28 spec renumbered its reserved
// codes into -32020..-32099 (`mcp_err_missing_client_capability` =
// -32021 in `mcp.nu`), but the tasks extension draft still pins
// MISSING_REQUIRED_CLIENT_CAPABILITY to -32003. The extension is
// normative for its own methods, so `mcp_tasks_err_missing_capability`
// is -32003 here. Revisit if the extension is renumbered to match.
//
// ── API ─────────────────────────────────────────────────────────────
//
// Identity + status:
//   ( mcp_tasks_ext_id )                       → s   extension label
//   ( mcp_task_status_name st )                → s   "working" | …
//   ( mcp_task_status_from_name name )         → i   -1 when unknown
//   ( mcp_task_status_is_terminal st )         → b
//
// Capability negotiation:
//   ( mcp_tasks_capability_json )              → Json  {"io.…/tasks":{}}
//   ( mcp_caps_declare_extension caps ext )    → v     caps.extensions[ext]={}
//   ( mcp_caps_declare_tasks caps )            → v
//   ( mcp_request_has_extension req ext )      → b
//   ( mcp_request_declares_tasks req )         → b
//   ( mcp_missing_capability_response id ext ) → Json  -32003 + data
//   ( mcp_task_invalid_id_response id msg )    → Json  -32602
//
// Store + task lifecycle (`s tp` is an opaque task handle; 0 = none):
//   ( mcp_task_store_new )                          → McpTaskStore
//   ( mcp_task_store_count store )                  → i
//   ( mcp_task_store_max )                          → i    2048
//   ( mcp_task_create store method tool args ttl poll ) → s  CONSUMES args
//   ( mcp_task_find store id )                      → s
//   ( mcp_task_nth store k )                        → s    live-task sweep
//   ( mcp_task_store_sweep store now )              → i    expired dropped
//   ( mcp_task_store_free store )                   → v
//
//   ( mcp_task_id tp )              → s     borrowed
//   ( mcp_task_status tp )          → i
//   ( mcp_task_tool tp )            → s     borrowed
//   ( mcp_task_method tp )          → s     borrowed
//   ( mcp_task_args tp )            → Json  BORROWED — do not free
//   ( mcp_task_link tp )            → i
//   ( mcp_task_set_link tp v )      → v
//   ( mcp_task_cancel_requested tp ) → b    cooperative cancel signal
//
//   ( mcp_task_set_working tp msg )        → v
//   ( mcp_task_set_message tp msg )        → v     status unchanged
//   ( mcp_task_complete tp result )        → v     CONSUMES result
//   ( mcp_task_fail tp code message )      → v
//   ( mcp_task_fail_error tp error )       → v     CONSUMES error
//   ( mcp_task_cancel tp )                 → v
//   ( mcp_task_request_input tp requests )  → v    CONSUMES requests
//   ( mcp_task_take_input_responses tp )   → ?Json owned; clears
//
// Wire shapes:
//   ( mcp_task_create_result tp )   → Json  CreateTaskResult, resultType "task"
//   ( mcp_task_detail tp )          → Json  DetailedTask (tasks/get body)
//   ( mcp_task_notification tp )    → Json  notifications/tasks envelope
//   ( mcp_tasks_listen_ids params ) → ( Vec String )  subscriptions/listen
//   ( mcp_tasks_subscribed_notification ids ) → Json  CONSUMES ids
//
// Request handling:
//   ( mcp_tasks_is_method method )                 → b
//   ( mcp_tasks_handle_get store id params )       → Json
//   ( mcp_tasks_handle_update store id params )    → Json
//   ( mcp_tasks_handle_cancel store id params )    → Json
//   ( mcp_tasks_dispatch store req id method )     → ?Json
//
// `mcp_tasks_dispatch` is the whole `tasks/*` surface in one call:
// None when `method` is not a tasks method, otherwise the capability
// gate, the taskId lookup and the right handler. A server that must
// refresh its own job state before answering a poll should instead
// intercept `tasks/get` itself, advance the job, and then call
// `mcp_tasks_handle_get` — that is why the handlers are exported
// individually.
//
// ── Memory model ────────────────────────────────────────────────────
//
// The store owns every task and every Json inside it;
// `mcp_task_store_free` releases all of it. Task handles (`s`) stay
// valid until the task is swept or the store is freed. Functions taking
// a Json CONSUME it; `mcp_task_args` is the one BORROWING accessor.

$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Constants ───────────────────────────────────────────────────────

: i mcp_task_working 0
: i mcp_task_input_required 1
: i mcp_task_completed 2
: i mcp_task_failed 3
: i mcp_task_cancelled 4

// MISSING_REQUIRED_CLIENT_CAPABILITY as pinned by the tasks extension
// draft (the base spec's own renumbered code is -32021; see the header).
: i mcp_tasks_err_missing_capability -32003

@ mcp_tasks_ext_id → s { ^ `io.modelcontextprotocol/tasks` }

@ mcp_task_status_name i st → s {
    ? == st mcp_task_input_required { ^ `input_required` } {}
    ? == st mcp_task_completed { ^ `completed` } {}
    ? == st mcp_task_failed { ^ `failed` } {}
    ? == st mcp_task_cancelled { ^ `cancelled` } {}
    ^ `working`
}

@ mcp_task_status_from_name s name → i {
    ? != 0 ( nurl_str_eq name `working` ) { ^ mcp_task_working } {}
    ? != 0 ( nurl_str_eq name `input_required` ) { ^ mcp_task_input_required } {}
    ? != 0 ( nurl_str_eq name `completed` ) { ^ mcp_task_completed } {}
    ? != 0 ( nurl_str_eq name `failed` ) { ^ mcp_task_failed } {}
    ? != 0 ( nurl_str_eq name `cancelled` ) { ^ mcp_task_cancelled } {}
    ^ -1
}

// completed / failed / cancelled are terminal; working and
// input_required are not (input_required resumes via tasks/update).
@ mcp_task_status_is_terminal i st → b {
    ^ | == st mcp_task_completed | == st mcp_task_failed == st mcp_task_cancelled
}

// ── Capability negotiation ──────────────────────────────────────────

// The `extensions` object a tasks-capable peer declares:
// {"io.modelcontextprotocol/tasks": {}}. Empty object = supported, no
// extension-specific settings are defined.
@ mcp_tasks_capability_json → Json {
    : Json exts ( json_obj_new )
    ( json_obj_set exts ( mcp_tasks_ext_id ) ( json_obj_new ) )
    ^ exts
}

// Declare an extension in a `capabilities` object (the shape
// `server/discover` returns), creating `extensions` when absent.
@ mcp_caps_declare_extension Json caps s ext → v {
    : ?Json e ( json_obj_get caps `extensions` )
    ?? e {
        T ev → { ( json_obj_set ev ext ( json_obj_new ) ) }
        F _ → {
            : Json exts ( json_obj_new )
            ( json_obj_set exts ext ( json_obj_new ) )
            ( json_obj_set caps `extensions` exts )
        }
    }
}

@ mcp_caps_declare_tasks Json caps → v {
    ( mcp_caps_declare_extension caps ( mcp_tasks_ext_id ) )
}

// Does this request declare `ext` in its per-request client
// capabilities? Path:
// params._meta["io.modelcontextprotocol/clientCapabilities"].extensions[ext]
// A legacy (handshake-era) request has no `_meta` and so declares
// nothing — which is the correct answer: the spec forbids returning a
// CreateTaskResult to it.
@ mcp_request_has_extension Json req s ext → b {
    : ?Json p ( json_obj_get req `params` )
    ?? p {
        T pv → {
            : ?Json m ( json_obj_get pv `_meta` )
            ?? m {
                T mv → {
                    : ?Json c ( json_obj_get mv `io.modelcontextprotocol/clientCapabilities` )
                    ?? c {
                        T cv → {
                            : ?Json x ( json_obj_get cv `extensions` )
                            ?? x {
                                T xv → { ^ ( json_obj_has xv ext ) }
                                F _ → { ^ F }
                            }
                        }
                        F _ → { ^ F }
                    }
                }
                F _ → { ^ F }
            }
        }
        F _ → { ^ F }
    }
}

@ mcp_request_declares_tasks Json req → b {
    ^ ( mcp_request_has_extension req ( mcp_tasks_ext_id ) )
}

// -32003 with the `data.requiredCapabilities` payload the spec shows,
// so a client can see exactly which extension it is missing.
@ mcp_missing_capability_response Json id s ext → Json {
    : Json exts ( json_obj_new )
    ( json_obj_set exts ext ( json_obj_new ) )
    : Json req_caps ( json_obj_new )
    ( json_obj_set req_caps `extensions` exts )
    : Json data ( json_obj_new )
    ( json_obj_set data `requiredCapabilities` req_caps )
    ^ ( mcp_response_error_data id mcp_tasks_err_missing_capability
    `Missing required client capability` data )
}

@ mcp_tasks_missing_capability_response Json id → Json {
    ^ ( mcp_missing_capability_response id ( mcp_tasks_ext_id ) )
}

// Unknown / expired taskId → -32602 (Invalid params), per the spec's
// "Protocol Errors" table.
@ mcp_task_invalid_id_response Json id s message → Json {
    ^ ( mcp_response_error id mcp_err_invalid_params message )
}

// ── Task record + store ─────────────────────────────────────────────
//
// Tasks live on the heap and are addressed by an opaque `s` handle so
// that field writes (`= . t status …`) hit the real record rather than
// a Vec-element copy. The store keeps the handles.

: McpTask {
    String id  // 32 hex chars of CSPRNG output — unguessable (spec: security)
    i status
    String status_message
    i created_ms
    i updated_ms
    i ttl_ms  // < 0 → unlimited (encoded as JSON null)
    i poll_ms  // <= 0 → pollIntervalMs omitted
    String method  // augmented request's method, e.g. "tools/call"
    String tool  // tool name for tools/call, else empty
    Json args  // the original request arguments (owned)
    Json result  // CallToolResult once completed (JNull before)
    Json error  // JSON-RPC error object once failed (JNull before)
    Json input_requests  // outstanding server→client requests (JObj)
    Json input_responses  // responses delivered by tasks/update (JObj)
    i link  // opaque server-side handle (own job id); 0 = unused
    i cancel_req  // 1 once tasks/cancel was seen (cooperative signal)
}

: McpTaskStore { ( Vec s ) tasks }

@ mcp_task_store_new → McpTaskStore {
    ^ @ McpTaskStore { ( vec_new [s] ) }
}

// Hard cap on retained tasks. Every task holds its arguments and its
// final result, so an unbounded store is a memory sink for a server
// whose clients never poll. At the cap `mcp_task_create` drops the
// oldest TERMINAL task (its result is already deliverable, and a client
// that never polled has forfeited it); if every task is still live the
// oldest one goes, since it is the closest to its TTL either way.
@ mcp_task_store_max → i { ^ 2048 }

@ mcp_task_store_count McpTaskStore store → i {
    ^ ( vec_len [s] . store tasks )
}

@ __mcp_task_at McpTaskStore store i k → s {
    ^ ?? ( vec_get [s] . store tasks k ) { T x → x F → # s 0 }
}

@ __mcp_task_free s tp → v {
    ? == # i tp 0 { ^ v } {}
    : *McpTask t # *McpTask tp
    ( string_free . t id )
    ( string_free . t status_message )
    ( string_free . t method )
    ( string_free . t tool )
    ( json_free . t args )
    ( json_free . t result )
    ( json_free . t error )
    ( json_free . t input_requests )
    ( json_free . t input_responses )
    ( nurl_free tp )
}

// Index of the eviction victim: the oldest terminal task, else index 0.
@ __mcp_task_victim McpTaskStore store → i {
    : i n ( vec_len [s] . store tasks )
    : ~ i k 0
    ~ < k n {
        : s pp ( __mcp_task_at store k )
        ? != # i pp 0 {
            : *McpTask t # *McpTask pp
            ? ( mcp_task_status_is_terminal . t status ) { ^ k } {}
        } {}
        = k + k 1
    }
    ^ 0
}

// CONSUMES `args`. `ttl_ms` < 0 means unlimited; `poll_ms` <= 0 omits
// the polling hint. Returns an opaque task handle (never 0).
@ mcp_task_create McpTaskStore store s method s tool Json args i ttl_ms i poll_ms → s {
    ? >= ( vec_len [s] . store tasks ) ( mcp_task_store_max ) {
        : i victim ( __mcp_task_victim store )
        ( __mcp_task_free ( __mcp_task_at store victim ) )
        ( vec_remove [s] . store tasks victim )
    } {}
    : i now ( now_ms )
    : *McpTask t # *McpTask ( nurl_alloc Z McpTask )
    // 16 CSPRNG bytes → 32 hex chars. The spec treats a task id as a
    // bearer token for server-side state, so it must not be guessable.
    = . t id ( rand_hex_str 16 )
    = . t status mcp_task_working
    = . t status_message ( string_new )
    = . t created_ms now
    = . t updated_ms now
    = . t ttl_ms ttl_ms
    = . t poll_ms poll_ms
    = . t method ( string_from method )
    = . t tool ( string_from tool )
    = . t args args
    = . t result ( json_null )
    = . t error ( json_null )
    = . t input_requests ( json_obj_new )
    = . t input_responses ( json_obj_new )
    = . t link 0
    = . t cancel_req 0
    : s tp # s t
    ( vec_push [s] . store tasks tp )
    ^ tp
}

// The k-th retained task, 0 when out of range. Order is unspecified and
// changes as tasks are swept — this is for a server sweeping its own
// live tasks (advancing jobs, pushing notifications), not for paging.
@ mcp_task_nth McpTaskStore store i k → s {
    ? | < k 0 >= k ( vec_len [s] . store tasks ) { ^ # s 0 } {}
    ^ ( __mcp_task_at store k )
}

@ mcp_task_find McpTaskStore store s id → s {
    ? == ( nurl_str_len id ) 0 { ^ # s 0 } {}
    : i n ( vec_len [s] . store tasks )
    : ~ s found # s 0
    : ~ i k 0
    ~ & == # i found 0 < k n {
        : s pp ( __mcp_task_at store k )
        ? != # i pp 0 {
            : *McpTask t # *McpTask pp
            ? != 0 ( nurl_str_eq ( string_data . t id ) id ) { = found pp } {}
        } {}
        = k + k 1
    }
    ^ found
}

// A task with a finite TTL is discardable once `createdAt + ttlMs` has
// elapsed. The spec lets the server mark it failed and delete it at any
// point after that; this store deletes.
@ __mcp_task_expired s tp i now → b {
    : *McpTask t # *McpTask tp
    ? < . t ttl_ms 0 { ^ F } {}
    ^ > now + . t created_ms . t ttl_ms
}

// Drop every expired task. Returns how many were dropped. Handlers call
// this before a lookup so an expired id reads as unknown.
@ mcp_task_store_sweep McpTaskStore store i now → i {
    : ~ i dropped 0
    : ~ i k 0
    ~ < k ( vec_len [s] . store tasks ) {
        : s pp ( __mcp_task_at store k )
        ? & != # i pp 0 ( __mcp_task_expired pp now ) {
            ( __mcp_task_free pp )
            ( vec_remove [s] . store tasks k )
            = dropped + dropped 1
        } {
            = k + k 1
        }
    }
    ^ dropped
}

@ mcp_task_store_free McpTaskStore store → v {
    : i n ( vec_len [s] . store tasks )
    : ~ i k 0
    ~ < k n {
        ( __mcp_task_free ( __mcp_task_at store k ) )
        = k + k 1
    }
    ( vec_free [s] . store tasks )
}

// ── Task accessors ──────────────────────────────────────────────────

@ mcp_task_id s tp → s { : *McpTask t # *McpTask tp ^ ( string_data . t id ) }

@ mcp_task_status s tp → i { : *McpTask t # *McpTask tp ^ . t status }

@ mcp_task_tool s tp → s { : *McpTask t # *McpTask tp ^ ( string_data . t tool ) }

@ mcp_task_method s tp → s { : *McpTask t # *McpTask tp ^ ( string_data . t method ) }

// BORROWED — the store still owns it. Clone before keeping it.
@ mcp_task_args s tp → Json { : *McpTask t # *McpTask tp ^ . t args }

@ mcp_task_link s tp → i { : *McpTask t # *McpTask tp ^ . t link }

@ mcp_task_set_link s tp i v → v { : *McpTask t # *McpTask tp = . t link v }

// Cancellation is COOPERATIVE: `tasks/cancel` records intent and acks;
// the server polls this flag and decides whether and when to stop.
@ mcp_task_cancel_requested s tp → b {
    : *McpTask t # *McpTask tp
    ^ == . t cancel_req 1
}

@ mcp_task_request_cancel s tp → v {
    : *McpTask t # *McpTask tp
    = . t cancel_req 1
}

// ── Task state transitions ──────────────────────────────────────────

@ __mcp_task_touch * McpTask t → v { = . t updated_ms ( now_ms ) }

@ __mcp_task_set_message * McpTask t s msg → v {
    ( string_free . t status_message )
    = . t status_message ( string_from msg )
}

// Replace the status message without touching the status — a progress
// description for a long-running "working" task.
@ mcp_task_set_message s tp s msg → v {
    : *McpTask t # *McpTask tp
    ( __mcp_task_set_message t msg )
    ( __mcp_task_touch t )
}

@ mcp_task_set_working s tp s msg → v {
    : *McpTask t # *McpTask tp
    = . t status mcp_task_working
    ( __mcp_task_set_message t msg )
    ( __mcp_task_touch t )
}

// CONSUMES `result` — the CallToolResult the original request would
// have returned. A tool-level failure (isError: true) is still a
// COMPLETED task: `failed` is reserved for JSON-RPC protocol faults.
@ mcp_task_complete s tp Json result → v {
    : *McpTask t # *McpTask tp
    = . t status mcp_task_completed
    ( json_free . t result )
    = . t result result
    // A completed task has nothing outstanding.
    ( json_free . t input_requests )
    = . t input_requests ( json_obj_new )
    ( __mcp_task_touch t )
}

// CONSUMES `error` — a JSON-RPC error object ({code, message[, data]}).
@ mcp_task_fail_error s tp Json error → v {
    : *McpTask t # *McpTask tp
    = . t status mcp_task_failed
    ( json_free . t error )
    = . t error error
    ( json_free . t input_requests )
    = . t input_requests ( json_obj_new )
    ( __mcp_task_touch t )
}

// Fail with a JSON-RPC error built from code + message. The message
// also becomes the statusMessage, which the spec says SHOULD carry
// diagnostic information on a failed task.
@ mcp_task_fail s tp i code s message → v {
    : Json err ( json_obj_new )
    ( json_obj_set err `code` ( json_int code ) )
    ( json_obj_set err `message` ( json_str_lit message ) )
    : *McpTask t # *McpTask tp
    ( __mcp_task_set_message t message )
    ( mcp_task_fail_error tp err )
}

@ mcp_task_cancel s tp → v {
    : *McpTask t # *McpTask tp
    = . t status mcp_task_cancelled
    = . t cancel_req 1
    ( json_free . t input_requests )
    = . t input_requests ( json_obj_new )
    ( __mcp_task_touch t )
}

// CONSUMES `requests` — a JObj of outstanding server→client requests
// keyed by identifiers unique over the task's lifetime (the spec
// forbids reusing a key once its response has been delivered). Moves
// the task to input_required.
@ mcp_task_request_input s tp Json requests → v {
    : *McpTask t # *McpTask tp
    = . t status mcp_task_input_required
    ( json_free . t input_requests )
    = . t input_requests requests
    ( __mcp_task_touch t )
}

// Merge one tasks/update payload into the pending responses. CONSUMES
// `responses`. Keys that are not currently outstanding are IGNORED, per
// the spec — that covers keys never issued, already-answered keys and
// superseded ones, and it is what makes duplicate client updates safe.
@ __mcp_task_put_input_responses s tp Json responses → i {
    : *McpTask t # *McpTask tp
    : ~ i taken 0
    : ( Vec String ) keys ( json_obj_keys responses )
    : i n ( vec_len [String] keys )
    : ~ i k 0
    ~ < k n {
        : ?String ko ( vec_get [String] keys k )
        ?? ko {
            T ks → {
                : s key ( string_data ks )
                ? ( json_obj_has . t input_requests key ) {
                    : ?Json vo ( json_obj_get responses key )
                    ?? vo {
                        T vv → {
                            ( json_obj_set . t input_responses key ( json_clone vv ) )
                            = taken + taken 1
                        }
                        F _ → {}
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ( json_free responses )
    ( __mcp_task_touch t )
    ^ taken
}

// Collect the responses delivered so far and clear the slot. None when
// nothing has arrived. The server calls this from its own scheduler,
// applies the answers, and moves the task back to working.
@ mcp_task_take_input_responses s tp → ?Json {
    : *McpTask t # *McpTask tp
    : ( Vec String ) keys ( json_obj_keys . t input_responses )
    : i n ( vec_len [String] keys )
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ? == n 0 { ^ @ ?Json { F @ Json { JNull } } } {}
    : Json out . t input_responses
    = . t input_responses ( json_obj_new )
    ^ @ ?Json { T out }
}

// ── Wire shapes ─────────────────────────────────────────────────────

@ __mcp_task_iso i ms → String {
    ^ ( time_format_iso ( time_from_unix / ms 1000 ) )
}

// The DetailedTask body: the common Task fields plus the status-specific
// payload (result / error / inputRequests). This is what `tasks/get`
// returns and what a `notifications/tasks` notification carries — the
// spec requires them to be identical.
@ mcp_task_detail s tp → Json {
    : *McpTask t # *McpTask tp
    : Json o ( json_obj_new )
    ( json_obj_set o `taskId` ( json_str_lit ( string_data . t id ) ) )
    ( json_obj_set o `status` ( json_str_lit ( mcp_task_status_name . t status ) ) )
    ? > ( string_len . t status_message ) 0 {
        ( json_obj_set o `statusMessage` ( json_str_lit ( string_data . t status_message ) ) )
    } {}
    : String c ( __mcp_task_iso . t created_ms )
    ( json_obj_set o `createdAt` ( json_str_lit ( string_data c ) ) )
    ( string_free c )
    : String u ( __mcp_task_iso . t updated_ms )
    ( json_obj_set o `lastUpdatedAt` ( json_str_lit ( string_data u ) ) )
    ( string_free u )
    ? < . t ttl_ms 0 {
        ( json_obj_set o `ttlMs` ( json_null ) )
    } {
        ( json_obj_set o `ttlMs` ( json_int . t ttl_ms ) )
    }
    ? > . t poll_ms 0 {
        ( json_obj_set o `pollIntervalMs` ( json_int . t poll_ms ) )
    } {}
    ? == . t status mcp_task_completed {
        ( json_obj_set o `result` ( json_clone . t result ) )
    } {}
    ? == . t status mcp_task_failed {
        ( json_obj_set o `error` ( json_clone . t error ) )
    } {}
    ? == . t status mcp_task_input_required {
        ( json_obj_set o `inputRequests` ( json_clone . t input_requests ) )
    } {}
    ^ o
}

// CreateTaskResult — what a task-augmented `tools/call` returns instead
// of a CallToolResult. `resultType` is set here to "task"; the central
// injection in `mcp_response_result` only fills in "complete" when the
// field is absent, so wrapping this in the usual envelope is safe.
@ mcp_task_create_result s tp → Json {
    : Json o ( mcp_task_detail tp )
    ( json_obj_set o `resultType` ( json_str_lit `task` ) )
    ^ o
}

@ mcp_task_notification s tp → Json {
    ^ ( mcp_notification `notifications/tasks` ( mcp_task_detail tp ) )
}

// `subscriptions/listen` params → the task ids the client wants status
// notifications for (`params.notifications.taskIds`). Owned Vec.
@ mcp_tasks_listen_ids Json params → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ?Json n ( json_obj_get params `notifications` )
    ?? n {
        T nv → {
            : ?Json ids ( json_obj_get nv `taskIds` )
            ?? ids {
                T av → {
                    : i len ( json_arr_len av )
                    : ~ i k 0
                    ~ < k len {
                        : ?Json e ( json_arr_get av k )
                        ?? e {
                            T ev → {
                                : s sv ( json_as_str ev )
                                ? > ( nurl_str_len sv ) 0 {
                                    ( vec_push [String] out ( string_from sv ) )
                                } {}
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ^ out
}

// The `notifications/subscriptions/acknowledged` reply listing the task
// ids the server agreed to push status for. CONSUMES `ids`.
@ mcp_tasks_subscribed_notification ( Vec String ) ids → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [String] ids )
    : ~ i k 0
    ~ < k n {
        : ?String e ( vec_get [String] ids k )
        ?? e { T sv → ( json_arr_push arr ( json_str_lit ( string_data sv ) ) ) F → {} }
        = k + k 1
    }
    ( vec_free_with [String] ids \ String x → v { ( string_free x ) } )
    : Json notifications ( json_obj_new )
    ( json_obj_set notifications `taskIds` arr )
    : Json params ( json_obj_new )
    ( json_obj_set params `notifications` notifications )
    ^ ( mcp_notification `notifications/subscriptions/acknowledged` params )
}

// ── Request handlers ────────────────────────────────────────────────

@ mcp_tasks_is_method s method → b {
    ? != 0 ( nurl_str_eq method `tasks/get` ) { ^ T } {}
    ? != 0 ( nurl_str_eq method `tasks/update` ) { ^ T } {}
    ? != 0 ( nurl_str_eq method `tasks/cancel` ) { ^ T } {}
    ^ F
}

@ __mcp_tasks_param_id Json params → s {
    : ?Json t ( json_obj_get params `taskId` )
    ?? t { T j → { ^ ( json_as_str j ) } F _ → { ^ `` } }
}

// Sweep expired tasks, then look up. 0 when unknown or already expired
// — the spec explicitly allows reporting a purged task as not found.
@ __mcp_tasks_lookup McpTaskStore store Json params → s {
    ( mcp_task_store_sweep store ( now_ms ) )
    ^ ( mcp_task_find store ( __mcp_tasks_param_id params ) )
}

@ mcp_tasks_handle_get McpTaskStore store Json id Json params → Json {
    : s tp ( __mcp_tasks_lookup store params )
    ? == # i tp 0 {
        ^ ( mcp_task_invalid_id_response id `Failed to retrieve task: task not found or expired` )
    } {}
    ^ ( mcp_response_result id ( mcp_task_detail tp ) )
}

// Empty acknowledgement. The ack is eventually consistent: the responses
// are recorded here, and the task's observable status only changes once
// the server's own scheduler picks them up.
@ mcp_tasks_handle_update McpTaskStore store Json id Json params → Json {
    : s tp ( __mcp_tasks_lookup store params )
    ? == # i tp 0 {
        ^ ( mcp_task_invalid_id_response id `Failed to update task: task not found or expired` )
    } {}
    : ?Json ir ( json_obj_get params `inputResponses` )
    ?? ir {
        T iv → { ( __mcp_task_put_input_responses tp ( json_clone iv ) ) }
        F _ → {}
    }
    ^ ( mcp_response_result id ( json_obj_new ) )
}

// Records intent and acks. The status is NOT forced to cancelled here:
// cancellation is cooperative, and the work may well finish first.
@ mcp_tasks_handle_cancel McpTaskStore store Json id Json params → Json {
    : s tp ( __mcp_tasks_lookup store params )
    ? == # i tp 0 {
        ^ ( mcp_task_invalid_id_response id `Failed to cancel task: task not found or expired` )
    } {}
    ? ( mcp_task_status_is_terminal ( mcp_task_status tp ) ) {} {
        ( mcp_task_request_cancel tp )
    }
    ^ ( mcp_response_result id ( json_obj_new ) )
}

// The whole `tasks/*` surface: None when `method` is not one of them,
// otherwise the capability gate (-32003 for a client that did not
// declare the extension on this request) and the matching handler.
@ mcp_tasks_dispatch McpTaskStore store Json req Json id s method → ?Json {
    ? ( mcp_tasks_is_method method ) {} { ^ @ ?Json { F @ Json { JNull } } }
    ? ( mcp_request_declares_tasks req ) {} {
        ^ @ ?Json { T ( mcp_tasks_missing_capability_response id ) }
    }
    : ?Json po ( json_obj_get req `params` )
    : Json params ?? po {
        T pv → ( json_clone pv )
        F → ( json_obj_new )
    }
    : ~ Json out ( json_null )
    ? != 0 ( nurl_str_eq method `tasks/get` ) {
        = out ( mcp_tasks_handle_get store id params )
    } {
        ? != 0 ( nurl_str_eq method `tasks/update` ) {
            = out ( mcp_tasks_handle_update store id params )
        } {
            = out ( mcp_tasks_handle_cancel store id params )
        }
    }
    ( json_free params )
    ^ @ ?Json { T out }
}
