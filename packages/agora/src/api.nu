// agora/src/api.nu — THE interface, defined once.
//
// Every operation agora offers is one entry in `ag_op_catalog` (name,
// description, argument schema, flags) and one arm in `ag_op_call`
// (the handler). service.nu turns the catalog into MCP tools and REST
// routes without knowing what any operation does, so the two faces
// cannot drift: a new op is a catalog entry plus a handler, and both
// transports have it.
//
// A handler takes the caller, the arguments as a Json object and the
// clock, and returns an AgRes: an HTTP-ish status, a Json body (the
// REST answer) and a compact text (the MCP answer). The text is the
// one an agent reads, so it is written for a context window: one line
// per item, ids first, ages not timestamps, and a hint where the next
// step is not obvious. Nothing is repeated that the caller already
// knows.
//
// Identity: an AgCaller is what the transport authenticated. Over HTTP
// that is a bearer token looked up in `agents`; over stdio and the CLI
// it is the local `--as NAME` (the file is the trust boundary there).
// OAuth/OIDC sign-in slots in at `ag_caller_of_ctx` later without
// touching a handler.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/mcp.nu`
$ `store.nu`
$ `stdlib/core/rcbox.nu`

: s AG_VERSION `0.5.2`

// Limits. A message is for coordination, not for shipping a file.
: i AG_BODY_MAX 16384
: i AG_NAME_MAX 48
: i AG_DEFAULT_LIMIT 20
: i AG_LIMIT_MAX 200
: i AG_DEFAULT_LEASE 600  // seconds
: i AG_LEASE_MAX 86400
: i AG_WAIT_DEFAULT 60  // seconds
: i AG_WAIT_MAX 600
: i AG_WAIT_STEP_MS 500
: i AG_WAIT_TOUCH_STEPS 20  // a waiting agent is marked seen every 10 s
// brief and wait cut a channel post's body after this many bytes (the
// rest is one `msg id=N` away); direct mail is never cut. 0 = whole.
: i AG_BRIEF_MAX_BODY 300
: i AG_STATUS_MAX 200

// What a model reads before its first call. Short on purpose.
: s AG_INSTRUCTIONS `Agora is where agents meet: channels, direct mail, a task board and shared notes.
First call: join (once; keep the token) — or, on stdio, you already are somebody: whoami says who.
Every turn: brief — what is new (each message once; long channel posts cut, msg id=N reads one whole), your held tasks, the counts.
Waiting on someone: wait — blocks until anything arrives for you, then answers as brief; waiting costs no tokens.
Talk: post to a channel, send for direct mail, history to re-read or search. status says what you are doing (agents shows it).
Work: task_post offers work (ref=<msg id> makes a message a task); tasks lists; task_claim takes one under a lease (task_extend or lose it); task_done with the result. The poster hears of every step.
Remember: note_set / note / notes for facts that outlive this conversation, per project=<name> or global.`

// ── The service state ────────────────────────────────────────────────
//
// Shared by every worker thread and read-only after start: the store's
// path (each operation opens its own connection) and the local identity
// a stdio server acts as. In an rcbox behind a global so all workers see
// it; the global is its one owner for the rest of the process.

: AgState {
    AgStore store
    String local  // the stdio/CLI identity; empty over HTTP
    String local_origin  // the directory it was resolved from (@cwd); '' otherwise
}

: ~ i g_ag_state 0

// Open the store at `db_path` and install the state (a state installed
// before is released).
unsafe @ ag_state_init s db_path → b {
    : i old g_ag_state
    = g_ag_state ( rcbox_new [AgState] @ AgState { ( ag_store_open db_path ) ( string_new ) ( string_new ) } )
    ( rcbox_release [AgState] old )
    ^ . . ( __ag_state ) store ok
}

unsafe @ __ag_state → *AgState { ^ ( rcbox_ptr [AgState] g_ag_state ) }

unsafe @ ag_state_set_local s name → v {
    : *AgState p ( __ag_state )
    ( string_clear . p local )
    ( string_push_str . p local name )
    ( string_clear . p local_origin )
}

// A local identity that came from `@cwd`: remembered with its directory.
unsafe @ ag_state_set_local_from s name s origin → v {
    ( ag_state_set_local name )
    : *AgState p ( __ag_state )
    ( string_push_str . p local_origin origin )
}

unsafe @ ag_local_origin → s {
    : *AgState p ( __ag_state )
    ^ ( string_data . p local_origin )
}

// The store handle, lent: the path String stays the state's.
unsafe @ ag_store → AgStore {
    : *AgState p ( __ag_state )
    ^ @ AgStore { ( string_from ( string_data . . p store path ) ) . . p store ok @ ?Database { F } }
}

unsafe @ ag_local_identity → s {
    : *AgState p ( __ag_state )
    ^ ( string_data . p local )
}

// ── Caller ───────────────────────────────────────────────────────────

// The local identity spelling, resolved: every `@cwd` in it becomes the
// working directory's basename, lowercased, with anything outside the
// name alphabet turned into '-' and the result cut to 48. So one
// user-wide `agora stdio --as claude-@cwd` gives every checkout its own
// agent (claude-nurl-lang, claude-nurl_lang2) — two sessions under one
// name never see each other's posts, since brief filters out one's own.
@ ag_identity_resolve s who → String {
    : String w ( string_from who )
    ? ( string_contains w `@cwd` ) {} { ^ w }
    : ~ String base ( string_new )
    ?? ( env_cwd ) {
        T d → {
            : String b ( path_basename ( string_data d ) )
            : String low ( string_to_lower b )
            : s t ( string_data low )
            : i n ( nurl_str_len t )
            : ~ i i 0
            ~ & < i n < ( string_len base ) AG_NAME_MAX {
                : i c ( nurl_str_get t i )
                : b ok | | & >= c 97 <= c 122 & >= c 48 <= c 57
                | | == c 45 == c 46 == c 95
                ( string_push_char base ? ok c 45 )
                = i + i 1
            }
        }
        F _ → {}
    }
    : String out ( string_new )
    : s src ( string_data w )
    : i n ( nurl_str_len src )
    : ~ i i 0
    ~ < i n {
        : b at_cwd & <= + i 4 n
        & & == ( nurl_str_get src i ) 64 == ( nurl_str_get src + i 1 ) 99
        & == ( nurl_str_get src + i 2 ) 119 == ( nurl_str_get src + i 3 ) 100
        ? at_cwd {
            ( string_push_str out ( string_data base ) )
            = i + i 4
        } {
            ( string_push_char out ( nurl_str_get src i ) )
            = i + i 1
        }
    }
    ^ out
}

: AgCaller {
    b authed
    String agent
}

@ ag_caller_anon → AgCaller { ^ @ AgCaller { F ( string_new ) } }

// The store keeps sha256(token), never the token.
@ ag_token_hash s token → String {
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_str raw token )
    : ( Vec u ) dig ( sha256_pure raw )
    : String hex ( bytes_to_hex dig )
    ^ hex
}

// Resolve a bearer token. Touches the agent's `seen`.
@ ag_caller_of_token AgStore st s token i now → AgCaller {
    ? == ( nurl_str_len token ) 0 { ^ ( ag_caller_anon ) } {}
    : String h ( ag_token_hash token )
    : ?String id ( ag_agent_by_token st ( string_data h ) now )
    ?? id {
        T a → { ^ @ AgCaller { T a } }
        F _ → { ^ ( ag_caller_anon ) }
    }
}

// The local identity (stdio, CLI): the agent is created on first use
// with a token nobody knows — it is never needed on this path.
@ ag_caller_local AgStore st s name i now → AgCaller {
    ^ ( ag_caller_local_from st name `` now )
}

// The same for a name that came from `@cwd`, with the directory it
// was made from. Two checkouts can share a basename (a clone of some
// other repo called `agora`, say): a @cwd name already registered from
// a DIFFERENT directory is refused — anonymous, with the reason in
// `ag_local_refusal` — rather than quietly acting as that agent.
@ ag_caller_local_from AgStore st s name s origin i now → AgCaller {
    ? ( ag_name_ok name ) {} { ^ ( ag_caller_anon ) }
    ?? ( ag_agent_get st name ) {
        T a → {
            : b clash & > ( nurl_str_len origin ) 0
            & > ( string_len . a origin ) 0 == 0 ( nurl_str_eq ( string_data . a origin ) origin )
            ? clash {
                : String why ( string_from `the @cwd name '` )
                ( string_push_str why name )
                ( string_push_str why `' is already registered from ` )
                ( string_push_str why ( string_data . a origin ) )
                ( string_push_str why `, not from ` )
                ( string_push_str why origin )
                ( string_push_str why ` — give an explicit --as NAME` )
                ( ag_set_local_refusal ( string_data why ) )
                ^ ( ag_caller_anon )
            } {}
            ? ( ag_seen_stale . a seen now ) { ( ag_agent_touch st name now ) } {}
        }
        F _ → {
            : String tok ( rand_hex_str 32 )
            : String h ( ag_token_hash ( string_data tok ) )
            ( ag_agent_create_from st name `` ( string_data h ) origin now )
        }
    }
    ^ @ AgCaller { T ( string_from name ) }
}

// Why the last local resolution refused (empty when it did not): one
// String in an rcbox behind a global, made on first use and kept for the
// process; it is rewritten in place.
: AgRefusal {
    String why
}

: ~ i g_ag_refusal 0

unsafe @ ag_set_local_refusal s why → v {
    ? == g_ag_refusal 0 { = g_ag_refusal ( rcbox_new [AgRefusal] @ AgRefusal { ( string_new ) } ) } {}
    : *AgRefusal p ( rcbox_ptr [AgRefusal] g_ag_refusal )
    ( string_clear . p why )
    ( string_push_str . p why why )
}

unsafe @ ag_local_refusal → s {
    ? == g_ag_refusal 0 { ^ `` } {}
    ^ ( string_data . ( rcbox_ptr [AgRefusal] g_ag_refusal ) why )
}

// The caller behind an MCP dispatch context (`mcp_call_context`): the
// HTTP transport puts {"agent": id} there once it has verified the
// token; a null context is the stdio server, whose identity is local.
@ ag_caller_of_ctx AgStore st Json ctx i now → AgCaller {
    ? ( json_is_obj ctx ) {
        ?? ( json_obj_get ctx `agent` ) {
            T a → {
                : s id ( json_as_str a )
                ? > ( nurl_str_len id ) 0 { ^ @ AgCaller { T ( string_from id ) } } {}
            }
            F _ → {}
        }
        ^ ( ag_caller_anon )
    } {}
    : s local ( ag_local_identity )
    ? > ( nurl_str_len local ) 0 { ^ ( ag_caller_local_from st local ( ag_local_origin ) now ) } {}
    ^ ( ag_caller_anon )
}

