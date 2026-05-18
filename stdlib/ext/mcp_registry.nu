// stdlib/ext/mcp_registry.nu — MCP server framework.
//
// High-level "register a tool/prompt/resource with a closure handler"
// API for building MCP servers. Sits on top of stdlib/ext/mcp.nu (the
// JSON-RPC envelope + result builders) and is consumed by
// stdlib/ext/mcp_stdio_server.nu (stdio transport) and
// stdlib/ext/mcp_http.nu (HTTP transport — wired via the
// existing mcp_http_handler taking the registry's dispatch as the
// routing core).
//
// The Channel[A] generic-propagation compiler fix (2026-05-17)
// unlocked closure-in-Vec storage, which is what makes a uniform
// `mcp_registry_add_*` API possible — handlers are stored on the
// registry struct as Vec[McpTool] / Vec[McpPrompt] / Vec[McpResource]
// and dispatched by name lookup at request time.
//
// Spec coverage (Model Context Protocol 2024-11-05):
//   * initialize / initialized
//   * tools/list, tools/call
//   * prompts/list, prompts/get
//   * resources/list, resources/read
//   * ping (heartbeat — empty result)
//
// Out of scope here (deferred):
//   * resources/subscribe + change notifications (needs SSE push)
//   * completion/complete (rarely-used spec feature)
//   * sampling/createMessage (server→client; bidirectional reverse RPC)
//   * roots/list (client-side feature)
//
// Memory model:
//   McpRegistry OWNS its String + Json fields + the Vec containers.
//   Handlers are borrowed closures — they MUST outlive the registry
//   (or be plain `@` function references that have static lifetime).
//   mcp_registry_dispatch returns an OWNED Json envelope; caller
//   frees via json_free.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

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

// ── Registry ──────────────────────────────────────────────────────────

: McpRegistry {
    String server_name
    String server_version
    ( Vec McpTool ) tools
    ( Vec McpPrompt ) prompts
    ( Vec McpResource ) resources
}

@ mcp_registry_new s name s version → McpRegistry {
    ^ @ McpRegistry {
        ( string_from name )
        ( string_from version )
        ( vec_new [McpTool] )
        ( vec_new [McpPrompt] )
        ( vec_new [McpResource] )
    }
}

@ mcp_registry_free McpRegistry r → v {
    ( string_free . r server_name )
    ( string_free . r server_version )
    // Tools
    : i tn ( vec_len [McpTool] . r tools )
    : *McpTool tp ( vec_data [McpTool] . r tools )
    : ~ i k 0
    ~ < k tn {
        : McpTool t . tp k
        ( string_free . t name )
        ( string_free . t description )
        ( json_free . t input_schema )
        = k + k 1
    }
    ( vec_free [McpTool] . r tools )
    // Prompts
    : i pn ( vec_len [McpPrompt] . r prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r prompts )
    = k 0
    ~ < k pn {
        : McpPrompt p . pp k
        ( string_free . p name )
        ( string_free . p description )
        ( json_free . p arguments_schema )
        = k + k 1
    }
    ( vec_free [McpPrompt] . r prompts )
    // Resources
    : i rn ( vec_len [McpResource] . r resources )
    : *McpResource rp ( vec_data [McpResource] . r resources )
    = k 0
    ~ < k rn {
        : McpResource res . rp k
        ( string_free . res uri )
        ( string_free . res name )
        ( string_free . res mime_type )
        ( string_free . res description )
        = k + k 1
    }
    ( vec_free [McpResource] . r resources )
}

// CONSUMES `name`, `description`, `schema`. Handler is borrowed.
@ mcp_registry_add_tool McpRegistry r s name s description Json schema ( @ Json Json ) handler → v {
    : McpTool t @ McpTool {
        ( string_from name )
        ( string_from description )
        schema
        handler
    }
    ( vec_push [McpTool] . r tools t )
}

@ mcp_registry_add_prompt McpRegistry r s name s description Json args_schema ( @ Json Json ) handler → v {
    : McpPrompt p @ McpPrompt {
        ( string_from name )
        ( string_from description )
        args_schema
        handler
    }
    ( vec_push [McpPrompt] . r prompts p )
}

@ mcp_registry_add_resource McpRegistry r s uri s name s mime_type s description ( @ Json ) handler → v {
    : McpResource res @ McpResource {
        ( string_from uri )
        ( string_from name )
        ( string_from mime_type )
        ( string_from description )
        handler
    }
    ( vec_push [McpResource] . r resources res )
}

