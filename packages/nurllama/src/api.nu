// packages/nurllama/src/api.nu — an ollama-compatible and an
// OpenAI-compatible HTTP API, on one server.
//
// Speaks enough of ollama's and of OpenAI's wire protocols that existing
// clients of either work unchanged. ollama's:
//
//   POST /api/generate   { model, prompt, stream?, options? }
//   POST /api/chat       { model, messages[{role,content}], stream?, options? }
//        → NDJSON: one JSON object per token while generating, then a
//          final object with done:true (+ token counts). stream:false
//          returns a single aggregated object.
//   GET  /api/tags       the local store, as ollama's model list
//   POST /api/show       { model } → the model's metadata
//   GET  /                "nurllama is running"
//
// OpenAI's:
//
//   POST /v1/chat/completions  { model, messages, stream?, max_tokens?,
//        temperature?, top_p?, seed?, stop?, stream_options? }
//        → one chat.completion, or server-sent chat.completion.chunk
//          events ending in `data: [DONE]`
//   POST /v1/completions       { model, prompt, … } → text_completion
//   GET  /v1/models            the local store (+ the default model)
//   GET  /v1/models/:id
//
// Both protocols run the same generation loop (__api_generate). A server
// started with a token answers every data route — /api/*, /v1/*, /web/* —
// only with `Authorization: Bearer <token>`.
//
// Streaming rides the http package's stream hook (http_app_stream):
// the handler owns the TcpConn and writes chunked NDJSON itself, so a
// token reaches the client the moment it is decoded.
//
// One model is resident at a time (LRU of one): a request naming a
// different model swaps it in. Generation is serialised — the decode
// loop owns the device — which is honest for a single-GPU host; the
// server is single-worker so that serialisation is structural rather
// than a lock.

$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/ext/json.nu`
$ `deps/http/src/http.nu`
$ `deps/gguf/src/gguf.nu`
$ `tokenizer.nu`
$ `model.nu`
$ `diffuse.nu`
$ `sample.nu`
$ `chat.nu`
$ `store.nu`
$ `config.nu`
$ `history.nu`
$ `webui.nu`
$ `stdlib/ext/uuid.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/utf8.nu`

// The resident model + the store root, reachable from the handlers. A
// mutable `s` global owns the string it is given (docs/MEMORY.md §1): an
// assignment releases the one it replaces, and the last is released when
// the program ends — so each setter is the assignment of an owned copy.
@ __api_llm_blank → ( Locked ? Llm ) { ^ ( locked_new [? Llm] @ ?Llm { F } ) }

: ( Locked ? Llm ) g_api_llm ( __api_llm_blank )  // the resident model (F = none)
: ~ i g_api_style 0

// Config for the wizard-started server (`nurllama start`): the default
// model the web UI chats with and the bearer token (empty = open access).
// The conversation history is history.nu's, opened once at startup.
: ~ i g_api_auth 0

// The server's text settings: the resident model's name (it changes as
// requests load and unload models), the model store's root, and the
// wizard's default model, bearer token and --weights file.
// Handlers run on many threads, so they live in a Locked struct and are
// read as copies; as plain string globals, a model switch freed the name
// another request was comparing against.
: ApiCfg {
    String name
    String root
    String token
    String model
    String weights  // serve --weights (empty = none)
}

@ __api_cfg0 → ( Locked ApiCfg ) {
    ^ ( locked_new [ApiCfg] @ ApiCfg { ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) } )
}

: ( Locked ApiCfg ) g_api_cfg ( __api_cfg0 )

// Setting `k` (0 name, 1 root, 2 token, 3 model, 5 weights).
@ __api_cfg_set i k s v → v {
    : ~ ApiCfg c ( locked_take [ApiCfg] g_api_cfg )
    ? == k 0 { = . c name ( string_from v ) } {}
    ? == k 1 { = . c root ( string_from v ) } {}
    ? == k 2 { = . c token ( string_from v ) } {}
    ? == k 3 { = . c model ( string_from v ) } {}
    ? == k 5 { = . c weights ( string_from v ) } {}
    ( locked_restore [ApiCfg] g_api_cfg c )
}

// A copy of setting `k`.
@ __api_cfg_get i k → String {
    : ~ ApiCfg c ( locked_take [ApiCfg] g_api_cfg )
    : ~ String r ( string_new )
    ? == k 0 { = r ( string_from ( string_data . c name ) ) } {}
    ? == k 1 { = r ( string_from ( string_data . c root ) ) } {}
    ? == k 2 { = r ( string_from ( string_data . c token ) ) } {}
    ? == k 3 { = r ( string_from ( string_data . c model ) ) } {}
    ? == k 5 { = r ( string_from ( string_data . c weights ) ) } {}
    ( locked_restore [ApiCfg] g_api_cfg c )
    ^ r
}

@ __api_cfg_name → String { ^ ( __api_cfg_get 0 ) }

@ __api_cfg_root → String { ^ ( __api_cfg_get 1 ) }

@ __api_cfg_token → String { ^ ( __api_cfg_get 2 ) }

@ __api_cfg_model → String { ^ ( __api_cfg_get 3 ) }

@ __api_cfg_weights → String { ^ ( __api_cfg_get 5 ) }

@ __api_set_token s tok → v { ( __api_cfg_set 2 tok ) }

@ __api_set_model s m → v { ( __api_cfg_set 3 m ) }

@ __api_set_name s name → v { ( __api_cfg_set 0 name ) }

@ api_set_root String root → v { ( __api_cfg_set 1 ( string_data root ) ) }

@ __api_unload → v {
    ( locked_set [? Llm] g_api_llm @ ?Llm { F } )
    ( __api_cfg_set 0 `` )
}

// serve --weights: when set, every model this server opens takes its
// tensors from this safetensors file instead of the GGUF's own (the GGUF
// still supplies the hyperparameters and the tokenizer) — the API twin of
// `run --weights`, for serving a finetuned/merged checkpoint. Empty = none.
@ api_set_weights s w → v { ( __api_cfg_set 5 w ) }

// One more owner of the resident model (a handler runs after __api_ensure
// loaded it).
@ __api_llm → Llm {
    : ?Llm cur ( locked_take [? Llm] g_api_llm )
    : ~ ? Llm out @ ?Llm { F }
    ?? cur { T m → { = out @ ?Llm { T ( Llm_share m ) } } F → {} }
    ( locked_restore [? Llm] g_api_llm cur )
    ?? out {
        T m → { ^ m }
        F → { ( nurl_panic `nurllama: no model is resident` ) }
    }
}

@ __api_resident → b {
    : ?Llm cur ( locked_take [? Llm] g_api_llm )
    : b r ( opt_is_some [Llm] cur )
    ( locked_restore [? Llm] g_api_llm cur )
    ^ r
}

// Load `name` unless it is already resident. Empty error = success.
@ __api_ensure s name → String {
    ? & ( __api_resident ) != 0 ( nurl_str_eq ( string_data ( __api_cfg_name ) ) name ) { ^ ( string_new ) } {}
    ( __api_unload )
    : String rootS ( __api_cfg_root )
    : ?String rp ( nl_resolve rootS name )
    ?? rp {
        T path → {
            // the chat style comes from the model's own metadata
            : ~ i style CHAT_PLAIN
            ?? ( model_meta ( string_data path ) ) {
                T gg → {
                    = style ( chat_style_of gg )
                }
                F _e → {}
            }
            : !Llm String lr ? > ( nurl_str_len ( string_data ( __api_cfg_weights ) ) ) 0
            ( llm_open_st ( string_data path ) ( string_data ( __api_cfg_weights ) ) 0 )
            ( llm_open ( string_data path ) 0 )
            ?? lr {
                T m → {
                    ( locked_set [? Llm] g_api_llm @ ?Llm { T ( Llm_share m ) } )
                    = g_api_style style
                    ( __api_set_name name )
                    ^ ( string_new )
                }
                F e → { ^ e }
            }
        }
        F → {
            : String msg ( string_from `model '` )
            ( string_push_str msg name )
            ( string_push_str msg `' not found — not a local file and not a stored name (nurllama list; nurllama pull hf.co/ORG/REPO/FILE.gguf)` )
            ^ msg
        }
    }
}

// ── request-body helpers ────────────────────────────────────────────

@ __api_body_json HttpRequest req → !Json JsonError {
    : String txt ( bytes_to_str . req body )
    : !Json JsonError r ( json_parse ( string_data txt ) )
    ^ r
}

@ __api_str Json j s key s def → String {
    ?? ( json_obj_get j key ) {
        T v → { ^ ( string_from ( json_str_data v ) ) }
        F → { ^ ( string_from def ) }
    }
}