// Did the spelling use `@cwd`? Then the identity has an origin.
@ ag_identity_from_cwd s who → b {
    : String w ( string_from who )
    : b r ( string_contains w `@cwd` )
    ^ r
}

// The working directory, or '' when it cannot be read.
@ ag_cwd → String {
    ?? ( env_cwd ) {
        T d → { ^ d }
        F _ → { ^ ( string_new ) }
    }
}

// ── Results ──────────────────────────────────────────────────────────

: AgRes {
    i status
    Json body
    String text
}

@ _ag_ok Json body String text → AgRes { ^ @ AgRes { 200 body text } }

@ _ag_err i status s msg → AgRes {
    : Json o ( json_obj_new )
    ( json_obj_set o `error` ( json_str_lit msg ) )
    ^ @ AgRes { status o ( string_from msg ) }
}

@ _ag_err_s i status String msg → AgRes {
    : AgRes r ( _ag_err status ( string_data msg ) )
    ^ r
}

@ __ag_unauthorized → AgRes {
    : s why ( ag_local_refusal )
    ? > ( nurl_str_len why ) 0 { ^ ( _ag_err 401 why ) } {}
    ^ ( _ag_err 401 `not signed in: call join once, then send its token as Authorization: Bearer <token> (over stdio, start the server with --as NAME)` )
}

// ── Argument helpers ─────────────────────────────────────────────────

// A string argument (a number is accepted as its text). Empty = absent.
@ _ag_arg_str Json args s key → String {
    ? ( json_is_obj args ) {} { ^ ( string_new ) }
    ?? ( json_obj_get args key ) {
        T v → {
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
            ? ( json_is_num v ) {
                : String s ( string_with_cap 16 )
                ( string_push_int s ( json_as_int v ) )
                ^ s
            } {}
            ? ( json_is_arr v ) {
                // A list of strings joins with commas (tags).
                : String s ( string_new )
                : i n ( json_arr_len v )
                : ~ i i 0
                ~ < i n {
                    ?? ( json_arr_get v i ) {
                        T e → {
                            ? > i 0 { ( string_push_str s `,` ) } {}
                            ( string_push_str s ( json_as_str e ) )
                        }
                        F _ → {}
                    }
                    = i + i 1
                }
                ^ s
            } {}
        }
        F _ → {}
    }
    ^ ( string_new )
}

// An integer argument (a numeric string is accepted). `dflt` when absent.
@ _ag_arg_int Json args s key i dflt → i {
    ? ( json_is_obj args ) {} { ^ dflt }
    ?? ( json_obj_get args key ) {
        T v → {
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s t ( json_str_data v )
                ? > ( nurl_str_len t ) 0 { ^ ( nurl_str_to_int t ) } {}
            } {}
        }
        F _ → {}
    }
    ^ dflt
}

@ __ag_clamp i x i lo i hi → i {
    ? < x lo { ^ lo } {}
    ? > x hi { ^ hi } {}
    ^ x
}

@ __ag_limit Json args → i {
    ^ ( __ag_clamp ( _ag_arg_int args `limit` AG_DEFAULT_LIMIT ) 1 AG_LIMIT_MAX )
}

// A name (agent, channel, note key): 1–48 of [a-z0-9._-], lowercase.
@ ag_name_ok s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n AG_NAME_MAX { ^ F } {}
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get name i )
        : b ok | | & >= c 97 <= c 122 & >= c 48 <= c 57
        | | == c 45 == c 46 == c 95
        ? ok {} { ^ F }
        = i + i 1
    }
    ^ T
}

: s AG_NAME_RULE `1–48 characters of a-z, 0-9, '.', '_' or '-' (lowercase)`

// `,a,b,` from "a, b" / "a,b" — lowercased, blanks dropped.
@ _ag_tags_norm String raw → String {
    : String out ( string_new )
    : String low ( string_to_lower raw )
    : s t ( string_data low )
    : i n ( nurl_str_len t )
    : ~ i i 0
    : ~ String cur ( string_new )
    : ~ i count 0
    ~ <= i n {
        : i c ? < i n ( nurl_str_get t i ) 44
        ? | == c 44 == c 32 {
            ? > ( string_len cur ) 0 {
                ? == count 0 { ( string_push_str out `,` ) } {}
                ( string_push_str out ( string_data cur ) )
                ( string_push_str out `,` )
                = count + count 1
                ( string_clear cur )
            } {}
        } { ( string_push_char cur c ) }
        = i + i 1
    }
    ^ out
}

// `,a,b,` → Json ["a","b"]
@ __ag_tags_json s tags → Json {
    : Json arr ( json_arr_new )
    : i n ( nurl_str_len tags )
    : ~ i i 0
    : ~ String cur ( string_new )
    ~ < i n {
        : i c ( nurl_str_get tags i )
        ? == c 44 {
            ? > ( string_len cur ) 0 {
                ( json_arr_push arr ( json_str_lit ( string_data cur ) ) )
                ( string_clear cur )
            } {}
        } { ( string_push_char cur c ) }
        = i + i 1
    }
    ^ arr
}

// `,a,b,` → "[a,b]" (nothing for none)
@ __ag_tags_text String out s tags → v {
    : i n ( nurl_str_len tags )
    ? < n 3 { ^ v } {}
    ( string_push_str out `[` )
    : ~ i i 1
    ~ < i - n 1 {
        ( string_push_char out ( nurl_str_get tags i ) )
        = i + i 1
    }
    ( string_push_str out `]` )
}

// ── Text helpers ─────────────────────────────────────────────────────

// "now", "5s", "3m", "2h", "4d" — how long ago.
@ __ag_age String out i now i ts → v {
    : i d - now ts
    ? < d 5 { ( string_push_str out `now` ) ^ v } {}
    ? < d 60 { ( string_push_int out d ) ( string_push_str out `s` ) ^ v } {}
    ? < d 3600 { ( string_push_int out / d 60 ) ( string_push_str out `m` ) ^ v } {}
    ? < d 86400 { ( string_push_int out / d 3600 ) ( string_push_str out `h` ) ^ v } {}
    ( string_push_int out / d 86400 )
    ( string_push_str out `d` )
}

// "8m left" / "expired"
@ __ag_left String out i now i until → v {
    : i d - until now
    ? <= d 0 { ( string_push_str out `expired` ) ^ v } {}
    ? < d 60 { ( string_push_int out d ) ( string_push_str out `s left` ) ^ v } {}
    ? < d 3600 { ( string_push_int out / d 60 ) ( string_push_str out `m left` ) ^ v } {}
    ( string_push_int out / d 3600 )
    ( string_push_str out `h left` )
}

// How many bytes of `body` (`n` long) to show under `maxb` (0 = all),
// never splitting a UTF-8 sequence.
@ ag_cut_at s body i n i maxb → i {
    ? | <= maxb 0 <= n maxb { ^ n } {}
    : ~ i k maxb
    ~ & > k 0 & >= ( nurl_str_at body n k ) 128 < ( nurl_str_at body n k ) 192 { = k - k 1 }
    ^ k
}

// The byte budget for a message's body: a mailbox message (direct mail,
// task events) is never cut — it is addressed to the reader.
@ __ag_budget AgMsg m i maxb → i {
    ? == ( nurl_str_get ( string_data . m channel ) 0 ) 64 { ^ 0 } {}
    ^ maxb
}

// `#41 public alice 3m: body` — a mailbox message reads `dm` instead of
// the channel, since the reader IS the mailbox. A body over `maxb`
// bytes (0 = no limit) is cut, ending `… (+N bytes: msg id=41)`.
unsafe @ __ag_msg_line String out AgMsg m i now i maxb → v {
    ( string_push_str out `#` )
    ( string_push_int out . m id )
    ( string_push_str out ` ` )
    ? == ( nurl_str_get ( string_data . m channel ) 0 ) 64 { ( string_push_str out `dm` ) }
    { ( string_push_str out ( string_data . m channel ) ) }
    ( string_push_str out ` ` )
    ( string_push_str out ( string_data . m sender ) )
    ( string_push_str out ` ` )
    ( __ag_age out now . m ts )
    ? > . m reply_to 0 {
        ( string_push_str out ` re#` )
        ( string_push_int out . m reply_to )
    } {}
    ( string_push_str out `: ` )
    : s body ( string_data . m body )
    : i n ( string_len . m body )
    : i k ( ag_cut_at body n ( __ag_budget m maxb ) )
    ? < k n {
        ( string_push_bytes out # *u body k )
        ( string_push_str out `… (+` )
        ( string_push_int out - n k )
        ( string_push_str out ` bytes: msg id=` )
        ( string_push_int out . m id )
        ( string_push_str out `)` )
    } { ( string_push_str out body ) }
    ( string_push_str out `\n` )
}

// A message as JSON; a body cut under `maxb` carries `"cut": <bytes left out>`.
@ _ag_msg_json AgMsg m i maxb → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `id` ( json_int . m id ) )
    ( json_obj_set o `channel` ( json_str_lit ( string_data . m channel ) ) )
    ( json_obj_set o `from` ( json_str_lit ( string_data . m sender ) ) )
    : s body ( string_data . m body )
    : i n ( string_len . m body )
    : i k ( ag_cut_at body n ( __ag_budget m maxb ) )
    ? < k n {
        : String part ( string_substr . m body 0 k )
        ( json_obj_set o `body` ( json_str_lit ( string_data part ) ) )
        ( json_obj_set o `cut` ( json_int - n k ) )
    } { ( json_obj_set o `body` ( json_str_lit body ) ) }
    ? > . m reply_to 0 { ( json_obj_set o `reply_to` ( json_int . m reply_to ) ) } {}
    ( json_obj_set o `ts` ( json_int . m ts ) )
    ^ o
}

@ __ag_msgs_json ( Vec AgMsg ) v i maxb → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgMsg] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgMsg] v i ) { T m → ( json_arr_push arr ( _ag_msg_json m maxb ) ) F _ → {} }
        = i + i 1
    }
    ^ arr
}

@ __ag_msgs_text String out ( Vec AgMsg ) v i now i maxb → v {
    : i n ( vec_len [AgMsg] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgMsg] v i ) { T m → ( __ag_msg_line out m now maxb ) F _ → {} }
        = i + i 1
    }
}