// ── Lookup helpers ────────────────────────────────────────────────────

@ __mcp_find_tool_index McpRegistry r s name → i {
    : i n ( vec_len [McpTool] . r tools )
    : *McpTool tp ( vec_data [McpTool] . r tools )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpTool t . tp k
        ? != 0 ( nurl_str_eq ( string_data . t name ) name ) { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __mcp_find_prompt_index McpRegistry r s name → i {
    : i n ( vec_len [McpPrompt] . r prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r prompts )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpPrompt p . pp k
        ? != 0 ( nurl_str_eq ( string_data . p name ) name ) { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __mcp_find_resource_index McpRegistry r s uri → i {
    : i n ( vec_len [McpResource] . r resources )
    : *McpResource rp ( vec_data [McpResource] . r resources )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : McpResource res . rp k
        ? != 0 ( nurl_str_eq ( string_data . res uri ) uri ) { = found k } {}
        = k + k 1
    }
    ^ found
}

// ── Per-method dispatchers ────────────────────────────────────────────

// initialize: returns server capabilities + info per spec §3.2.
@ __mcp_dispatch_initialize McpRegistry r → Json {
    : Json info ( json_obj_new )
    ( json_obj_set info `name` ( json_str_lit ( string_data . r server_name ) ) )
    ( json_obj_set info `version` ( json_str_lit ( string_data . r server_version ) ) )

    : Json caps ( json_obj_new )
    // Declare capability per category that has any registered entries.
    // Empty object = "supported with no extra options".
    ? > ( vec_len [McpTool] . r tools ) 0
    { ( json_obj_set caps `tools` ( json_obj_new ) ) } {}
    ? > ( vec_len [McpPrompt] . r prompts ) 0
    { ( json_obj_set caps `prompts` ( json_obj_new ) ) } {}
    ? > ( vec_len [McpResource] . r resources ) 0
    { ( json_obj_set caps `resources` ( json_obj_new ) ) } {}

    : Json out ( json_obj_new )
    ( json_obj_set out `protocolVersion` ( json_str_lit `2024-11-05` ) )
    ( json_obj_set out `capabilities` caps )
    ( json_obj_set out `serverInfo` info )
    ^ out
}

// tools/list: build the array of {name, description, inputSchema}.
@ __mcp_dispatch_tools_list McpRegistry r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpTool] . r tools )
    : *McpTool tp ( vec_data [McpTool] . r tools )
    : ~ i k 0
    ~ < k n {
        : McpTool t . tp k
        : Json e ( json_obj_new )
        ( json_obj_set e `name` ( json_str_lit ( string_data . t name ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . t description ) ) )
        ( json_obj_set e `inputSchema` ( json_clone . t input_schema ) )
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `tools` arr )
    ^ out
}

// tools/call: lookup by name, invoke the handler with the `arguments`
// sub-object. Returns the handler's tool-result envelope verbatim.
// Errors (unknown tool) returned as the spec-defined tool error
// envelope ({content: [...], isError: true}).
@ __mcp_dispatch_tools_call McpRegistry r ?Json params → Json {
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
    : i idx ( __mcp_find_tool_index r tool_name )
    ? < idx 0 {
        ( json_free args )
        : String msg ( string_from `unknown tool: ` )
        ( string_push_str msg tool_name )
        : Json out ( mcp_tool_result_error ( string_data msg ) )
        ( string_free msg )
        ^ out
    } {}
    : *McpTool tp ( vec_data [McpTool] . r tools )
    : McpTool t . tp idx
    : ( @ Json Json ) h . t handler
    : Json result ( h args )
    ( json_free args )
    ^ result
}

// prompts/list: build the array of {name, description, arguments}.
@ __mcp_dispatch_prompts_list McpRegistry r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpPrompt] . r prompts )
    : *McpPrompt pp ( vec_data [McpPrompt] . r prompts )
    : ~ i k 0
    ~ < k n {
        : McpPrompt p . pp k
        : Json e ( json_obj_new )
        ( json_obj_set e `name` ( json_str_lit ( string_data . p name ) ) )
        ( json_obj_set e `description` ( json_str_lit ( string_data . p description ) ) )
        ( json_obj_set e `arguments` ( json_clone . p arguments_schema ) )
        ( json_arr_push arr e )
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `prompts` arr )
    ^ out
}