@ __api_bool Json j s key b def → b {
    ?? ( json_obj_get j key ) {
        T v → { ^ ? ( json_is_bool v ) ( json_bool_val v ) def }
        F → { ^ def }
    }
}

// options.<key>, ollama's nesting
@ __api_opt_i Json j s key i def → i {
    ?? ( json_obj_get j `options` ) {
        T o → {
            ?? ( json_obj_get o key ) {
                T v → {
                    ?? ( json_num_as_i v ) {
                        T n → { ^ n }
                        F → { ^ def }
                    }
                }
                F → { ^ def }
            }
        }
        F → { ^ def }
    }
}

@ __api_opt_f Json j s key f def → f {
    ?? ( json_obj_get j `options` ) {
        T o → {
            ?? ( json_obj_get o key ) {
                T v → {
                    ?? ( json_num_as_f v ) {
                        T x → { ^ x }
                        F → { ^ def }
                    }
                }
                F → { ^ def }
            }
        }
        F → { ^ def }
    }
}

// ── NDJSON frames ───────────────────────────────────────────────────

// A chat frame's piece is the answer's, or with `thinking` the reasoning's
// (ollama's message.thinking).
@ __api_frame_token s model s field s piece b thinking → String {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `model` ( json_str_lit model ) )
    ? ( nurl_str_eq field `response` ) {
        : b _2 ( json_obj_set j `response` ( json_str_lit piece ) )
    } {
        : Json msg ( json_obj_new )
        : b _3 ( json_obj_set msg `role` ( json_str_lit `assistant` ) )
        : b _4 ( json_obj_set msg `content` ( json_str_lit ? thinking `` piece ) )
        ? thinking { : b _t ( json_obj_set msg `thinking` ( json_str_lit piece ) ) } {}
        : b _5 ( json_obj_set j `message` msg )
    }
    : b _6 ( json_obj_set j `done` ( json_bool F ) )
    : String out ( json_stringify j )
    ( string_push_char out 10 )
    ^ out
}

// `thinking`: the whole reasoning, on a non-streamed chat reply that had one.
@ __api_frame_done s model s field i nprompt i neval b with_text s finish s full b has_think s thinking → String {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `model` ( json_str_lit model ) )
    ? ( nurl_str_eq field `response` ) {
        : b _2 ( json_obj_set j `response` ( json_str_lit ? with_text full `` ) )
    } {
        : Json msg ( json_obj_new )
        : b _3 ( json_obj_set msg `role` ( json_str_lit `assistant` ) )
        : b _4 ( json_obj_set msg `content` ( json_str_lit ? with_text full `` ) )
        ? & with_text has_think { : b _t ( json_obj_set msg `thinking` ( json_str_lit thinking ) ) } {}
        : b _5 ( json_obj_set j `message` msg )
    }
    : b _6 ( json_obj_set j `done` ( json_bool T ) )
    : b _7 ( json_obj_set j `done_reason` ( json_str_lit finish ) )
    : b _8 ( json_obj_set j `prompt_eval_count` ( json_int nprompt ) )
    : b _9 ( json_obj_set j `eval_count` ( json_int neval ) )
    : String out ( json_stringify j )
    ( string_push_char out 10 )
    ^ out
}

@ __api_write_str TcpConn c String s → b {
    : ( Vec u ) b2 ( bytes_from_str ( string_data s ) )
    : !v NetErr r ( response_write_chunk c b2 )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ^ ok
}

@ __api_begin_ndjson TcpConn c → b {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Content-Type` `application/x-ndjson` ) )
    : !v NetErr r ( response_begin_chunked c 200 hs )
    : ~ b ok T
    ?? r { T _ → {} F _ → { = ok F } }
    ^ ok
}

// ── the wire protocols ──────────────────────────────────────────────
//
// ONE generation loop (__api_generate) serves every endpoint; what differs
// is only how its text goes out:
//   API_OLLAMA_GEN   POST /api/generate          NDJSON frames, `response`
//   API_OLLAMA_CHAT  POST /api/chat              NDJSON frames, `message`
//   API_OAI_CHAT     POST /v1/chat/completions   SSE chat.completion.chunk
//                                                events, or one chat.completion
//   API_OAI_TEXT     POST /v1/completions        SSE / one text_completion
// so a stop sequence, a chat dialect's terminator, a token that ends inside
// a UTF-8 character or the context running out behave the same whichever
// protocol asked.
: i API_OLLAMA_GEN 0
: i API_OLLAMA_CHAT 1
: i API_OAI_CHAT 2
: i API_OAI_TEXT 3

@ __api_is_oai i proto → b { ^ >= proto API_OAI_CHAT }

// One generation request, whatever protocol it came in.
: GenReq {
    i proto
    String model
    String prompt
    b stream
    i npredict  // tokens at most; ≤ 0 = until the turn or the context ends
    f temp
    i topk  // ≤ 0: no top-k filter
    f topp
    i seed
    ( Vec String ) stops  // generation ends at the first; it is not emitted
    b usage  // OpenAI stream_options.include_usage
    String id  // OpenAI: chatcmpl-… / cmpl-…
    i created  // OpenAI: unix seconds
    // A chat reply's reasoning goes apart from its answer (__api_think_split);
    // `think_open`: the prompt leaves the reply inside a <think> block
    b split
    b think_open
}

// An error in the asking protocol's shape — ollama's {"error": msg}, or
// OpenAI's {"error": {message, type, param, code}} (`code` may be empty).
@ __api_error_body i proto i status s msg s code → String {
    : Json j ( json_obj_new )
    ? ( __api_is_oai proto ) {
        : Json e ( json_obj_new )
        : b _1 ( json_obj_set e `message` ( json_str_lit msg ) )
        : s ty ? == status 401 `authentication_error` ? >= status 500 `server_error` `invalid_request_error`
        : b _2 ( json_obj_set e `type` ( json_str_lit ty ) )
        : b _3 ( json_obj_set e `param` ( json_null ) )
        : b _4 ( json_obj_set e `code` ? > ( nurl_str_len code ) 0 ( json_str_lit code ) ( json_null ) )
        : b _5 ( json_obj_set j `error` e )
    } {
        : b _6 ( json_obj_set j `error` ( json_str_lit msg ) )
    }
    : String txt ( json_stringify j )
    ( string_push_char txt 10 )
    ^ txt
}

@ __api_error_chunked TcpConn c i proto i status s msg s code → b {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Content-Type` `application/json` ) )
    : !v NetErr r ( response_begin_chunked c status hs )
    ?? r { T _ → {} F _ → { ^ T } }
    : b _w ( __api_write_str c ( __api_error_body proto status msg code ) )
    : !v NetErr _e ( response_end_chunked c )
    ^ T
}

// The same error as a plain response (the non-streaming routes).
@ __api_error_resp i proto i status s msg s code → HttpResponse {
    : HttpResponse resp ( response_new status )
    ( response_set_header resp `Content-Type` `application/json` )
    ( response_set_body_str resp ( string_data ( __api_error_body proto status msg code ) ) )
    ^ resp
}

// ── OpenAI frames ───────────────────────────────────────────────────

// The fields every OpenAI completion object starts with.
@ __oai_head GenReq rq s object → Json {
    : Json j ( json_obj_new )
    : b _1 ( json_obj_set j `id` ( json_str_lit ( string_data . rq id ) ) )
    : b _2 ( json_obj_set j `object` ( json_str_lit object ) )
    : b _3 ( json_obj_set j `created` ( json_int . rq created ) )
    : b _4 ( json_obj_set j `model` ( json_str_lit ( string_data . rq model ) ) )
    ^ j
}

@ __oai_usage i nprompt i neval → Json {
    : Json u ( json_obj_new )
    : b _1 ( json_obj_set u `prompt_tokens` ( json_int nprompt ) )
    : b _2 ( json_obj_set u `completion_tokens` ( json_int neval ) )
    : b _3 ( json_obj_set u `total_tokens` ( json_int + nprompt neval ) )
    ^ u
}

// `data: <obj>\n\n` — one server-sent event.
@ __oai_event Json j → String {
    : String out ( string_from `data: ` )
    : String txt ( json_stringify j )
    ( string_push_str out ( string_data txt ) )
    ( string_push_str out `\n\n` )
    ^ out
}