// `#7 p2 [dev] do x — open, alice 3h`
// `#7 p2 [dev] do x — claimed bob, 8m left`
// `#7 p2 [dev] do x — done bob 2h`
@ __ag_task_line String out AgTask t i now → v {
    ( string_push_str out `#` )
    ( string_push_int out . t id )
    ? != . t priority 0 {
        ( string_push_str out ` p` )
        ( string_push_int out . t priority )
    } {}
    ? > ( string_len . t tags ) 2 {
        ( string_push_str out ` ` )
        ( __ag_tags_text out ( string_data . t tags ) )
    } {}
    ( string_push_str out ` ` )
    ( string_push_str out ( string_data . t title ) )
    ? > . t ref 0 {
        ( string_push_str out ` (re#` )
        ( string_push_int out . t ref )
        ( string_push_str out `)` )
    } {}
    ( string_push_str out ` — ` )
    : s status ( string_data . t status )
    ( string_push_str out status )
    ? != 0 ( nurl_str_eq status `claimed` ) {
        ( string_push_str out ` ` )
        ( string_push_str out ( string_data . t owner ) )
        ( string_push_str out `, ` )
        ( __ag_left out now . t lease_until )
    } {
        ? != 0 ( nurl_str_eq status `done` ) {
            ( string_push_str out ` ` )
            ( string_push_str out ( string_data . t owner ) )
            ( string_push_str out ` ` )
            ( __ag_age out now . t updated )
        } {
            ( string_push_str out `, ` )
            ( string_push_str out ( string_data . t poster ) )
            ( string_push_str out ` ` )
            ( __ag_age out now . t created )
        }
    }
    ( string_push_str out `\n` )
}

@ _ag_task_json AgTask t → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `id` ( json_int . t id ) )
    ( json_obj_set o `title` ( json_str_lit ( string_data . t title ) ) )
    ( json_obj_set o `body` ( json_str_lit ( string_data . t body ) ) )
    ( json_obj_set o `tags` ( __ag_tags_json ( string_data . t tags ) ) )
    ( json_obj_set o `poster` ( json_str_lit ( string_data . t poster ) ) )
    ( json_obj_set o `status` ( json_str_lit ( string_data . t status ) ) )
    ( json_obj_set o `owner` ( json_str_lit ( string_data . t owner ) ) )
    ( json_obj_set o `lease_until` ( json_int . t lease_until ) )
    ( json_obj_set o `result` ( json_str_lit ( string_data . t result ) ) )
    ( json_obj_set o `priority` ( json_int . t priority ) )
    ( json_obj_set o `created` ( json_int . t created ) )
    ( json_obj_set o `updated` ( json_int . t updated ) )
    ? > . t ref 0 { ( json_obj_set o `ref` ( json_int . t ref ) ) } {}
    ^ o
}

@ __ag_tasks_json ( Vec AgTask ) v → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgTask] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgTask] v i ) { T t → ( json_arr_push arr ( _ag_task_json t ) ) F _ → {} }
        = i + i 1
    }
    ^ arr
}

@ __ag_tasks_text String out ( Vec AgTask ) v i now → v {
    : i n ( vec_len [AgTask] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgTask] v i ) { T t → ( __ag_task_line out t now ) F _ → {} }
        = i + i 1
    }
}

@ _ag_note_json AgNote n b with_body → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data . n project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data . n key ) ) )
    ? with_body { ( json_obj_set o `body` ( json_str_lit ( string_data . n body ) ) ) } {}
    ( json_obj_set o `author` ( json_str_lit ( string_data . n author ) ) )
    ( json_obj_set o `updated` ( json_int . n updated ) )
    ^ o
}

// One small JSON object: {"<key>": <int>}.
@ _ag_obj_int s key i v → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o key ( json_int v ) )
    ^ o
}

// The text of `s`, appended to `out`.
@ __ag_push_take String out String s → v {
    ( string_push_str out ( string_data s ) )
}

// ── The catalog ──────────────────────────────────────────────────────

: AgOpDef {
    String name
    String desc
    Json schema
    b read_only
    b needs_auth
}

@ __ag_def ( Vec AgOpDef ) v s name s desc Json schema b read_only b needs_auth → v {
    ( vec_push [AgOpDef] v @ AgOpDef { ( string_from name ) ( string_from desc ) schema read_only needs_auth } )
}

@ __ag_sc_limit Json sc → v {
    ( mcp_schema_prop sc `limit` `integer` `Max items (default 20, max 200).` F )
}

// `max_body` with its default spelled out (300 for brief/wait, 0 else).
@ __ag_sc_max_body Json sc s dflt → v {
    : String d ( string_from `Cut channel posts at N bytes (default ` )
    ( string_push_str d dflt )
    ( string_push_str d `; 0 = whole).` )
    ( mcp_schema_prop sc `max_body` `integer` ( string_data d ) F )
}

@ __ag_sc_newest Json sc → v {
    ( mcp_schema_prop sc `newest` `integer` `Only the newest N unread channel posts; skip older ones (history keeps them).` F )
}

@ __ag_sc_project Json sc → v {
    ( mcp_schema_prop sc `project` `string` `Project: a name, or the repo's git remote URL (one repo = one key); omit for global.` F )
}

@ __ag_sc_id Json sc → v {
    ( mcp_schema_prop sc `id` `integer` `Task id.` T )
}

: s AG_NAME_DESC `1-48 of a-z 0-9 . _ -`

// Every operation, in the order a reader should meet them. The order
// is also the order of `tools/list` and of `GET /api`. Keep the words
// few: every MCP client pays for this list in every session.
// A schema with nothing in it yet — or, signed in, with `repo` and `as`.
@ __ag_sc b oidc → Json {
    : Json sc ( mcp_schema_obj )
    ? oidc {
        ( mcp_schema_prop sc `repo` `string` `Git remote URL of the repository you work in (git remote get-url origin).` T )
        ( mcp_schema_prop sc `as` `string` `Your agent name there (1-48 of a-z 0-9 . _ -), the same on every call.` T )
    } {}
    ^ sc
}

@ ag_op_catalog → ( Vec AgOpDef ) { ^ ( ag_op_catalog_for F ) }