// prompts/get: invoke the prompt handler with `arguments`. Handler
// returns the spec-shaped {description, messages} object (or just
// messages; we wrap if missing).
@ __mcp_dispatch_prompts_get McpRegistry r ?Json params → Json {
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
        : Json e ( json_obj_new )
        ( json_obj_set e `__error__` ( json_str_lit `missing prompt name` ) )
        ^ e
    } {}
    : i idx ( __mcp_find_prompt_index r pname )
    ? < idx 0 {
        ( json_free args )
        : Json e ( json_obj_new )
        ( json_obj_set e `__error__` ( json_str_lit `unknown prompt` ) )
        ^ e
    } {}
    : *McpPrompt pp ( vec_data [McpPrompt] . r prompts )
    : McpPrompt p . pp idx
    : ( @ Json Json ) h . p handler
    : Json result ( h args )
    ( json_free args )
    ^ result
}

// resources/list: build the array of resource descriptors.
@ __mcp_dispatch_resources_list McpRegistry r → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [McpResource] . r resources )
    : *McpResource rp ( vec_data [McpResource] . r resources )
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
    ^ out
}

// resources/read: lookup by uri, invoke handler. Spec response shape
// is {contents: [{uri, mimeType, text|blob}]}. Handler returns the
// inner content object; we wrap it.
@ __mcp_dispatch_resources_read McpRegistry r ?Json params → Json {
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
        : Json e ( json_obj_new )
        ( json_obj_set e `__error__` ( json_str_lit `missing uri` ) )
        ^ e
    } {}
    : i idx ( __mcp_find_resource_index r uri )
    ? < idx 0 {
        : Json e ( json_obj_new )
        ( json_obj_set e `__error__` ( json_str_lit `unknown resource` ) )
        ^ e
    } {}
    : *McpResource rp ( vec_data [McpResource] . r resources )
    : McpResource res . rp idx
    : ( @ Json ) h . res handler
    : Json content ( h )
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
    ^ out
}