// One streamed chunk: `text` as the delta (chat) or the text (completions);
// `role` puts the assistant role on a chat delta (the first chunk); a
// non-empty `finish` closes the choice (its delta is then empty);
// `reasoning`: the text is the reasoning's (delta.reasoning_content, the
// field DeepSeek's API, vLLM and llama.cpp's server use).
@ __oai_chunk GenReq rq s text b role s finish b reasoning → String {
    : b chat == . rq proto API_OAI_CHAT
    : Json j ( __oai_head rq ? chat `chat.completion.chunk` `text_completion` )
    : Json ch ( json_obj_new )
    : b _1 ( json_obj_set ch `index` ( json_int 0 ) )
    : b fin > ( nurl_str_len finish ) 0
    ? chat {
        : Json d ( json_obj_new )
        ? role { : b _2 ( json_obj_set d `role` ( json_str_lit `assistant` ) ) } {}
        ? fin {} { : b _3 ( json_obj_set d ? reasoning `reasoning_content` `content` ( json_str_lit text ) ) }
        : b _4 ( json_obj_set ch `delta` d )
    } {
        : b _5 ( json_obj_set ch `text` ( json_str_lit text ) )
    }
    : b _6 ( json_obj_set ch `logprobs` ( json_null ) )
    : b _7 ( json_obj_set ch `finish_reason` ? fin ( json_str_lit finish ) ( json_null ) )
    : Json arr ( json_arr_new )
    : b _8 ( json_arr_push arr ch )
    : b _9 ( json_obj_set j `choices` arr )
    // with include_usage every chunk carries `usage: null`; the counts
    // come in a chunk of their own at the end
    ? . rq usage { : b _a ( json_obj_set j `usage` ( json_null ) ) } {}
    ^ ( __oai_event j )
}

// ── the generation loop ─────────────────────────────────────────────

// Where the first stop sequence starts in `full` at or after `from`, or -1.
@ __api_stop_at String full i from ( Vec String ) stops → i {
    : String rest ( string_substr full from - ( string_len full ) from )
    : ~ i best -1
    : ~ i k 0
    ~ < k ( vec_len [String] stops ) {
        : s sp ( string_data ( vec_at [String] stops k ) )
        ? > ( nurl_str_len sp ) 0 {
            : i at ( nurl_str_find ( string_data rest ) sp )
            ? & >= at 0 | < best 0 < at best { = best at } {}
        } {}
        = k + k 1
    }
    ^ ? < best 0 -1 + from best
}

// Where a chat reply's reasoning and answer lie in its text so far: the
// reasoning is full[rs, re), the answer full[cs …) — cs = -1 while the
// reasoning is still open. `has`: there is reasoning at all; `undecided`:
// the text so far (whitespace, or the start of `<think>`) may still open a
// block, and nothing of it can be sent yet. A reply is inside a block from
// its first byte when the prompt left it there (`open` — GLM's templates
// end the prompt with <think>), or when it opens one itself, first thing;
// the block closes at the first `</think>`. Without `split` — a raw
// completion — all of it is answer. A pure function of the text: the
// stream and the whole reply cut it the same way.
: ThinkSplit {
    i rs
    i re
    i cs
    b has
    b undecided
}

@ __api_think_split String full b split b open → ThinkSplit {
    : i n ( string_len full )
    : ThinkSplit none @ ThinkSplit { 0 0 0 F F }
    ? split {} { ^ none }
    : ~ i rs 0
    ? open {} {
        : ~ i lead 0
        ~ & < lead n != ( is_space ( string_get full lead ) ) 0 { = lead + lead 1 }
        : String tail ( string_substr full lead - n lead )
        ? != 0 ( nurl_str_starts ( string_data tail ) `<think>` ) { = rs + lead 7 } {
            ? != 0 ( nurl_str_starts `<think>` ( string_data tail ) ) { ^ @ ThinkSplit { 0 0 -1 F T } } {}
            ^ none
        }
    }
    : String body ( string_substr full rs - n rs )
    : i e ( nurl_str_find ( string_data body ) `</think>` )
    ? < e 0 { ^ @ ThinkSplit { rs n -1 T F } } {}
    ^ @ ThinkSplit { rs + rs e + + rs e 8 T F }
}

// How many bytes at the end of `full` (past `from`, which is already out)
// must wait for the next token before they can be sent: a UTF-8 character
// the last token ended inside (byte-level BPE splits CJK and emoji across
// tokens, and half a character is not text a client can show), or the
// start of a stop sequence the next token may complete.
@ __api_hold String full i from ( Vec String ) stops → i {
    : i n ( string_len full )
    : ~ i hold 0
    // an unfinished UTF-8 sequence: its lead byte, and how long it says it is
    : ~ i p - n 1
    : ~ i back 0
    ~ & & >= p from < back 4 == & ( string_get full p ) 192 128 {
        = p - p 1
        = back + back 1
    }
    ? >= p from {
        : i lead ( string_get full p )
        : i need ? < lead 128 1 ? < lead 224 2 ? < lead 240 3 4
        ? < - n p need { = hold - n p } {}
    } {}
    // a proper prefix of a stop sequence
    : ~ i k 0
    ~ < k ( vec_len [String] stops ) {
        : String sp ( string_clone ( vec_at [String] stops k ) )
        : ~ i len - ( string_len sp ) 1
        ? > len - n from { = len - n from } {}
        ~ > len hold {
            : String pre ( string_substr sp 0 len )
            ? ( string_ends_with full ( string_data pre ) ) {
                = hold len
                = len 0
            } { = len - len 1 }
        }
        = k + k 1
    }
    ^ hold
}

// Generated bytes as text. A model's tokens are bytes, and nothing makes
// a sequence of them UTF-8 — a byte-level vocabulary can end a character
// and start a wrong one — but both APIs hand out text, inside JSON, which
// must be UTF-8 (RFC 8259 §8.1): every malformed byte becomes U+FFFD (the
// validating decoder's own recovery), well-formed text passes unchanged.
// A streamed piece never ends inside a character (__api_hold), so the
// pieces come out exactly as the whole text does.
@ __api_utf8 String raw → String {
    : ( Slice u ) v ( string_bytes raw )
    : i n ( slice_len [u] v )
    : String out ( string_with_cap n )
    : ~ i p 0
    ~ < p n {
        : Utf8Dec d ( utf8_decode_at v p )
        ( utf8_push_cp out . d cp )
        = p + p ? > . d width 0 . d width 1
    }
    ^ out
}

// Stream full[from, upto) as one piece in the request's protocol — of the
// reasoning, or of the answer.
@ __api_send TcpConn c GenReq rq String full i from i upto b reasoning → b {
    : String piece ( __api_utf8 ( string_substr full from - upto from ) )
    ? ( __api_is_oai . rq proto ) {
        ^ ( __api_write_str c ( __oai_chunk rq ( string_data piece ) F `` reasoning ) )
    } {}
    : s field ? == . rq proto API_OLLAMA_GEN `response` `message`
    ^ ( __api_write_str c ( __api_frame_token ( string_data . rq model ) field ( string_data piece ) reasoning ) )
}

// Append one token's text to the reply `full`; T when a stop sequence in
// the answer (never in the reasoning) has ended it — cut off at the stop.
@ _api_take inout String full s piece b split b open ( Vec String ) stops → b {
    ( string_push_str full piece )
    : i ans . ( __api_think_split full split open ) cs
    ? < ans 0 { ^ F } {}
    : i cut ( __api_stop_at full ans stops )
    ? < cut 0 { ^ F } {}
    = full ( string_substr full 0 cut )
    ^ T
}

// What of `full` can go out now and can no longer change: reasoning
// full[rfrom, rupto) and answer full[cfrom, cupto), each from where the last
// send of it stopped (rsent, csent; -1 = nothing yet — both are moved on).
// While a reasoning block is open, a possible start of `</think>` is held
// back; in the answer, a possible start of a stop sequence; in both, a half
// UTF-8 character. `last`: the reply is over, nothing is held.
: Ready {
    i rfrom
    i rupto
    i cfrom
    i cupto
}

@ _api_ready String full b split b open ( Vec String ) stops b last inout i rsent inout i csent → Ready {
    : ~ Ready r @ Ready { 0 0 0 0 }
    : ThinkSplit ts ( __api_think_split full split open )
    ? & . ts undecided ! last { ^ r } {}
    : i n ( string_len full )
    ? . ts has {
        ? < rsent 0 { = rsent . ts rs } {}
        : ~ i rup . ts re
        ? & < . ts cs 0 ! last {
            : ( Vec String ) close ( vec_new [String] )
            ( vec_push [String] close ( string_from `</think>` ) )
            = rup - n ( __api_hold full rsent close )
        } {}
        ? > rup rsent {
            = . r rfrom rsent
            = . r rupto rup
            = rsent rup
        } {}
    } {}
    // (a reply that ends while it might still have opened a block: answer)
    : i cs ? . ts undecided 0 . ts cs
    ? >= cs 0 {
        ? < csent 0 { = csent cs } {}
        : i cup ? last n - n ( __api_hold full csent stops )
        ? > cup csent {
            = . r cfrom csent
            = . r cupto cup
            = csent cup
        } {}
    } {}
    ^ r
}