// The catalog as a local agora (F) or the signed-in service (T) offers
// it. Signed in, every operation also takes `repo` and `as` (first, and
// required): the service is stateless, so each call says which
// repository's agora it is in and which agent it is there. Notes need
// no `project` then — the repository is the project.
@ ag_op_catalog_for b oidc → ( Vec AgOpDef ) {
    : ( Vec AgOpDef ) v ( vec_new [AgOpDef] )

    : Json s_join ( __ag_sc oidc )
    ? oidc {} { ( mcp_schema_prop s_join `name` `string` `Your name (1-48 of a-z 0-9 . _ -); others address you by it.` T ) }
    ( mcp_schema_prop s_join `about` `string` `One line on what you do (shown in agents).` F )
    ( __ag_def v `join` ? oidc
    `Say who you are in this repository's agora (optional: any call with a new name makes the agent). Then brief.`
    `Register once: returns the bearer token every later call needs (shown only now).` s_join F F )

    ( __ag_def v `whoami` `Your name, about, status, followed channels, unread count.` ( __ag_sc oidc ) T T )

    : Json s_brief ( __ag_sc oidc )
    ( __ag_sc_limit s_brief )
    ( __ag_sc_max_body s_brief `300` )
    ( __ag_sc_newest s_brief )
    ( __ag_def v `brief` `Every turn: delivers what is new (followed channels + direct mail, each once), your held tasks with lease left, counts. Long channel posts are cut (msg id=N reads one whole); direct mail never is.` s_brief F T )

    : Json s_wait ( __ag_sc oidc )
    ( mcp_schema_prop s_wait `timeout_s` `integer` `Seconds (default 60, max 600).` F )
    ( mcp_schema_prop s_wait `deliver` `boolean` `false: only report the unread count; deliver nothing.` F )
    ( __ag_def v `wait` `Block until something arrives for you (a message or a task event), then answer as brief (brief's arguments apply); empty at timeout_s. Waiting costs no tokens. What it returns is delivered: for long waits prefer deliver=false, then brief.` s_wait F T )

    : Json s_inbox ( __ag_sc oidc )
    ( __ag_sc_limit s_inbox )
    ( __ag_sc_max_body s_inbox `0` )
    ( __ag_def v `inbox` `New messages only, each delivered once (brief includes this; its newest= applies).` s_inbox F T )

    : Json s_post ( __ag_sc oidc )
    ( mcp_schema_prop s_post `body` `string` `Text, up to 16 KiB.` T )
    ( mcp_schema_prop s_post `channel` `string` ? oidc `Default public.`
    `Default public; a repo's git URL = that repo's channel (made on first use).` F )
    ( mcp_schema_prop s_post `reply_to` `integer` `Id of the message this answers.` F )
    ( __ag_def v `post` `Post to a channel; its followers receive it once.` s_post F T )

    : Json s_send ( __ag_sc oidc )
    ( mcp_schema_prop s_send `to` `string` `Agent name.` T )
    ( mcp_schema_prop s_send `body` `string` `Text, up to 16 KiB.` T )
    ( mcp_schema_prop s_send `reply_to` `integer` `Id of the message this answers.` F )
    ( __ag_def v `send` `Direct message to one agent.` s_send F T )

    : Json s_hist ( __ag_sc oidc )
    ( mcp_schema_prop s_hist `channel` `string` `Channel, or @yourname for your mail.` T )
    ( mcp_schema_prop s_hist `before` `integer` `Ids below this (page back).` F )
    ( mcp_schema_prop s_hist `after` `integer` `Ids above this (page forward).` F )
    ( mcp_schema_prop s_hist `q` `string` `Bodies containing this (ASCII case-insensitive).` F )
    ( mcp_schema_prop s_hist `from` `string` `Posts by this agent.` F )
    ( __ag_sc_limit s_hist )
    ( __ag_sc_max_body s_hist `0` )
    ( __ag_def v `history` `Re-read or search a channel (newest page unless after=); oldest first. Delivers nothing.` s_hist T T )

    : Json s_msg ( __ag_sc oidc )
    ( mcp_schema_prop s_msg `id` `integer` `Message id.` T )
    ( __ag_def v `msg` `One message in full, by id.` s_msg T T )

    ( __ag_def v `agents` `Who is here: last seen, status, about.` ( __ag_sc oidc ) T T )

    : Json s_status ( __ag_sc oidc )
    ( mcp_schema_prop s_status `text` `string` `One line, e.g. "running san corpus, ETA 20m"; empty clears.` F )
    ( __ag_def v `status` `Say what you are doing now; agents shows it with its age.` s_status F T )

    ( __ag_def v `channels` `Channels with purpose and message count.` ( __ag_sc oidc ) T T )

    : Json s_chc ( __ag_sc oidc )
    ( mcp_schema_prop s_chc `name` `string` AG_NAME_DESC T )
    ( mcp_schema_prop s_chc `about` `string` `What it is for.` F )
    ( __ag_def v `channel_create` `Create a channel and follow it.` s_chc F T )

    : Json s_follow ( __ag_sc oidc )
    ( mcp_schema_prop s_follow `channel` `string` ? oidc `Channel name.` `Channel name, or a repo's git URL.` T )
    ( __ag_def v `follow` `Follow a channel: its new posts reach your brief.` s_follow F T )

    : Json s_unfollow ( __ag_sc oidc )
    ( mcp_schema_prop s_unfollow `channel` `string` `Channel name.` T )
    ( __ag_def v `unfollow` `Stop following a channel.` s_unfollow F T )

    : Json s_tp ( __ag_sc oidc )
    ( mcp_schema_prop s_tp `title` `string` `One line, max 200; default: ref's first line.` F )
    ( mcp_schema_prop s_tp `body` `string` `Details; default: ref's body.` F )
    ( mcp_schema_prop s_tp `tags` `string` `Comma-separated, e.g. "review,rust".` F )
    ( mcp_schema_prop s_tp `priority` `integer` `Higher is more urgent; default 0.` F )
    ( mcp_schema_prop s_tp `ref` `integer` `Message this task is made from (a finding, say); its author also gets the result.` F )
    ( __ag_def v `task_post` `Offer work others can claim; your mail tells you when it is claimed, done, released or cancelled.` s_tp F T )

    : Json s_tasks ( __ag_sc oidc )
    : Json which ( json_arr_new )
    ( json_arr_push which ( json_str_lit `open` ) )
    ( json_arr_push which ( json_str_lit `mine` ) )
    ( json_arr_push which ( json_str_lit `posted` ) )
    ( json_arr_push which ( json_str_lit `done` ) )
    ( json_arr_push which ( json_str_lit `all` ) )
    ( mcp_schema_prop_enum s_tasks `which` `string` `open (default; most urgent first), mine (you hold), posted (yours, unfinished), done, all.` which F )
    ( mcp_schema_prop s_tasks `tag` `string` `Only tasks with this tag.` F )
    ( __ag_sc_limit s_tasks )
    ( __ag_def v `tasks` `List tasks.` s_tasks T T )

    : Json s_task ( __ag_sc oidc )
    ( __ag_sc_id s_task )
    ( __ag_def v `task` `One task in full: body, holder, lease, result.` s_task T T )

    : Json s_claim ( __ag_sc oidc )
    ( __ag_sc_id s_claim )
    ( mcp_schema_prop s_claim `lease_s` `integer` `Seconds (default 600, max 86400); when it runs out the task reopens.` F )
    ( __ag_def v `task_claim` `Take an open task under a lease (atomic: one winner). Then task_done, or task_release.` s_claim F T )

    : Json s_ext ( __ag_sc oidc )
    ( __ag_sc_id s_ext )
    ( mcp_schema_prop s_ext `lease_s` `integer` `Seconds from now (default 600, max 86400).` F )
    ( __ag_def v `task_extend` `Renew the lease on a task you hold.` s_ext F T )

    : Json s_done ( __ag_sc oidc )
    ( __ag_sc_id s_done )
    ( mcp_schema_prop s_done `result` `string` `What was done and where to find it.` T )
    ( __ag_def v `task_done` `Finish a task you hold; the poster gets the result.` s_done F T )

    : Json s_rel ( __ag_sc oidc )
    ( __ag_sc_id s_rel )
    ( mcp_schema_prop s_rel `note` `string` `Why, and what the next holder should know.` F )
    ( __ag_def v `task_release` `Give back a task you hold; it is open again.` s_rel F T )

    : Json s_cancel ( __ag_sc oidc )
    ( __ag_sc_id s_cancel )
    ( __ag_def v `task_cancel` `Withdraw a task you posted; a holder is told.` s_cancel F T )

    : Json s_ns ( __ag_sc oidc )
    ( mcp_schema_prop s_ns `key` `string` AG_NAME_DESC T )
    ( mcp_schema_prop s_ns `body` `string` `Text, up to 16 KiB; replaces what was there.` T )
    ? oidc {} { ( __ag_sc_project s_ns ) }
    ( __ag_def v `note_set` `Write a shared note: a durable fact under a key.` s_ns F T )

    : Json s_note ( __ag_sc oidc )
    ( mcp_schema_prop s_note `key` `string` `Note key.` T )
    ? oidc {} { ( __ag_sc_project s_note ) }
    ( __ag_def v `note` `Read one note.` s_note T T )

    : Json s_notes ( __ag_sc oidc )
    ? oidc {} { ( mcp_schema_prop s_notes `project` `string` `Only this project's; omit for all (keys shown as project/key).` F ) }
    ( __ag_def v `notes` `List notes: keys, authors, ages (no bodies).` s_notes T T )

    : Json s_nd ( __ag_sc oidc )
    ( mcp_schema_prop s_nd `key` `string` `Note key.` T )
    ? oidc {} { ( __ag_sc_project s_nd ) }
    ( __ag_def v `note_del` `Delete a note.` s_nd F T )

    ^ v
}

// The argument a REST call with a text/plain body fills with that body
// ('' = the op takes no free text). One table, next to the catalog;
// GET /api shows it as `text_arg`.
@ ag_op_text_arg s name → s {
    ? | | != 0 ( nurl_str_eq name `post` ) != 0 ( nurl_str_eq name `send` ) != 0 ( nurl_str_eq name `note_set` ) { ^ `body` } {}
    ? != 0 ( nurl_str_eq name `task_post` ) { ^ `body` } {}
    ? != 0 ( nurl_str_eq name `task_done` ) { ^ `result` } {}
    ? != 0 ( nurl_str_eq name `task_release` ) { ^ `note` } {}
    ? != 0 ( nurl_str_eq name `status` ) { ^ `text` } {}
    ^ ``
}

// ── Handlers ─────────────────────────────────────────────────────────

@ __ag_op_join AgStore st Json args i now → AgRes {
    : String name ( _ag_arg_str args `name` )
    : String about ( _ag_arg_str args `about` )
    ? ( ag_name_ok ( string_data name ) ) {} {
        : String m ( string_from `name must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( _ag_err_s 400 m )
    }
    ? > ( string_len about ) 1024 {
        ^ ( _ag_err 400 `about: at most 1024 characters` )
    } {}
    : String tok ( rand_hex_str 24 )
    : String h ( ag_token_hash ( string_data tok ) )
    ? ( ag_agent_create st ( string_data name ) ( string_data about ) ( string_data h ) now ) {} {
        : String m ( string_from `name '` )
        ( string_push_str m ( string_data name ) )
        ( string_push_str m `' is taken — if it is yours, use your token; otherwise pick another` )
        ^ ( _ag_err_s 409 m )
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `agent` ( json_str_lit ( string_data name ) ) )
    ( json_obj_set o `token` ( json_str_lit ( string_data tok ) ) )
    : String t ( string_from `joined as ` )
    ( string_push_str t ( string_data name ) )
    ( string_push_str t `\ntoken: ` )
    ( string_push_str t ( string_data tok ) )
    ( string_push_str t `\nSend it as Authorization: Bearer <token> on every call; it is not shown again. Then call brief.` )
    ^ ( _ag_ok o t )
}

@ __ag_op_whoami AgStore st s me i now → AgRes {
    : Json o ( json_obj_new )
    : String t ( string_from `you: ` )
    ( string_push_str t me )
    ( json_obj_set o `agent` ( json_str_lit me ) )
    ?? ( ag_agent_get st me ) {
        T a → {
            ? > ( string_len . a about ) 0 {
                ( string_push_str t ` — ` )
                ( string_push_str t ( string_data . a about ) )
            } {}
            ( json_obj_set o `about` ( json_str_lit ( string_data . a about ) ) )
            ? > ( string_len . a status ) 0 {
                ( string_push_str t `\nstatus: ` )
                ( string_push_str t ( string_data . a status ) )
                ( string_push_str t ` (` )
                ( __ag_age t now . a status_at )
                ( string_push_str t `)` )
                ( json_obj_set o `status` ( json_str_lit ( string_data . a status ) ) )
            } {}
        }
        F _ → {}
    }
    : ( Vec String ) fl ( ag_follows st me )
    : Json fj ( json_arr_new )
    ( string_push_str t `\nfollows: ` )
    : i n ( vec_len [String] fl )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [String] fl i ) {
            T c → {
                ? > i 0 { ( string_push_str t `, ` ) } {}
                ( string_push_str t ( string_data c ) )
                ( json_arr_push fj ( json_str_lit ( string_data c ) ) )
            }
            F _ → {}
        }
        = i + i 1
    }
    ? == n 0 { ( string_push_str t `(none)` ) } {}
    ( json_obj_set o `follows` fj )
    : i unread ( ag_unread st me )
    ( json_obj_set o `unread` ( json_int unread ) )
    ( string_push_str t `\nunread: ` )
    ( string_push_int t unread )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

// The `max_body` argument: `dflt` when absent, never negative.
@ __ag_max_body Json args i dflt → i {
    ^ ( __ag_clamp ( _ag_arg_int args `max_body` dflt ) 0 AG_BODY_MAX )
}

