// stdlib/ext/anthropic.nu — Anthropic Messages API client (Claude)
//
// Sends a chat turn to https://api.anthropic.com/v1/messages and parses
// the response. Builds on stdlib/ext/http.nu (transport) and
// stdlib/ext/json.nu (request body + response decode), so callers don't
// touch raw libcurl or hand-format JSON.
//
// This is the keystone module for NURL as an LLM agent host: with
// `claude_messages` you can drive Claude from a NURL program with the
// same code-shape as any other HTTP+JSON wrapper. The full
// `claude_messages_full` adds multi-turn conversations, tool-use, and
// tool_choice control — enough to build a real agent loop on top of
// `stdlib/std/process.nu`, `stdlib/std/fs.nu`, and friends.
//
// ── Quick start: single-turn chat ───────────────────────────────────
//
//   ( claude_messages       s api_key s model s system_prompt
//                           s user_text i max_tokens )
//                                       → ! Json ClaudeErr
//
//   ( claude_text           Json r )    → s   first text block; "" if none
//   ( claude_stop_reason    Json r )    → s   borrowed
//   ( claude_model          Json r )    → s   borrowed
//   ( claude_input_tokens   Json r )    → i
//   ( claude_output_tokens  Json r )    → i
//   ( claude_response_free  Json r )    → v   alias for json_free
//   ( claude_err_name       ClaudeErr e ) → s
//
// ── Full surface: multi-turn + tool-use ─────────────────────────────
//
// Send a full conversation, optionally with tool definitions. The
// caller maintains a Vec[Json] of messages across turns, appending
// the assistant's response and any tool_result blocks between calls.
//
//   ( claude_messages_full  s api_key s model s system_prompt
//                           ( Vec Json ) messages
//                           ( Vec Json ) tools
//                           s tool_choice
//                           i max_tokens )
//                                       → ! Json ClaudeErr
//
// Production knobs (caching + extended thinking) live on a higher arity:
//
//   ( claude_messages_full_ex  s api_key s model s system_prompt
//                              ( Vec Json ) messages
//                              ( Vec Json ) tools
//                              s tool_choice
//                              i max_tokens
//                              b cache_system
//                              b cache_tools
//                              i thinking_budget )
//                                       → ! Json ClaudeErr
//
//   cache_system / cache_tools attach `cache_control: ephemeral` to the
//   system block and the last tool definition respectively, so the
//   server reuses KV-cache for the stable prefix on subsequent turns.
//   thinking_budget > 0 enables extended thinking with the given
//   budget. claude_messages_full is just the F/F/0 specialization.
//
//   ( claude_msg_user_text_cached      s text ) → Json
//   ( claude_msg_assistant_text_cached s text ) → Json
//   Per-message cache breakpoints — emit array-form content with
//   cache_control on the text block. Use these to mark long stable
//   conversation snippets (RAG context, rendered file contents).
//
//   ( claude_cache_creation_tokens Json r ) → i
//   ( claude_cache_read_tokens     Json r ) → i
//   Usage accessors for cache hit/miss tracking.
//
// Memory model for `_full`:
//   * `messages` and `tools` are BORROWED — each element is deep-cloned
//     into the request body. The caller's Vec[Json] survives the call
//     untouched and can be reused / extended for the next turn.
//   * On the Result-Ok path the returned Json is owned by the caller.
//
// Message builders (return owned Json — push into a Vec[Json], or pass
// to a builder that consumes them):
//
//   ( claude_msg_user_text       s text )       → Json
//                                                  {role:"user", content:"text"}
//   ( claude_msg_assistant_text  s text )       → Json
//                                                  {role:"assistant", content:"text"}
//   ( claude_msg_assistant_response Json r )    → Json
//                                                  Clones r["content"] (the array
//                                                  of text + tool_use blocks) and
//                                                  wraps it as
//                                                  {role:"assistant", content:[…]}.
//                                                  Use this between turns to feed
//                                                  the assistant's last reply back
//                                                  into the messages array.
//   ( claude_msg_user_blocks     ( Vec Json ) blocks ) → Json
//                                                  {role:"user", content:[…]}.
//                                                  CONSUMES `blocks`.
//   ( claude_tool_result_block   s tool_use_id s text b is_error ) → Json
//                                                  Single tool_result block to
//                                                  push into a Vec[Json] before
//                                                  calling claude_msg_user_blocks.
//
// Multimodal content blocks (push into Vec[Json] + claude_msg_user_blocks):
//
//   ( claude_text_block          s text )                       → Json
//   ( claude_image_url_block     s url )                        → Json
//   ( claude_image_b64_block     s media_type s data_b64 )      → Json
//   ( claude_document_url_block  s url )                        → Json
//   ( claude_document_b64_block  s data_b64 )                   → Json
//
// Typical vision turn:
//
//   ( vec_push [Json] blocks ( claude_text_block      `Describe:` ) )
//   ( vec_push [Json] blocks ( claude_image_url_block `https://…/cat.png` ) )
//   ( vec_push [Json] msgs   ( claude_msg_user_blocks blocks ) )
//
// Tool definitions:
//
//   ( claude_tool_def s name s description Json input_schema ) → Json
//                                                  {name, description, input_schema}.
//                                                  CONSUMES input_schema.
//
// `tool_choice` is a raw `s` for ergonomic literal use:
//
//   ""           — omit field; Claude defaults to "auto" when tools exist.
//   "auto"       — explicit auto.
//   "any"        — must call some tool.
//   "none"       — disallow tools (force text reply).
//   "tool:NAME"  — force the named tool.
//
// Response inspection (for tool-use loops):
//
//   ( claude_has_tool_use Json r )      → b   stop_reason == "tool_use"
//   ( claude_tool_calls   Json r )      → ( Vec Json )
//                                          Owned Vec of CLONED tool_use blocks.
//                                          Free with a per-element drop closure:
//                                          : (@ v Json) drop \ Json e → v { ( json_free e ) }
//                                          ( vec_free_with [Json] tcs drop )
//   ( claude_tool_use_id    Json tu )   → s    BORROWED; "" if missing
//   ( claude_tool_use_name  Json tu )   → s    BORROWED; "" if missing
//   ( claude_tool_use_input Json tu )   → ? Json   BORROWED; None if missing
//
// All accessors return safe defaults ("" / 0 / None / empty Vec) if the
// response is not shaped like a successful Messages reply, so callers
// can write straight-line code without nesting `??` for every probe.
//
// ── Memory model summary ────────────────────────────────────────────
//
//   * Inputs (api_key / model / system_prompt / user_text / tool_use_id
//     / tool_choice / tool/message names) are raw `s` pointers,
//     BORROWED. Pass literals or `string_data` views.
//   * `system_prompt` may be `` (empty) to omit the field.
//   * Vec[Json] inputs to `claude_messages_full` are BORROWED.
//   * Vec[Json] inputs to `claude_msg_user_blocks` are CONSUMED.
//   * Json inputs to `claude_msg_assistant_response`, `claude_tool_calls`
//     etc. are BORROWED — they remain valid after the call.
//   * Json inputs to builder constructors that embed (e.g.
//     `claude_tool_def`'s `input_schema`) are CONSUMED.
//   * On the Result-Ok path the caller OWNS the returned Json and must
//     `claude_response_free` (or `json_free`) it exactly once.
//   * Accessors return BORROWED views into the response — copy with
//     `string_from` if you need them to outlive the Json.
//
// ── Errors ──────────────────────────────────────────────────────────
//
//   ClaudeAuth            api_key was empty
//   ClaudeHttpConnect/…   transport error (1:1 mapping from HttpErr)
//   ClaudeJson            response body wasn't valid JSON
//   ClaudeApi             HTTP status was not 200 (e.g. 4xx/5xx)
//   ClaudeShape           response parsed but content[0].text missing
//                         (returned only when shape probes fail; the
//                         high-level `claude_messages` does not produce
//                         it directly — `claude_text` returns "" instead.
//                         Reserved for callers that want a stricter
//                         envelope.)
//
// ── Endpoint and version ────────────────────────────────────────────
//
// URL is hardcoded to `https://api.anthropic.com/v1/messages` and the
// `anthropic-version` header is fixed to `2023-06-01`. If you need a
// different endpoint (proxy, on-prem) or version, copy this module and
// edit those two literals — the rest of the wrapper is generic.