// Send what _api_ready says can go: the reasoning's piece, then the answer's.
@ __api_flush TcpConn c GenReq rq String full b last inout i rsent inout i csent → b {
    : Ready r ( _api_ready full . rq split . rq think_open . rq stops last rsent csent )
    ? > . r rupto . r rfrom { ? ( __api_send c rq full . r rfrom . r rupto T ) {} { ^ F } } {}
    ? > . r cupto . r cfrom { ? ( __api_send c rq full . r cfrom . r cupto F ) {} { ^ F } } {}
    ^ T
}

// The finished reply's reasoning and answer, as one non-streamed reply
// gives them (has = it reasoned at all).
: Parts {
    b has
    String reasoning
    String answer
}

@ _api_parts String full b split b open → Parts {
    : ThinkSplit ts ( __api_think_split full split open )
    : i n ( string_len full )
    : i cs ? . ts undecided 0 . ts cs
    ^ @ Parts {
        . ts has
        ? . ts has ( string_substr full . ts rs - . ts re . ts rs ) ( string_new )
        ? >= cs 0 ( string_substr full cs - n cs ) ( string_new )
    }
}

// Open the response a streaming request is answered on. An OpenAI chat
// stream's first event carries the assistant role and no text.
@ __api_begin_stream TcpConn c GenReq rq → b {
    ? ( __api_is_oai . rq proto ) {
        : ( Vec Header ) hs ( vec_new [Header] )
        ( vec_push [Header] hs ( header_new `Content-Type` `text/event-stream` ) )
        ( vec_push [Header] hs ( header_new `Cache-Control` `no-cache` ) )
        : !v NetErr r ( response_begin_chunked c 200 hs )
        ?? r { T _ → {} F _ → { ^ F } }
        ? == . rq proto API_OAI_CHAT { ^ ( __api_write_str c ( __oai_chunk rq `` T `` F ) ) } {}
        ^ T
    } {}
    ^ ( __api_begin_ndjson c )
}

// Close a stream: ollama's done frame; OpenAI's closing chunk, the usage
// chunk when asked for, and `data: [DONE]`.
@ __api_end_stream TcpConn c GenReq rq s finish i nprompt i neval → v {
    ? ( __api_is_oai . rq proto ) {
        : b _1 ( __api_write_str c ( __oai_chunk rq `` F finish F ) )
        ? . rq usage {
            : Json j ( __oai_head rq ? == . rq proto API_OAI_CHAT `chat.completion.chunk` `text_completion` )
            : b _2 ( json_obj_set j `choices` ( json_arr_new ) )
            : b _3 ( json_obj_set j `usage` ( __oai_usage nprompt neval ) )
            : b _4 ( __api_write_str c ( __oai_event j ) )
        } {}
        : b _5 ( __api_write_str c ( string_from `data: [DONE]\n\n` ) )
    } {
        : s field ? == . rq proto API_OLLAMA_GEN `response` `message`
        : b _6 ( __api_write_str c ( __api_frame_done ( string_data . rq model ) field nprompt neval F finish `` F `` ) )
    }
    : !v NetErr _e ( response_end_chunked c )
}

// Answer a non-streaming request with the whole text at once: its answer,
// and its reasoning apart when it had one.
@ __api_reply_once TcpConn c GenReq rq s finish i nprompt i neval String raw → v {
    : Parts ts ( _api_parts raw . rq split . rq think_open )
    : String full ( __api_utf8 . ts answer )
    : String thinking ( __api_utf8 . ts reasoning )
    ? ( __api_is_oai . rq proto ) {
        : b chat == . rq proto API_OAI_CHAT
        : Json j ( __oai_head rq ? chat `chat.completion` `text_completion` )
        : Json ch ( json_obj_new )
        : b _1 ( json_obj_set ch `index` ( json_int 0 ) )
        ? chat {
            : Json msg ( json_obj_new )
            : b _2 ( json_obj_set msg `role` ( json_str_lit `assistant` ) )
            : b _3 ( json_obj_set msg `content` ( json_str_lit ( string_data full ) ) )
            ? . ts has { : b _r ( json_obj_set msg `reasoning_content` ( json_str_lit ( string_data thinking ) ) ) } {}
            : b _4 ( json_obj_set ch `message` msg )
        } {
            : b _5 ( json_obj_set ch `text` ( json_str_lit ( string_data full ) ) )
        }
        : b _6 ( json_obj_set ch `logprobs` ( json_null ) )
        : b _7 ( json_obj_set ch `finish_reason` ( json_str_lit finish ) )
        : Json arr ( json_arr_new )
        : b _8 ( json_arr_push arr ch )
        : b _9 ( json_obj_set j `choices` arr )
        : b _a ( json_obj_set j `usage` ( __oai_usage nprompt neval ) )
        : ( Vec Header ) hs ( vec_new [Header] )
        ( vec_push [Header] hs ( header_new `Content-Type` `application/json` ) )
        : !v NetErr r ( response_begin_chunked c 200 hs )
        ?? r { T _ → {} F _ → { ^ } }
        : String txt ( json_stringify j )
        ( string_push_char txt 10 )
        : b _w ( __api_write_str c txt )
        : !v NetErr _e ( response_end_chunked c )
        ^
    } {}
    ? ( __api_begin_ndjson c ) {} { ^ }
    : s field ? == . rq proto API_OLLAMA_GEN `response` `message`
    : b _w2 ( __api_write_str c ( __api_frame_done ( string_data . rq model ) field nprompt neval T finish ( string_data full ) . ts has ( string_data thinking ) ) )
    : !v NetErr _e2 ( response_end_chunked c )
}

// Generate for `rq` and answer it. Every token's text is appended to
// `full`; a stop sequence in the answer (not the reasoning) ends the
// generation and is cut off; while streaming, everything that can no
// longer change goes out at once (__api_flush). finish_reason is
// `stop` when the model ended its turn (end-of-sequence, its dialect's
// terminator) or a stop sequence matched, `length` when the token budget
// or the context ran out.
@ __api_generate TcpConn c GenReq rq → b {
    : Llm m ( __api_llm )
    : Tok t ( Tok_share ( llm_tok m ) )
    : ( Vec i ) ids ( tok_encode t ( string_data . rq prompt ) T )
    : i nprompt ( vec_len [i] ids )
    ? >= nprompt ( llm_n_ctx m ) {
        ^ ( __api_error_chunked c . rq proto 400 `prompt is longer than the model's context` `context_length_exceeded` )
    } {}
    : ~ i limit - ( llm_n_ctx m ) nprompt
    ? & > . rq npredict 0 < . rq npredict limit { = limit . rq npredict } {}
    ? . rq stream { ? ( __api_begin_stream c rq ) {} { ^ T } } {}

    : ~ String full ( string_new )
    : ~ i rsent -1
    : ~ i csent -1
    : ~ i produced 0
    : ~ b ended F
    : ~ b broken F
    // Diffusion model: the block-denoise loop produces the whole response
    // (src/diffuse.nu); its tokens then go through the same path as an
    // autoregressive model's, just all at once.
    : b diffusion ( llm_is_diffusion m )
    : Rng rng ( rng_seed . rq seed )
    : ~ ( Vec i ) gen ( vec_new [i] )
    ? diffusion { = gen ( dz_generate m ids limit 32 0.7 0.5 16 . rq temp rng ) } { ( llm_prefill m ids ) }
    : ~ i pos nprompt
    ~ & & ! ended ! broken ? diffusion < produced ( vec_len [i] gen ) < produced limit {
        : i nt ? diffusion ( vec_at [i] gen produced ) ( sample_next m rng . rq temp . rq topk . rq topp )
        ? & ! diffusion ( llm_is_eog m nt ) { = ended T } {
            : String piece ( bytes_to_str ( tok_piece t nt ) )
            // a chat dialect's terminator may arrive as plain text
            ? & ! diffusion ( chat_stop_matches g_api_style ( string_data piece ) ) { = ended T } {
                = produced + produced 1
                // a stop sequence ends the answer (never the reasoning)
                ? ( _api_take full ( string_data piece ) . rq split . rq think_open . rq stops ) { = ended T } {}
                ? . rq stream { ? ( __api_flush c rq full ended rsent csent ) {} { = broken T } } {}
                ? | | ended broken diffusion {} {
                    ( llm_eval m nt pos )
                    = pos + pos 1
                }
            }
        }
    }
    ? broken { ^ T } {}
    : s finish ? ended `stop` ? & diffusion < produced limit `stop` `length`
    ? . rq stream {
        // what was held back for a stop or a `</think>` that never came
        ? ( __api_flush c rq full T rsent csent ) {} { ^ T }
        ( __api_end_stream c rq finish nprompt produced )
    } {
        ( __api_reply_once c rq finish nprompt produced full )
    }
    ^ T
}