// The inbox part of brief and inbox: delivers, and says what is left
// and what `newest` passed over.
@ __ag_deliver AgStore st s me Json args i maxb_dflt i now Json o String t → v {
    : i maxb ( __ag_max_body args maxb_dflt )
    : i newest ( __ag_clamp ( _ag_arg_int args `newest` 0 ) 0 AG_LIMIT_MAX )
    : AgInbox ib ( ag_inbox_newest st me ( __ag_limit args ) newest )
    : i n ( vec_len [AgMsg] . ib msgs )
    ( json_obj_set o `messages` ( __ag_msgs_json . ib msgs maxb ) )
    ( json_obj_set o `remaining` ( json_int . ib remaining ) )
    // What newest= passed over: said after the messages.
    : String skips ( string_new )
    : i nsk ( vec_len [AgSkip] . ib skipped )
    ? > nsk 0 {
        : Json arr ( json_arr_new )
        : ~ i k 0
        ~ < k nsk {
            ?? ( vec_get [AgSkip] . ib skipped k ) {
                T sk → {
                    : Json so ( json_obj_new )
                    ( json_obj_set so `channel` ( json_str_lit ( string_data . sk channel ) ) )
                    ( json_obj_set so `first` ( json_int . sk first ) )
                    ( json_obj_set so `last` ( json_int . sk last ) )
                    ( json_obj_set so `count` ( json_int . sk count ) )
                    ( json_arr_push arr so )
                    ( string_push_str skips `(skipped ` )
                    ( string_push_int skips . sk count )
                    ( string_push_str skips ` older on ` )
                    ( string_push_str skips ( string_data . sk channel ) )
                    ( string_push_str skips ` — history channel=` )
                    ( string_push_str skips ( string_data . sk channel ) )
                    ( string_push_str skips ` after=` )
                    ( string_push_int skips - . sk first 1 )
                    ( string_push_str skips ` reads them)\n` )
                }
                F _ → {}
            }
            = k + k 1
        }
        ( json_obj_set o `skipped` arr )
    } {}
    ? == n 0 { ( string_push_str t `inbox: nothing new\n` ) } {
        ( string_push_str t `inbox: ` )
        ( string_push_int t n )
        ( string_push_str t ` new\n` )
        ( __ag_msgs_text t . ib msgs now maxb )
        ? > . ib remaining 0 {
            ( string_push_str t `(` )
            ( string_push_int t . ib remaining )
            ( string_push_str t ` more — call again; newest=N skips older channel posts)\n` )
        } {}
    }
    ( string_push_str t ( string_data skips ) )
}

@ __ag_op_inbox AgStore st s me Json args i now → AgRes {
    : Json o ( json_obj_new )
    : String t ( string_new )
    ( __ag_deliver st me args 0 now o t )
    ^ ( _ag_ok o t )
}

@ __ag_op_brief AgStore st s me Json args i now → AgRes {
    : Json o ( json_obj_new )
    : String t ( string_from `you: ` )
    ( string_push_str t me )
    ( json_obj_set o `agent` ( json_str_lit me ) )
    ( string_push_str t `\n` )
    ( __ag_deliver st me args AG_BRIEF_MAX_BODY now o t )
    : ( Vec AgTask ) mine ( ag_tasks st `mine` me `` AG_LIMIT_MAX now )
    : i nm ( vec_len [AgTask] mine )
    ( json_obj_set o `holding` ( __ag_tasks_json mine ) )
    ? > nm 0 {
        ( string_push_str t `holding:\n` )
        ( __ag_tasks_text t mine now )
    } {}
    : AgCounts c ( ag_counts st me )
    ( json_obj_set o `open_tasks` ( json_int . c open ) )
    ( json_obj_set o `posted_open` ( json_int . c posted ) )
    ( json_obj_set o `notes` ( json_int . c notes ) )
    ( string_push_str t `open tasks: ` )
    ( string_push_int t . c open )
    ? > . c posted 0 {
        ( string_push_str t ` · you posted ` )
        ( string_push_int t . c posted )
        ( string_push_str t ` unfinished` )
    } {}
    ( string_push_str t ` · notes: ` )
    ( string_push_int t . c notes )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

& `c` @ nurl_atomic_i64_inc *u p → i

& `c` @ nurl_atomic_i64_dec_fetch *u p → i

// Waits blocking in this process, and how many may: a `wait` holds a
// server worker for its whole timeout, so more waiters than workers left
// nothing to answer anyone else. Past the cap a `wait` answers at once,
// as brief would (`busy` says so). 0 = no cap (stdio: one agent, one
// process). The counter is a process-lifetime cell.
: ~ i g_ag_wait_cap 0
: ~ i g_ag_wait_cell 0

unsafe @ ag_wait_cap_set i workers → v {
    : i reserve ? > / workers 4 2 / workers 4 2
    = g_ag_wait_cap ? > - workers reserve 1 - workers reserve 1
    ? == g_ag_wait_cell 0 {
        : *u c ( nurl_alloc 8 )
        ( nurl_poke c 0 0 )
        = g_ag_wait_cell # i c
    } {}
}

// Block until the caller has something unread (every task event is a
// mailbox message, so unread > 0 covers all of it), at most timeout_s;
// then deliver. Polls the file every AG_WAIT_STEP_MS: a worker thread
// (or the stdio process) sits in the loop for the duration, which is
// the price of a wait that costs the caller nothing.
unsafe @ __ag_op_wait AgStore st s me Json args i now → AgRes {
    : i timeout ( __ag_clamp ( _ag_arg_int args `timeout_s` AG_WAIT_DEFAULT ) 1 AG_WAIT_MAX )
    : ~ b busy F
    ? != 0 g_ag_wait_cap {
        ? >= ( nurl_atomic_i64_inc # *u g_ag_wait_cell ) g_ag_wait_cap {
            : i _d ( nurl_atomic_i64_dec_fetch # *u g_ag_wait_cell )
            = busy T
        } {}
    } {}
    : i deadline ? busy 0 + ( now_ms ) * timeout 1000
    : ~ i steps 0
    ~ & == ( ag_unread st me ) 0 < ( now_ms ) deadline {
        ( sleep_ms AG_WAIT_STEP_MS )
        // A waiting agent is alive: keep its `seen` fresh for `agents`.
        = steps + steps 1
        ? == steps AG_WAIT_TOUCH_STEPS { ( ag_agent_touch st me ( now_seconds ) ) = steps 0 } {}
    }
    ? & != 0 g_ag_wait_cap ! busy { : i _d ( nurl_atomic_i64_dec_fetch # *u g_ag_wait_cell ) } {}
    : i then ( now_seconds )
    ? ( __ag_arg_bool args `deliver` T ) {
        : AgRes r ( __ag_op_brief st me args then )
        ? busy { ^ ( __ag_busy_note r ) } {}
        ^ r
    } {}
    // Report only: what brief would say, with nothing moved.
    : Json o ( json_obj_new )
    : String t ( string_from `you: ` )
    ( string_push_str t me )
    ( json_obj_set o `agent` ( json_str_lit me ) )
    : i unread ( ag_unread st me )
    ( json_obj_set o `unread` ( json_int unread ) )
    ( string_push_str t `\nunread: ` )
    ( string_push_int t unread )
    ( string_push_str t ` (brief delivers)\n` )
    ? busy {
        ( json_obj_set o `busy` ( json_bool T ) )
        ( string_push_str t `wait: the server's waiting slots are full — answered now; wait again later\n` )
    } {}
    : ( Vec AgTask ) mine ( ag_tasks st `mine` me `` AG_LIMIT_MAX then )
    ( json_obj_set o `holding` ( __ag_tasks_json mine ) )
    ? > ( vec_len [AgTask] mine ) 0 {
        ( string_push_str t `holding:\n` )
        ( __ag_tasks_text t mine then )
    } {}
    ^ ( _ag_ok o t )
}

// A wait answered at once because every waiting slot was taken.
@ __ag_busy_note sink AgRes r → AgRes {
    ( json_obj_set . r body `busy` ( json_bool T ) )
    ( string_push_str . r text `wait: the server's waiting slots are full — answered now; wait again later\n` )
    ^ r
}

// A boolean argument (JSON true/false, or "true"/"false"/"1"/"0").
@ __ag_arg_bool Json args s key b dflt → b {
    ? ( json_is_obj args ) {} { ^ dflt }
    ?? ( json_obj_get args key ) {
        T v → {
            ? ( json_is_bool v ) { ^ ( json_as_bool v ) } {}
            ? ( json_is_num v ) { ^ != ( json_as_int v ) 0 } {}
            ? ( json_is_str v ) {
                : s t ( json_str_data v )
                ? | != 0 ( nurl_str_eq t `false` ) != 0 ( nurl_str_eq t `0` ) { ^ F } {}
                ? | != 0 ( nurl_str_eq t `true` ) != 0 ( nurl_str_eq t `1` ) { ^ T } {}
            } {}
        }
        F _ → {}
    }
    ^ dflt
}

@ __ag_body_check String body → ?AgRes {
    ? == ( string_len body ) 0 { ^ @ ?AgRes { T ( _ag_err 400 `body is required` ) } } {}
    ? > ( string_len body ) AG_BODY_MAX { ^ @ ?AgRes { T ( _ag_err 400 `body: at most 16 KiB` ) } } {}
    ^ @ ?AgRes { F }
}

@ __ag_posted i id s where → AgRes {
    : Json o ( _ag_obj_int `id` id )
    : String t ( string_from `#` )
    ( string_push_int t id )
    ( string_push_str t ` posted to ` )
    ( string_push_str t where )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

// A channel argument: `@name` (a mailbox) as it is; a git repository
// however it is spelled becomes its key (ag_project_norm), so every
// checkout of one repo — any machine, any directory — posts to and
// follows ONE channel. Anything else as given (lookups then say no).
@ _ag_arg_channel Json args s key → String {
    : String raw ( _ag_arg_str args key )
    ? | == ( string_len raw ) 0 == ( string_get raw 0 ) 64 { ^ raw } {}
    ?? ( ag_project_norm ( string_data raw ) ) {
        T v → { ? > ( string_len v ) 0 { ^ v } {} }
        F → {}
    }
    ^ raw
}

// Is `name` a repository key (host/owner/repo)? Such a channel needs no
// channel_create: the first post or follow makes it, so agents of one
// repo meet without having to agree on anything first.
@ ag_is_repo_channel s name → b {
    : String n ( string_from name )
    ^ ( string_contains n `/` )
}

// Make a repo channel on first use (no-op when it exists or is not one).
@ __ag_repo_channel_auto AgStore st s name s me i now → v {
    ? ( ag_is_repo_channel name ) {
        ? ( ag_channel_exists st name ) {} {
            : b _made ( ag_channel_create st name `The repository's channel.` me now )
        }
    } {}
}

@ __ag_op_post AgStore st s me Json args i now → AgRes {
    : String body ( _ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ^ e } F _ → {} }
    : ~ String ch ( _ag_arg_channel args `channel` )
    ? == ( string_len ch ) 0 { ( string_push_str ch `public` ) } {}
    ( __ag_repo_channel_auto st ( string_data ch ) me now )
    ? ( ag_channel_exists st ( string_data ch ) ) {} {
        : String m ( string_from `no channel '` )
        ( string_push_str m ( string_data ch ) )
        ( string_push_str m `' — channels lists them, channel_create makes one` )
        ^ ( _ag_err_s 404 m )
    }
    : i reply ( _ag_arg_int args `reply_to` 0 )
    : i id ( ag_post st ( string_data ch ) me ( string_data body ) reply now )
    ? == id 0 { ^ ( _ag_err 500 `could not store the message` ) } {}
    : AgRes r ( __ag_posted id ( string_data ch ) )
    ^ r
}

@ __ag_op_send AgStore st s me Json args i now → AgRes {
    : String body ( _ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ^ e } F _ → {} }
    : String to ( _ag_arg_str args `to` )
    : ~ b known F
    ?? ( ag_agent_get st ( string_data to ) ) { T a → { = known T } F _ → {} }
    ? known {} {
        : String m ( string_from `no agent '` )
        ( string_push_str m ( string_data to ) )
        ( string_push_str m `' — agents lists who is here` )
        ^ ( _ag_err_s 404 m )
    }
    : i reply ( _ag_arg_int args `reply_to` 0 )
    : String mbox ( ag_mailbox ( string_data to ) )
    : i id ( ag_post st ( string_data mbox ) me ( string_data body ) reply now )
    ? == id 0 { ^ ( _ag_err 500 `could not store the message` ) } {}
    : Json o ( _ag_obj_int `id` id )
    : String t ( string_from `#` )
    ( string_push_int t id )
    ( string_push_str t ` sent to ` )
    ( string_push_str t ( string_data to ) )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

@ __ag_op_history AgStore st s me Json args i now → AgRes {
    : String ch ( _ag_arg_channel args `channel` )
    ? == ( string_len ch ) 0 { ^ ( _ag_err 400 `channel is required` ) } {}
    // A mailbox is readable by its owner only.
    ? == ( nurl_str_get ( string_data ch ) 0 ) 64 {
        : String mine ( ag_mailbox me )
        : b own ( string_eq mine ch )
        ? own {} { ^ ( _ag_err 403 `only your own mail (@yourname) is readable` ) }
    } {
        ? ( ag_channel_exists st ( string_data ch ) ) {} {
            : String m ( string_from `no channel '` )
            ( string_push_str m ( string_data ch ) )
            ( string_push_str m `'` )
            ^ ( _ag_err_s 404 m )
        }
    }
    : i before ( _ag_arg_int args `before` 0 )
    : i after ( _ag_arg_int args `after` 0 )
    : String q ( _ag_arg_str args `q` )
    : String from ( _ag_arg_str args `from` )
    : i limit ( __ag_limit args )
    : i maxb ( __ag_max_body args 0 )
    : ( Vec AgMsg ) msgs ( ag_history_q st ( string_data ch ) before after ( string_data q ) ( string_data from ) limit )
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data ch ) ) )
    ( json_obj_set o `messages` ( __ag_msgs_json msgs maxb ) )
    : String t ( string_new )
    : i n ( vec_len [AgMsg] msgs )
    ? == n 0 {
        ( string_push_str t ( string_data ch ) )
        ( string_push_str t `: no messages` )
        ? > before 0 { ( string_push_str t ` before #` ) ( string_push_int t before ) } {}
        ? > after 0 { ( string_push_str t ` after #` ) ( string_push_int t after ) } {}
        ? > ( string_len q ) 0 { ( string_push_str t ` matching ` ) ( string_push_str t ( string_data q ) ) } {}
        ? > ( string_len from ) 0 { ( string_push_str t ` from ` ) ( string_push_str t ( string_data from ) ) } {}
        ( string_push_str t `\n` )
    } {
        ( __ag_msgs_text t msgs now maxb )
        // Where the next page is: forward when paging forward and the
        // page was full, else backward from the first one shown.
        ? & & > after 0 == before 0 == n limit {
            ?? ( vec_get [AgMsg] msgs - n 1 ) {
                T last → {
                    ( string_push_str t `(newer: history after=` )
                    ( string_push_int t . last id )
                    ( string_push_str t `)\n` )
                }
                F _ → {}
            }
        } {
            ? | == after 0 > before 0 {
                ?? ( vec_get [AgMsg] msgs 0 ) {
                    T first → {
                        ? & == n limit > . first id 1 {
                            ( string_push_str t `(older: history before=` )
                            ( string_push_int t . first id )
                            ( string_push_str t `)\n` )
                        } {}
                    }
                    F _ → {}
                }
            } {}
        }
    }
    ^ ( _ag_ok o t )
}

// The caller may read message `m`: any channel, but a mailbox only its own.
@ __ag_may_read AgMsg m s me → b {
    ? == ( nurl_str_get ( string_data . m channel ) 0 ) 64 {
        : String mine ( ag_mailbox me )
        : b own ( string_eq mine . m channel )
        ^ own
    } {}
    ^ T
}

@ __ag_no_msg i id → AgRes {
    : String m ( string_from `no message #` )
    ( string_push_int m id )
    ^ ( _ag_err_s 404 m )
}

@ __ag_op_msg AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    ?? ( ag_msg_get st id ) {
        F _ → { ^ ( __ag_no_msg id ) }
        T m → {
            ? ( __ag_may_read m me ) {} { ^ ( _ag_err 403 `that message is in another agent's mailbox` ) }
            : Json o ( _ag_msg_json m 0 )
            : String t ( string_new )
            ( __ag_msg_line t m now 0 )
            ^ ( _ag_ok o t )
        }
    }
}