$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/result.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/int.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/json.nu`

: | ClaudeErr {
    ClaudeAuth
    ClaudeHttpConnect
    ClaudeHttpTimeout
    ClaudeHttpTls
    ClaudeHttpDns
    ClaudeHttpInvalidUrl
    ClaudeHttpOther
    ClaudeJson
    ClaudeApi
    ClaudeShape
}

@ claude_err_name ClaudeErr e → s {
    ^ ?? e {
        ClaudeAuth → `ClaudeAuth`
        ClaudeHttpConnect → `ClaudeHttpConnect`
        ClaudeHttpTimeout → `ClaudeHttpTimeout`
        ClaudeHttpTls → `ClaudeHttpTls`
        ClaudeHttpDns → `ClaudeHttpDns`
        ClaudeHttpInvalidUrl → `ClaudeHttpInvalidUrl`
        ClaudeHttpOther → `ClaudeHttpOther`
        ClaudeJson → `ClaudeJson`
        ClaudeApi → `ClaudeApi`
        ClaudeShape → `ClaudeShape`
    }
}

@ __claude_map_http HttpErr e → ClaudeErr {
    ^ ?? e {
        HttpConnect → @ ClaudeErr { ClaudeHttpConnect }
        HttpTimeout → @ ClaudeErr { ClaudeHttpTimeout }
        HttpTls → @ ClaudeErr { ClaudeHttpTls }
        HttpDns → @ ClaudeErr { ClaudeHttpDns }
        HttpInvalidUrl → @ ClaudeErr { ClaudeHttpInvalidUrl }
        HttpOther → @ ClaudeErr { ClaudeHttpOther }
    }
}

// ── Message builders ────────────────────────────────────────────────

// Plain {role: "user", content: "text"} message.
@ claude_msg_user_text s text → Json {
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `user` ) )
    ( json_obj_set m `content` ( json_str_lit text ) )
    ^ m
}

// Plain {role: "assistant", content: "text"} message — useful for
// prefilling few-shot examples or replaying a known assistant reply.
// Use `claude_msg_assistant_response` when feeding back a real Claude
// turn (which may include tool_use blocks).
@ claude_msg_assistant_text s text → Json {
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `assistant` ) )
    ( json_obj_set m `content` ( json_str_lit text ) )
    ^ m
}

// Wrap a response's full content array (text + tool_use blocks) as the
// assistant's turn for the next call. Clones the array so the original
// response stays independently owned.
@ claude_msg_assistant_response Json r → Json {
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `assistant` ) )
    : ?Json content ( json_obj_get r `content` )
    ?? content {
        T cv → {
            ( json_obj_set m `content` ( json_clone cv ) )
        }
        F → {
            ( json_obj_set m `content` ( json_arr_new ) )
        }
    }
    ^ m
}

// {role: "user", content: [<blocks>]} — typically the tool_result reply
// turn. CONSUMES the Vec; each element is moved into the wrapped JArr.
@ claude_msg_user_blocks ( Vec Json ) blocks → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [Json] blocks )
    : ~ i k 0
    ~ < k n {
        : ?Json e ( vec_get [Json] blocks k )
        ?? e {
            T jv → ( json_arr_push arr jv )
            F → {}
        }
        = k + k 1
    }
    // Drop the now-emptied Vec; the JArr owns the moved elements.
    ( vec_free [Json] blocks )
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `user` ) )
    ( json_obj_set m `content` arr )
    ^ m
}

// Single tool_result content block. Push these into a Vec[Json] then
// pass to `claude_msg_user_blocks` to make a complete tool-result turn.
// `is_error = T` flags the result as an error so the model knows to
// adjust strategy rather than treat the text as authoritative.
@ claude_tool_result_block s tool_use_id s text b is_error → Json {
    : Json block ( json_obj_new )
    ( json_obj_set block `type` ( json_str_lit `tool_result` ) )
    ( json_obj_set block `tool_use_id` ( json_str_lit tool_use_id ) )
    ( json_obj_set block `content` ( json_str_lit text ) )
    ? is_error {
        ( json_obj_set block `is_error` ( json_bool T ) )
    } {}
    ^ block
}

// ── Prompt caching helpers ──────────────────────────────────────────
//
// Anthropic prompt caching: mark stable prefixes (system prompt, tool
// definitions, conversation history) with `cache_control: {type:
// "ephemeral"}` so subsequent turns reuse the KV-cache and the prompt
// tokens cost ~10% (cache reads) instead of full price. Up to 4 cache
// breakpoints per request — the API picks the longest matching prefix.
//
// Typical pattern: cache the system prompt + tool definitions once
// (`cache_system: T`, `cache_tools: T` to claude_messages_full_ex),
// optionally insert a per-message breakpoint after long context blocks
// using `claude_msg_user_text_cached`.
//
// `__claude_cache_ephemeral` returns a fresh ephemeral marker that can
// be moved into any Json block via `json_obj_set X "cache_control" ...`.
@ __claude_cache_ephemeral → Json {
    : Json m ( json_obj_new )
    ( json_obj_set m `type` ( json_str_lit `ephemeral` ) )
    ^ m
}

// User message that injects a cache breakpoint at the end of the text.
// Equivalent to claude_msg_user_text but emits the array-of-blocks form
// {role:"user", content:[{type:"text", text:..., cache_control:{...}}]}
// so Anthropic treats this exact prefix as a cache point.
@ claude_msg_user_text_cached s text → Json {
    : Json block ( json_obj_new )
    ( json_obj_set block `type` ( json_str_lit `text` ) )
    ( json_obj_set block `text` ( json_str_lit text ) )
    ( json_obj_set block `cache_control` ( __claude_cache_ephemeral ) )
    : Json arr ( json_arr_new )
    ( json_arr_push arr block )
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `user` ) )
    ( json_obj_set m `content` arr )
    ^ m
}