// ── request parsing ─────────────────────────────────────────────────

// A top-level number of the body (OpenAI puts its knobs there).
@ __api_num_i Json j s key i def → i {
    ?? ( json_obj_get j key ) {
        T v → { ?? ( json_num_as_i v ) { T n → { ^ n } F → { ^ def } } }
        F → { ^ def }
    }
}

@ __api_num_f Json j s key f def → f {
    ?? ( json_obj_get j key ) {
        T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F → { ^ def } } }
        F → { ^ def }
    }
}

// `stop`: one string or an array of them (OpenAI; ollama's options.stop).
@ __api_stops Json v inout ( Vec String ) out → v {
    ? ( json_is_str v ) { ( vec_push [String] out ( string_from ( json_str_data v ) ) ) ^ } {}
    ? ( json_is_arr v ) {
        : ~ i k 0
        ~ < k ( json_arr_len v ) {
            ?? ( json_arr_get v k ) {
                T e → { ? ( json_is_str e ) { ( vec_push [String] out ( string_from ( json_str_data e ) ) ) } {} }
                F → {}
            }
            = k + k 1
        }
    } {}
}

// An OpenAI message's content as text: a string, or an array of parts of
// which only `text` ones are understood — an image or audio part is
// refused (F), not silently dropped.
@ __oai_content Json mo inout String out → b {
    ?? ( json_obj_get mo `content` ) {
        T cv → {
            ? ( json_is_str cv ) { ( string_push_str out ( json_str_data cv ) ) ^ T } {}
            ? ( json_is_null cv ) { ^ T } {}
            ? ( json_is_arr cv ) {
                : ~ i k 0
                ~ < k ( json_arr_len cv ) {
                    ?? ( json_arr_get cv k ) {
                        T part → {
                            : String ty ( __api_str part `type` `` )
                            ? ( nurl_str_eq ( string_data ty ) `text` ) {} { ^ F }
                            ? & > k 0 > ( string_len out ) 0 { ( string_push_char out 10 ) } {}
                            : String tx ( __api_str part `text` `` )
                            ( string_push_str out ( string_data tx ) )
                        }
                        F → {}
                    }
                    = k + k 1
                }
                ^ T
            } {}
            ^ F
        }
        F → { ^ T }
    }
}

// The OpenAI fields of `j` into `rq` — a chat's messages into `msgs`, to be
// rendered once the model (and so its chat template) is loaded; an error
// message (empty = none).
// What this server cannot do is refused with a reason rather than ignored:
// more than one choice, tools, a structured response format, logprobs, an
// image part.
// A chat message from a request: its role, its text, and an assistant
// message's reasoning when the request gives it apart (`rkey`: OpenAI's
// reasoning_content, ollama's thinking).
@ _api_chat_msg s role String content Json mo s rkey → ChatMsg {
    ?? ( json_obj_get mo rkey ) {
        T rv → {
            ? & ( json_is_str rv ) != 0 ( nurl_str_eq role `assistant` ) { ^ ( chat_msg_r role ( string_data content ) ( json_str_data rv ) ) } {}
        }
        F → {}
    }
    ^ ( chat_msg role ( string_data content ) )
}

// The template switches a request may set (ChatOpts): OpenAI's top-level
// reasoning_effort, and vLLM's chat_template_kwargs {reasoning_effort,
// enable_thinking} — the template's own variables, passed through.
@ _api_chat_opts Json j inout ChatOpts o → v {
    ?? ( json_obj_get j `reasoning_effort` ) { T v → { ? ( json_is_str v ) { = . o effort ( string_from ( json_str_data v ) ) } {} } F → {} }
    ?? ( json_obj_get j `chat_template_kwargs` ) {
        T kw → {
            ?? ( json_obj_get kw `reasoning_effort` ) { T v → { ? ( json_is_str v ) { = . o effort ( string_from ( json_str_data v ) ) } {} } F → {} }
            ?? ( json_obj_get kw `enable_thinking` ) { T v → { ? ( json_is_bool v ) { = . o thinking ? ( json_bool_val v ) 1 0 } {} } F → {} }
        }
        F → {}
    }
}

@ __oai_parse Json j inout GenReq rq inout ( Vec ChatMsg ) msgs inout ChatOpts opts → String {
    : b chat == . rq proto API_OAI_CHAT
    ? > ( __api_num_i j `n` 1 ) 1 { ^ ( string_from `n > 1 is not supported: nurllama returns one choice` ) } {}
    ? > ( __api_num_i j `best_of` 1 ) 1 { ^ ( string_from `best_of > 1 is not supported` ) } {}
    ?? ( json_obj_get j `tools` ) {
        T tv → { ? & ( json_is_arr tv ) > ( json_arr_len tv ) 0 { ^ ( string_from `tools are not supported` ) } {} }
        F → {}
    }
    ?? ( json_obj_get j `response_format` ) {
        T rf → {
            : String ty ( __api_str rf `type` `text` )
            ? ( nurl_str_eq ( string_data ty ) `text` ) {} { ^ ( string_from `response_format other than text is not supported` ) }
        }
        F → {}
    }
    ? ( __api_bool j `logprobs` F ) { ^ ( string_from `logprobs are not supported` ) } {}
    = . rq stream ( __api_bool j `stream` F )
    ?? ( json_obj_get j `stream_options` ) {
        T so → { = . rq usage ( __api_bool so `include_usage` F ) }
        F → {}
    }
    // OpenAI's own defaults: temperature 1, top_p 1, no top-k (top_k is
    // not OpenAI's, but servers commonly take it); a chat runs to the end
    // of its turn, a completion to 16 tokens
    = . rq npredict ( __api_num_i j `max_completion_tokens` ( __api_num_i j `max_tokens` ? chat 0 16 ) )
    = . rq temp ( __api_num_f j `temperature` 1.0 )
    = . rq topp ( __api_num_f j `top_p` 1.0 )
    = . rq topk ( __api_num_i j `top_k` 0 )
    = . rq seed ( __api_num_i j `seed` ( monotonic_ns ) )
    ?? ( json_obj_get j `stop` ) { T sv → { ( __api_stops sv . rq stops ) } F → {} }
    ? chat {
        ?? ( json_obj_get j `messages` ) {
            T arr → {
                ? ( json_is_arr arr ) {} { ^ ( string_from `messages must be an array` ) }
                : ~ i k 0
                ~ < k ( json_arr_len arr ) {
                    ?? ( json_arr_get arr k ) {
                        T mo → {
                            : ~ String role ( __api_str mo `role` `user` )
                            // OpenAI's newer name for the system turn
                            ? ( nurl_str_eq ( string_data role ) `developer` ) { = role ( string_from `system` ) } {}
                            : ~ String content ( string_new )
                            ? ( __oai_content mo content ) {} { ^ ( string_from `only text message content is supported` ) }
                            ( vec_push [ChatMsg] msgs ( _api_chat_msg ( string_data role ) content mo `reasoning_content` ) )
                        }
                        F → {}
                    }
                    = k + k 1
                }
            }
            F → { ^ ( string_from `missing "messages"` ) }
        }
        ( _api_chat_opts j opts )
    } {
        ?? ( json_obj_get j `prompt` ) {
            T pv → {
                ? ( json_is_str pv ) { = . rq prompt ( string_from ( json_str_data pv ) ) } {
                    ? & ( json_is_arr pv ) == ( json_arr_len pv ) 1 {
                        ?? ( json_arr_get pv 0 ) {
                            T p0 → {
                                ? ( json_is_str p0 ) { = . rq prompt ( string_from ( json_str_data p0 ) ) } { ^ ( string_from `prompt must be a string` ) }
                            }
                            F → {}
                        }
                    } { ^ ( string_from `prompt must be a string (or an array of exactly one)` ) }
                }
            }
            F → { ^ ( string_from `missing "prompt"` ) }
        }
    }
    ^ ( string_new )
}

