// stdlib/ext/mcp_server.nu — WRITE AN MCP SERVER IN NURL.
//
// START HERE for anything server-side. Register tools/prompts/
// resources with closure handlers, pick a transport, done — you never
// touch JSON-RPC, the dual-era version gate, `server/discover`, or the
// `_meta` decorations by hand. Hand-rolling those is how three servers
// in this repo each grew their own subtly-different copy; this module
// is the one copy.
//
//   : McpServer srv ( mcp_server_new `my-server` `1.0.0` )
//   ( mcp_server_add_tool srv `echo` `Echo the text back.`
//     ( mcp_schema_of1 `text` `string` `Text to echo` T )
//     \ Json a → Json { ^ ( echo_tool a ) } )
//   ?? ( mcp_server_serve_stdio srv ) { T _ → {} F _ → {} }
//
// …and `mcp_server_serve_http srv host port token` is the same
// program over Streamable HTTP, bearer auth included.
//
// Working examples: examples/mcp_echo_server.nu (stdio),
// examples/mcp_echo_server_http.nu (HTTP). Real servers built on it:
// packages/nurl-mcp, packages/swarm-mcp, packages/mermaid-server.
//
// The MCP module family (all of `stdlib/ext/mcp*.nu`):
//   mcp_server.nu   ← YOU ARE HERE — build a server (any transport)
//   mcp.nu            JSON-RPC envelopes + result builders (the layer
//                     under this one; use it directly only for shapes
//                     this module does not model yet)
//   mcp_http.nu       Streamable-HTTP transport (POST/GET-SSE/DELETE)
//   mcp_session.nu    per-session state: SSE queues, subscriptions,
//                     server→client RPC (sampling)
//   mcp_tasks.nu      the io.modelcontextprotocol/tasks extension
//   mcp_client.nu     CLIENT over HTTP     — consuming someone else's server
//   mcp_stdio.nu      CLIENT over stdio    — spawns a server as a child
//   mcp_search.nu     search/fetch tool helpers
//
// Spec coverage — DUAL-ERA per the 2026-07-28 versioning page: one
// server serves both modern (per-request `_meta`, `server/discover`)
// and legacy (initialize handshake) clients on the same endpoint:
//   * server/discover (2026-07-28 — servers MUST implement)
//   * initialize / initialized (legacy handshake; echoes the client's
//     requested revision when supported)
//   * tools/list, tools/call            (with ToolAnnotations)
//   * prompts/list, prompts/get
//   * resources/list, resources/read, resources/templates/list
//     (list/read results carry the 2026-07-28 CacheableResult fields
//     ttlMs + cacheScope, per `mcp_server_set_cache_policy`)
//   * completion/complete (argument autocompletion for prompts/resources)
//   * ping (legacy heartbeat — empty result)
//   * tasks/get, tasks/update, tasks/cancel — only once a task store
//     is attached with `mcp_server_set_task_store`, which is also what
//     declares the extension in the server's capabilities
// Requests declaring an unsupported `_meta` protocolVersion get the
// spec-shaped UnsupportedProtocolVersionError (-32022); results for
// modern requests carry `_meta` serverInfo. `resultType: "complete"`
// rides on every result via mcp.nu's envelope builder.
//
// Out of scope here (transport-level; served by mcp_session/mcp_http):
//   * resources/subscribe + notifications/resources/updated — session-
//     scoped in mcp_http_handler_session over the mcp_session queue
//     (this dispatch stays session-agnostic)
//   * sampling/createMessage (server→client reverse RPC — mcp_session)
// Out of scope (client-side feature):
//   * roots/list
//
// Every handler runs under `recover`: a panic inside one becomes a
// tool/prompt/resource error envelope instead of killing the process.
// That is the difference between this and a hand-rolled dispatch loop
// over stdio, where one bad `json_as_str` takes the server down.
//
// ── STABLE SURFACE ───────────────────────────────────────────────────
//
// Public API = the `mcp_server_*` / `mcp_rpc_err_*` functions and the
// `McpServerErr` enum, and nothing else. Everything `__`-prefixed is
// internal and changes without notice; `McpServer` and `McpRpcErr` are
// OPAQUE — every field is `__`-prefixed so that reaching in
// (`. srv __tools`) reads at the call site as the violation it is.
// Use the accessors and a field reorder underneath cannot touch you.
//
// The compatibility rules this module holds itself to, so that work
// underneath cannot break code above it:
//
//   1. No existing function ever gains a parameter. NURL has no
//      default arguments, so a new parameter is a break at every call
//      site. Extensions arrive as NEW functions beside the old ones,
//      or as setters on the handle.
//   2. `McpServerErr` is FROZEN at its three variants. `??` over an
//      enum is exhaustive, so a fourth variant breaks every consumer's
//      match. New failure detail arrives through
//      `mcp_server_err_name`, not through new variants. `McpRpcErr` is
//      a struct precisely so that a new JSON-RPC failure is a new
//      CODE, not a new variant.
//   3. Handler types are FROZEN: `( @ Json Json )` for tools, prompts
//      and completions, `( @ Json )` for resources. A tool that needs
//      to know what the client declared on THIS request registers
//      through `mcp_server_add_tool_ctx` and receives an McpCall
//      beside its arguments; the plain form stays untouched. Anything
//      a future revision puts on a request becomes an McpCall
//      accessor, never a new handler parameter. The same accessor
//      carries what the HOST knows about the caller
//      (`mcp_call_context`, attached by `mcp_server_dispatch_as`) —
//      which is also what `mcp_server_add_tool_gated` filters the
//      tool list on, so an authorisation-aware server is one server,
//      not one per role.
//   4. `mcp_server_dispatch` takes the whole REQUEST for the same
//      reason: per-request `_meta` is part of the protocol now, and a
//      method-plus-params entry point would have had to grow.
//
// Memory model:
//   McpServer OWNS its String + Json fields + the Vec containers.
//   `mcp_server_add_*` CONSUMES the name / description / schema it is
//   given and BORROWS the handler closure — the handler must outlive
//   the server. A bare function name is not a closure value in NURL, so
//   a top-level handler is wrapped at the registration site:
//   `\ Json a → Json { ^ ( my_tool a ) }`. That wrapper captures
//   nothing and lives as long as the program.
//   `mcp_server_dispatch` / `_envelope` return an OWNED Json; the
//   caller frees it with json_free (the transports here already do).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/mcp_tasks.nu`
$ `stdlib/ext/mcp_http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// ── Types the handler records refer to ────────────────────────────────
//
// These come FIRST because `McpTool` holds a closure type that takes an
// `McpCall` by value: a named type inside a function type must already
// be defined when the struct that holds it is emitted, or LLVM makes it
// an opaque forward reference and rejects the module. nurlc diagnoses
// that at the declaration now; before it did, the failure was a link
// error on macOS-arm64 and Windows while x86-64 Linux built clean.

// A pre-dispatch hook for tasks/*, boxed so it can live in a Vec.
: McpTaskHook {
    ( @ v ) f
}

// ── Per-call context ──────────────────────────────────────────────────
//
// What a tool handler can learn about the request it is answering,
// beyond its own arguments. OPAQUE and BORROWED: the request Json
// belongs to the transport and is freed after the reply goes out, so a
// handler must not keep an McpCall past its own return.
//
// It exists so that the frozen `( @ Json Json )` handler type never has
// to grow: anything a future revision puts on a request becomes an
// accessor here, not a new parameter on every handler in every server.
//
// Two things ride here, from two different parties:
//   __req  — what the CLIENT sent (the JSON-RPC request, `_meta` etc.)
//   __ctx  — what the HOST knows about the caller and the client never
//            gets to assert: who they are, what they may do. Set by
//            `mcp_server_dispatch_as` / `_envelope_as`; JSON null when
//            the server was entered through the plain dispatch.

: McpCall {
    Json __req
    Json __ctx
}

// The raw JSON-RPC request, for `_meta` fields with no accessor yet.
@ mcp_call_request McpCall c → Json { ^ . c __req }

// The caller context the HOST attached to this dispatch (see
// `mcp_server_dispatch_as`), or JSON null. BORROWED — do not free, do
// not keep past the handler's return. This is where a tool learns the
// authenticated principal behind the request: the transport resolved
// the credential, the server threaded it through, and no client
// argument can forge it.
@ mcp_call_context McpCall c → Json { ^ . c __ctx }

// Did the client declare the io.modelcontextprotocol/tasks extension on
// THIS request? A server that can answer a long call as a task checks
// this before doing so — a client that did not declare tasks cannot
// poll one, so handing it a task id would strand the work.
@ mcp_call_wants_tasks McpCall c → b {
    ^ ( mcp_request_declares_tasks . c __req )
}

// The protocol revision this request declared, or `` for a legacy-era
// request that declared none.
@ mcp_call_protocol_version McpCall c → s {
    ^ ( mcp_request_protocol_version . c __req )
}

// Prompt: parameterised prompt template the client can retrieve. The
// handler receives the `arguments` Json (matching the prompt's
// declared argument schema) and returns the prompt's `messages` Json
// — typically a Vec of {role, content} objects.
: McpPrompt {
    String name
    String description
    Json arguments_schema
    ( @ Json Json ) handler
}

// Resource: URI-addressable content. The handler is called with no
// args (the URI identifies the resource) and returns the resource
// contents — usually a {uri, mimeType, text} or {uri, mimeType, blob}
// object per the MCP spec §6.4.
: McpResource {
    String uri
    String name
    String mime_type
    String description
    ( @ Json ) handler
}

// Resource TEMPLATE (spec §resources, `resources/templates/list`): a
// family of resources addressed by a URI template rather than one
// fixed URI — `nurl://stdlib/{path}`. The handler receives the part of
// the requested URI that filled the variable, so a template registered
// as `nurl://stdlib/{path}` and read as `nurl://stdlib/ext/csv.nu`
// hands the handler `ext/csv.nu`.
//
// Only a single trailing `{var}` is supported, which is the shape every
// template in this tree uses and the only one that can be matched by a
// prefix compare. A template whose variable is not final is rejected at
// registration rather than silently never matching.
//
// A template is not a resource: `resources/list` must NOT contain it
// (a client would try to read the literal `{path}`), and a client that
// only reads `resources/list` cannot discover it. That is what
// `resources/templates/list` is for, and a server that serves templated
// URIs without answering it is advertising nothing a client can find.
: McpResourceTemplate {
    String uri_template
    String prefix
    String name
    String mime_type
    String description
    ( @ Json Json ) handler
}