// Same idea for assistant prefills: rare but useful for few-shot
// scaffolding where the assistant turn is long and reused.
@ claude_msg_assistant_text_cached s text → Json {
    : Json block ( json_obj_new )
    ( json_obj_set block `type` ( json_str_lit `text` ) )
    ( json_obj_set block `text` ( json_str_lit text ) )
    ( json_obj_set block `cache_control` ( __claude_cache_ephemeral ) )
    : Json arr ( json_arr_new )
    ( json_arr_push arr block )
    : Json m ( json_obj_new )
    ( json_obj_set m `role` ( json_str_lit `assistant` ) )
    ( json_obj_set m `content` arr )
    ^ m
}

// ── Multimodal content blocks (vision + documents) ──────────────────
//
// Build single content blocks for image / document inputs. Push them
// (alongside text blocks via `claude_text_block`) into a Vec[Json] and
// wrap with `claude_msg_user_blocks` for a complete user turn.
//
// Anthropic content-block shapes:
//   text:     {"type":"text","text":"..."}
//   image:    {"type":"image","source":{"type":"url"|"base64", ...}}
//   document: {"type":"document","source":{"type":"url"|"base64", ...}}
//
// Image sources support PNG, JPEG, GIF, and WebP. Documents are PDF
// (Anthropic's vision-capable models extract text + figures from each
// page directly, no preprocessing needed).
//
// Memory model: all inputs (url, media_type, text, base64 data) are
// raw `s` BORROWED — pass literals or `string_data` views.

// Plain text content block — symmetric to claude_image_*_block, useful
// when assembling a mixed text + image / text + document user turn.
@ claude_text_block s text → Json {
    : Json b ( json_obj_new )
    ( json_obj_set b `type` ( json_str_lit `text` ) )
    ( json_obj_set b `text` ( json_str_lit text ) )
    ^ b
}

// Image content block — URL source. Anthropic fetches the URL on the
// server side and decodes the image; no preprocessing on the caller.
//   {"type":"image","source":{"type":"url","url":"https://..."}}
@ claude_image_url_block s url → Json {
    : Json src ( json_obj_new )
    ( json_obj_set src `type` ( json_str_lit `url` ) )
    ( json_obj_set src `url` ( json_str_lit url ) )
    : Json b ( json_obj_new )
    ( json_obj_set b `type` ( json_str_lit `image` ) )
    ( json_obj_set b `source` src )
    ^ b
}

// Image content block — base64-encoded inline data. `media_type` is one
// of "image/png", "image/jpeg", "image/gif", "image/webp". `data_b64`
// is the raw base64 payload (no `data:` URI prefix). Use `b64_encode`
// from stdlib/std/encode.nu on a Vec[u] read via `read_file_bytes`.
//   {"type":"image","source":{"type":"base64",
//                              "media_type":"image/png","data":"..."}}
@ claude_image_b64_block s media_type s data_b64 → Json {
    : Json src ( json_obj_new )
    ( json_obj_set src `type` ( json_str_lit `base64` ) )
    ( json_obj_set src `media_type` ( json_str_lit media_type ) )
    ( json_obj_set src `data` ( json_str_lit data_b64 ) )
    : Json b ( json_obj_new )
    ( json_obj_set b `type` ( json_str_lit `image` ) )
    ( json_obj_set b `source` src )
    ^ b
}

// Document content block — URL source. Use for PDFs hosted online.
// media_type is fixed to "application/pdf" by Anthropic.
//   {"type":"document","source":{"type":"url","url":"https://..."}}
@ claude_document_url_block s url → Json {
    : Json src ( json_obj_new )
    ( json_obj_set src `type` ( json_str_lit `url` ) )
    ( json_obj_set src `url` ( json_str_lit url ) )
    : Json b ( json_obj_new )
    ( json_obj_set b `type` ( json_str_lit `document` ) )
    ( json_obj_set b `source` src )
    ^ b
}

// Document content block — base64-encoded inline PDF.
//   {"type":"document","source":{"type":"base64",
//                                 "media_type":"application/pdf",
//                                 "data":"..."}}
@ claude_document_b64_block s data_b64 → Json {
    : Json src ( json_obj_new )
    ( json_obj_set src `type` ( json_str_lit `base64` ) )
    ( json_obj_set src `media_type` ( json_str_lit `application/pdf` ) )
    ( json_obj_set src `data` ( json_str_lit data_b64 ) )
    : Json b ( json_obj_new )
    ( json_obj_set b `type` ( json_str_lit `document` ) )
    ( json_obj_set b `source` src )
    ^ b
}