// The ollama fields of `j` into `rq`.
@ __ollama_parse Json j inout GenReq rq → v {
    ? == . rq proto API_OLLAMA_GEN {
        = . rq prompt ( __api_str j `prompt` `` )
    } {
        // the message list through the model's own chat template
        : ( Vec ChatMsg ) msgs ( vec_new [ChatMsg] )
        ?? ( json_obj_get j `messages` ) {
            T arr → {
                : ~ i k 0
                ~ < k ( json_arr_len arr ) {
                    ?? ( json_arr_get arr k ) {
                        T mo → {
                            : String role ( __api_str mo `role` `user` )
                            : String content ( __api_str mo `content` `` )
                            ( vec_push [ChatMsg] msgs ( _api_chat_msg ( string_data role ) content mo `thinking` ) )
                        }
                        F → {}
                    }
                    = k + k 1
                }
            }
            F → {}
        }
        // ollama's `think` is the template's enable_thinking
        : ~ ChatOpts opts ( chat_opts_none )
        ?? ( json_obj_get j `think` ) { T v → { ? ( json_is_bool v ) { = . opts thinking ? ( json_bool_val v ) 1 0 } {} } F → {} }
        = . rq prompt ( chat_render_opts g_api_style msgs opts )
    }
    = . rq stream ( __api_bool j `stream` T )
    = . rq npredict ( __api_opt_i j `num_predict` 128 )
    = . rq temp ( __api_opt_f j `temperature` 0.8 )
    = . rq topk ( __api_opt_i j `top_k` 40 )
    = . rq topp ( __api_opt_f j `top_p` 0.95 )
    = . rq seed ( __api_opt_i j `seed` 42 )
    ?? ( json_obj_get j `options` ) {
        T o → { ?? ( json_obj_get o `stop` ) { T sv → { ( __api_stops sv . rq stops ) } F → {} } }
        F → {}
    }
}

// ── the stream hook: every generating route ─────────────────────────

@ __api_stream_hook TcpConn c HttpRequest req → b {
    : s path ( string_data . req path )
    : ~ i proto -1
    ? ( nurl_str_eq path `/api/generate` ) { = proto API_OLLAMA_GEN } {}
    ? ( nurl_str_eq path `/api/chat` ) { = proto API_OLLAMA_CHAT } {}
    ? ( nurl_str_eq path `/v1/chat/completions` ) { = proto API_OAI_CHAT } {}
    ? ( nurl_str_eq path `/v1/completions` ) { = proto API_OAI_TEXT } {}
    ? < proto 0 { ^ F } {}
    ? ( nurl_str_eq ( string_data . req method ) `POST` ) {} { ^ F }
    ? ( __api_authed req ) {} {
        ^ ( __api_error_chunked c proto 401 `unauthorized: this server wants Authorization: Bearer <token>` `invalid_api_key` )
    }

    : !Json JsonError pj ( __api_body_json req )
    ?? pj {
        F _ → { ^ ( __api_error_chunked c proto 400 `invalid JSON body` `` ) }
        T j → {
            // the request's own model, or the server's default
            : ~ String model ( __api_str j `model` `` )
            ? > ( string_len model ) 0 {} {
                = model ( __api_cfg_model )
            }
            ? > ( string_len model ) 0 {} {
                ^ ( __api_error_chunked c proto 400 `missing "model" and the server has no default — start it as: nurllama serve <model>` `` )
            }
            : b oai ( __api_is_oai proto )
            : String idp ( string_from ? == proto API_OAI_CHAT `chatcmpl-` `cmpl-` )
            ( string_push_str idp ( string_data ( uuid_v4 ) ) )
            : b chat | == proto API_OAI_CHAT == proto API_OLLAMA_CHAT
            : ~ GenReq rq @ GenReq { proto ( string_clone model ) ( string_new ) F 0 0.0 0 1.0 0 ( vec_new [String] ) F idp ( now_seconds ) chat F }
            : ~ ( Vec ChatMsg ) msgs ( vec_new [ChatMsg] )
            : ~ ChatOpts opts ( chat_opts_none )
            ? oai {
                : String perr ( __oai_parse j rq msgs opts )
                ? > ( string_len perr ) 0 { ^ ( __api_error_chunked c proto 400 ( string_data perr ) `` ) } {}
            } {}
            // (the model loads after the request is known to be one it can
            // answer — a refused request must not swap the resident model)
            : String lerr ( __api_ensure ( string_data model ) )
            ? > ( string_len lerr ) 0 {
                ^ ( __api_error_chunked c proto 404 ( string_data lerr ) `model_not_found` )
            } {}
            ? oai {
                ? == proto API_OAI_CHAT { = . rq prompt ( chat_render_opts g_api_style msgs opts ) } {}
            } { ( __ollama_parse j rq ) }
            // a chat prompt that ends inside <think> (GLM's) leaves the reply
            // reasoning from its first token
            = . rq think_open & chat ( string_ends_with ( string_trim_end . rq prompt ) `<think>` )
            ^ ( __api_generate c rq )
        }
    }
}

// ── plain JSON routes ───────────────────────────────────────────────

// The names in the local store.
@ __api_store_names → ( Vec String ) {
    : String mdir ( path_join ( string_data ( __api_cfg_root ) ) `manifests` )
    ?? ( dir_list ( string_data mdir ) ) {
        T names → { ^ names }
        F _ → { ^ ( vec_new [String] ) }
    }
}

@ __api_tags HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : Json arr ( json_arr_new )
    : String rootS ( __api_cfg_root )
    : ( Vec String ) names ( __api_store_names )
    : ~ i k 0
    ~ < k ( vec_len [String] names ) {
        : s nm ( string_data ( vec_at [String] names k ) )
        : Json o ( json_obj_new )
        : b _1 ( json_obj_set o `name` ( json_str_lit nm ) )
        : b _2 ( json_obj_set o `model` ( json_str_lit nm ) )
        : ~ i sz 0
        ?? ( nl_resolve rootS nm ) {
            T bp → {
                ?? ( file_size ( string_data bp ) ) {
                    T n → { = sz n }
                    F _ → {}
                }
            }
            F → {}
        }
        : b _3 ( json_obj_set o `size` ( json_int sz ) )
        : b _4 ( json_arr_push arr o )
        = k + k 1
    }
    : Json root ( json_obj_new )
    : b _r ( json_obj_set root `models` arr )
    : String txt ( json_stringify root )
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `application/json` )
    ( response_set_body_str resp ( string_data txt ) )
    ^ resp
}

@ __api_show HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : !Json JsonError pj ( __api_body_json req )
    ?? pj {
        F _ → { ^ ( response_text 400 `{"error":"invalid JSON body"}\n` ) }
        T j → {
            : String model ( __api_str j `model` `` )
            : String rootS ( __api_cfg_root )
            : ?String rp ( nl_resolve rootS ( string_data model ) )
            ?? rp {
                F → {
                    ^ ( response_text 404 `{"error":"model not found"}\n` )
                }
                T path → {
                    : Json o ( json_obj_new )
                    : b _1 ( json_obj_set o `model` ( json_str_lit ( string_data model ) ) )
                    ?? ( model_meta ( string_data path ) ) {
                        T gg → {
                            : Json d ( json_obj_new )
                            : s arch ( gguf_kv_str_or gg `general.architecture` `?` )
                            : b _2 ( json_obj_set d `general.architecture` ( json_str_lit arch ) )
                            // the architecture's own keys (they were read as llama.*,
                            // which only a llama model has)
                            : String kb ( string_from arch ) ( string_push_str kb `.block_count` )
                            : String ke ( string_from arch ) ( string_push_str ke `.embedding_length` )
                            : String kc ( string_from arch ) ( string_push_str kc `.context_length` )
                            : b _3 ( json_obj_set d ( string_data kb ) ( json_int ( gguf_kv_int_or gg ( string_data kb ) 0 ) ) )
                            : b _4 ( json_obj_set d ( string_data ke ) ( json_int ( gguf_kv_int_or gg ( string_data ke ) 0 ) ) )
                            : b _5 ( json_obj_set d ( string_data kc ) ( json_int ( gguf_kv_int_or gg ( string_data kc ) 0 ) ) )
                            : b _6 ( json_obj_set d `tensors` ( json_int ( gguf_n_tensors gg ) ) )
                            : b _7 ( json_obj_set o `model_info` d )
                        }
                        F _e → {}
                    }
                    : String txt ( json_stringify o )
                    : HttpResponse resp ( response_new 200 )
                    ( response_set_header resp `Content-Type` `application/json` )
                    ( response_set_body_str resp ( string_data txt ) )
                    ^ resp
                }
            }
        }
    }
}

// ── OpenAI's model list ─────────────────────────────────────────────

// One OpenAI model object: `created` is when the model file was written.
@ __oai_model_obj s name → Json {
    : Json o ( json_obj_new )
    : b _1 ( json_obj_set o `id` ( json_str_lit name ) )
    : b _2 ( json_obj_set o `object` ( json_str_lit `model` ) )
    : ~ i created 0
    ?? ( nl_resolve ( __api_cfg_root ) name ) {
        T bp → { ?? ( fs_stat ( string_data bp ) ) { T st → { = created . st mtime } F _ → {} } }
        F → {}
    }
    : b _3 ( json_obj_set o `created` ( json_int created ) )
    : b _4 ( json_obj_set o `owned_by` ( json_str_lit `nurllama` ) )
    ^ o
}