// Completion provider (spec §6.7, completion/complete). Bound to a
// single reference — a prompt (`ref/prompt` + name) or a resource
// template (`ref/resource` + uri). The handler receives the request's
// `argument` object (`{name, value}` — the argument being completed and
// the partial text typed so far) and returns a Json ARRAY of candidate
// string values. The dispatcher wraps that array in the spec-shaped
// `{completion: {values, total, hasMore}}` envelope.
: McpCompletion {
    String ref_type
    String ref_id
    ( @ Json Json ) handler
}

// ── Protocol-level failure ────────────────────────────────────────────
//
// A dispatch either produces a RESULT or fails at the JSON-RPC level,
// and those are different things — so they travel in different places.
// The earlier design signalled failure in-band, as a `__error__` key on
// the result object, which had two problems. It shared a namespace with
// whatever a handler returned (a resource handler emitting a field of
// that name became a protocol error), and having no room for a code it
// mapped every failure to -32601 "method not found" — so a `prompts/get`
// missing its `name` told the client the method did not exist, and the
// client dutifully stopped calling it.
//
// `!Json McpRpcErr` has room for the code and cannot collide with
// handler output, because the failure is not a Json object at all.
//
// A JSON-RPC error object is {code, message, data}, and `data` is where
// the protocol puts what the client is supposed to DO about the failure
// — `supported` on an unsupported version, `requiredCapabilities` on a
// missing extension. Carrying only code and message would drop exactly
// the actionable half.
//
// OPAQUE: read it with `mcp_rpc_err_code` / `_message` / `_data`, free
// it with `mcp_rpc_err_free`. Owns its message and its data.

: McpRpcErr {
    i __code
    String __message
    Json __data
}

@ mcp_rpc_err i code s message → McpRpcErr {
    ^ @ McpRpcErr { code ( string_from message ) ( json_null ) }
}

// CONSUMES `data`.
@ mcp_rpc_err_data i code s message Json data → McpRpcErr {
    ^ @ McpRpcErr { code ( string_from message ) data }
}

@ mcp_rpc_err_code McpRpcErr e → i { ^ . e __code }

@ mcp_rpc_err_message McpRpcErr e → s { ^ ( string_data . e __message ) }

// Borrowed; `json_is_null` when the failure carries none.
@ mcp_rpc_err_get_data McpRpcErr e → Json { ^ . e __data }

@ mcp_rpc_err_free McpRpcErr e → v {
    ( string_free . e __message )
    ( json_free . e __data )
}

// ── Handler-bearing record types ──────────────────────────────────────

// Tool: callable function exposed to the LLM. The handler receives the
// `arguments` Json (whatever the LLM passes per the tool's
// inputSchema) and returns a tool-result envelope, typically built
// via mcp_tool_result_text / mcp_tool_result_error.
: McpTool {
    String name
    String description
    Json input_schema
    ( @ Json Json ) handler
    // Handler for tools registered with `_add_tool_ctx`; `has_ctx`
    // picks which of the two runs. Two fields rather than one
    // wider handler type because the plain `( @ Json Json )` shape is
    // frozen API (STABLE SURFACE rule 3) and most tools want it.
    ( @ Json Json McpCall ) ctx_handler
    b has_ctx
    // ToolAnnotations (spec 2025-03-26), or Json null when the tool
    // was registered without them. An ABSENT destructiveHint defaults
    // to TRUE in the spec, so an unannotated harmless tool is presented
    // to the user as if it could destroy state.
    Json annotations
    // Per-caller visibility (`mcp_server_add_tool_gated`): the tool is
    // listed and callable only when `visible` says so for the caller
    // context of the dispatch. `gated` F = always visible, and the
    // predicate is a placeholder that is never consulted.
    ( @ b Json ) visible
    b gated
}

// ── The server handle ─────────────────────────────────────────────────
//
// OPAQUE. Every field is `__`-prefixed for one reason: so that a
// consumer reaching in (`. srv __tools`) reads at the call site as the
// contract violation it is. Read the handle through the accessors
// below — `mcp_server_name`, `_version`, `_tool_count`, `_has_tool` —
// and a field reorder or a new field underneath cannot touch you.
//
// `__ctl` is a one-slot ( Vec i ) holding the serving flag, and it is
// a Vec rather than an `i` field for a reason worth stating: a struct
// is passed BY VALUE in NURL, so `= . r __frozen 1` inside a method
// writes to that method's own copy and no caller ever sees it. A Vec
// shares its control block across copies — the same property that
// makes `mcp_server_add_tool` work at all — so the flag set during a
// dispatch is visible to a later `add`. (nurlc now warns on the scalar
// form; this module is where that warning was first earned.)
//
// The flag flips on the first dispatch, and registration after that
// point fails loudly at the `add` (see `__mcp_server_check_open`).
// `tools/list` results carry `ttlMs: 60000`, so a client may legally
// cache the tool list — a tool registered after the first request is
// invisible to that client until its cache expires, and invisible to
// the author entirely.

: McpServer {
    String __name
    String __version
    ( Vec McpTool ) __tools
    ( Vec McpPrompt ) __prompts
    ( Vec McpResource ) __resources
    ( Vec McpResourceTemplate ) __templates
    ( Vec McpCompletion ) __completions
    ( Vec i ) __ctl
    // The `cacheScope` a CacheableResult carries. A String rather than
    // a scalar for the same reason `__ctl` is a Vec: a struct is passed
    // by value, so only a shared handle lets a setter reach every copy.
    String __cache_scope
    // Server instructions (2026-07-28 `server/discover`, and the
    // legacy handshake's `instructions`): how a model should approach
    // this server, which tool to reach for first. Empty = omitted.
    // A String, so `mcp_server_set_instructions` can rewrite it
    // through the shared control block rather than replacing a field
    // that a by-value copy would swallow.
    String __instructions
    // Zero or one task store. A ( Vec ) so that "no store" and "an
    // empty store" stay distinguishable, and so that attaching one
    // after construction is visible to every copy of the handle.
    ( Vec McpTaskStore ) __tasks
    // Called before any tasks/* method is dispatched — the hook a
    // server needs when its task state is only current after it polls
    // something (swarm-mcp advances its cluster here). Empty Vec = no
    // hook. Wrapped in a struct because a closure is not spellable as
    // a generic type argument.
    ( Vec McpTaskHook ) __task_hook
}

: i MCP_CTL_SERVING 0
// Slots 1..3 hold the CacheableResult TTLs, in ms. Defaults below.
: i MCP_CTL_TTL_LIST 1
: i MCP_CTL_TTL_READ 2

@ mcp_server_new s name s version → McpServer {
    ^ @ McpServer {
        ( string_from name )
        ( string_from version )
        ( vec_new [McpTool] )
        ( vec_new [McpPrompt] )
        ( vec_new [McpResource] )
        ( vec_new [McpResourceTemplate] )
        ( vec_new [McpCompletion] )
        ( __mcp_ctl_new )
        ( string_from `private` )
        ( string_new )
        ( vec_new [McpTaskStore] )
        ( vec_new [McpTaskHook] )
    }
}

@ __mcp_ctl_new → ( Vec i ) {
    : ( Vec i ) c ( vec_with_cap [i] 3 )
    ( vec_push [i] c 0 )
    // Defaults: a registry fixed after startup but possibly behind
    // auth — a modest TTL, private. A server whose surface is public
    // and static says so with `mcp_server_set_cache_policy`.
    ( vec_push [i] c 60000 )
    ( vec_push [i] c 5000 )
    ^ c
}

// ── Accessors (the supported way to read the handle) ──────────────────

@ mcp_server_name McpServer r → s { ^ ( string_data . r __name ) }

@ mcp_server_version McpServer r → s { ^ ( string_data . r __version ) }

@ mcp_server_tool_count McpServer r → i { ^ ( vec_len [McpTool] . r __tools ) }

@ mcp_server_prompt_count McpServer r → i { ^ ( vec_len [McpPrompt] . r __prompts ) }

@ mcp_server_resource_count McpServer r → i { ^ ( vec_len [McpResource] . r __resources ) }

@ mcp_server_has_tool McpServer r s name → b {
    ^ >= ( __mcp_find_tool_index r name ) 0
}