// ── Dispatcher ────────────────────────────────────────────────────────
//
// Single entry point routing JSON-RPC method names to the per-method
// handlers above. Returns the raw `result` field's Json (caller wraps
// in the JSON-RPC envelope with the request `id`).
//
// Unknown methods OR dispatch failures: returns a Json object with a
// `__error__` field — caller turns that into a JSON-RPC error response
// (method not found / internal error).
@ mcp_registry_dispatch McpRegistry r s method ?Json params → Json {
    ? != 0 ( nurl_str_eq method `initialize` ) {
        ^ ( __mcp_dispatch_initialize r )
    } {}
    ? != 0 ( nurl_str_eq method `tools/list` ) {
        ^ ( __mcp_dispatch_tools_list r )
    } {}
    ? != 0 ( nurl_str_eq method `tools/call` ) {
        ^ ( __mcp_dispatch_tools_call r params )
    } {}
    ? != 0 ( nurl_str_eq method `prompts/list` ) {
        ^ ( __mcp_dispatch_prompts_list r )
    } {}
    ? != 0 ( nurl_str_eq method `prompts/get` ) {
        ^ ( __mcp_dispatch_prompts_get r params )
    } {}
    ? != 0 ( nurl_str_eq method `resources/list` ) {
        ^ ( __mcp_dispatch_resources_list r )
    } {}
    ? != 0 ( nurl_str_eq method `resources/read` ) {
        ^ ( __mcp_dispatch_resources_read r params )
    } {}
    ? != 0 ( nurl_str_eq method `ping` ) {
        ^ ( json_obj_new )
    } {}
    : Json e ( json_obj_new )
    ( json_obj_set e `__error__` ( json_str_lit `method not found` ) )
    ^ e
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

: | McpServeErr {
    McpServeReadIo
    McpServeWriteIo
    McpServeOther
}

@ mcp_serve_err_name McpServeErr e → s {
    ^ ?? e {
        McpServeReadIo  → `McpServeReadIo`
        McpServeWriteIo → `McpServeWriteIo`
        McpServeOther   → `McpServeOther`
    }
}

@ __mcp_extract_method Json req → String {
    : ?Json m ( json_obj_get req `method` )
    ?? m {
        T jm → { ^ ( string_from ( json_as_str jm ) ) }
        F _ → { ^ ( string_new ) }
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

// Build the JSON-RPC response envelope for one dispatch result. Handles
// both success ({result, id}) and the error sub-shape recognised by
// `mcp_registry_dispatch` (a Json object with an `__error__` field).
// CONSUMES `result` + `id`.
@ __mcp_envelope_response Json result Json id → Json {
    : ?Json errf ( json_obj_get result `__error__` )
    ?? errf {
        T jerr → {
            : s msg ( json_as_str jerr )
            : Json resp ( mcp_response_error id -32601 msg )
            ( json_free result )
            ^ resp
        }
        F _ → { ^ ( mcp_response_result id result ) }
    }
}

// Single iteration of the stdio main loop. Returns T when EOF reached
// (caller terminates the loop), F otherwise.
@ __mcp_serve_stdio_once McpRegistry r → b {
    : ?Json req ( mcp_read_request )
    ?? req {
        T jr → {
            : String method ( __mcp_extract_method jr )
            : Json id ( __mcp_extract_id_or_null jr )
            : b had_id ( __mcp_has_id jr )
            : ?Json mparams ( json_obj_get jr `params` )
            : Json result ( mcp_registry_dispatch r ( string_data method ) mparams )
            ? had_id {
                : Json resp ( __mcp_envelope_response result id )
                ( mcp_send_message resp )
                ( json_free resp )
            } {
                // Notification — no response (per JSON-RPC 2.0 §4.1).
                ( json_free result )
                ( json_free id )
            }
            ( string_free method )
            ( json_free jr )
            ^ F
        }
        F _ → { ^ T }
    }
}

@ mcp_serve_stdio McpRegistry r → ! v McpServeErr {
    : ~ b done F
    ~ ! done {
        = done ( __mcp_serve_stdio_once r )
    }
    ^ @ ! v McpServeErr { T 0 }
}

// ── HTTP transport adapter ───────────────────────────────────────────
//
// `mcp_registry_envelope` is the transport-agnostic dispatch entry
// point. Given a parsed JSON-RPC request Json, runs the registry
// dispatch and produces either a response Json (Some) or None (the
// request was a pure notification with no id).
//
// `mcp_http_dispatch_for_registry` wraps this for the existing
// `mcp_http_handler` (stdlib/ext/mcp_http.nu) which expects a
// `( @ ? Json Json )` dispatch closure shape.
//
// Caller wires it together like:
//   : McpRegistry r ( mcp_registry_new `my-server` `1.0.0` )
//   ( mcp_registry_add_tool r `echo` `Echo back input` schema echo_handler )
//   : ( @ ? Json Json ) disp ( mcp_http_dispatch_for_registry r )
//   : ( @ HttpResponse HttpRequest ) h ( mcp_http_handler disp )
//   : HttpServer s ( server_new listener h )
//   ( server_run s )

@ mcp_registry_envelope McpRegistry r Json req → ? Json {
    : String method ( __mcp_extract_method req )
    : b had_id ( __mcp_has_id req )
    : Json id ( __mcp_extract_id_or_null req )
    : ?Json mparams ( json_obj_get req `params` )
    : Json result ( mcp_registry_dispatch r ( string_data method ) mparams )
    ( string_free method )
    ? had_id {
        : Json resp ( __mcp_envelope_response result id )
        ^ @ ? Json { T resp }
    } {
        // Notification — caller (mcp_http_handler) maps this to a
        // 202 Accepted with no body.
        ( json_free result )
        ( json_free id )
        ^ @ ? Json { F ( json_null ) }
    }
}

@ mcp_http_dispatch_for_registry McpRegistry r → ( @ ?Json Json ) {
    ^ \ Json req → ?Json { ^ ( mcp_registry_envelope r req ) }
}

// Bearer-auth middleware. Decorates an HTTP handler so requests
// without a matching `Authorization: Bearer <token>` header get a
// stock 401 Unauthorized + WWW-Authenticate challenge before the
// inner handler runs. Token comparison is byte-exact (no constant-
// time guard yet — for high-security deployments swap in a runtime
// helper that calls `CRYPTO_memcmp`).
@ mcp_http_with_bearer_auth ( @ HttpResponse HttpRequest ) inner s expected_token → ( @ HttpResponse HttpRequest ) {
    ^ \ HttpRequest req → HttpResponse {
        : b ok F
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
                        : ~ b match T
                        : ~ i k 0
                        ~ & match < k tlen {
                            ? != ( nurl_str_get avs + 7 k )
                                  ( nurl_str_get expected_token k )
                            { = match F } {}
                            = k + k 1
                        }
                        ? match { = ok T } {}
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