// ── Tool definition builder ─────────────────────────────────────────
//
// Anthropic uses snake_case `input_schema` (MCP uses camelCase
// `inputSchema` — see stdlib/ext/mcp.nu#mcp_tool_descriptor).
@ claude_tool_def s name s description Json input_schema → Json {
    : Json t ( json_obj_new )
    ( json_obj_set t `name` ( json_str_lit name ) )
    ( json_obj_set t `description` ( json_str_lit description ) )
    ( json_obj_set t `input_schema` input_schema )
    ^ t
}

// ── tool_choice parser ──────────────────────────────────────────────

@ __claude_parse_tool_choice s tc → ?Json {
    : i n ( nurl_str_len tc )
    ? == n 0 {
        ^ @ ?Json { F @ Json { JNull } }
    } {}

    ? != ( nurl_str_eq tc `auto` ) 0 {
        : Json o ( json_obj_new )
        ( json_obj_set o `type` ( json_str_lit `auto` ) )
        ^ @ ?Json { T o }
    } {}
    ? != ( nurl_str_eq tc `any` ) 0 {
        : Json o ( json_obj_new )
        ( json_obj_set o `type` ( json_str_lit `any` ) )
        ^ @ ?Json { T o }
    } {}
    ? != ( nurl_str_eq tc `none` ) 0 {
        : Json o ( json_obj_new )
        ( json_obj_set o `type` ( json_str_lit `none` ) )
        ^ @ ?Json { T o }
    } {}
    ? != ( nurl_str_starts tc `tool:` ) 0 {
        // Extract the suffix via String to get clean ownership; the literal
        // 5 is the byte length of "tool:". Empty NAME yields "" and the
        // server will reject the request with 400 — caller's fault for
        // passing "tool:" with no name.
        : String full ( string_from tc )
        : i suffix_n - n 5
        : String name ( string_substr full 5 suffix_n )
        : Json o ( json_obj_new )
        ( json_obj_set o `type` ( json_str_lit `tool` ) )
        ( json_obj_set o `name` ( json_str_lit ( string_data name ) ) )
        ( string_free name )
        ( string_free full )
        ^ @ ?Json { T o }
    } {}

    // Unknown shape — fall through and omit the field.
    ^ @ ?Json { F @ Json { JNull } }
}

// ── Internal: clone Vec[Json] so the body owns disjoint copies ──────

@ __claude_clone_vec_json ( Vec Json ) src → ( Vec Json ) {
    : ( Vec Json ) out ( vec_new [Json] )
    : i n ( vec_len [Json] src )
    : ~ i k 0
    ~ < k n {
        : ?Json e ( vec_get [Json] src k )
        ?? e {
            T jv → ( vec_push [Json] out ( json_clone jv ) )
            F → {}
        }
        = k + k 1
    }
    ^ out
}

// ── Build the full request body ─────────────────────────────────────
//
// Builds the JSON payload for /v1/messages. Caller's `messages` and
// `tools` are BORROWED — each element is deep-cloned into the body.
// `tool_choice` is the raw `s` form documented at the top of this file.
//
// `cache_system`: when T and system_prompt is non-empty, the system
// field is emitted as the array form
// [{type:"text", text:..., cache_control:{type:"ephemeral"}}] so the
// system prefix participates in prompt caching.
//
// `cache_tools`: when T and at least one tool is supplied, the LAST
// tool definition gets cache_control:{type:"ephemeral"} attached. The
// API caches everything from the start of the request up to and
// including that breakpoint, so marking the last tool covers the whole
// tools array (which is the usual desired shape).
//
// `thinking_budget`: when > 0, emits
// {"thinking":{"type":"enabled","budget_tokens":N}} so Claude runs
// extended thinking with the given token budget. 0 disables thinking.

@ __claude_build_body_full_ex
s model s system_prompt
( Vec Json ) messages
( Vec Json ) tools
s tool_choice
i max_tokens
b cache_system
b cache_tools
i thinking_budget → Json {
    : Json body ( json_obj_new )
    ( json_obj_set body `model` ( json_str_lit model ) )
    ( json_obj_set body `max_tokens` ( json_int max_tokens ) )

    ? > ( nurl_str_len system_prompt ) 0 {
        ? cache_system {
            // Array form lets us attach cache_control. The single text block
            // mirrors what Anthropic returns for the bare-string form.
            : Json sblock ( json_obj_new )
            ( json_obj_set sblock `type` ( json_str_lit `text` ) )
            ( json_obj_set sblock `text` ( json_str_lit system_prompt ) )
            ( json_obj_set sblock `cache_control` ( __claude_cache_ephemeral ) )
            : Json sarr ( json_arr_new )
            ( json_arr_push sarr sblock )
            ( json_obj_set body `system` sarr )
        } {
            ( json_obj_set body `system` ( json_str_lit system_prompt ) )
        }
    } {}

    // Extended thinking — emit when budget is positive. Anthropic
    // requires thinking before any tool_use blocks, so this is fine to
    // combine with the tools array below.
    ? > thinking_budget 0 {
        : Json th ( json_obj_new )
        ( json_obj_set th `type` ( json_str_lit `enabled` ) )
        ( json_obj_set th `budget_tokens` ( json_int thinking_budget ) )
        ( json_obj_set body `thinking` th )
    } {}

    // Messages array (always required, even if empty — but the API rejects
    // empty messages, so we just trust the caller here).
    : ( Vec Json ) msgs_cloned ( __claude_clone_vec_json messages )
    ( json_obj_set body `messages` ( json_arr msgs_cloned ) )

    // Tools array — only emit when the caller supplied at least one.
    : i tn ( vec_len [Json] tools )
    ? > tn 0 {
        : ( Vec Json ) tools_cloned ( __claude_clone_vec_json tools )
        ? cache_tools {
            // Attach cache_control to the LAST tool — the longest cacheable
            // prefix the API can reuse on the next call when the tools array
            // is unchanged.
            : i last_idx - tn 1
            : ?Json last_e ( vec_get [Json] tools_cloned last_idx )
            ?? last_e {
                T last_t → {
                    ( json_obj_set last_t `cache_control` ( __claude_cache_ephemeral ) )
                }
                F → {}
            }
        } {}
        ( json_obj_set body `tools` ( json_arr tools_cloned ) )
    } {}

    // tool_choice — only meaningful when tools are present.
    ? > tn 0 {
        : ?Json tc ( __claude_parse_tool_choice tool_choice )
        ?? tc {
            T j → ( json_obj_set body `tool_choice` j )
            F → {}
        }
    } {}

    ^ body
}