// How long a client may cache this server's LISTINGS (tools/list,
// prompts/list, resources/list) and its resource READS, and whether a
// shared cache may hold them (`public`) or only the requesting client
// (`private`). CacheableResult, 2026-07-28.
//
// The defaults — 60 s / 5 s, private — suit a server that may sit
// behind auth and whose resources are live. They are wrong for the
// other common shape: a public server whose tool surface is fixed at
// build time, where an hour and `public` are honest and a 60-second
// private TTL costs every client a re-listing per minute for a list
// that cannot change.
//
// A TTL of 0 leaves that result uncached.
@ mcp_server_set_cache_policy McpServer r i list_ttl_ms i read_ttl_ms s scope → v {
    ( vec_set [i] . r __ctl MCP_CTL_TTL_LIST list_ttl_ms )
    ( vec_set [i] . r __ctl MCP_CTL_TTL_READ read_ttl_ms )
    ( string_clear . r __cache_scope )
    ( string_push_str . r __cache_scope scope )
}

@ __mcp_ctl McpServer r i slot → i {
    ?? ( vec_get [i] . r __ctl slot ) { T v → { ^ v } F → { ^ 0 } }
}

// Stamp a listing result with the server's cache policy.
@ __mcp_mark_list McpServer r Json out → v {
    : i ttl ( __mcp_ctl r MCP_CTL_TTL_LIST )
    ? > ttl 0 { ( mcp_result_set_cacheable out ttl ( string_data . r __cache_scope ) ) } {}
}

@ __mcp_mark_read McpServer r Json out → v {
    : i ttl ( __mcp_ctl r MCP_CTL_TTL_READ )
    ? > ttl 0 { ( mcp_result_set_cacheable out ttl ( string_data . r __cache_scope ) ) } {}
}

// T once the server has served its first request — see `__ctl`.
@ mcp_server_is_serving McpServer r → b {
    ?? ( vec_get [i] . r __ctl MCP_CTL_SERVING ) { T v → { ^ != v 0 } F → { ^ F } }
}

@ mcp_server_free McpServer r → v {
    ( string_free . r __name )
    ( string_free . r __version )
    // Tools
    : i tn ( vec_len [McpTool] . r __tools )
    : *McpTool tp ( vec_data [McpTool] . r __tools )
    : ~ i k 0
    ~ < k tn {
        : McpTool t . tp k
        ( string_free . t name )
        ( string_free . t description )
        ( json_free . t input_schema )
        ( json_free . t annotations )
        = k + k 1
    }
    ( vec_free [McpTool] . r __tools )
    // Prompts
    : i pn ( vec_len [McpPrompt] . r __prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r __prompts )
    = k 0
    ~ < k pn {
        : McpPrompt p . pp k
        ( string_free . p name )
        ( string_free . p description )
        ( json_free . p arguments_schema )
        = k + k 1
    }
    ( vec_free [McpPrompt] . r __prompts )
    // Resources
    : i rn ( vec_len [McpResource] . r __resources )
    : *McpResource rp ( vec_data [McpResource] . r __resources )
    = k 0
    ~ < k rn {
        : McpResource res . rp k
        ( string_free . res uri )
        ( string_free . res name )
        ( string_free . res mime_type )
        ( string_free . res description )
        = k + k 1
    }
    ( vec_free [McpResource] . r __resources )
    // Templates
    : i wn ( vec_len [McpResourceTemplate] . r __templates )
    : *McpResourceTemplate wp ( vec_data [McpResourceTemplate] . r __templates )
    = k 0
    ~ < k wn {
        : McpResourceTemplate t . wp k
        ( string_free . t uri_template )
        ( string_free . t prefix )
        ( string_free . t name )
        ( string_free . t mime_type )
        ( string_free . t description )
        = k + k 1
    }
    ( vec_free [McpResourceTemplate] . r __templates )
    // Completions
    : i cn ( vec_len [McpCompletion] . r __completions )
    : *McpCompletion cp ( vec_data [McpCompletion] . r __completions )
    = k 0
    ~ < k cn {
        : McpCompletion c . cp k
        ( string_free . c ref_type )
        ( string_free . c ref_id )
        = k + k 1
    }
    ( vec_free [McpCompletion] . r __completions )
    ( vec_free [i] . r __ctl )
    ( string_free . r __instructions )
    ( string_free . r __cache_scope )
    // The task store is borrowed — freed by whoever created it.
    ( vec_free [McpTaskStore] . r __tasks )
    ( vec_free [McpTaskHook] . r __task_hook )
}

// ── Registration guards ───────────────────────────────────────────────
//
// A duplicate name or a late registration is a bug in the SERVER, not
// in any request, so both are caught at startup and loudly. The
// alternatives are worse than a panic: a duplicate silently shadows —
// `tools/list` advertises two entries, `tools/call` only ever reaches
// the first, and the tool that does nothing is the one the author just
// wrote. A late registration can reallocate a Vec that a dispatch in
// flight is holding a `vec_data` pointer into, which is a
// use-after-free that shows up as corruption under load, far from its
// cause.

@ __mcp_server_reject s kind s name s why → v {
    : String m ( string_from `mcp_server: cannot register ` )
    ( string_push_str m kind )
    ( string_push_str m ` "` )
    ( string_push_str m name )
    ( string_push_str m `" — ` )
    ( string_push_str m why )
    ( panic ( string_data m ) )
}

// Every `mcp_server_add_*` calls this first. `dup` is the index a
// lookup returned, or -1 when the name is free.
@ __mcp_server_check_open McpServer r s kind s name i dup → v {
    ? ( mcp_server_is_serving r ) {
        ( __mcp_server_reject kind name `the server is already serving requests` )
    } {}
    ? >= dup 0 {
        ( __mcp_server_reject kind name `that name is already registered` )
    } {}
}

// CONSUMES `name`, `description`, `schema`. Handler is borrowed.
@ mcp_server_add_tool McpServer r s name s description Json schema ( @ Json Json ) handler → v {
    ( __mcp_server_check_open r `tool` name ( __mcp_find_tool_index r name ) )
    : McpTool t @ McpTool {
        ( string_from name )
        ( string_from description )
        schema
        handler
        \ Json a McpCall c → Json { ^ ( json_obj_new ) }
        F
        ( json_null )
        \ Json c → b { ^ T }
        F
    }
    ( vec_push [McpTool] . r __tools t )
}

// Same, plus ToolAnnotations — the trust hints a client uses to decide
// what to auto-allow. A tool that skips them is presented as if it
// could destroy state, because an ABSENT destructiveHint defaults to
// TRUE in the spec, so prefer this form for anything read-only.
// CONSUMES `name`, `description`, `schema`.
@ mcp_server_add_tool_full McpServer r s name s description Json schema
b read_only b destructive b idempotent b open_world ( @ Json Json ) handler → v {
    ( __mcp_server_check_open r `tool` name ( __mcp_find_tool_index r name ) )
    : Json ann ( json_obj_new )
    ( json_obj_set ann `readOnlyHint` ( json_bool read_only ) )
    ( json_obj_set ann `destructiveHint` ( json_bool destructive ) )
    ( json_obj_set ann `idempotentHint` ( json_bool idempotent ) )
    ( json_obj_set ann `openWorldHint` ( json_bool open_world ) )
    : McpTool t @ McpTool {
        ( string_from name )
        ( string_from description )
        schema
        handler
        \ Json a McpCall c → Json { ^ ( json_obj_new ) }
        F
        ann
        \ Json c → b { ^ T }
        F
    }
    ( vec_push [McpTool] . r __tools t )
}

// A tool whose handler also receives the per-call context — what the
// client declared on THIS request. The reason it is a separate
// registration rather than a wider handler type: `( @ Json Json )` is
// frozen API, and most tools neither need the context nor should pay
// for it. CONSUMES `name`, `description`, `schema`.
@ mcp_server_add_tool_ctx McpServer r s name s description Json schema
b read_only b destructive b idempotent b open_world
( @ Json Json McpCall ) handler → v {
    ( __mcp_server_check_open r `tool` name ( __mcp_find_tool_index r name ) )
    : Json ann ( json_obj_new )
    ( json_obj_set ann `readOnlyHint` ( json_bool read_only ) )
    ( json_obj_set ann `destructiveHint` ( json_bool destructive ) )
    ( json_obj_set ann `idempotentHint` ( json_bool idempotent ) )
    ( json_obj_set ann `openWorldHint` ( json_bool open_world ) )
    : McpTool t @ McpTool {
        ( string_from name )
        ( string_from description )
        schema
        \ Json a → Json { ^ ( json_obj_new ) }
        handler
        T
        ann
        \ Json c → b { ^ T }
        F
    }
    ( vec_push [McpTool] . r __tools t )
}

// A tool whose EXISTENCE depends on who is asking. `visible` is
// evaluated against the caller context of each dispatch (see
// `mcp_server_dispatch_as`): when it says F the tool is left out of
// `tools/list` and a `tools/call` naming it gets the same "unknown
// tool" envelope an unregistered name gets — a caller who may not use
// a tool is not told it exists. With the plain dispatch (context = JSON
// null) the predicate sees null and decides for that case too.
//
// This is how one server serves an admin the full surface and a viewer
// the read-only half without two servers, and without every handler
// re-checking a role its caller could never have reached it with. The
// handler receives the McpCall so it can read the same context
// (`mcp_call_context`) — the identity that made it visible is the
// identity it acts as. BORROWS `visible` and `handler`; CONSUMES
// `name`, `description`, `schema`.
@ mcp_server_add_tool_gated McpServer r s name s description Json schema
b read_only b destructive b idempotent b open_world
( @ b Json ) visible ( @ Json Json McpCall ) handler → v {
    ( __mcp_server_check_open r `tool` name ( __mcp_find_tool_index r name ) )
    : Json ann ( json_obj_new )
    ( json_obj_set ann `readOnlyHint` ( json_bool read_only ) )
    ( json_obj_set ann `destructiveHint` ( json_bool destructive ) )
    ( json_obj_set ann `idempotentHint` ( json_bool idempotent ) )
    ( json_obj_set ann `openWorldHint` ( json_bool open_world ) )
    : McpTool t @ McpTool {
        ( string_from name )
        ( string_from description )
        schema
        \ Json a → Json { ^ ( json_obj_new ) }
        handler
        T
        ann
        visible
        T
    }
    ( vec_push [McpTool] . r __tools t )
}