// GET /v1/models — the store, and the server's default model when it is
// not one of them (a path given to `serve`).
@ __oai_models HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __api_error_resp API_OAI_CHAT 401 `unauthorized: this server wants Authorization: Bearer <token>` `invalid_api_key` ) }
    : Json arr ( json_arr_new )
    : ( Vec String ) names ( __api_store_names )
    : String dflt ( __api_cfg_model )
    : ~ b listed F
    : ~ i k 0
    ~ < k ( vec_len [String] names ) {
        : s nm ( string_data ( vec_at [String] names k ) )
        ? ( nurl_str_eq nm ( string_data dflt ) ) { = listed T } {}
        : b _1 ( json_arr_push arr ( __oai_model_obj nm ) )
        = k + k 1
    }
    ? & ! listed > ( string_len dflt ) 0 { : b _2 ( json_arr_push arr ( __oai_model_obj ( string_data dflt ) ) ) } {}
    : Json root ( json_obj_new )
    : b _3 ( json_obj_set root `object` ( json_str_lit `list` ) )
    : b _4 ( json_obj_set root `data` arr )
    : String txt ( json_stringify root )
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `application/json` )
    ( response_set_body_str resp ( string_data txt ) )
    ^ resp
}

// GET /v1/models/:id — a model this server can open.
@ __oai_model HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __api_error_resp API_OAI_CHAT 401 `unauthorized: this server wants Authorization: Bearer <token>` `invalid_api_key` ) }
    : ~ String id ( string_new )
    ?? ( params_get ps `id` ) { T v → { = id ( string_from ( string_data v ) ) } F → {} }
    ?? ( nl_resolve ( __api_cfg_root ) ( string_data id ) ) {
        T _p → {
            : String txt ( json_stringify ( __oai_model_obj ( string_data id ) ) )
            : HttpResponse resp ( response_new 200 )
            ( response_set_header resp `Content-Type` `application/json` )
            ( response_set_body_str resp ( string_data txt ) )
            ^ resp
        }
        F → {
            : String msg ( string_from `model '` )
            ( string_push_str msg ( string_data id ) )
            ( string_push_str msg `' not found` )
            ^ ( __api_error_resp API_OAI_CHAT 404 ( string_data msg ) `model_not_found` )
        }
    }
}

// ── the web chat UI: cookie sessions + the nurldb history ────────────

// The per-client GUID. Read from the `nl_client` cookie; minted (and
// set on the response) on first contact. Each browser thereby carries
// its own identity, and conversations are scoped to it.
@ __web_guid HttpRequest req HttpResponse resp → String {
    ?? ( request_cookie req `nl_client` ) {
        T c → { ? > ( string_len c ) 0 { ^ c } {} }
        F → {}
    }
    : String guid ( uuid_v4 )
    : String sc ( string_from `nl_client=` )
    ( string_push_str sc ( string_data guid ) )
    ( string_push_str sc `; Path=/; Max-Age=34560000; SameSite=Lax; HttpOnly` )
    ( response_set_header resp `Set-Cookie` ( string_data sc ) )
    ^ guid
}

// True when the request may touch the data endpoints: always, for an
// open server; otherwise it must carry `Authorization: Bearer <token>`.
// Every data route asks this — /api/*, /v1/* and /web/* alike.
@ __api_authed HttpRequest req → b {
    ? == g_api_auth 0 { ^ T } {}
    ?? ( header_get . req headers `Authorization` ) {
        T h → {
            : String want ( string_from `Bearer ` )
            ( string_push_str want ( string_data ( __api_cfg_token ) ) )
            : b ok ( nurl_str_eq ( string_data h ) ( string_data want ) )
            ^ ok
        }
        F → {}
    }
    ^ F
}

@ __web_unauth → HttpResponse {
    ^ ( response_text 401 `{"error":"unauthorized"}\n` )
}

@ __web_json HttpResponse resp s txt → HttpResponse {
    ( response_set_header resp `Content-Type` `application/json` )
    ( response_set_body_str resp txt )
    ^ resp
}

// Synchronous full-reply generation: run the model over `ids` and
// return the decoded text (no streaming — the web UI wants one reply).
// Diffusion models denoise a block; others sample autoregressively.
@ __web_gen_reply Llm m ( Vec i ) ids i npredict f temp i seed → String {
    : Tok t ( Tok_share ( llm_tok m ) )
    : String out ( string_new )
    ? > ( vec_len [i] ids ) ( llm_n_ctx m ) { ^ out } {}
    ? ( llm_is_diffusion m ) {
        // Conservative diffusion defaults that produce correct output on
        // EVERY llada2 variant: block 32, a high mask-commit threshold,
        // and editing OFF (edit-threshold 1.1). The token-editing pass is
        // a LLaDA2.1 capability — enabling it on a 2.0 model (not trained
        // for it) degrades into repetition ("France France"). Power users
        // tune per-call via the CLI `run` command.
        : Rng drng ( rng_seed seed )
        : ( Vec i ) gen ( dz_generate m ids npredict 32 0.9 1.1 8 temp drng )
        : ~ i gi 0
        ~ < gi ( vec_len [i] gen ) {
            : ~ i gid 0
            ?? ( vec_get [i] gen gi ) { T x → { = gid x } F → {} }
            : ( Vec u ) pb ( tok_piece t gid )
            : String piece ( bytes_to_str pb )
            ( string_push_str out ( string_data piece ) )
            = gi + gi 1
        }
        ^ ( __api_utf8 out )
    } {}
    // autoregressive
    ( llm_prefill m ids )
    : Rng rng ( rng_seed seed )
    : i nprompt ( vec_len [i] ids )
    : ~ i pos nprompt
    : ~ i produced 0
    : ~ b stop F
    ~ & & < produced npredict < pos ( llm_n_ctx m ) ! stop {
        : i nt ( sample_next m rng temp 40 0.95 )
        ? ( llm_is_eog m nt ) { = stop T } {
            : ( Vec u ) pb ( tok_piece t nt )
            : String piece ( bytes_to_str pb )
            ? ( chat_stop_matches g_api_style ( string_data piece ) ) { = stop T } {
                ( string_push_str out ( string_data piece ) )
                ( llm_eval m nt pos )
                = pos + pos 1
                = produced + produced 1
            }
        }
    }
    ^ ( __api_utf8 out )
}

// Ensure the configured model is loaded, render the message history
// through its chat template, and return the assistant's reply — or
// the reason it cannot (no model configured / the load failed).
@ __web_reply Json history s new_content → !String String {
    ? == 0 ( nurl_str_len ( string_data ( __api_cfg_model ) ) ) {
        ^ @ !String String { F ( string_from `no model is configured — restart the server with a model: nurllama serve MODEL (or run the setup wizard: nurllama start)` ) }
    } {}
    : String lerr ( __api_ensure ( string_data ( __api_cfg_model ) ) )
    ? > ( string_len lerr ) 0 {
        ^ @ !String String { F lerr }
    } {}
    : Llm m ( __api_llm )
    : Tok t ( Tok_share ( llm_tok m ) )
    // message list = stored history + the new user turn
    : ( Vec ChatMsg ) msgs ( vec_new [ChatMsg] )
    : ~ i k 0
    ~ < k ( json_arr_len history ) {
        ?? ( json_arr_get history k ) {
            T mo → {
                : String role ( __api_str mo `role` `user` )
                : String content ( __api_str mo `content` `` )
                ( vec_push [ChatMsg] msgs ( chat_msg ( string_data role ) ( string_data content ) ) )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_push [ChatMsg] msgs ( chat_msg `user` new_content ) )
    : String prompt ( chat_render g_api_style msgs )
    : ( Vec i ) ids ( tok_encode t ( string_data prompt ) T )
    : String reply ( __web_gen_reply m ids 512 0.0 42 )
    // the conversation keeps the answer; a reasoning model's reasoning is
    // cut off as the APIs cut it (__api_think_split)
    : b open ( string_ends_with ( string_trim_end prompt ) `<think>` )
    ^ @ !String String { T . ( _api_parts reply T open ) answer }
}

// GET /web/session — mint/refresh the cookie, return the client id and
// the configured model.
@ __web_session HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : HttpResponse resp ( response_new 200 )
    : String guid ( __web_guid req resp )
    : b _e ( hist_ensure_client ( string_data guid ) ( hist_now ) )
    : Json o ( json_obj_new )
    : b _1 ( json_obj_set o `client` ( json_str_lit ( string_data guid ) ) )
    : b _2 ( json_obj_set o `model` ( json_str_lit ( string_data ( __api_cfg_model ) ) ) )
    : String txt ( json_stringify o )
    : HttpResponse r ( __web_json resp ( string_data txt ) )
    ^ r
}

// GET /web/conversations — this client's conversations, newest first.
@ __web_conversations HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : HttpResponse resp ( response_new 200 )
    : String guid ( __web_guid req resp )
    : Json arr ( hist_list_conversations ( string_data guid ) )
    : String txt ( json_stringify arr )
    : HttpResponse r ( __web_json resp ( string_data txt ) )
    ^ r
}