// Backward-compat shim — same shape as before, no caching, no thinking.
@ __claude_build_body_full
s model s system_prompt
( Vec Json ) messages
( Vec Json ) tools
s tool_choice
i max_tokens → Json {
    ^ ( __claude_build_body_full_ex
    model system_prompt messages tools tool_choice max_tokens
    F F 0 )
}

// Total request budget. The Anthropic SDK defaults to 600 s (10 min)
// because Claude can spend a long time generating before any byte is
// flushed — especially for long contexts on opus-class models. The
// MVP HTTP layer's 30 s budget would otherwise time out reliably on
// any non-trivial agent loop.
//
// `ANTHROPIC_TIMEOUT_MS` env override lets callers tune this without
// recompiling. Out-of-range / unparseable values fall back to 600 000.
@ __claude_timeout_ms → i {
    : ?String env ( env_get `ANTHROPIC_TIMEOUT_MS` )
    ?? env {
        T s → {
            : !i ParseErr p ( int_parse ( string_data s ) )
            ( string_free s )
            ?? p {
                T n → {
                    ? > n 0 { ^ n } {}
                }
                F _ → {}
            }
        }
        F → {}
    }
    ^ 600000
}

@ __claude_connect_timeout_ms → i {
    ^ 15000
}

// Build the CRLF-delimited headers blob. `x-api-key` carries the secret;
// `anthropic-version` pins the API contract; `content-type` is set here
// even though http_post_with_headers also injects it, so the blob is
// self-describing if a future caller switches to http_request directly.
@ __claude_headers s api_key → String {
    : String b ( string_with_cap 256 )
    ( string_push_str b `x-api-key: ` )
    ( string_push_str b api_key )
    ( string_push_str b `\r\n` )
    ( string_push_str b `anthropic-version: 2023-06-01\r\n` )
    ( string_push_str b `content-type: application/json\r\n` )
    ^ b
}