// Is tool `t` visible to the caller context `ctx`? Ungated tools always
// are; a gated one asks its predicate.
@ __mcp_tool_visible McpTool t Json ctx → b {
    ? ! . t gated { ^ T } {}
    : ( @ b Json ) vis . t visible
    ^ ( vis ctx )
}

// How a model should approach this server: which tool to reach for
// first, what the cheap probe is, what the expensive one costs. Rides
// `server/discover` and the legacy handshake result. Every server that
// hand-rolled its dispatch wrote one of these; the facade had no
// channel for it, which is one reason they kept hand-rolling.
@ mcp_server_set_instructions McpServer r s text → v {
    ( string_clear . r __instructions )
    ( string_push_str . r __instructions text )
}

@ mcp_server_instructions McpServer r → s { ^ ( string_data . r __instructions ) }

// Attach a task store, which is what turns tasks/get, tasks/update and
// tasks/cancel on and declares the io.modelcontextprotocol/tasks
// extension in the server's capabilities. Without one those methods
// answer "method not found", which is correct: a server that cannot
// hold a task must not claim it can.
//
// The store is BORROWED — it outlives the server or the server outlives
// nothing. `hook` runs before each tasks/* dispatch, for a server whose
// task state is only current after it polls something; pass
// `\ → v {}` when there is nothing to do.
@ mcp_server_set_task_store McpServer r McpTaskStore store ( @ v ) hook → v {
    ( vec_clear [McpTaskStore] . r __tasks )
    ( vec_push [McpTaskStore] . r __tasks store )
    ( vec_clear [McpTaskHook] . r __task_hook )
    ( vec_push [McpTaskHook] . r __task_hook @ McpTaskHook { hook } )
}

@ mcp_server_has_task_store McpServer r → b {
    ^ > ( vec_len [McpTaskStore] . r __tasks ) 0
}

@ mcp_server_add_prompt McpServer r s name s description Json args_schema ( @ Json Json ) handler → v {
    ( __mcp_server_check_open r `prompt` name ( __mcp_find_prompt_index r name ) )
    : McpPrompt p @ McpPrompt {
        ( string_from name )
        ( string_from description )
        args_schema
        handler
    }
    ( vec_push [McpPrompt] . r __prompts p )
}

@ mcp_server_add_resource McpServer r s uri s name s mime_type s description ( @ Json ) handler → v {
    ( __mcp_server_check_open r `resource` uri ( __mcp_find_resource_index r uri ) )
    : McpResource res @ McpResource {
        ( string_from uri )
        ( string_from name )
        ( string_from mime_type )
        ( string_from description )
        handler
    }
    ( vec_push [McpResource] . r __resources res )
}

// Register a resource TEMPLATE. `uri_template` must end in a single
// `{var}` — the part of a requested URI that follows the literal
// prefix is handed to the handler as the request's `uri` plus a
// `variable` field holding it. CONSUMES the four strings.
@ mcp_server_add_resource_template McpServer r s uri_template s name s mime_type s description ( @ Json Json ) handler → v {
    ( __mcp_server_check_open r `resource template` uri_template
    ( __mcp_find_template_index r uri_template ) )
    : i n ( nurl_str_len uri_template )
    : i open ( nurl_str_find uri_template `{` )
    ? | < open 0 != ( nurl_str_get uri_template - n 1 ) 125 {
        ( __mcp_server_reject `resource template` uri_template
        `a URI template must end in a single '{var}' — only a trailing variable can be matched by prefix, and a template that never matches is worse than none` )
    } {}
    : McpResourceTemplate t @ McpResourceTemplate {
        ( string_from uri_template )
        ( string_from ( nurl_str_slice uri_template 0 open ) )
        ( string_from name )
        ( string_from mime_type )
        ( string_from description )
        handler
    }
    ( vec_push [McpResourceTemplate] . r __templates t )
}

// Register a completion provider. `ref_type` is `ref/prompt` or
// `ref/resource`; `ref_id` is the prompt name or resource URI the
// completion is attached to. The handler receives the `argument`
// object and returns a Json array of candidate string values.
// CONSUMES `ref_type`, `ref_id`. Handler is borrowed.
@ mcp_server_add_completion McpServer r s ref_type s ref_id ( @ Json Json ) handler → v {
    ( __mcp_server_check_open r `completion` ref_id
    ( __mcp_find_completion_index r ref_type ref_id ) )
    : McpCompletion c @ McpCompletion {
        ( string_from ref_type )
        ( string_from ref_id )
        handler
    }
    ( vec_push [McpCompletion] . r __completions c )
}

// ── Lookup helpers ────────────────────────────────────────────────────

@ __mcp_find_tool_index McpServer r s name → i {
    : i n ( vec_len [McpTool] . r __tools )
    : *McpTool tp ( vec_data [McpTool] . r __tools )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpTool t . tp k
        ? != 0 ( nurl_str_eq ( string_data . t name ) name ) { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __mcp_find_prompt_index McpServer r s name → i {
    : i n ( vec_len [McpPrompt] . r __prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r __prompts )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpPrompt p . pp k
        ? != 0 ( nurl_str_eq ( string_data . p name ) name ) { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __mcp_find_resource_index McpServer r s uri → i {
    : i n ( vec_len [McpResource] . r __resources )
    : *McpResource rp ( vec_data [McpResource] . r __resources )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpResource res . rp k
        ? != 0 ( nurl_str_eq ( string_data . res uri ) uri ) { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __mcp_find_template_index McpServer r s uri_template → i {
    : i n ( vec_len [McpResourceTemplate] . r __templates )
    : *McpResourceTemplate tp ( vec_data [McpResourceTemplate] . r __templates )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpResourceTemplate t . tp k
        ? != 0 ( nurl_str_eq ( string_data . t uri_template ) uri_template ) { = found k } {}
        = k + k 1
    }
    ^ found
}

// The template whose literal prefix `uri` starts with, or -1. Longest
// prefix wins, so `nurl://stdlib/{path}` beats a hypothetical
// `nurl://{rest}` for a stdlib URI rather than whichever registered
// first.
@ __mcp_match_template McpServer r s uri → i {
    : i n ( vec_len [McpResourceTemplate] . r __templates )
    : *McpResourceTemplate tp ( vec_data [McpResourceTemplate] . r __templates )
    : ~ i k 0
    : ~ i best -1
    : ~ i best_len -1
    ~ < k n {
        : McpResourceTemplate t . tp k
        : s pre ( string_data . t prefix )
        : i plen ( nurl_str_len pre )
        ? & != 0 ( nurl_str_starts uri pre ) > plen best_len {
            = best k
            = best_len plen
        } {}
        = k + k 1
    }
    ^ best
}

@ __mcp_find_completion_index McpServer r s ref_type s ref_id → i {
    : i n ( vec_len [McpCompletion] . r __completions )
    : *McpCompletion cp ( vec_data [McpCompletion] . r __completions )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpCompletion c . cp k
        ? & != 0 ( nurl_str_eq ( string_data . c ref_type ) ref_type )
        != 0 ( nurl_str_eq ( string_data . c ref_id ) ref_id )
        { = found k } {}
        = k + k 1
    }
    ^ found
}

// ── Per-method dispatchers ────────────────────────────────────────────

// Capability object: one entry per category that has any registered
// entries. Empty object = "supported with no extra options".
@ __mcp_server_caps McpServer r → Json {
    : Json caps ( json_obj_new )
    ? > ( vec_len [McpTool] . r __tools ) 0
    { ( json_obj_set caps `tools` ( json_obj_new ) ) } {}
    ? > ( vec_len [McpPrompt] . r __prompts ) 0
    { ( json_obj_set caps `prompts` ( json_obj_new ) ) } {}
    ? | > ( vec_len [McpResource] . r __resources ) 0
    > ( vec_len [McpResourceTemplate] . r __templates ) 0
    { ( json_obj_set caps `resources` ( json_obj_new ) ) } {}
    ? > ( vec_len [McpCompletion] . r __completions ) 0
    { ( json_obj_set caps `completions` ( json_obj_new ) ) } {}
    // Only declare the tasks extension when a store is actually
    // attached — a client that sees it declared will send tasks/get.
    ? ( mcp_server_has_task_store r ) { ( mcp_caps_declare_tasks caps ) } {}
    ^ caps
}

// initialize (legacy handshake): returns server capabilities + info.
// Version negotiation per the handshake-era spec: echo the client's
// requested `protocolVersion` when we support it, else answer with
// the newest handshake-era revision we do support (a legacy client
// would disconnect on a non-handshake revision like 2026-07-28).
@ __mcp_dispatch_initialize McpServer r ? Json params → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit ( string_data . r __name ) ) )
    ( json_obj_set info `version` ( json_str_lit ( string_data . r __version ) ) )

    : Json caps ( __mcp_server_caps r )
    : s ver ( mcp_initialize_version_for params )
    : Json out ( json_obj_new )
    ( json_obj_set out `protocolVersion` ( json_str_lit ver ) )
    ( json_obj_set out `capabilities` caps )
    ( json_obj_set out `serverInfo` info )
    ? > ( string_len . r __instructions ) 0 {
        ( json_obj_set out `instructions`
        ( json_str_lit ( string_data . r __instructions ) ) )
    } {}
    ^ out
}

// server/discover (2026-07-28, MUST): supported versions + caps +
// identity. The registry has no instructions channel yet — empty.
@ __mcp_dispatch_discover McpServer r → Json {
    ^ ( mcp_discover_result
    ( string_data . r __name )
    ( string_data . r __version )
    ( __mcp_server_caps r )
    ( string_data . r __instructions ) )
}

// tools/list: build the array of {name, description, inputSchema} —
// only the tools visible to this dispatch's caller context.
@ __mcp_dispatch_tools_list McpServer r Json ctx → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpTool] . r __tools )
    : *McpTool tp ( vec_data [McpTool] . r __tools )
    : ~ i k 0
    ~ < k n {
        : McpTool t . tp k
        ? ! ( __mcp_tool_visible t ctx ) {
            = k + k 1
            continue
        } {}
        : Json e ( json_obj_new )
        ( json_obj_set e `name` ( json_str_lit ( string_data . t name ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . t description ) ) )
        ( json_obj_set e `inputSchema` ( json_clone . t input_schema ) )
        ? ( json_is_obj . t annotations ) {
            ( json_obj_set e `annotations` ( json_clone . t annotations ) )
        } {}
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `tools` arr )
    ( __mcp_mark_list r out )
    ^ out
}