// GET /web/conversations/:id/messages — only if this client owns it.
@ __web_messages HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : HttpResponse resp ( response_new 200 )
    : String guid ( __web_guid req resp )
    : ~ i conv -1
    ?? ( params_get ps `id` ) {
        T idv → {
            ?? ( string_to_int idv ) { T n → { = conv n } F _ → {} }
        }
        F → {}
    }
    : String owner ( hist_conversation_owner conv )
    : b owns ( nurl_str_eq ( string_data owner ) ( string_data guid ) )
    ? owns {} {
        ^ ( response_text 404 `{"error":"not found"}\n` )
    }
    : Json arr ( hist_get_messages conv )
    : String txt ( json_stringify arr )
    : HttpResponse r ( __web_json resp ( string_data txt ) )
    ^ r
}

// DELETE /web/conversations/:id — only if this client owns it.
@ __web_delete HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : HttpResponse resp ( response_new 200 )
    : String guid ( __web_guid req resp )
    : ~ i conv -1
    ?? ( params_get ps `id` ) {
        T idv → {
            ?? ( string_to_int idv ) { T n → { = conv n } F _ → {} }
        }
        F → {}
    }
    : b ok ( hist_delete_conversation conv ( string_data guid ) )
    : Json o ( json_obj_new )
    : b _1 ( json_obj_set o `ok` ( json_bool ok ) )
    : String txt ( json_stringify o )
    : HttpResponse r ( __web_json resp ( string_data txt ) )
    ^ r
}

// POST /web/chat  { "conversation_id": N|null, "content": "…" }
// Persists the user turn, generates a reply against the conversation's
// full history, persists that too, and returns { conversation_id, reply }.
@ __web_chat HttpRequest req Params ps → HttpResponse {
    ? ( __api_authed req ) {} { ^ ( __web_unauth ) }
    : HttpResponse resp ( response_new 200 )
    : String guid ( __web_guid req resp )
    : b _e ( hist_ensure_client ( string_data guid ) ( hist_now ) )
    : ~ i rc_status 200
    : ~ String out_txt ( string_new )
    ?? ( __api_body_json req ) {
        F _ → {
            = rc_status 400
            = out_txt ( string_from `{"error":"invalid JSON body"}` )
        }
        T j → {
            : String content ( __api_str j `content` `` )
            ? == 0 ( string_len content ) {
                = rc_status 400
                = out_txt ( string_from `{"error":"empty content"}` )
            } {
                : ~ i conv -1
                ?? ( json_obj_get j `conversation_id` ) {
                    T cv → { ?? ( json_num_as_i cv ) { T n → { = conv n } F → {} } }
                    F → {}
                }
                // an unknown or someone-else's conversation starts a new one
                ? >= conv 0 {
                    : String own ( hist_conversation_owner conv )
                    ? ( nurl_str_eq ( string_data own ) ( string_data guid ) ) {} { = conv -1 }
                } {}
                ? < conv 0 {
                    = conv ( hist_new_conversation ( string_data guid ) ( string_data ( __api_cfg_model ) ) ( hist_now ) )
                } {}
                // the prior turns (before adding this one) are the context
                : Json history ( hist_get_messages conv )
                : b _u ( hist_add_message conv `user` ( string_data content ) ( hist_now ) )
                ?? ( __web_reply history ( string_data content ) ) {
                    T reply → {
                        : b _a ( hist_add_message conv `assistant` ( string_data reply ) ( hist_now ) )
                        : Json o ( json_obj_new )
                        : b _1 ( json_obj_set o `conversation_id` ( json_int conv ) )
                        : b _2 ( json_obj_set o `reply` ( json_str_lit ( string_data reply ) ) )
                        = out_txt ( json_stringify o )
                    }
                    F emsg → {
                        = rc_status 500
                        : Json eo ( json_obj_new )
                        : b _e1 ( json_obj_set eo `error` ( json_str_lit ( string_data emsg ) ) )
                        = out_txt ( json_stringify eo )
                    }
                }
            }
        }
    }
    // A failure answers on `resp` too: it carries the Set-Cookie a first
    // contact was given, and the conversation just made for that cookie
    // stays reachable (a fresh response dropped it, and the client never
    // saw its own conversation again).
    = . resp status rc_status
    : HttpResponse r ( __web_json resp ( string_data out_txt ) )
    ^ r
}

// GET / — the web chat app for a browser (Accept: text/html), or the
// ollama-compatible status line for a programmatic client, so existing
// tooling that probes `/` is undisturbed.
@ __api_root HttpRequest req Params ps → HttpResponse {
    : ~ b wants_html F
    ?? ( header_get . req headers `Accept` ) {
        T a → {
            ? >= ( nurl_str_find ( string_data a ) `text/html` ) 0 { = wants_html T } {}
        }
        F → {}
    }
    ? wants_html {
        : HttpResponse resp ( response_new 200 )
        : String guid ( __web_guid req resp )
        ( response_set_header resp `Content-Type` `text/html; charset=utf-8` )
        ( response_set_body_str resp ( webui_html ) )
        ^ resp
    } {}
    ^ ( response_text 200 `nurllama is running\n` )
}

// Serve on `host:port`. Single worker: the decode loop owns the device,
// so serialisation is structural rather than a lock. `model` (may be
// empty) is the default: the web UI chats with it, and an /api request
// that names no model of its own falls back to it.
@ api_serve String root s host i port s model → i {
    : NlConfig cfg @ NlConfig {
        ( string_from model ) ( string_from host ) port
        ( string_from `open` ) ( string_new ) ( string_new )
    }
    : i rc ( api_serve_cfg root cfg )
    ^ rc
}

// Serve with a full wizard config: a default model for the web UI, an
// optional bearer token, and the conversation-history database.
@ api_serve_cfg String root NlConfig cfg → i {
    ( api_set_root root )
    = g_api_auth ? ( nurl_str_eq ( string_data . cfg auth ) `token` ) 1 0
    ( __api_set_token ( string_data . cfg token ) )
    ( __api_set_model ( string_data . cfg model ) )
    // The history before the port: a second server on this NURLLAMA_HOME
    // (the database's lock) fails here, before it serves anything.
    : String hdir ( hist_dir root )
    : String herr ( hist_open hdir )
    ? > ( string_len herr ) 0 {
        ( nurl_eprintln ( string_data herr ) )
        ^ 1
    } {}

    : HttpApp a ( http_app_new )
    ( http_app_workers a 1 )
    ( http_app_body_max a 4194304 )
    ( http_app_get a `/` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_root rq ps ) } )
    ( http_app_get a `/api/tags` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_tags rq ps ) } )
    ( http_app_post a `/api/show` \ HttpRequest rq Params ps → HttpResponse { ^ ( __api_show rq ps ) } )
    ( http_app_get a `/v1/models` \ HttpRequest rq Params ps → HttpResponse { ^ ( __oai_models rq ps ) } )
    ( http_app_get a `/v1/models/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __oai_model rq ps ) } )
    ( http_app_get a `/web/session` \ HttpRequest rq Params ps → HttpResponse { ^ ( __web_session rq ps ) } )
    ( http_app_get a `/web/conversations` \ HttpRequest rq Params ps → HttpResponse { ^ ( __web_conversations rq ps ) } )
    ( http_app_get a `/web/conversations/:id/messages` \ HttpRequest rq Params ps → HttpResponse { ^ ( __web_messages rq ps ) } )
    ( http_app_delete a `/web/conversations/:id` \ HttpRequest rq Params ps → HttpResponse { ^ ( __web_delete rq ps ) } )
    ( http_app_post a `/web/chat` \ HttpRequest rq Params ps → HttpResponse { ^ ( __web_chat rq ps ) } )
    ( http_app_stream a \ TcpConn c HttpRequest rq → b { ^ ( __api_stream_hook c rq ) } )

    : String msg ( string_from `nurllama serving on http://` )
    ( string_push_str msg ( string_data . cfg host ) )
    ( string_push_char msg 58 )
    ( string_push_int msg . cfg port )
    ( nurl_print ( string_data msg ) )
    ( nurl_print `\n` )
    : i rc ( http_app_listen a ( string_data . cfg host ) . cfg port )
    ( __api_unload )
    ( hist_close )
    ^ rc
}