@ __ag_op_status AgStore st s me Json args i now → AgRes {
    : String text ( _ag_arg_str args `text` )
    ? > ( string_len text ) AG_STATUS_MAX { ^ ( _ag_err 400 `text: at most 200 bytes` ) } {}
    ? ( string_contains text `\n` ) { ^ ( _ag_err 400 `text: one line` ) } {}
    ? ( ag_agent_set_status st me ( string_data text ) now ) {} { ^ ( _ag_err 500 `could not store the status` ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit ( string_data text ) ) )
    : String t ( string_from ? > ( string_len text ) 0 `status set\n` `status cleared\n` )
    ^ ( _ag_ok o t )
}

@ __ag_op_agents AgStore st i now → AgRes {
    : ( Vec AgAgent ) v ( ag_agents st )
    : Json arr ( json_arr_new )
    : String t ( string_new )
    : i n ( vec_len [AgAgent] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgAgent] v i ) {
            T a → {
                : Json o ( json_obj_new )
                ( json_obj_set o `agent` ( json_str_lit ( string_data . a id ) ) )
                ( json_obj_set o `about` ( json_str_lit ( string_data . a about ) ) )
                ( json_obj_set o `seen` ( json_int . a seen ) )
                ( string_push_str t ( string_data . a id ) )
                ( string_push_str t ` (seen ` )
                ( __ag_age t now . a seen )
                ? > ( string_len . a status ) 0 {
                    ( json_obj_set o `status` ( json_str_lit ( string_data . a status ) ) )
                    ( json_obj_set o `status_at` ( json_int . a status_at ) )
                    ( string_push_str t `; status ` )
                    ( __ag_age t now . a status_at )
                    ( string_push_str t `: ` )
                    ( string_push_str t ( string_data . a status ) )
                } {}
                ( json_arr_push arr o )
                ( string_push_str t `)` )
                ? > ( string_len . a about ) 0 {
                    ( string_push_str t ` — ` )
                    ( string_push_str t ( string_data . a about ) )
                } {}
                ( string_push_str t `\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    ? == n 0 { ( string_push_str t `nobody has joined yet\n` ) } {}
    : Json o ( json_obj_new )
    ( json_obj_set o `agents` arr )
    ^ ( _ag_ok o t )
}

@ __ag_op_channels AgStore st i now → AgRes {
    : ( Vec AgChannel ) v ( ag_channels st )
    : Json arr ( json_arr_new )
    : String t ( string_new )
    : i n ( vec_len [AgChannel] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgChannel] v i ) {
            T c → {
                : Json o ( json_obj_new )
                ( json_obj_set o `channel` ( json_str_lit ( string_data . c name ) ) )
                ( json_obj_set o `about` ( json_str_lit ( string_data . c about ) ) )
                ( json_obj_set o `messages` ( json_int . c count ) )
                ( json_arr_push arr o )
                ( string_push_str t ( string_data . c name ) )
                ( string_push_str t ` (` )
                ( string_push_int t . c count )
                ( string_push_str t `)` )
                ? > ( string_len . c about ) 0 {
                    ( string_push_str t ` — ` )
                    ( string_push_str t ( string_data . c about ) )
                } {}
                ( string_push_str t `\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `channels` arr )
    ^ ( _ag_ok o t )
}

@ __ag_op_channel_create AgStore st s me Json args i now → AgRes {
    : String name ( _ag_arg_channel args `name` )
    : String about ( _ag_arg_str args `about` )
    ? | ( ag_name_ok ( string_data name ) ) ( ag_is_repo_channel ( string_data name ) ) {} {
        : String m ( string_from `channel name must be ` )
        ( string_push_str m AG_NAME_RULE )
        ( string_push_str m `, or a git repository (remote URL or host/owner/repo)` )
        ^ ( _ag_err_s 400 m )
    }
    ? ( ag_channel_create st ( string_data name ) ( string_data about ) me now ) {} {
        : String m ( string_from `channel '` )
        ( string_push_str m ( string_data name ) )
        ( string_push_str m `' exists already` )
        ^ ( _ag_err_s 409 m )
    }
    ( ag_follow st me ( string_data name ) )
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data name ) ) )
    : String t ( string_from `created and following ` )
    ( string_push_str t ( string_data name ) )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

@ __ag_op_follow AgStore st s me Json args i now b on → AgRes {
    : String ch ( _ag_arg_channel args `channel` )
    ? == ( string_len ch ) 0 { ^ ( _ag_err 400 `channel is required` ) } {}
    ? on { ( __ag_repo_channel_auto st ( string_data ch ) me now ) } {}
    ? ( ag_channel_exists st ( string_data ch ) ) {} {
        : String m ( string_from `no channel '` )
        ( string_push_str m ( string_data ch ) )
        ( string_push_str m `'` )
        ^ ( _ag_err_s 404 m )
    }
    : b ok ? on ( ag_follow st me ( string_data ch ) ) ( ag_unfollow st me ( string_data ch ) )
    ? ok {} {
        ? on { ^ ( _ag_err 500 `could not follow` ) }
        {
            : String m ( string_from `you were not following ` )
            ( string_push_str m ( string_data ch ) )
            ^ ( _ag_err_s 409 m )
        }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data ch ) ) )
    ( json_obj_set o `following` ( json_bool on ) )
    : String t ( string_from ? on `following ` `no longer following ` )
    ( string_push_str t ( string_data ch ) )
    ( string_push_str t `\n` )
    ^ ( _ag_ok o t )
}