// tools/call: lookup by name, invoke the handler with the `arguments`
// sub-object. Returns the handler's tool-result envelope verbatim.
// Errors (unknown tool) returned as the spec-defined tool error
// envelope ({content: [...], isError: true}).
@ __mcp_dispatch_tools_call McpServer r ? Json params McpCall call → Json {
    : ~ s tool_name ``
    : ~ Json args ( json_null )
    ?? params {
        T p → {
            : ?Json nm ( json_obj_get p `name` )
            ?? nm {
                T jn → { = tool_name ( json_as_str jn ) }
                F _ → {}
            }
            : ?Json ag ( json_obj_get p `arguments` )
            ?? ag {
                T jag → { ( json_free args ) = args ( json_clone jag ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ? == 0 ( nurl_str_len tool_name ) {
        ( json_free args )
        ^ ( mcp_tool_result_error `missing tool name` )
    } {}
    : ~ i idx ( __mcp_find_tool_index r tool_name )
    // A gated tool the caller may not see is, to that caller, not
    // registered — same envelope, no hint that the name exists.
    ? >= idx 0 {
        : *McpTool tp0 ( vec_data [McpTool] . r __tools )
        ? ! ( __mcp_tool_visible . tp0 idx . call __ctx ) { = idx -1 } {}
    } {}
    ? < idx 0 {
        ( json_free args )
        : String msg ( string_from `unknown tool: ` )
        ( string_push_str msg tool_name )
        : Json out ( mcp_tool_result_error ( string_data msg ) )
        ( string_free msg )
        ^ out
    } {}
    : *McpTool tp ( vec_data [McpTool] . r __tools )
    : McpTool t . tp idx
    : ( @ Json Json ) h . t handler
    : ( @ Json Json McpCall ) hc . t ctx_handler
    : b use_ctx . t has_ctx
    // Run the user handler under `recover` so a panic inside it doesn't
    // unwind the dispatch — which over stdio (mcp_server_serve_stdio has no outer
    // recover) would kill the whole server process. The handler's result is
    // carried OUT of the recover closure through a shared-ctl Vec sink: a
    // closure captures locals by value, so a direct `= result ...` inside it
    // would NOT propagate, but `vec_push` mutates the Vec's shared control
    // block in place and does. An empty sink after recover means the handler
    // panicked, so the stock tool-error envelope stands.
    : ( Vec Json ) sink ( vec_with_cap [Json] 1 )
    : !v PanicInfo pr ( recover \ → v {
        ? use_ctx { ( vec_push [Json] sink ( hc args call ) ) }
        { ( vec_push [Json] sink ( h args ) ) }
    } )
    : ~ Json result ( mcp_tool_result_error `tool handler panicked` )
    ?? pr {
        T _ → {}
        F p → {
            ( mcp_log ( nurl_str_cat `tool handler panicked: ` ( string_data . p msg ) ) )
            ( panic_info_free p )
        }
    }
    ? > ( vec_len [Json] sink ) 0 {
        : ?Json e0 ( vec_get [Json] sink 0 )
        ?? e0 { T jv → { ( json_free result ) = result jv } F → {} }
    } {}
    ( vec_free [Json] sink )
    ( json_free args )
    ^ result
}

// prompts/list carries `arguments` as an ARRAY of
// `{name, description, required}` (MCP spec §prompts), not as a JSON
// Schema — the one place in the protocol where an argument list is not
// a schema. A prompt registered with a `mcp_schema_obj` (the natural
// thing to reach for, and what every caller did) therefore advertised
// a shape no client can read.
//
// Both spellings are accepted: an array passes through, and a schema
// object is converted, since a schema holds exactly the three fields
// the array wants. Returns a fresh Json the caller owns.
@ __mcp_prompt_args_array Json declared → Json {
    ? ( json_is_arr declared ) { ^ ( json_clone declared ) } {}
    : Json out ( json_arr_new )
    ? ! ( json_is_obj declared ) { ^ out } {}
    ?? ( json_obj_get declared `properties` ) {
        T props → {
            : ( Vec String ) keys ( json_obj_keys props )
            : i n ( vec_len [String] keys )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] keys k ) {
                    T key → {
                        : s ks ( string_data key )
                        : Json e ( json_obj_new )
                        ( json_obj_set e `name` ( json_str_lit ks ) )
                        ?? ( json_obj_get props ks ) {
                            T pv → {
                                ?? ( json_obj_get pv `description` ) {
                                    T d → { ( json_obj_set e `description` ( json_clone d ) ) }
                                    F _ → {}
                                }
                            }
                            F _ → {}
                        }
                        ( json_obj_set e `required`
                        ( json_bool ( __mcp_schema_requires declared ks ) ) )
                        ( json_arr_push out e )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ^ out
}

@ __mcp_schema_requires Json schema s name → b {
    ?? ( json_obj_get schema `required` ) {
        T req → {
            : i n ( json_arr_len req )
            : ~ i k 0
            ~ < k n {
                ?? ( json_arr_get req k ) {
                    T v → { ? != 0 ( nurl_str_eq ( json_as_str v ) name ) { ^ T } {} }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
    ^ F
}

// prompts/list: build the array of {name, description, arguments}.
@ __mcp_dispatch_prompts_list McpServer r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpPrompt] . r __prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r __prompts )
    : ~ i k 0
    ~ < k n {
        : McpPrompt p . pp k
        : Json e ( json_obj_new )
        ( json_obj_set e `name` ( json_str_lit ( string_data . p name ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . p description ) ) )
        ( json_obj_set e `arguments` ( __mcp_prompt_args_array . p arguments_schema ) )
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `prompts` arr )
    ( __mcp_mark_list r out )
    ^ out
}

// prompts/get: invoke the prompt handler with `arguments`. Handler
// returns the spec-shaped {description, messages} object (or just
// messages; we wrap if missing).
@ __mcp_dispatch_prompts_get McpServer r ? Json params → !Json McpRpcErr {
    : ~ s pname ``
    : ~ Json args ( json_null )
    ?? params {
        T p → {
            : ?Json nm ( json_obj_get p `name` )
            ?? nm {
                T jn → { = pname ( json_as_str jn ) }
                F _ → {}
            }
            : ?Json ag ( json_obj_get p `arguments` )
            ?? ag {
                T jag → { ( json_free args ) = args ( json_clone jag ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ? == 0 ( nurl_str_len pname ) {
        ( json_free args )
        ^ @ !Json McpRpcErr { F ( mcp_rpc_err mcp_err_invalid_params
            `prompts/get requires a "name" parameter` ) }
    } {}
    : i idx ( __mcp_find_prompt_index r pname )
    ? < idx 0 {
        ( json_free args )
        : String m ( string_from `unknown prompt: ` )
        ( string_push_str m pname )
        : McpRpcErr e ( mcp_rpc_err mcp_err_invalid_params ( string_data m ) )
        ( string_free m )
        ^ @ !Json McpRpcErr { F e }
    } {}
    : *McpPrompt pp ( vec_data [McpPrompt] . r __prompts )
    : McpPrompt p . pp idx
    : ( @ Json Json ) h . p handler
    // Panic-guard via a shared-ctl Vec sink (see __mcp_dispatch_tools_call
    // for why a direct closure assignment can't carry the value out). An
    // empty sink after recover means the handler panicked → -32603.
    : ( Vec Json ) sink ( vec_with_cap [Json] 1 )
    : !v PanicInfo pr ( recover \ → v { ( vec_push [Json] sink ( h args ) ) } )
    ?? pr {
        T _ → {}
        F pi → {
            ( mcp_log ( nurl_str_cat `prompt handler panicked: ` ( string_data . pi msg ) ) )
            ( panic_info_free pi )
        }
    }
    ( json_free args )
    ? <= ( vec_len [Json] sink ) 0 {
        ( vec_free [Json] sink )
        ^ @ !Json McpRpcErr { F ( mcp_rpc_err mcp_err_internal_error
            `prompt handler panicked` ) }
    } {}
    : ?Json e0 ( vec_get [Json] sink 0 )
    : Json result ?? e0 { T jv → jv F → ( json_obj_new ) }
    ( vec_free [Json] sink )
    ^ @ !Json McpRpcErr { T result }
}

// resources/list: build the array of resource descriptors.
@ __mcp_dispatch_resources_list McpServer r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpResource] . r __resources )
    : *McpResource rp ( vec_data [McpResource] . r __resources )
    : ~ i k 0
    ~ < k n {
        : McpResource res . rp k
        : Json e ( json_obj_new )
        ( json_obj_set e `uri` ( json_str_lit ( string_data . res uri ) ) )
        ( json_obj_set e `name` ( json_str_lit ( string_data . res name ) ) )
        ( json_obj_set e `mimeType` ( json_str_lit ( string_data . res mime_type ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . res description ) ) )
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `resources` arr )
    ( __mcp_mark_list r out )
    ^ out
}

// resources/templates/list: the templated families, kept out of
// `resources/list` because a client would try to read the literal
// `{path}`. Without this method a templated URI is unreachable through
// the protocol however well it is served.
@ __mcp_dispatch_templates_list McpServer r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpResourceTemplate] . r __templates )
    : *McpResourceTemplate tp ( vec_data [McpResourceTemplate] . r __templates )
    : ~ i k 0
    ~ < k n {
        : McpResourceTemplate t . tp k
        : Json e ( json_obj_new )
        ( json_obj_set e `uriTemplate` ( json_str_lit ( string_data . t uri_template ) ) )
        ( json_obj_set e `name` ( json_str_lit ( string_data . t name ) ) )
        ( json_obj_set e `mimeType` ( json_str_lit ( string_data . t mime_type ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . t description ) ) )
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `resourceTemplates` arr )
    ( __mcp_mark_list r out )
    ^ out
}

// Read through a template. The handler gets `{uri, variable}` — the
// URI as asked for, and the part that filled the trailing `{var}` —
// and returns the same inner content object an exact resource's
// handler does. Panic-guarded like every other handler.
@ __mcp_read_template McpServer r i idx s uri → !Json McpRpcErr {
    : *McpResourceTemplate tp ( vec_data [McpResourceTemplate] . r __templates )
    : McpResourceTemplate t . tp idx
    : ( @ Json Json ) h . t handler
    : i plen ( nurl_str_len ( string_data . t prefix ) )
    : Json arg ( json_obj_new )
    ( json_obj_set arg `uri` ( json_str_lit uri ) )
    ( json_obj_set arg `variable`
    ( json_str_lit ( nurl_str_slice uri plen - ( nurl_str_len uri ) plen ) ) )
    : ( Vec Json ) sink ( vec_with_cap [Json] 1 )
    : !v PanicInfo pr ( recover \ → v { ( vec_push [Json] sink ( h arg ) ) } )
    ?? pr {
        T _ → {}
        F pi → {
            ( mcp_log ( nurl_str_cat `resource template handler panicked: `
            ( string_data . pi msg ) ) )
            ( panic_info_free pi )
        }
    }
    ( json_free arg )
    ? <= ( vec_len [Json] sink ) 0 {
        ( vec_free [Json] sink )
        ^ @ !Json McpRpcErr { F ( mcp_rpc_err mcp_err_internal_error
            `resource template handler panicked` ) }
    } {}
    : ?Json c0 ( vec_get [Json] sink 0 )
    : Json content ?? c0 { T jv → jv F → ( json_null ) }
    ( vec_free [Json] sink )
    // A handler that cannot serve this particular URI says so by
    // returning a null / non-object, which is a not-found rather than
    // an empty success — the shape nurlapi shipped, where a templated
    // read answered `{"contents":[]}` and looked like it had worked.
    ? ! ( json_is_obj content ) {
        ( json_free content )
        : String m ( string_from `unknown resource: ` )
        ( string_push_str m uri )
        : McpRpcErr e ( mcp_rpc_err mcp_err_resource_not_found ( string_data m ) )
        ( string_free m )
        ^ @ !Json McpRpcErr { F e }
    } {}
    ?? ( json_obj_get content `uri` ) {
        T _ → {}
        F _ → { ( json_obj_set content `uri` ( json_str_lit uri ) ) }
    }
    ?? ( json_obj_get content `mimeType` ) {
        T _ → {}
        F _ → {
            ( json_obj_set content `mimeType`
            ( json_str_lit ( string_data . t mime_type ) ) )
        }
    }
    : Json arr ( json_arr_new )
    ( json_arr_push arr content )
    : Json out ( json_obj_new )
    ( json_obj_set out `contents` arr )
    ( __mcp_mark_read r out )
    ^ @ !Json McpRpcErr { T out }
}

// resources/read: lookup by uri, invoke handler. Spec response shape
// is {contents: [{uri, mimeType, text|blob}]}. Handler returns the
// inner content object; we wrap it.
@ __mcp_dispatch_resources_read McpServer r ? Json params → !Json McpRpcErr {
    : ~ s uri ``
    ?? params {
        T p → {
            : ?Json u ( json_obj_get p `uri` )
            ?? u {
                T ju → { = uri ( json_as_str ju ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ? == 0 ( nurl_str_len uri ) {
        ^ @ !Json McpRpcErr { F ( mcp_rpc_err mcp_err_invalid_params
            `resources/read requires a "uri" parameter` ) }
    } {}
    : i idx ( __mcp_find_resource_index r uri )
    ? < idx 0 {
        // No exact resource — try the templates before giving up.
        : i tidx ( __mcp_match_template r uri )
        ? >= tidx 0 { ^ ( __mcp_read_template r tidx uri ) } {}
        : String m ( string_from `unknown resource: ` )
        ( string_push_str m uri )
        : McpRpcErr e ( mcp_rpc_err mcp_err_resource_not_found ( string_data m ) )
        ( string_free m )
        ^ @ !Json McpRpcErr { F e }
    } {}
    : *McpResource rp ( vec_data [McpResource] . r __resources )
    : McpResource res . rp idx
    : ( @ Json ) h . res handler
    // Panic-guard via a shared-ctl Vec sink (see __mcp_dispatch_tools_call).
    // An empty sink after recover means the handler panicked → -32603;
    // otherwise post-process the content and wrap it in the spec-shaped
    // {contents:[...]} envelope.
    : ( Vec Json ) sink ( vec_with_cap [Json] 1 )
    : !v PanicInfo pr ( recover \ → v { ( vec_push [Json] sink ( h ) ) } )
    ?? pr {
        T _ → {}
        F pi → {
            ( mcp_log ( nurl_str_cat `resource handler panicked: ` ( string_data . pi msg ) ) )
            ( panic_info_free pi )
        }
    }
    ? <= ( vec_len [Json] sink ) 0 {
        ( vec_free [Json] sink )
        ^ @ !Json McpRpcErr { F ( mcp_rpc_err mcp_err_internal_error
            `resource handler panicked` ) }
    } {}
    : ?Json c0 ( vec_get [Json] sink 0 )
    : Json content ?? c0 { T jv → jv F → ( json_null ) }
    ( vec_free [Json] sink )
    // Ensure the content has the expected fields. If handler didn't
    // include `uri` / `mimeType`, splice them in from the registry.
    : ?Json have_uri ( json_obj_get content `uri` )
    ?? have_uri {
        T _ → {}
        F _ → { ( json_obj_set content `uri` ( json_str_lit uri ) ) }
    }
    : ?Json have_mime ( json_obj_get content `mimeType` )
    ?? have_mime {
        T _ → {}
        F _ → { ( json_obj_set content `mimeType` ( json_str_lit ( string_data . res mime_type ) ) ) }
    }
    : Json arr ( json_arr_new )
    ( json_arr_push arr content )
    : Json out ( json_obj_new )
    ( json_obj_set out `contents` arr )
    // resources/read is also a CacheableResult in 2026-07-28.
    ( __mcp_mark_read r out )
    ^ @ !Json McpRpcErr { T out }
}

// Wrap a values array in the spec-shaped completion result. CONSUMES
// `values`. `total` is the array length; `hasMore` is always false (we
// never truncate — a provider that wants paging caps its own array, and
// the spec's 100-value soft limit is the provider's responsibility).
@ __mcp_completion_envelope Json values → Json {
    : i total ( json_arr_len values )
    : Json comp ( json_obj_new )
    ( json_obj_set comp `values` values )
    ( json_obj_set comp `total` ( json_int total ) )
    ( json_obj_set comp `hasMore` ( json_bool F ) )
    : Json out ( json_obj_new )
    ( json_obj_set out `completion` comp )
    ^ out
}

// completion/complete (spec §6.7): resolve a completion provider by its
// ref — `ref/prompt` + name, or `ref/resource` + uri — and invoke it
// with the request's `argument` object. Returns
// {completion: {values, total, hasMore}}. An unknown ref yields an empty
// completion list rather than an error (per spec: completion is a hint).
@ __mcp_dispatch_completion McpServer r ? Json params → Json {
    : ~ s ref_type ``
    : ~ s ref_id ``
    : ~ Json arg ( json_null )
    ?? params {
        T p → {
            : ?Json rf ( json_obj_get p `ref` )
            ?? rf {
                T jr → {
                    : ?Json rt ( json_obj_get jr `type` )
                    ?? rt { T x → { = ref_type ( json_as_str x ) } F _ → {} }
                    : ?Json rn ( json_obj_get jr `name` )
                    ?? rn { T x → { = ref_id ( json_as_str x ) } F _ → {} }
                    ? == 0 ( nurl_str_len ref_id ) {
                        : ?Json ru ( json_obj_get jr `uri` )
                        ?? ru { T x → { = ref_id ( json_as_str x ) } F _ → {} }
                    } {}
                }
                F _ → {}
            }
            : ?Json ag ( json_obj_get p `argument` )
            ?? ag { T x → { ( json_free arg ) = arg ( json_clone x ) } F _ → {} }
        }
        F _ → {}
    }
    : i idx ( __mcp_find_completion_index r ref_type ref_id )
    ? < idx 0 {
        ( json_free arg )
        ^ ( __mcp_completion_envelope ( json_arr_new ) )
    } {}
    : *McpCompletion cp ( vec_data [McpCompletion] . r __completions )
    : McpCompletion c . cp idx
    : ( @ Json Json ) h . c handler
    // Panic-guard via a shared-ctl Vec sink (see __mcp_dispatch_tools_call).
    // `values` defaults to an empty array — completion is a hint, so a broken
    // provider must not take the connection (or stdio process) down; an empty
    // sink after recover means the handler panicked.
    : ( Vec Json ) sink ( vec_with_cap [Json] 1 )
    : !v PanicInfo pr ( recover \ → v { ( vec_push [Json] sink ( h arg ) ) } )
    : ~ Json values ( json_arr_new )
    ?? pr {
        T _ → {}
        F pi → {
            ( mcp_log ( nurl_str_cat `completion handler panicked: ` ( string_data . pi msg ) ) )
            ( panic_info_free pi )
        }
    }
    ? > ( vec_len [Json] sink ) 0 {
        : ?Json e0 ( vec_get [Json] sink 0 )
        ?? e0 { T jv → { ( json_free values ) = values jv } F → {} }
    } {}
    ( vec_free [Json] sink )
    ( json_free arg )
    // Defensive: a provider that returns a non-array gets an empty list.
    ? ( json_is_arr values ) {} { ( json_free values ) = values ( json_arr_new ) }
    ^ ( __mcp_completion_envelope values )
}

// ── Dispatcher ────────────────────────────────────────────────────────
//
// Single entry point, request in. On success it returns the raw
// `result` field's Json (the caller wraps it in the JSON-RPC envelope
// with the request `id`); on failure an McpRpcErr carrying the code the
// client should actually see.
//
// It takes the whole REQUEST rather than a method name and params
// because a per-request `_meta` is now part of the protocol — the
// declared protocol version, the declared extensions — and a handler
// that answers `tools/call` may need to know what the client declared.
// Passing method+params would have meant either losing that or growing
// a parameter later, and STABLE SURFACE rule 1 says a published
// function never grows one.
//
// Marks the server as serving. From here on `mcp_server_add_*` is a
// registration-time error rather than a tool no client will see — see
// `__ctl`.
@ mcp_server_dispatch McpServer r Json req → !Json McpRpcErr {
    ^ ( mcp_server_dispatch_as r req ( json_null ) )
}

// The same dispatch with a CALLER CONTEXT attached: a Json the HOST
// built from what it authenticated (principal, role, organisation —
// whatever its tools need), never from anything the client sent. It
// reaches every tool through `mcp_call_context`, and it is what the
// `visible` predicate of a gated tool (`mcp_server_add_tool_gated`)
// decides on, so `tools/list` and `tools/call` agree per caller. The
// context is BORROWED for the duration of the call: the host frees it
// after the reply, and nothing in the result refers to it.
//
// One server, built once, serves every caller: the per-request work is
// authenticating and building `ctx`, not registering tools.
@ mcp_server_dispatch_as McpServer r Json req Json ctx → !Json McpRpcErr {
    ( vec_set [i] . r __ctl MCP_CTL_SERVING 1 )
    : ~ s method ``
    ?? ( json_obj_get req `method` ) {
        T mv → { = method ( json_as_str mv ) }
        F _ → {}
    }
    : ?Json params ( json_obj_get req `params` )
    : McpCall call @ McpCall { req ctx }
    ? != 0 ( nurl_str_eq method `server/discover` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_discover r ) }
    } {}
    ? != 0 ( nurl_str_eq method `initialize` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_initialize r params ) }
    } {}
    ? != 0 ( nurl_str_eq method `tools/list` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_tools_list r ctx ) }
    } {}
    ? != 0 ( nurl_str_eq method `tools/call` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_tools_call r params call ) }
    } {}
    ? != 0 ( nurl_str_eq method `prompts/list` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_prompts_list r ) }
    } {}
    ? != 0 ( nurl_str_eq method `prompts/get` ) {
        ^ ( __mcp_dispatch_prompts_get r params )
    } {}
    ? != 0 ( nurl_str_eq method `resources/templates/list` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_templates_list r ) }
    } {}
    ? != 0 ( nurl_str_eq method `resources/list` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_resources_list r ) }
    } {}
    ? != 0 ( nurl_str_eq method `resources/read` ) {
        ^ ( __mcp_dispatch_resources_read r params )
    } {}
    ? != 0 ( nurl_str_eq method `completion/complete` ) {
        ^ @ !Json McpRpcErr { T ( __mcp_dispatch_completion r params ) }
    } {}
    ? != 0 ( nurl_str_eq method `ping` ) {
        ^ @ !Json McpRpcErr { T ( json_obj_new ) }
    } {}
    // tasks/get, tasks/update, tasks/cancel — only when a store is
    // attached. Without one these fall through to method-not-found,
    // which is the honest answer: the capability was never declared.
    ? & ( mcp_tasks_is_method method ) ( mcp_server_has_task_store r ) {
        ^ ( __mcp_dispatch_tasks r req method )
    } {}
    // Any `notifications/*` is ACCEPTED. The lifecycle ones —
    // `notifications/initialized` above all, which every client sends
    // straight after initialize — are not optional, and the spec says
    // a receiver must ignore a notification it does not recognise
    // rather than answer it. Treating them as unknown methods produced
    // a "notification failed: unknown method" log line per session for
    // a client doing exactly what it must.
    ? != 0 ( nurl_str_starts method `notifications/` ) {
        ^ @ !Json McpRpcErr { T ( json_obj_new ) }
    } {}
    : String m ( string_from `unknown method: ` )
    ( string_push_str m method )
    : McpRpcErr e ( mcp_rpc_err mcp_err_method_not_found ( string_data m ) )
    ( string_free m )
    ^ @ !Json McpRpcErr { F e }
}