// ── Public: full multi-turn + tool-use entry point with caching/thinking ─
//
// Adds the production-grade tuning knobs:
//
//   cache_system   — mark the system prompt as a cache breakpoint.
//                    Saves ~90% on system tokens for every reuse turn.
//   cache_tools    — mark the last tool definition as a cache breakpoint.
//                    Recommended any time you have non-trivial tool
//                    schemas that don't change between turns.
//   thinking_budget — when > 0, enables extended thinking with the
//                    given token budget. The model emits internal
//                    reasoning blocks before the final answer; useful
//                    for hard reasoning tasks. 0 disables.
//
// Both Vec[Json] inputs are BORROWED — caller still owns and frees
// them after the call.
@ claude_messages_full_ex
s api_key s model s system_prompt
( Vec Json ) messages
( Vec Json ) tools
s tool_choice
i max_tokens
b cache_system
b cache_tools
i thinking_budget
→ !Json ClaudeErr {
    ? == ( nurl_str_len api_key ) 0 {
        ^ @ !Json ClaudeErr { F @ ClaudeErr { ClaudeAuth } }
    } {}

    : Json body
    ( __claude_build_body_full_ex
    model system_prompt messages tools tool_choice max_tokens
    cache_system cache_tools thinking_budget )
    : String body_str ( json_stringify body )
    ( json_free body )

    : String headers ( __claude_headers api_key )

    // Use http_request_to so the per-call timeout is configurable. Claude
    // turns regularly run 30+ seconds on opus-class models with long
    // contexts; the MVP HTTP layer's 30-second total budget would
    // otherwise time out the second turn of every multi-turn agent loop.
    : !Response HttpErr res
    ( http_request_to `POST`
    `https://api.anthropic.com/v1/messages`
    ( string_data body_str )
    ( string_data headers )
    ( __claude_timeout_ms )
    ( __claude_connect_timeout_ms ) )
    ( string_free body_str )
    ( string_free headers )

    ?? res {
        T r → {
            : i st ( http_status r )
            : String body_owned ( string_from ( http_body_str r ) )
            ( response_free r )

            : !Json JsonError pj ( json_parse ( string_data body_owned ) )
            ( string_free body_owned )

            ?? pj {
                T j → {
                    ? != st 200 {
                        ( json_free j )
                        ^ @ !Json ClaudeErr { F @ ClaudeErr { ClaudeApi } }
                    } {}
                    ^ @ !Json ClaudeErr { T j }
                }
                F _ → {
                    ^ @ !Json ClaudeErr { F @ ClaudeErr { ClaudeJson } }
                }
            }
        }
        F he → {
            ^ @ !Json ClaudeErr { F ( __claude_map_http # HttpErr he ) }
        }
    }
    // All arms above terminate; this is unreachable but keeps the
    // codegen happy if it can't yet prove total coverage.
    ^ @ !Json ClaudeErr { F @ ClaudeErr { ClaudeShape } }
}

// Backward-compatible shim: same signature as before, no caching, no
// thinking. Existing callers keep working unchanged.
@ claude_messages_full
s api_key s model s system_prompt
( Vec Json ) messages
( Vec Json ) tools
s tool_choice
i max_tokens
→ !Json ClaudeErr {
    ^ ( claude_messages_full_ex
    api_key model system_prompt messages tools tool_choice max_tokens
    F F 0 )
}

// ── Streaming entry point ───────────────────────────────────────────
//
// Open a streaming HTTP connection to /v1/messages with `stream: true`
// in the body. The caller pulls SSE chunks via `http_stream_next` from
// `stdlib/ext/http.nu` and feeds them into the SSE parser also there:
//
//   ~ ! done {
//     : ? String chopt ( http_stream_next st )
//     ?? chopt {
//       T ch → {
//         ( string_push_str acc ( string_data ch ) )
//         ( string_free ch )
//         // pop frames from acc, parse with sse_parse_frame, then
//         // claude_stream_event_text_delta to extract delta text
//         …
//       }
//       F → { = done T }
//     }
//   }
//   ( http_stream_close st )
//
// Anthropic event types (`event:` field of each SSE frame):
//
//   message_start       : Json {message: {id, model, usage, ...}}
//   content_block_start : new content block opened (text or tool_use)
//   content_block_delta : Json {delta: {type:"text_delta", text:"..."}}
//                         OR {delta: {type:"input_json_delta", partial_json:"..."}}
//   content_block_stop  : block finished
//   message_delta       : usage / stop_reason finalisation
//   message_stop        : stream done
//   ping                : keepalive (no payload)
//   error               : Json {error: {type, message}}
//
// Each frame's `data:` field is JSON. Parse with `json_parse` and probe
// fields with `json_obj_get` / `json_get`.
//
// Vec[Json] inputs are BORROWED (deep-cloned into the body), exactly
// like claude_messages_full_ex. The returned HttpStream is OWNED — the
// caller MUST `http_stream_close` it.
@ claude_messages_stream_ex
s api_key s model s system_prompt
( Vec Json ) messages
( Vec Json ) tools
s tool_choice
i max_tokens
b cache_system
b cache_tools
i thinking_budget
→ !HttpStream ClaudeErr {
    ? == ( nurl_str_len api_key ) 0 {
        ^ @ !HttpStream ClaudeErr { F @ ClaudeErr { ClaudeAuth } }
    } {}

    : Json body
    ( __claude_build_body_full_ex
    model system_prompt messages tools tool_choice max_tokens
    cache_system cache_tools thinking_budget )
    ( json_obj_set body `stream` ( json_bool T ) )
    : String body_str ( json_stringify body )
    ( json_free body )

    // Add accept: text/event-stream so the server picks the SSE format.
    : String headers ( __claude_headers api_key )
    ( string_push_str headers `accept: text/event-stream\r\n` )

    : !HttpStream HttpErr s
    ( http_stream_open_to `POST`
    `https://api.anthropic.com/v1/messages`
    ( string_data body_str )
    ( string_data headers )
    ( __claude_timeout_ms )
    ( __claude_connect_timeout_ms ) )
    ( string_free body_str )
    ( string_free headers )

    ?? s {
        T st → { ^ @ !HttpStream ClaudeErr { T st } }
        F he → {
            ^ @ !HttpStream ClaudeErr { F ( __claude_map_http # HttpErr he ) }
        }
    }
    // Unreachable — both arms returned.
    ^ @ !HttpStream ClaudeErr { F @ ClaudeErr { ClaudeShape } }
}

// Streaming convenience: single-turn, no tools, no caching.
@ claude_messages_stream s api_key s model s system_prompt s user_text i max_tokens
→ !HttpStream ClaudeErr {
    : ( Vec Json ) msgs ( vec_new [Json] )
    ( vec_push [Json] msgs ( claude_msg_user_text user_text ) )
    : ( Vec Json ) tools ( vec_new [Json] )

    : !HttpStream ClaudeErr r
    ( claude_messages_stream_ex
    api_key model system_prompt msgs tools `` max_tokens
    F F 0 )

    : ( @ v Json ) drop_json \ Json e → v { ( json_free e ) }
    ( vec_free_with [Json] msgs drop_json )
    ( vec_free_with [Json] tools drop_json )
    ^ r
}

// ── SSE event extractors (Anthropic streaming) ─────────────────────
//
// All extractors take a parsed `SseEvent` (from `sse_parse_frame`) and
// return Option/owned-String. They internally `json_parse` the `data`
// field, navigate the documented Anthropic shape, copy the field of
// interest into an owned String (or extract an `i`), and free the
// transient Json. None signals "this event isn't the expected kind, OR
// the field was missing" — callers should treat this as a benign skip.
//
// The set covers a complete streaming + tool-use loop:
//
//   text_delta       — token-by-token assistant text   (existing)
//   input_json_delta — token-by-token tool-call JSON   (NEW)
//   index            — block index for content_block_* (NEW)
//   block_kind       — "text" / "tool_use" / "thinking" from
//                      content_block_start              (NEW)
//   tool_use_id      — tool_use id from content_block_start (NEW)
//   tool_use_name    — tool_use name from content_block_start (NEW)
//   stop_reason      — stop_reason from message_delta (NEW)
//   error_type       — error.type from `error` event (NEW)
//   error_message    — error.message from `error` event (NEW)
//
// Typical streaming-tool-use loop (per parsed SseEvent ev):
//
//   ?? ( claude_stream_event_block_kind ev ) {
//     T k → {
//       // content_block_start — open a slot for index N
//       : ? i idx ( claude_stream_event_index ev )
//       ?? idx { T n → ( … allocate state[n] for kind k …) F → {} }
//       ( string_free k )
//     }
//     F → {}
//   }
//   ?? ( claude_stream_event_text_delta ev ) {
//     T s → ( emit_chat_chunk ( string_data s ) )  ( string_free s )
//     F → {}
//   }
//   ?? ( claude_stream_event_input_json_delta ev ) {
//     T s → ( append_tool_args ( string_data s ) ) ( string_free s )
//     F → {}
//   }
//   ?? ( claude_stream_event_stop_reason ev ) {
//     T sr → ( … decide next turn …) ( string_free sr )
//     F → {}
//   }
//
// `claude_stream_event_text_delta` is the original convenience
// extractor; the rest mirror its pattern exactly.

// Convenience extractor for the common case: a `content_block_delta`
// SSE frame whose JSON payload carries a `delta.type == "text_delta"`
// with the next chunk of model output. Returns the text string in an
// owned String, or None when the event is some other shape (ping,
// message_start, content_block_stop, etc.).
//
// `data` is BORROWED — passes the JSON parser internally. Returns
// owned String for the delta text.
@ claude_stream_event_text_delta SseEvent ev → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `content_block_delta` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json delta ( json_obj_get j `delta` )
            ?? delta {
                T d → {
                    : ?Json typ ( json_obj_get d `type` )
                    ?? typ {
                        T tj → {
                            : s tname ( json_str_data tj )
                            ? != ( nurl_str_eq tname `text_delta` ) 0 {
                                : ?Json text_j ( json_obj_get d `text` )
                                ?? text_j {
                                    T tx → {
                                        : String out ( string_from ( json_str_data tx ) )
                                        ( json_free j )
                                        ^ @ ?String { T out }
                                    }
                                    F → {}
                                }
                            } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// `content_block_delta` SSE frame whose payload carries
// `delta.type == "input_json_delta"` with the next slice of the
// streamed `tool_use.input` JSON. Returns the partial JSON in an owned
// String (the caller concatenates these across frames and finally
// json_parses the assembled string). None for any other event shape.
//
// Symmetric to `claude_stream_event_text_delta` but for the tool-use
// stream — the missing half that turns NURL's existing streaming
// surface into a complete production chat-with-tools UX.
@ claude_stream_event_input_json_delta SseEvent ev → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `content_block_delta` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json delta ( json_obj_get j `delta` )
            ?? delta {
                T d → {
                    : ?Json typ ( json_obj_get d `type` )
                    ?? typ {
                        T tj → {
                            : s tname ( json_str_data tj )
                            ? != ( nurl_str_eq tname `input_json_delta` ) 0 {
                                : ?Json pjf ( json_obj_get d `partial_json` )
                                ?? pjf {
                                    T pjs → {
                                        : String out ( string_from ( json_str_data pjs ) )
                                        ( json_free j )
                                        ^ @ ?String { T out }
                                    }
                                    F → {}
                                }
                            } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// Block index for `content_block_start` / `content_block_delta` /
// `content_block_stop` frames. None for other event types or malformed
// frames. Anthropic streams interleave blocks (text + several tool_use)
// at distinct indices, so callers keep a per-index state map.
@ claude_stream_event_index SseEvent ev → ?i {
    : s en ( string_data . ev name )
    : i ea ( nurl_str_eq en `content_block_start` )
    : i eb ( nurl_str_eq en `content_block_delta` )
    : i ec ( nurl_str_eq en `content_block_stop` )
    ? & == ea 0 & == eb 0 == ec 0 {
        ^ @ ?i { F 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json idx ( json_obj_get j `index` )
            ?? idx {
                T ij → {
                    : ?i n ( json_num_as_i ij )
                    ?? n {
                        T x → {
                            ( json_free j )
                            ^ @ ?i { T x }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?i { F 0 }
}

// `content_block_start.content_block.type` — typically "text" or
// "tool_use" (also "thinking" when extended thinking is enabled).
// Owned String, or None for non-`content_block_start` events.
@ claude_stream_event_block_kind SseEvent ev → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `content_block_start` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json cb ( json_obj_get j `content_block` )
            ?? cb {
                T cbj → {
                    : ?Json typ ( json_obj_get cbj `type` )
                    ?? typ {
                        T tj → {
                            : String out ( string_from ( json_str_data tj ) )
                            ( json_free j )
                            ^ @ ?String { T out }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// Internal: extract the named string field from
// `content_block_start.content_block` when content_block.type == "tool_use".
// Returns owned String, or None when the event is the wrong kind, the
// content_block isn't a tool_use, or the field is missing.
@ __claude_stream_tool_use_field SseEvent ev s field → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `content_block_start` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json cb ( json_obj_get j `content_block` )
            ?? cb {
                T cbj → {
                    : ?Json typ ( json_obj_get cbj `type` )
                    ?? typ {
                        T tj → {
                            : s tname ( json_str_data tj )
                            ? != ( nurl_str_eq tname `tool_use` ) 0 {
                                : ?Json fj ( json_obj_get cbj field )
                                ?? fj {
                                    T fjs → {
                                        : String out ( string_from ( json_str_data fjs ) )
                                        ( json_free j )
                                        ^ @ ?String { T out }
                                    }
                                    F → {}
                                }
                            } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// Tool-use id from a `content_block_start` frame whose content_block is
// a tool_use block. Owned String, or None for any other shape.
@ claude_stream_event_tool_use_id SseEvent ev → ?String {
    ^ ( __claude_stream_tool_use_field ev `id` )
}

// Tool-use name from a `content_block_start` frame whose content_block
// is a tool_use block. Owned String, or None for any other shape.
@ claude_stream_event_tool_use_name SseEvent ev → ?String {
    ^ ( __claude_stream_tool_use_field ev `name` )
}

// `message_delta.delta.stop_reason` — finalised on the second-to-last
// frame of a stream. Common values: "end_turn", "tool_use",
// "max_tokens", "stop_sequence". Owned String, or None for other event
// kinds. Distinct from the synchronous response's `stop_reason` field
// because in streaming mode the value lives on the message_delta
// envelope rather than the top-level response object.
@ claude_stream_event_stop_reason SseEvent ev → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `message_delta` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json delta ( json_obj_get j `delta` )
            ?? delta {
                T d → {
                    : ?Json sr ( json_obj_get d `stop_reason` )
                    ?? sr {
                        T srj → {
                            : String out ( string_from ( json_str_data srj ) )
                            ( json_free j )
                            ^ @ ?String { T out }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// Internal: extract `error.<field>` for streaming `error` frames.
@ __claude_stream_error_field SseEvent ev s field → ?String {
    : s en ( string_data . ev name )
    ? == ( nurl_str_eq en `error` ) 0 {
        ^ @ ?String { F # String 0 }
    } {}
    : !Json JsonError pj ( json_parse ( string_data . ev data ) )
    ?? pj {
        T j → {
            : ?Json err ( json_obj_get j `error` )
            ?? err {
                T ej → {
                    : ?Json fj ( json_obj_get ej field )
                    ?? fj {
                        T fjs → {
                            : String out ( string_from ( json_str_data fjs ) )
                            ( json_free j )
                            ^ @ ?String { T out }
                        }
                        F → {}
                    }
                }
                F → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ^ @ ?String { F # String 0 }
}

// Streaming `error` event — `error.type` (e.g. "overloaded_error",
// "rate_limit_error"). Owned String, or None for non-error events.
@ claude_stream_event_error_type SseEvent ev → ?String {
    ^ ( __claude_stream_error_field ev `type` )
}

// Streaming `error` event — `error.message` (human-readable text).
// Owned String, or None for non-error events.
@ claude_stream_event_error_message SseEvent ev → ?String {
    ^ ( __claude_stream_error_field ev `message` )
}

// ── Public: single-turn convenience wrapper ─────────────────────────
//
// Thin shim over `claude_messages_full` that builds a one-message
// conversation [{role:"user", content:user_text}] with no tools.
@ claude_messages s api_key s model s system_prompt s user_text i max_tokens
→ !Json ClaudeErr {
    : ( Vec Json ) msgs ( vec_new [Json] )
    ( vec_push [Json] msgs ( claude_msg_user_text user_text ) )
    : ( Vec Json ) tools ( vec_new [Json] )

    : !Json ClaudeErr r
    ( claude_messages_full api_key model system_prompt msgs tools `` max_tokens )

    : ( @ v Json ) drop_json \ Json e → v { ( json_free e ) }
    ( vec_free_with [Json] msgs drop_json )
    ( vec_free_with [Json] tools drop_json )
    ^ r
}

// ── Response inspection ─────────────────────────────────────────────

// Walk the `content` array and return the `text` field of the first
// `{type:"text"}` block. Returns "" when the response holds only
// non-text blocks (e.g. tool_use), or when shape doesn't match.
@ claude_text Json r → s {
    : ?Json content ( json_obj_get r `content` )
    ?? content {
        T arr → {
            : i n ( json_arr_len arr )
            : ~ i k 0
            ~ < k n {
                : ?Json item ( json_arr_get arr k )
                ?? item {
                    T b → {
                        : ?Json typ ( json_obj_get b `type` )
                        ?? typ {
                            T tj → {
                                : s tname ( json_str_data tj )
                                ? != ( nurl_str_eq tname `text` ) 0 {
                                    : ?Json tx ( json_obj_get b `text` )
                                    ?? tx {
                                        T tjv → { ^ ( json_str_data tjv ) }
                                        F → {}
                                    }
                                } {}
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
    ^ ``
}

@ claude_stop_reason Json r → s {
    : ?Json sr ( json_obj_get r `stop_reason` )
    ?? sr {
        T j → { ^ ( json_str_data j ) }
        F → { ^ `` }
    }
    ^ ``
}

@ claude_model Json r → s {
    : ?Json m ( json_obj_get r `model` )
    ?? m {
        T j → { ^ ( json_str_data j ) }
        F → { ^ `` }
    }
    ^ ``
}

@ __claude_usage_int Json r s field → i {
    : ?Json u ( json_obj_get r `usage` )
    ?? u {
        T uo → {
            : ?Json it ( json_obj_get uo field )
            ?? it {
                T j → {
                    : ?i n ( json_num_as_i j )
                    ?? n {
                        T x → { ^ x }
                        F → { ^ 0 }
                    }
                }
                F → { ^ 0 }
            }
        }
        F → { ^ 0 }
    }
    ^ 0
}

@ claude_input_tokens Json r → i {
    ^ ( __claude_usage_int r `input_tokens` )
}

@ claude_output_tokens Json r → i {
    ^ ( __claude_usage_int r `output_tokens` )
}

// Tokens written into the prompt cache on this call. Non-zero only when
// at least one cache_control breakpoint was sent and the prefix wasn't
// already cached. Charged at full price (no discount on creation).
@ claude_cache_creation_tokens Json r → i {
    ^ ( __claude_usage_int r `cache_creation_input_tokens` )
}

// Tokens served from the prompt cache on this call. Charged at ~10% of
// the normal input rate — the savings signal you check for caching wins.
@ claude_cache_read_tokens Json r → i {
    ^ ( __claude_usage_int r `cache_read_input_tokens` )
}

@ claude_response_free Json r → v {
    ( json_free r )
}

// ── Tool-use extractors ─────────────────────────────────────────────

// True iff stop_reason == "tool_use" — the canonical signal that the
// assistant wants you to run one or more tools and feed the results
// back as the next message.
@ claude_has_tool_use Json r → b {
    : s sr ( claude_stop_reason r )
    ^ != ( nurl_str_eq sr `tool_use` ) 0
}

// Walk the response's content array and return owned CLONES of every
// {type:"tool_use"} block. The Vec is owned; free with:
//
//     ( vec_free_with [Json] tcs json_free )
//
// Cloning lets the caller free the response Json early without
// invalidating the tool_use handles.
@ claude_tool_calls Json r → ( Vec Json ) {
    : ( Vec Json ) out ( vec_new [Json] )
    : ?Json content ( json_obj_get r `content` )
    ?? content {
        T arr → {
            : i n ( json_arr_len arr )
            : ~ i k 0
            ~ < k n {
                : ?Json item ( json_arr_get arr k )
                ?? item {
                    T b → {
                        : ?Json typ ( json_obj_get b `type` )
                        ?? typ {
                            T tj → {
                                : s tname ( json_str_data tj )
                                ? != ( nurl_str_eq tname `tool_use` ) 0 {
                                    ( vec_push [Json] out ( json_clone b ) )
                                } {}
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
    ^ out
}

// Borrowed view of a tool_use block's "id" field. Returns "" if `tu`
// is not a tool_use block or the field is missing.
@ claude_tool_use_id Json tu → s {
    : ?Json id ( json_obj_get tu `id` )
    ?? id {
        T j → { ^ ( json_str_data j ) }
        F → { ^ `` }
    }
    ^ ``
}

// Borrowed view of a tool_use block's "name" field.
@ claude_tool_use_name Json tu → s {
    : ?Json n ( json_obj_get tu `name` )
    ?? n {
        T j → { ^ ( json_str_data j ) }
        F → { ^ `` }
    }
    ^ ``
}

// Borrowed view of a tool_use block's "input" field (an object Json).
// None when `tu` is not a tool_use block or "input" is missing. Use
// `json_clone` if you need it to outlive `tu`.
@ claude_tool_use_input Json tu → ?Json {
    ^ ( json_obj_get tu `input` )
}