// The first line of `body`, at most 200 bytes (cut on a character).
@ __ag_first_line String body → String {
    : s b ( string_data body )
    : i n ( string_len body )
    : ~ i e 0
    ~ & < e n != ( nurl_str_at b n e ) 10 { = e + e 1 }
    : i k ( ag_cut_at b e 200 )
    : String out ( string_substr body 0 k )
    ^ out
}

@ __ag_op_task_post AgStore st s me Json args i now → AgRes {
    : ~ String title ( _ag_arg_str args `title` )
    : ~ String body ( _ag_arg_str args `body` )
    : i ref ( _ag_arg_int args `ref` 0 )
    ? > ref 0 {
        ?? ( ag_msg_get st ref ) {
            F _ → { ^ ( __ag_no_msg ref ) }
            T m → {
                ? ( __ag_may_read m me ) {} { ^ ( _ag_err 403 `ref: that message is in another agent's mailbox` ) }
                ? == ( string_len title ) 0 { = title ( __ag_first_line . m body ) } {}
                ? == ( string_len body ) 0 { = body ( string_clone . m body ) } {}
            }
        }
    } {}
    ? == ( string_len title ) 0 { ^ ( _ag_err 400 `title is required (or ref=<message id>)` ) } {}
    ? > ( string_len title ) 200 { ^ ( _ag_err 400 `title: at most 200 characters` ) } {}
    ? > ( string_len body ) AG_BODY_MAX { ^ ( _ag_err 400 `body: at most 16 KiB` ) } {}
    : String rawtags ( _ag_arg_str args `tags` )
    : String tags ( _ag_tags_norm rawtags )
    : i prio ( __ag_clamp ( _ag_arg_int args `priority` 0 ) -100 100 )
    : i id ( ag_task_post_ref st ( string_data title ) ( string_data body ) ( string_data tags ) me prio ref now )
    ? == id 0 { ^ ( _ag_err 500 `could not store the task` ) } {}
    : Json o ( _ag_obj_int `id` id )
    : String t ( string_from `task #` )
    ( string_push_int t id )
    ? > ref 0 { ( string_push_str t ` (re#` ) ( string_push_int t ref ) ( string_push_str t `)` ) } {}
    ( string_push_str t ` posted — you will hear when it is claimed and done\n` )
    ^ ( _ag_ok o t )
}

@ __ag_op_tasks AgStore st s me Json args i now → AgRes {
    : ~ String which ( _ag_arg_str args `which` )
    ? == ( string_len which ) 0 { ( string_push_str which `open` ) } {}
    : String tag ( _ag_arg_str args `tag` )
    : String ltag ( string_to_lower tag )
    : ( Vec AgTask ) v ( ag_tasks st ( string_data which ) me ( string_data ltag ) ( __ag_limit args ) now )
    : Json o ( json_obj_new )
    ( json_obj_set o `which` ( json_str_lit ( string_data which ) ) )
    ( json_obj_set o `tasks` ( __ag_tasks_json v ) )
    : String t ( string_new )
    : i n ( vec_len [AgTask] v )
    ? == n 0 {
        ( string_push_str t `no ` )
        ( string_push_str t ( string_data which ) )
        ( string_push_str t ` tasks` )
        ? > ( string_len ltag ) 0 {
            ( string_push_str t ` tagged ` )
            ( string_push_str t ( string_data ltag ) )
        } {}
        ( string_push_str t `\n` )
    } { ( __ag_tasks_text t v now ) }
    ^ ( _ag_ok o t )
}

@ __ag_no_task i id → AgRes {
    : String m ( string_from `no task #` )
    ( string_push_int m id )
    ^ ( _ag_err_s 404 m )
}

@ __ag_op_task AgStore st Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    ?? ( ag_task_get st id now ) {
        F _ → { ^ ( __ag_no_task id ) }
        T tk → {
            : Json o ( _ag_task_json tk )
            : String t ( string_new )
            ( __ag_task_line t tk now )
            ? > ( string_len . tk body ) 0 {
                ( string_push_str t ( string_data . tk body ) )
                ( string_push_str t `\n` )
            } {}
            ? > ( string_len . tk result ) 0 {
                ( string_push_str t `result: ` )
                ( string_push_str t ( string_data . tk result ) )
                ( string_push_str t `\n` )
            } {}
            ^ ( _ag_ok o t )
        }
    }
}

// The common tail of the task state changes: map the store's verdict to
// a response, and say what happened.
@ __ag_task_verdict AgStore st i rc i id s did s wrong i now → AgRes {
    ? == rc AG_TASK_NOT_FOUND { ^ ( __ag_no_task id ) } {}
    ? == rc AG_TASK_WRONG_STATE {
        : String m ( string_from `task #` )
        ( string_push_int m id )
        ( string_push_str m ` ` )
        ( string_push_str m wrong )
        ^ ( _ag_err_s 409 m )
    } {}
    ? == rc AG_TASK_FAILED { ^ ( _ag_err 500 `could not update the task` ) } {}
    : Json o ( _ag_obj_int `id` id )
    : String t ( string_from `task #` )
    ( string_push_int t id )
    ( string_push_str t ` ` )
    ( string_push_str t did )
    ( string_push_str t `\n` )
    ?? ( ag_task_get st id now ) {
        T tk → {
            ( json_obj_set o `task` ( _ag_task_json tk ) )
        }
        F _ → {}
    }
    ^ ( _ag_ok o t )
}

@ __ag_lease Json args → i {
    ^ ( __ag_clamp ( _ag_arg_int args `lease_s` AG_DEFAULT_LEASE ) 30 AG_LEASE_MAX )
}

@ __ag_op_task_claim AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    : i lease ( __ag_lease args )
    : i rc ( ag_task_claim st id me lease now )
    : ~ String did ( string_from `claimed by you, lease ` )
    ( __ag_left did now + now lease )
    ( string_push_str did ` — task_done when finished` )
    : AgRes r ( __ag_task_verdict st rc id ( string_data did ) `is not open (someone holds it, or it is finished) — tasks shows what is` now )
    ^ r
}

@ __ag_op_task_extend AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    : i lease ( __ag_lease args )
    : i rc ( ag_task_extend st id me lease now )
    : ~ String did ( string_from `lease ` )
    ( __ag_left did now + now lease )
    : AgRes r ( __ag_task_verdict st rc id ( string_data did ) `is not held by you` now )
    ^ r
}

@ __ag_op_task_done AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    : String result ( _ag_arg_str args `result` )
    ? == ( string_len result ) 0 { ^ ( _ag_err 400 `result is required — say what was done` ) } {}
    ? > ( string_len result ) AG_BODY_MAX { ^ ( _ag_err 400 `result: at most 16 KiB` ) } {}
    : i rc ( ag_task_done st id me ( string_data result ) now )
    ^ ( __ag_task_verdict st rc id `done — the poster has your result` `is not held by you` now )
}

@ __ag_op_task_release AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    : String note ( _ag_arg_str args `note` )
    ? > ( string_len note ) AG_BODY_MAX { ^ ( _ag_err 400 `note: at most 16 KiB` ) } {}
    : i rc ( ag_task_release st id me ( string_data note ) now )
    ^ ( __ag_task_verdict st rc id `released — open again` `is not held by you` now )
}

@ __ag_op_task_cancel AgStore st s me Json args i now → AgRes {
    : i id ( _ag_arg_int args `id` 0 )
    : i rc ( ag_task_cancel st id me now )
    ^ ( __ag_task_verdict st rc id `cancelled` `is not yours to cancel, or is already finished` now )
}

// A project key: '' (global), a name, or a git repository however it is
// spelled. A remote URL — `git@github.com:org/repo.git`,
// `https://github.com/org/repo`, `ssh://git@host:22/org/repo.git` — and
// the bare `github.com/org/repo` all become `github.com/org/repo`
// (lowercased; no scheme, user, port, `.git` or trailing slash), so every
// checkout of one repository files its notes under one key whatever
// remote spelling it has. None when it is neither a name nor such a path.
: i AG_PROJECT_MAX 128

@ ag_project_norm s raw → ?String {
    : String t0 ( string_trim ( string_from raw ) )
    : String t ( string_to_lower t0 )
    : s src ( string_data t )
    : i n ( nurl_str_len src )
    ? == n 0 { ^ @ ?String { T ( string_new ) } } {}
    ? ( ag_name_ok src ) { ^ @ ?String { T t } } {}
    // Where the host starts: past `scheme://`, then past `user@`.
    : ~ i start 0
    : ~ b scp F
    : i sep ( nurl_str_find src `://` )
    ? >= sep 0 { = start + sep 3 } {}
    : ~ i k start
    : ~ i at -1
    ~ & < k n != ( nurl_str_get src k ) 47 {
        ? == ( nurl_str_get src k ) 64 { = at k } {}
        = k + k 1
    }
    ? >= at 0 { = start + at 1 } {}
    // scp-like `host:path` (no scheme): the first ':' ends the host.
    ? < sep 0 {
        : ~ i j start
        ~ & < j n & != ( nurl_str_get src j ) 47 != ( nurl_str_get src j ) 58 { = j + j 1 }
        = scp & < j n == ( nurl_str_get src j ) 58
    } {}
    : String out ( string_new )
    : ~ i i start
    : ~ b in_host T
    : ~ b in_port F
    ~ < i n {
        : i c ( nurl_str_get src i )
        ? in_host {
            ? == c 47 { = in_host F = in_port F ( string_push_char out 47 ) } {
                ? == c 58 {
                    // host:port (URL) or host:path (scp-like).
                    ? scp { = in_host F ( string_push_char out 47 ) } { = in_port T }
                } {
                    ? in_port {} { ( string_push_char out c ) }
                }
            }
        } { ( string_push_char out c ) }
        = i + i 1
    }
    // No trailing '/' or `.git`; no doubled '/'.
    : ~ i m ( string_len out )
    ~ & > m 0 == ( string_get out - m 1 ) 47 { = m - m 1 }
    ? & > m 4 != 0 ( nurl_str_eq ( string_data ( string_substr out - m 4 4 ) ) `.git` ) { = m - m 4 } {}
    : String key ( string_substr out 0 m )
    : s ks ( string_data key )
    : i kn ( nurl_str_len ks )
    ? | | == kn 0 > kn AG_PROJECT_MAX ! ( string_contains key `/` ) { ^ @ ?String { F } } {}
    ? | == ( nurl_str_get ks 0 ) 47 ( string_contains key `//` ) { ^ @ ?String { F } } {}
    : ~ i q 0
    ~ < q kn {
        : i c ( nurl_str_get ks q )
        : b ok | | & >= c 97 <= c 122 & >= c 48 <= c 57 | | | == c 45 == c 46 == c 95 == c 47
        ? ok {} { ^ @ ?String { F } }
        // No '.' or '..' segment.
        ? & == c 46 | == q 0 == ( nurl_str_get ks - q 1 ) 47 {
            : b dot_end | == + q 1 kn == ( nurl_str_get ks + q 1 ) 47
            : b dd_end & & < + q 1 kn == ( nurl_str_get ks + q 1 ) 46 | == + q 2 kn == ( nurl_str_get ks + q 2 ) 47
            ? | dot_end dd_end { ^ @ ?String { F } } {}
        } {}
        = q + q 1
    }
    ^ @ ?String { T key }
}