// tasks/*: run the server's pre-dispatch hook (its task state may only
// be current after it polls something), then hand the request to
// ext/mcp_tasks.nu, which owns the capability gate and the taskId
// lookup. That layer answers with a complete JSON-RPC ENVELOPE, so its
// `result` is unwrapped here and its `error` becomes an McpRpcErr —
// the envelope is built once, by the caller, for every method alike.
@ __mcp_dispatch_tasks McpServer r Json req s method → !Json McpRpcErr {
    : *McpTaskHook hp ( vec_data [McpTaskHook] . r __task_hook )
    ? > ( vec_len [McpTaskHook] . r __task_hook ) 0 {
        : McpTaskHook hk . hp 0
        : ( @ v ) f . hk f
        ( f )
    } {}
    : *McpTaskStore sp ( vec_data [McpTaskStore] . r __tasks )
    : McpTaskStore store . sp 0
    // mcp_tasks_dispatch wants the id to echo; it is re-wrapped by the
    // envelope layer anyway, so a null placeholder is enough here.
    ?? ( mcp_tasks_dispatch store req ( json_null ) method ) {
        T env → {
            ?? ( json_obj_get env `result` ) {
                T res → {
                    : Json out ( json_clone res )
                    ( json_free env )
                    ^ @ !Json McpRpcErr { T out }
                }
                F _ → {}
            }
            : ~ i code mcp_err_internal_error
            : ~ s msg `tasks dispatch failed`
            : ~ Json data ( json_null )
            ?? ( json_obj_get env `error` ) {
                T eo → {
                    ?? ( json_obj_get eo `code` ) {
                        T cv → { = code ( json_as_int cv ) }
                        F _ → {}
                    }
                    ?? ( json_obj_get eo `message` ) {
                        T mv → { = msg ( json_as_str mv ) }
                        F _ → {}
                    }
                    // `data` carries what the client should DO about it —
                    // `requiredCapabilities` on the missing-extension
                    // gate. Dropping it leaves a correct code with no
                    // way to act on it.
                    ?? ( json_obj_get eo `data` ) {
                        T dv → { ( json_free data ) = data ( json_clone dv ) }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            : McpRpcErr e ( mcp_rpc_err_data code msg data )
            ( json_free env )
            ^ @ !Json McpRpcErr { F e }
        }
        F _ → {}
    }
    : String m ( string_from `unhandled tasks method: ` )
    ( string_push_str m method )
    : McpRpcErr e2 ( mcp_rpc_err mcp_err_method_not_found ( string_data m ) )
    ( string_free m )
    ^ @ !Json McpRpcErr { F e2 }
}

// ── Stdio transport ──────────────────────────────────────────────────
//
// Server-side stdio MCP — pairs with the client-side stdio_client
// shipped in stdlib/ext/mcp_stdio.nu. NURL can now be a usable MCP
// server over stdio, ready to be spawned by any MCP-aware host
// (Claude Desktop, MCP Inspector, custom agent runners).
//
// Loop: read a JSON-RPC frame off stdin (line-delimited per the
// stdio transport spec), dispatch via the registry, write the
// response to stdout. Requests with `id` get responses; pure
// notifications (no `id`) don't. EOF on stdin → clean exit.
//
// Errors are surfaced via JSON-RPC error envelopes (code -32601
// "method not found" for unknown methods, -32603 "internal error"
// for handler failures). Transport-level failures (stdin closed,
// JSON parse error) are silent — the spec says the host process
// drives the lifecycle.

: | McpServerErr {
    McpServerReadIo
    McpServerWriteIo
    McpServerOther
}

@ mcp_server_err_name McpServerErr e → s {
    ^ ?? e {
        McpServerReadIo → `McpServerReadIo`
        McpServerWriteIo → `McpServerWriteIo`
        McpServerOther → `McpServerOther`
    }
}

@ __mcp_extract_id_or_null Json req → Json {
    : ?Json idf ( json_obj_get req `id` )
    ?? idf {
        T jid → { ^ ( json_clone jid ) }
        F _ → { ^ ( json_null ) }
    }
}

@ __mcp_has_id Json req → b {
    : ?Json idf ( json_obj_get req `id` )
    ?? idf {
        T _ → { ^ T }
        F _ → { ^ F }
    }
}

// Single iteration of the stdio main loop. Returns T when EOF reached
// (caller terminates the loop), F otherwise.
//
// Routes through `mcp_server_envelope` so the stdio transport gets
// the same dual-era behavior as HTTP (version gate, `server/discover`,
// modern `_meta` decorations). This also fixed a latent double-free:
// the old inline path called `json_free resp` after `mcp_send_message`
// — which already CONSUMES its message.
@ __mcp_server_serve_stdio_once McpServer r → b {
    : ?Json req ( mcp_read_request )
    ?? req {
        T jr → {
            : ?Json resp_o ( mcp_server_envelope r jr )
            ?? resp_o {
                T resp → { ( mcp_send_message resp ) }
                // Notification — no response (per JSON-RPC 2.0 §4.1).
                F e → { ( json_free e ) }
            }
            ( json_free jr )
            ^ F
        }
        F _ → { ^ T }
    }
}

@ mcp_server_serve_stdio McpServer r → !v McpServerErr {
    : ~ b done F
    ~ ! done {
        = done ( __mcp_server_serve_stdio_once r )
    }
    ^ @ !v McpServerErr { T 0 }
}

// ── HTTP transport adapter ───────────────────────────────────────────
//
// `mcp_server_envelope` is the transport-agnostic dispatch entry
// point. Given a parsed JSON-RPC request Json, runs the registry
// dispatch and produces either a response Json (Some) or None (the
// request was a pure notification with no id).
//
// `mcp_server_http_dispatch` wraps this for the existing
// `mcp_http_handler` (stdlib/ext/mcp_http.nu) which expects a
// `( @ ? Json Json )` dispatch closure shape.
//
// Caller wires it together like:
//   : McpServer r ( mcp_server_new `my-server` `1.0.0` )
//   ( mcp_server_add_tool r `echo` `Echo back input` schema echo_handler )
//   : ( @ ? Json Json ) disp ( mcp_server_http_dispatch r )
//   : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler disp )
//   : HttpServer s ( server_new listener h )
//   ( server_run s )

@ mcp_server_envelope McpServer r Json req → ?Json {
    ^ ( mcp_server_envelope_as r req ( json_null ) )
}

// `mcp_server_envelope` with a caller context — see
// `mcp_server_dispatch_as` for what the context is and who owns it.
// An HTTP host that authenticates per request builds the dispatch
// closure per request around this:
//
//   : Json ctx ( my_principal_json req )        // from the credential
//   : ( @ ?Json Json ) d \ Json rq → ?Json { ^ ( mcp_server_envelope_as srv rq ctx ) }
//   : HttpResponse out ( ( mcp_http_handler d ) req )
//   ( nurl_free # s # *u d 1 )                  // the closure's env
//   ( json_free ctx )
@ mcp_server_envelope_as McpServer r Json req Json ctx → ?Json {
    : b had_id ( __mcp_has_id req )
    : Json id ( __mcp_extract_id_or_null req )

    // Modern-era version gate (2026-07-28): a request that DECLARES a
    // protocol version we don't support MUST get the spec-shaped
    // UnsupportedProtocolVersionError — the client picks a mutual
    // revision from `data.supported` and retries. A request with no
    // `_meta` version is legacy-era and served as before.
    : s req_ver ( mcp_request_protocol_version req )
    : b is_modern > ( nurl_str_len req_ver ) 0
    ? & is_modern ! ( mcp_version_supported req_ver ) {
        ? had_id {
            : Json resp ( mcp_unsupported_version_response id req_ver )
            ( json_free id )
            ^ @ ?Json { T resp }
        } {
            ( json_free id )
            ^ @ ?Json { F }
        }
    } {}

    ?? ( mcp_server_dispatch_as r req ctx ) {
        T result → {
            // Modern-era servers SHOULD identify themselves in each
            // result's `_meta`.
            ? & is_modern ( json_is_obj result ) {
                ( mcp_result_set_server_info result
                ( string_data . r __name )
                ( string_data . r __version ) )
            } {}
            ? had_id {
                // The envelope clones the id into the response; this copy
                // was for the error paths and has done its work.
                : Json resp ( mcp_response_result id result )
                ( json_free id )
                ^ @ ?Json { T resp }
            } {
                // Notification — caller (mcp_http_handler) maps this
                // to a 202 Accepted with no body.
                ( json_free result )
                ( json_free id )
                ^ @ ?Json { F }
            }
        }
        F e → {
            ? had_id {
                : ~ Json resp ( json_null )
                ? ( json_is_null ( mcp_rpc_err_get_data e ) ) {
                    ( json_free resp )
                    = resp ( mcp_response_error id ( mcp_rpc_err_code e )
                    ( mcp_rpc_err_message e ) )
                } {
                    ( json_free resp )
                    = resp ( mcp_response_error_data id ( mcp_rpc_err_code e )
                    ( mcp_rpc_err_message e ) ( json_clone ( mcp_rpc_err_get_data e ) ) )
                }
                ( mcp_rpc_err_free e )
                ( json_free id )
                ^ @ ?Json { T resp }
            } {
                // A notification cannot be answered, not even to say it
                // failed (JSON-RPC 2.0 §4.1) — log and drop.
                ( mcp_log ( nurl_str_cat `notification failed: `
                ( mcp_rpc_err_message e ) ) )
                ( mcp_rpc_err_free e )
                ( json_free id )
                ^ @ ?Json { F }
            }
        }
    }
}

@ mcp_server_http_dispatch McpServer r → ( @ ?Json Json ) {
    ^ \ Json req → ?Json { ^ ( mcp_server_envelope r req ) }
}

// Serve this server over Streamable HTTP on host:port and block. An
// empty `token` serves unauthenticated; a non-empty one requires
// `Authorization: Bearer <token>` on every request (constant-time
// compare — see `mcp_server_with_bearer_auth`).
//
// This is the whole HTTP main() for a server that needs nothing
// special. A server that does — its own routing, TLS, a listener it
// runs on another thread — builds the same pieces itself from
// `mcp_server_http_dispatch` and `mcp_http_handler`, which is what
// this function does in five lines.
@ mcp_server_serve_http McpServer r s host i port s token → !v NetErr {
    : ( @ ?Json Json ) disp ( mcp_server_http_dispatch r )
    : !TcpListener NetErr lr ( tcp_listen host port )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) inner
            ( mcp_http_handler \ Json rq → ?Json { ^ ( disp rq ) } )
            : ( @ HttpResponse HttpRequest ) h ? > ( nurl_str_len token ) 0
            ( mcp_server_with_bearer_auth
            \ HttpRequest rq → HttpResponse { ^ ( inner rq ) } token )
            \ HttpRequest rq → HttpResponse { ^ ( inner rq ) }
            : HttpServer srv ( server_new listener h )
            : !v NetErr rr ( server_run srv )
            ( server_stop srv )
            ^ rr
        }
        F e → { ^ @ !v NetErr { F e } }
    }
}

// Bearer-auth middleware. Decorates an HTTP handler so requests
// without a matching `Authorization: Bearer <token>` header get a
// stock 401 Unauthorized + WWW-Authenticate challenge before the
// inner handler runs. Token comparison is byte-exact (no constant-
// time guard yet — for high-security deployments swap in a runtime
// helper that calls `CRYPTO_memcmp`).
@ mcp_server_with_bearer_auth ( @ HttpResponse HttpRequest ) inner s expected_token → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : ~ b ok F
        : ?String auth ( header_get . req headers `Authorization` )
        ?? auth {
            T av → {
                : s avs ( string_data av )
                : i avn ( nurl_str_len avs )
                // "Bearer X" — prefix length 7. Compare X to expected.
                ? & >= avn 8
                & == ( nurl_str_get avs 0 ) 66
                & == ( nurl_str_get avs 1 ) 101
                & == ( nurl_str_get avs 2 ) 97
                & == ( nurl_str_get avs 3 ) 114
                & == ( nurl_str_get avs 4 ) 101
                & == ( nurl_str_get avs 5 ) 114
                == ( nurl_str_get avs 6 ) 32
                {
                    : i tlen ( nurl_str_len expected_token )
                    ? == - avn 7 tlen {
                        // Constant-time compare (std/subtle.nu) so the
                        // loop's duration cannot leak how many leading
                        // bytes matched — a timing oracle that recovers
                        // the token byte-by-byte. Length is checked
                        // above; leaking length is standard
                        // (cf. compare_digest).
                        ? ( constant_time_eq_n # s + # i avs 7 expected_token tlen )
                        { = ok T } {}
                    } {}
                } {}
                ( string_free av )
            }
            F _ → {}
        }
        ? ok { ^ ( inner req ) } {
            : HttpResponse r ( response_text 401 `Unauthorized\n` )
            ( response_set_header r `WWW-Authenticate` `Bearer realm="mcp"` )
            ^ r
        }
    }
}