// The `project` argument of the note ops (see ag_project_norm).
@ __ag_arg_project Json args → ?String {
    : String pr ( _ag_arg_str args `project` )
    ^ ( ag_project_norm ( string_data pr ) )
}

@ __ag_bad_project → AgRes {
    : String m ( string_from `project must be a name (` )
    ( string_push_str m AG_NAME_RULE )
    ( string_push_str m `) or a git repository: a remote URL or host/owner/repo` )
    ^ ( _ag_err_s 400 m )
}

// `project/key` when the note has a project, `key` otherwise.
@ __ag_note_ref String out s project s key → v {
    ? > ( nurl_str_len project ) 0 {
        ( string_push_str out project )
        ( string_push_str out `/` )
    } {}
    ( string_push_str out key )
}

@ __ag_op_note_set AgStore st s me Json args i now → AgRes {
    : String key ( _ag_arg_str args `key` )
    ? ( ag_name_ok ( string_data key ) ) {} {
        : String m ( string_from `key must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( _ag_err_s 400 m )
    }
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { = project p } F _ → { ^ ( __ag_bad_project ) } }
    : String body ( _ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ^ e } F _ → {} }
    : b ok ( ag_note_set st ( string_data project ) ( string_data key ) ( string_data body ) me now )
    ? ok {} { ^ ( _ag_err 500 `could not store the note` ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data key ) ) )
    : String t ( string_from `note ` )
    ( __ag_note_ref t ( string_data project ) ( string_data key ) )
    ( string_push_str t ` saved\n` )
    ^ ( _ag_ok o t )
}

@ __ag_no_note String project String key → AgRes {
    : String m ( string_from `no note '` )
    ( __ag_note_ref m ( string_data project ) ( string_data key ) )
    ( string_push_str m `' — notes lists them` )
    ^ ( _ag_err_s 404 m )
}

@ __ag_op_note AgStore st Json args i now → AgRes {
    : String key ( _ag_arg_str args `key` )
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { = project p } F _ → { ^ ( __ag_bad_project ) } }
    ?? ( ag_note_get st ( string_data project ) ( string_data key ) ) {
        F _ → { ^ ( __ag_no_note project key ) }
        T n → {
            : Json o ( _ag_note_json n T )
            : String t ( string_new )
            ( __ag_note_ref t ( string_data . n project ) ( string_data . n key ) )
            ( string_push_str t ` (` )
            ( string_push_str t ( string_data . n author ) )
            ( string_push_str t ` ` )
            ( __ag_age t now . n updated )
            ( string_push_str t `):\n` )
            ( string_push_str t ( string_data . n body ) )
            ( string_push_str t `\n` )
            ^ ( _ag_ok o t )
        }
    }
}

@ __ag_op_notes AgStore st Json args i now → AgRes {
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { = project p } F _ → { ^ ( __ag_bad_project ) } }
    : b all == ( string_len project ) 0
    : ( Vec AgNote ) v ( ag_notes st ( string_data project ) all F )
    : Json arr ( json_arr_new )
    : String t ( string_new )
    : i n ( vec_len [AgNote] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgNote] v i ) {
            T x → {
                ( json_arr_push arr ( _ag_note_json x F ) )
                ? all { ( __ag_note_ref t ( string_data . x project ) ( string_data . x key ) ) }
                { ( string_push_str t ( string_data . x key ) ) }
                ( string_push_str t ` (` )
                ( string_push_str t ( string_data . x author ) )
                ( string_push_str t ` ` )
                ( __ag_age t now . x updated )
                ( string_push_str t `)\n` )
            }
            F _ → {}
        }
        = i + i 1
    }
    ? == n 0 {
        ? all { ( string_push_str t `no notes yet — note_set writes one\n` ) } {
            ( string_push_str t `no notes for project ` )
            ( string_push_str t ( string_data project ) )
            ( string_push_str t ` — note_set project=` )
            ( string_push_str t ( string_data project ) )
            ( string_push_str t ` key=… writes one\n` )
        }
    } {}
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `notes` arr )
    ^ ( _ag_ok o t )
}

@ __ag_op_note_del AgStore st Json args i now → AgRes {
    : String key ( _ag_arg_str args `key` )
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { = project p } F _ → { ^ ( __ag_bad_project ) } }
    ? ( ag_note_del st ( string_data project ) ( string_data key ) ) {} { ^ ( __ag_no_note project key ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data key ) ) )
    : String t ( string_from `note ` )
    ( __ag_note_ref t ( string_data project ) ( string_data key ) )
    ( string_push_str t ` deleted\n` )
    ^ ( _ag_ok o t )
}

// ── Dispatch ─────────────────────────────────────────────────────────

// Does the catalog know `name`, and does it need a signed-in caller?
// -1 unknown, 0 open, 1 needs auth.
// A fixed table, not the catalog: building the catalog (every schema)
// on every request was most of a cheap op's cost. The unit test checks
// this table against the catalog entry by entry.
: s AG_OP_NAMES ` whoami brief wait inbox post send history msg agents status channels channel_create follow unfollow task_post tasks task task_claim task_extend task_done task_release task_cancel note_set note notes note_del `

@ ag_op_auth_kind s name → i {
    ? != 0 ( nurl_str_eq name `join` ) { ^ 0 } {}
    : i n ( nurl_str_len name )
    ? | == n 0 > n AG_NAME_MAX { ^ -1 } {}
    ? ( string_contains ( string_from name ) ` ` ) { ^ -1 } {}
    : String key ( string_from ` ` )
    ( string_push_str key name )
    ( string_push_str key ` ` )
    : String names ( string_from AG_OP_NAMES )
    ? ( string_contains names ( string_data key ) ) { ^ 1 } {}
    ^ -1
}

// Run one operation for `c`. `args` is BORROWED (a Json object, or
// anything else for "no arguments").
@ ag_op_call AgStore st AgCaller c s name Json args i now → AgRes {
    : i kind ( ag_op_auth_kind name )
    ? < kind 0 {
        : String m ( string_from `unknown operation '` )
        ( string_push_str m name )
        ( string_push_str m `'` )
        ^ ( _ag_err_s 404 m )
    } {}
    ? & == kind 1 ! . c authed { ^ ( __ag_unauthorized ) } {}
    : s me ( string_data . c agent )
    ? != 0 ( nurl_str_eq name `join` ) { ^ ( __ag_op_join st args now ) } {}
    ? != 0 ( nurl_str_eq name `whoami` ) { ^ ( __ag_op_whoami st me now ) } {}
    ? != 0 ( nurl_str_eq name `brief` ) { ^ ( __ag_op_brief st me args now ) } {}
    ? != 0 ( nurl_str_eq name `wait` ) { ^ ( __ag_op_wait st me args now ) } {}
    ? != 0 ( nurl_str_eq name `inbox` ) { ^ ( __ag_op_inbox st me args now ) } {}
    ? != 0 ( nurl_str_eq name `post` ) { ^ ( __ag_op_post st me args now ) } {}
    ? != 0 ( nurl_str_eq name `send` ) { ^ ( __ag_op_send st me args now ) } {}
    ? != 0 ( nurl_str_eq name `history` ) { ^ ( __ag_op_history st me args now ) } {}
    ? != 0 ( nurl_str_eq name `msg` ) { ^ ( __ag_op_msg st me args now ) } {}
    ? != 0 ( nurl_str_eq name `agents` ) { ^ ( __ag_op_agents st now ) } {}
    ? != 0 ( nurl_str_eq name `status` ) { ^ ( __ag_op_status st me args now ) } {}
    ? != 0 ( nurl_str_eq name `channels` ) { ^ ( __ag_op_channels st now ) } {}
    ? != 0 ( nurl_str_eq name `channel_create` ) { ^ ( __ag_op_channel_create st me args now ) } {}
    ? != 0 ( nurl_str_eq name `follow` ) { ^ ( __ag_op_follow st me args now T ) } {}
    ? != 0 ( nurl_str_eq name `unfollow` ) { ^ ( __ag_op_follow st me args now F ) } {}
    ? != 0 ( nurl_str_eq name `task_post` ) { ^ ( __ag_op_task_post st me args now ) } {}
    ? != 0 ( nurl_str_eq name `tasks` ) { ^ ( __ag_op_tasks st me args now ) } {}
    ? != 0 ( nurl_str_eq name `task` ) { ^ ( __ag_op_task st args now ) } {}
    ? != 0 ( nurl_str_eq name `task_claim` ) { ^ ( __ag_op_task_claim st me args now ) } {}
    ? != 0 ( nurl_str_eq name `task_extend` ) { ^ ( __ag_op_task_extend st me args now ) } {}
    ? != 0 ( nurl_str_eq name `task_done` ) { ^ ( __ag_op_task_done st me args now ) } {}
    ? != 0 ( nurl_str_eq name `task_release` ) { ^ ( __ag_op_task_release st me args now ) } {}
    ? != 0 ( nurl_str_eq name `task_cancel` ) { ^ ( __ag_op_task_cancel st me args now ) } {}
    ? != 0 ( nurl_str_eq name `note_set` ) { ^ ( __ag_op_note_set st me args now ) } {}
    ? != 0 ( nurl_str_eq name `note` ) { ^ ( __ag_op_note st args now ) } {}
    ? != 0 ( nurl_str_eq name `notes` ) { ^ ( __ag_op_notes st args now ) } {}
    ? != 0 ( nurl_str_eq name `note_del` ) { ^ ( __ag_op_note_del st args now ) } {}
    // In the catalog but not here: a programming error, and the test
    // that calls every catalog entry is what catches it.
    : String m ( string_from `operation '` )
    ( string_push_str m name )
    ( string_push_str m `' has no handler` )
    ^ ( _ag_err_s 501 m )
}
