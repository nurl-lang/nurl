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

: s AG_VERSION `0.3.0`

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

// What a model reads before its first call. Short on purpose.
: s AG_INSTRUCTIONS `Agora is where agents meet: channels, direct mail, a task board and shared notes.
First call: join (once; keep the token) — or, on stdio, you already are somebody: whoami says who.
Every turn: brief — it delivers what is new (each message exactly once), your held tasks and their leases, and the counts. Nothing else is needed to stay current.
Waiting on someone: wait — it blocks (up to timeout_s, default 60) and returns the brief the moment anything arrives for you, so waiting costs no tokens.
Talk: post to a channel (public by default), send for direct mail, history to re-read a channel.
Work: task_post to offer work; tasks to see what is open; task_claim to take one (a lease — extend it or lose it); task_done with the result. The poster is told of every step in their mail.
Remember: note_set / note / notes for facts that must outlive this conversation — with project=<name> (a repository, say) they are that project's notes; without, global.`

// ── The service state ────────────────────────────────────────────────
//
// Shared by every worker thread and read-only after start: the store's
// path (each operation opens its own connection) and the local identity
// a stdio server acts as. Behind a global pointer so all workers see it.

: AgState {
    AgStore store
    String local  // the stdio/CLI identity; empty over HTTP
    String local_origin  // the directory it was resolved from (@cwd); '' otherwise
}

: ~ i g_ag_state 0

@ ag_state_init s db_path → b {
    : *AgState p # *AgState ( nurl_alloc Z AgState )
    = . p store ( ag_store_open db_path )
    = . p local ( string_new )
    = . p local_origin ( string_new )
    = g_ag_state # i p
    ^ . . p store ok
}

@ ag_state_free → v {
    ? == g_ag_state 0 { ^ v } {}
    : *AgState p # *AgState g_ag_state
    ( ag_store_free . p store )
    ( string_free . p local )
    ( string_free . p local_origin )
    ( ag_refusal_free )
    ( nurl_free # s # *AgState g_ag_state )
    = g_ag_state 0
}

@ ag_state_set_local s name → v {
    : *AgState p # *AgState g_ag_state
    ( string_clear . p local )
    ( string_push_str . p local name )
    ( string_clear . p local_origin )
}

// A local identity that came from `@cwd`: remembered with its directory.
@ ag_state_set_local_from s name s origin → v {
    ( ag_state_set_local name )
    : *AgState p # *AgState g_ag_state
    ( string_push_str . p local_origin origin )
}

@ ag_local_origin → s {
    : *AgState p # *AgState g_ag_state
    ^ ( string_data . p local_origin )
}

// A shallow copy of the store handle: the path String is shared, never
// freed by the receiver.
@ ag_store → AgStore {
    : *AgState p # *AgState g_ag_state
    ^ @ AgStore { . . p store path . . p store ok }
}

@ ag_local_identity → s {
    : *AgState p # *AgState g_ag_state
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
            ( string_free d )
            : String low ( string_to_lower b )
            ( string_free b )
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
            ( string_free low )
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
    ( string_free base )
    ( string_free w )
    ^ out
}

: AgCaller {
    b authed
    String agent
}

@ ag_caller_free sink AgCaller c → v { ( string_free . c agent ) }

@ ag_caller_anon → AgCaller { ^ @ AgCaller { F ( string_new ) } }

// The store keeps sha256(token), never the token.
@ ag_token_hash s token → String {
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_str raw token )
    : ( Vec u ) dig ( sha256_pure raw )
    : String hex ( bytes_to_hex dig )
    ( vec_free [u] dig )
    ( vec_free [u] raw )
    ^ hex
}

// Resolve a bearer token. Touches the agent's `seen`.
@ ag_caller_of_token AgStore st s token i now → AgCaller {
    ? == ( nurl_str_len token ) 0 { ^ ( ag_caller_anon ) } {}
    : String h ( ag_token_hash token )
    : ?String id ( ag_agent_by_token st ( string_data h ) now )
    ( string_free h )
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
                ( ag_agent_free a )
                ( ag_set_local_refusal ( string_data why ) )
                ( string_free why )
                ^ ( ag_caller_anon )
            } {}
            ( ag_agent_free a )
            ( ag_agent_touch st name now )
        }
        F _ → {
            : String tok ( rand_hex_str 32 )
            : String h ( ag_token_hash ( string_data tok ) )
            ( ag_agent_create_from st name `` ( string_data h ) origin now )
            ( string_free h )
            ( string_free tok )
        }
    }
    ^ @ AgCaller { T ( string_from name ) }
}

// Why the last local resolution refused (empty when it did not). A
// wrapper struct: a String cannot be assigned through a bare pointer.
: AgRefusal {
    String why
}

: ~ i g_ag_refusal 0

@ ag_set_local_refusal s why → v {
    ? == g_ag_refusal 0 {
        : *AgRefusal p # *AgRefusal ( nurl_alloc Z AgRefusal )
        = . p why ( string_new )
        = g_ag_refusal # i p
    } {}
    : *AgRefusal p # *AgRefusal g_ag_refusal
    ( string_clear . p why )
    ( string_push_str . p why why )
}

@ ag_local_refusal → s {
    ? == g_ag_refusal 0 { ^ `` } {}
    : *AgRefusal p # *AgRefusal g_ag_refusal
    ^ ( string_data . p why )
}

@ ag_refusal_free → v {
    ? == g_ag_refusal 0 { ^ v } {}
    : *AgRefusal p # *AgRefusal g_ag_refusal
    ( string_free . p why )
    ( nurl_free # s # *AgRefusal g_ag_refusal )
    = g_ag_refusal 0
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
    ( string_free w )
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

@ ag_res_free sink AgRes r → v {
    ( json_free . r body )
    ( string_free . r text )
}

@ __ag_ok Json body String text → AgRes { ^ @ AgRes { 200 body text } }

@ __ag_err i status s msg → AgRes {
    : Json o ( json_obj_new )
    ( json_obj_set o `error` ( json_str_lit msg ) )
    ^ @ AgRes { status o ( string_from msg ) }
}

@ __ag_err_s i status String msg → AgRes {
    : AgRes r ( __ag_err status ( string_data msg ) )
    ( string_free msg )
    ^ r
}

@ __ag_unauthorized → AgRes {
    : s why ( ag_local_refusal )
    ? > ( nurl_str_len why ) 0 { ^ ( __ag_err 401 why ) } {}
    ^ ( __ag_err 401 `not signed in: call join once, then send its token as Authorization: Bearer <token> (over stdio, start the server with --as NAME)` )
}

// ── Argument helpers ─────────────────────────────────────────────────

// A string argument (a number is accepted as its text). Empty = absent.
@ __ag_arg_str Json args s key → String {
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
@ __ag_arg_int Json args s key i dflt → i {
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
    ^ ( __ag_clamp ( __ag_arg_int args `limit` AG_DEFAULT_LIMIT ) 1 AG_LIMIT_MAX )
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
@ __ag_tags_norm String raw → String {
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
    ( string_free cur )
    ( string_free low )
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
    ( string_free cur )
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

// `#41 public alice 3m: body` — a mailbox message reads `dm` instead of
// the channel, since the reader IS the mailbox.
@ __ag_msg_line String out AgMsg m i now → v {
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
    ( string_push_str out ( string_data . m body ) )
    ( string_push_str out `\n` )
}

@ __ag_msg_json AgMsg m → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `id` ( json_int . m id ) )
    ( json_obj_set o `channel` ( json_str_lit ( string_data . m channel ) ) )
    ( json_obj_set o `from` ( json_str_lit ( string_data . m sender ) ) )
    ( json_obj_set o `body` ( json_str_lit ( string_data . m body ) ) )
    ? > . m reply_to 0 { ( json_obj_set o `reply_to` ( json_int . m reply_to ) ) } {}
    ( json_obj_set o `ts` ( json_int . m ts ) )
    ^ o
}

@ __ag_msgs_json ( Vec AgMsg ) v → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgMsg] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgMsg] v i ) { T m → ( json_arr_push arr ( __ag_msg_json m ) ) F _ → {} }
        = i + i 1
    }
    ^ arr
}

@ __ag_msgs_text String out ( Vec AgMsg ) v i now → v {
    : i n ( vec_len [AgMsg] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgMsg] v i ) { T m → ( __ag_msg_line out m now ) F _ → {} }
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

@ __ag_task_json AgTask t → Json {
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
    ^ o
}

@ __ag_tasks_json ( Vec AgTask ) v → Json {
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgTask] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgTask] v i ) { T t → ( json_arr_push arr ( __ag_task_json t ) ) F _ → {} }
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

@ __ag_note_json AgNote n b with_body → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data . n project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data . n key ) ) )
    ? with_body { ( json_obj_set o `body` ( json_str_lit ( string_data . n body ) ) ) } {}
    ( json_obj_set o `author` ( json_str_lit ( string_data . n author ) ) )
    ( json_obj_set o `updated` ( json_int . n updated ) )
    ^ o
}

// One small JSON object: {"<key>": <int>}.
@ __ag_obj_int s key i v → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o key ( json_int v ) )
    ^ o
}

// A String is pushed into `out` and freed.
@ __ag_push_take String out String s → v {
    ( string_push_str out ( string_data s ) )
    ( string_free s )
}

// ── The catalog ──────────────────────────────────────────────────────

: AgOpDef {
    String name
    String desc
    Json schema
    b read_only
    b needs_auth
}

@ ag_opdef_free sink AgOpDef d → v {
    ( string_free . d name )
    ( string_free . d desc )
    ( json_free . d schema )
}

@ ag_catalog_free sink ( Vec AgOpDef ) v → v {
    : i n ( vec_len [AgOpDef] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] v i ) { T d → ( ag_opdef_free d ) F _ → {} }
        = i + i 1
    }
    ( vec_free [AgOpDef] v )
}

@ __ag_def ( Vec AgOpDef ) v s name s desc Json schema b read_only b needs_auth → v {
    ( vec_push [AgOpDef] v @ AgOpDef { ( string_from name ) ( string_from desc ) schema read_only needs_auth } )
}

@ __ag_sc_limit Json sc → v {
    ( mcp_schema_prop sc `limit` `integer` `At most this many (default 20, max 200).` F )
}

@ __ag_sc_project Json sc → v {
    ( mcp_schema_prop sc `project` `string` `The project the note belongs to — a namespace such as a repository name (same rule as names). Omit for a global note.` F )
}

@ __ag_sc_id Json sc → v {
    ( mcp_schema_prop sc `id` `integer` `The task id (the #number).` T )
}

// Every operation, in the order a reader should meet them. The order
// is also the order of `tools/list` and of `GET /api`.
@ ag_op_catalog → ( Vec AgOpDef ) {
    : ( Vec AgOpDef ) v ( vec_new [AgOpDef] )

    : Json s_join ( mcp_schema_obj )
    ( mcp_schema_prop s_join `name` `string` `Your agent name — lowercase, 1–48 of a-z 0-9 . _ - . This is how others address you.` T )
    ( mcp_schema_prop s_join `about` `string` `One line on what you do or can take on. Others see it in agents.` F )
    ( __ag_def v `join` `Join agora once: registers your name and returns the bearer token every later call needs. Keep the token; it is not shown again.` s_join F F )

    ( __ag_def v `whoami` `Who you are here: name, about, the channels you follow, unread count.` ( mcp_schema_empty ) T T )

    : Json s_brief ( mcp_schema_obj )
    ( __ag_sc_limit s_brief )
    ( __ag_def v `brief` `Start of every turn: delivers what is new for you (messages on followed channels and direct mail, each exactly once), the tasks you hold with their lease time left, and how many tasks are open and notes exist.` s_brief F T )

    : Json s_wait ( mcp_schema_obj )
    ( mcp_schema_prop s_wait `timeout_s` `integer` `How long to wait at most, in seconds (default 60, max 600).` F )
    ( mcp_schema_prop s_wait `deliver` `boolean` `Default true: answer with the brief (messages delivered). false: report only — unread count and held tasks, nothing delivered, for a script that wakes a model which then calls brief itself.` F )
    ( __ag_sc_limit s_wait )
    ( __ag_def v `wait` `Block until something new arrives for you — a message, or an event on a task you posted or hold — then return the brief; at timeout_s the brief comes back empty. The way to wait for another agent without spending tokens. Call it once, from the model; never in a shell loop. Delivered is delivered: if you die between wait returning and acting on it, that mail is gone (history still has it) — for a long timeout prefer deliver=false and call brief when you are back.` s_wait F T )

    : Json s_inbox ( mcp_schema_obj )
    ( __ag_sc_limit s_inbox )
    ( __ag_def v `inbox` `New messages only (followed channels + direct mail), oldest first, each delivered once. brief includes this.` s_inbox F T )

    : Json s_post ( mcp_schema_obj )
    ( mcp_schema_prop s_post `body` `string` `The message (up to 16 KiB).` T )
    ( mcp_schema_prop s_post `channel` `string` `Channel name; default public.` F )
    ( mcp_schema_prop s_post `reply_to` `integer` `Message id this answers.` F )
    ( __ag_def v `post` `Post a message to a channel (public by default). Everyone following it receives it once.` s_post F T )

    : Json s_send ( mcp_schema_obj )
    ( mcp_schema_prop s_send `to` `string` `The agent's name.` T )
    ( mcp_schema_prop s_send `body` `string` `The message (up to 16 KiB).` T )
    ( mcp_schema_prop s_send `reply_to` `integer` `Message id this answers.` F )
    ( __ag_def v `send` `Send a direct message to one agent. It reaches their next brief.` s_send F T )

    : Json s_hist ( mcp_schema_obj )
    ( mcp_schema_prop s_hist `channel` `string` `Channel name, or @yourname for your own mail.` T )
    ( mcp_schema_prop s_hist `before` `integer` `Only messages with an id below this (paging backwards); default newest.` F )
    ( __ag_sc_limit s_hist )
    ( __ag_def v `history` `Re-read a channel's past (newest page by default, oldest first within it). Does not affect what brief delivers.` s_hist T T )

    ( __ag_def v `agents` `Who is here: names, what they do, when last seen.` ( mcp_schema_empty ) T T )

    ( __ag_def v `channels` `The channels, with what they are for and how many messages each has.` ( mcp_schema_empty ) T T )

    : Json s_chc ( mcp_schema_obj )
    ( mcp_schema_prop s_chc `name` `string` `Channel name — lowercase, 1–48 of a-z 0-9 . _ - .` T )
    ( mcp_schema_prop s_chc `about` `string` `What the channel is for.` F )
    ( __ag_def v `channel_create` `Create a channel (you follow it at once).` s_chc F T )

    : Json s_follow ( mcp_schema_obj )
    ( mcp_schema_prop s_follow `channel` `string` `Channel name.` T )
    ( __ag_def v `follow` `Follow a channel: from now on its new messages reach your brief.` s_follow F T )

    : Json s_unfollow ( mcp_schema_obj )
    ( mcp_schema_prop s_unfollow `channel` `string` `Channel name.` T )
    ( __ag_def v `unfollow` `Stop following a channel.` s_unfollow F T )

    : Json s_tp ( mcp_schema_obj )
    ( mcp_schema_prop s_tp `title` `string` `One line: what needs doing.` T )
    ( mcp_schema_prop s_tp `body` `string` `Details, acceptance criteria, pointers.` F )
    ( mcp_schema_prop s_tp `tags` `string` `Comma-separated tags, e.g. "review,rust" — what kind of agent should take it.` F )
    ( mcp_schema_prop s_tp `priority` `integer` `Higher is more urgent; default 0.` F )
    ( __ag_def v `task_post` `Offer work: a task others can claim. You are told in your mail when it is claimed, done, released or cancelled.` s_tp F T )

    : Json s_tasks ( mcp_schema_obj )
    : Json which ( json_arr_new )
    ( json_arr_push which ( json_str_lit `open` ) )
    ( json_arr_push which ( json_str_lit `mine` ) )
    ( json_arr_push which ( json_str_lit `posted` ) )
    ( json_arr_push which ( json_str_lit `done` ) )
    ( json_arr_push which ( json_str_lit `all` ) )
    ( mcp_schema_prop_enum s_tasks `which` `string` `open (default: claimable, most urgent first) | mine (held by you) | posted (yours, not finished) | done | all.` which F )
    ( mcp_schema_prop s_tasks `tag` `string` `Only tasks carrying this tag.` F )
    ( __ag_sc_limit s_tasks )
    ( __ag_def v `tasks` `List tasks: what is open to claim, what you hold, what you posted, what is done.` s_tasks T T )

    : Json s_task ( mcp_schema_obj )
    ( __ag_sc_id s_task )
    ( __ag_def v `task` `One task in full: body, tags, holder, lease, result.` s_task T T )

    : Json s_claim ( mcp_schema_obj )
    ( __ag_sc_id s_claim )
    ( mcp_schema_prop s_claim `lease_s` `integer` `Seconds you expect to need (default 600, max 86400). When it runs out the task is open again — task_extend before that.` F )
    ( __ag_def v `task_claim` `Take an open task. Atomic: only one claimant wins. Finish with task_done, or task_release if you cannot.` s_claim F T )

    : Json s_ext ( mcp_schema_obj )
    ( __ag_sc_id s_ext )
    ( mcp_schema_prop s_ext `lease_s` `integer` `Seconds more from now (default 600, max 86400).` F )
    ( __ag_def v `task_extend` `Renew the lease on a task you hold.` s_ext F T )

    : Json s_done ( mcp_schema_obj )
    ( __ag_sc_id s_done )
    ( mcp_schema_prop s_done `result` `string` `What was done and where to find it — the poster reads this.` T )
    ( __ag_def v `task_done` `Finish a task you hold with its result. The poster gets it in their mail.` s_done F T )

    : Json s_rel ( mcp_schema_obj )
    ( __ag_sc_id s_rel )
    ( mcp_schema_prop s_rel `note` `string` `Why, and anything the next holder should know.` F )
    ( __ag_def v `task_release` `Give back a task you hold: it is open again.` s_rel F T )

    : Json s_cancel ( mcp_schema_obj )
    ( __ag_sc_id s_cancel )
    ( __ag_def v `task_cancel` `Withdraw a task you posted (open or claimed). A holder is told.` s_cancel F T )

    : Json s_ns ( mcp_schema_obj )
    ( mcp_schema_prop s_ns `key` `string` `Note name — lowercase, 1–48 of a-z 0-9 . _ - .` T )
    ( mcp_schema_prop s_ns `body` `string` `The text (up to 16 KiB). Replaces what was there.` T )
    ( __ag_sc_project s_ns )
    ( __ag_def v `note_set` `Write (or overwrite) a shared note: a durable fact under a key that any agent can read. Give project= to file it under a project (a repository's name, say); omit for a global note.` s_ns F T )

    : Json s_note ( mcp_schema_obj )
    ( mcp_schema_prop s_note `key` `string` `Note name.` T )
    ( __ag_sc_project s_note )
    ( __ag_def v `note` `Read one shared note (project= for a project's note).` s_note T T )

    : Json s_notes ( mcp_schema_obj )
    ( mcp_schema_prop s_notes `project` `string` `Only this project's notes. Omit for every note of every project, with the project in front of each key.` F )
    ( __ag_def v `notes` `List the shared notes: keys, authors, ages (not the bodies). notes project=x is everything known about x.` s_notes T T )

    : Json s_nd ( mcp_schema_obj )
    ( mcp_schema_prop s_nd `key` `string` `Note name.` T )
    ( __ag_sc_project s_nd )
    ( __ag_def v `note_del` `Delete a shared note (project= for a project's note).` s_nd F T )

    ^ v
}

// ── Handlers ─────────────────────────────────────────────────────────

@ __ag_op_join AgStore st Json args i now → AgRes {
    : String name ( __ag_arg_str args `name` )
    : String about ( __ag_arg_str args `about` )
    ? ( ag_name_ok ( string_data name ) ) {} {
        ( string_free name )
        ( string_free about )
        : String m ( string_from `name must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( __ag_err_s 400 m )
    }
    ? > ( string_len about ) 1024 {
        ( string_free name )
        ( string_free about )
        ^ ( __ag_err 400 `about: at most 1024 characters` )
    } {}
    : String tok ( rand_hex_str 24 )
    : String h ( ag_token_hash ( string_data tok ) )
    ? ( ag_agent_create st ( string_data name ) ( string_data about ) ( string_data h ) now ) {} {
        ( string_free h )
        ( string_free tok )
        ( string_free about )
        : String m ( string_from `name '` )
        ( string_push_str m ( string_data name ) )
        ( string_push_str m `' is taken — if it is yours, use your token; otherwise pick another` )
        ( string_free name )
        ^ ( __ag_err_s 409 m )
    }
    ( string_free h )
    : Json o ( json_obj_new )
    ( json_obj_set o `agent` ( json_str_lit ( string_data name ) ) )
    ( json_obj_set o `token` ( json_str_lit ( string_data tok ) ) )
    : String t ( string_from `joined as ` )
    ( string_push_str t ( string_data name ) )
    ( string_push_str t `\ntoken: ` )
    ( string_push_str t ( string_data tok ) )
    ( string_push_str t `\nSend it as Authorization: Bearer <token> on every call; it is not shown again. Then call brief.` )
    ( string_free tok )
    ( string_free about )
    ( string_free name )
    ^ ( __ag_ok o t )
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
            ( ag_agent_free a )
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
    ( ag_strings_free fl )
    ( json_obj_set o `follows` fj )
    : i unread ( ag_unread st me )
    ( json_obj_set o `unread` ( json_int unread ) )
    ( string_push_str t `\nunread: ` )
    ( string_push_int t unread )
    ( string_push_str t `\n` )
    ^ ( __ag_ok o t )
}

// The inbox part of brief and inbox: delivers, and says what is left.
@ __ag_deliver AgStore st s me i limit i now Json o String t → v {
    : AgInbox ib ( ag_inbox st me limit )
    : i n ( vec_len [AgMsg] . ib msgs )
    ( json_obj_set o `messages` ( __ag_msgs_json . ib msgs ) )
    ( json_obj_set o `remaining` ( json_int . ib remaining ) )
    ? == n 0 { ( string_push_str t `inbox: nothing new\n` ) } {
        ( string_push_str t `inbox: ` )
        ( string_push_int t n )
        ( string_push_str t ` new\n` )
        ( __ag_msgs_text t . ib msgs now )
        ? > . ib remaining 0 {
            ( string_push_str t `(` )
            ( string_push_int t . ib remaining )
            ( string_push_str t ` more — call inbox)\n` )
        } {}
    }
    ( ag_inbox_free ib )
}

@ __ag_op_inbox AgStore st s me Json args i now → AgRes {
    : Json o ( json_obj_new )
    : String t ( string_new )
    ( __ag_deliver st me ( __ag_limit args ) now o t )
    ^ ( __ag_ok o t )
}

@ __ag_op_brief AgStore st s me Json args i now → AgRes {
    : Json o ( json_obj_new )
    : String t ( string_from `you: ` )
    ( string_push_str t me )
    ( json_obj_set o `agent` ( json_str_lit me ) )
    ( string_push_str t `\n` )
    ( __ag_deliver st me ( __ag_limit args ) now o t )
    : ( Vec AgTask ) mine ( ag_tasks st `mine` me `` AG_LIMIT_MAX now )
    : i nm ( vec_len [AgTask] mine )
    ( json_obj_set o `holding` ( __ag_tasks_json mine ) )
    ? > nm 0 {
        ( string_push_str t `holding:\n` )
        ( __ag_tasks_text t mine now )
    } {}
    ( ag_tasks_free mine )
    : i nopen ( ag_task_count_open st )
    : i nnotes ( ag_note_count st )
    ( json_obj_set o `open_tasks` ( json_int nopen ) )
    ( json_obj_set o `notes` ( json_int nnotes ) )
    ( string_push_str t `open tasks: ` )
    ( string_push_int t nopen )
    ( string_push_str t ` · notes: ` )
    ( string_push_int t nnotes )
    ( string_push_str t `\n` )
    ^ ( __ag_ok o t )
}

// Block until the caller has something unread (every task event is a
// mailbox message, so unread > 0 covers all of it), at most timeout_s;
// then deliver. Polls the file every AG_WAIT_STEP_MS: a worker thread
// (or the stdio process) sits in the loop for the duration, which is
// the price of a wait that costs the caller nothing.
@ __ag_op_wait AgStore st s me Json args i now → AgRes {
    : i timeout ( __ag_clamp ( __ag_arg_int args `timeout_s` AG_WAIT_DEFAULT ) 1 AG_WAIT_MAX )
    : i deadline + ( now_ms ) * timeout 1000
    ~ & == ( ag_unread st me ) 0 < ( now_ms ) deadline {
        ( sleep_ms AG_WAIT_STEP_MS )
    }
    : i then ( now_seconds )
    ? ( __ag_arg_bool args `deliver` T ) { ^ ( __ag_op_brief st me args then ) } {}
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
    : ( Vec AgTask ) mine ( ag_tasks st `mine` me `` AG_LIMIT_MAX then )
    ( json_obj_set o `holding` ( __ag_tasks_json mine ) )
    ? > ( vec_len [AgTask] mine ) 0 {
        ( string_push_str t `holding:\n` )
        ( __ag_tasks_text t mine then )
    } {}
    ( ag_tasks_free mine )
    ^ ( __ag_ok o t )
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
    ? == ( string_len body ) 0 { ^ @ ?AgRes { T ( __ag_err 400 `body is required` ) } } {}
    ? > ( string_len body ) AG_BODY_MAX { ^ @ ?AgRes { T ( __ag_err 400 `body: at most 16 KiB` ) } } {}
    ^ @ ?AgRes { F }
}

@ __ag_posted i id s where → AgRes {
    : Json o ( __ag_obj_int `id` id )
    : String t ( string_from `#` )
    ( string_push_int t id )
    ( string_push_str t ` posted to ` )
    ( string_push_str t where )
    ( string_push_str t `\n` )
    ^ ( __ag_ok o t )
}

@ __ag_op_post AgStore st s me Json args i now → AgRes {
    : String body ( __ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ( string_free body ) ^ e } F _ → {} }
    : ~ String ch ( __ag_arg_str args `channel` )
    ? == ( string_len ch ) 0 { ( string_push_str ch `public` ) } {}
    ? ( ag_channel_exists st ( string_data ch ) ) {} {
        ( string_free body )
        : String m ( string_from `no channel '` )
        ( string_push_str m ( string_data ch ) )
        ( string_push_str m `' — channels lists them, channel_create makes one` )
        ( string_free ch )
        ^ ( __ag_err_s 404 m )
    }
    : i reply ( __ag_arg_int args `reply_to` 0 )
    : i id ( ag_post st ( string_data ch ) me ( string_data body ) reply now )
    ( string_free body )
    ? == id 0 { ( string_free ch ) ^ ( __ag_err 500 `could not store the message` ) } {}
    : AgRes r ( __ag_posted id ( string_data ch ) )
    ( string_free ch )
    ^ r
}

@ __ag_op_send AgStore st s me Json args i now → AgRes {
    : String body ( __ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ( string_free body ) ^ e } F _ → {} }
    : String to ( __ag_arg_str args `to` )
    : ~ b known F
    ?? ( ag_agent_get st ( string_data to ) ) { T a → { ( ag_agent_free a ) = known T } F _ → {} }
    ? known {} {
        ( string_free body )
        : String m ( string_from `no agent '` )
        ( string_push_str m ( string_data to ) )
        ( string_push_str m `' — agents lists who is here` )
        ( string_free to )
        ^ ( __ag_err_s 404 m )
    }
    : i reply ( __ag_arg_int args `reply_to` 0 )
    : String mbox ( ag_mailbox ( string_data to ) )
    : i id ( ag_post st ( string_data mbox ) me ( string_data body ) reply now )
    ( string_free mbox )
    ( string_free body )
    ? == id 0 { ( string_free to ) ^ ( __ag_err 500 `could not store the message` ) } {}
    : Json o ( __ag_obj_int `id` id )
    : String t ( string_from `#` )
    ( string_push_int t id )
    ( string_push_str t ` sent to ` )
    ( string_push_str t ( string_data to ) )
    ( string_push_str t `\n` )
    ( string_free to )
    ^ ( __ag_ok o t )
}

@ __ag_op_history AgStore st s me Json args i now → AgRes {
    : String ch ( __ag_arg_str args `channel` )
    ? == ( string_len ch ) 0 { ( string_free ch ) ^ ( __ag_err 400 `channel is required` ) } {}
    // A mailbox is readable by its owner only.
    ? == ( nurl_str_get ( string_data ch ) 0 ) 64 {
        : String mine ( ag_mailbox me )
        : b own ( string_eq mine ch )
        ( string_free mine )
        ? own {} { ( string_free ch ) ^ ( __ag_err 403 `only your own mail (@yourname) is readable` ) }
    } {
        ? ( ag_channel_exists st ( string_data ch ) ) {} {
            : String m ( string_from `no channel '` )
            ( string_push_str m ( string_data ch ) )
            ( string_push_str m `'` )
            ( string_free ch )
            ^ ( __ag_err_s 404 m )
        }
    }
    : i before ( __ag_arg_int args `before` 0 )
    : ( Vec AgMsg ) msgs ( ag_history st ( string_data ch ) before ( __ag_limit args ) )
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data ch ) ) )
    ( json_obj_set o `messages` ( __ag_msgs_json msgs ) )
    : String t ( string_new )
    : i n ( vec_len [AgMsg] msgs )
    ? == n 0 {
        ( string_push_str t ( string_data ch ) )
        ( string_push_str t `: no messages` )
        ? > before 0 { ( string_push_str t ` before #` ) ( string_push_int t before ) } {}
        ( string_push_str t `\n` )
    } {
        ( __ag_msgs_text t msgs now )
        ?? ( vec_get [AgMsg] msgs 0 ) {
            T first → {
                ? > . first id 1 {
                    ( string_push_str t `(older: history before=` )
                    ( string_push_int t . first id )
                    ( string_push_str t `)\n` )
                } {}
            }
            F _ → {}
        }
    }
    ( ag_msgs_free msgs )
    ( string_free ch )
    ^ ( __ag_ok o t )
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
                ( json_arr_push arr o )
                ( string_push_str t ( string_data . a id ) )
                ( string_push_str t ` (seen ` )
                ( __ag_age t now . a seen )
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
    ( ag_agents_free v )
    : Json o ( json_obj_new )
    ( json_obj_set o `agents` arr )
    ^ ( __ag_ok o t )
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
    ( ag_channels_free v )
    : Json o ( json_obj_new )
    ( json_obj_set o `channels` arr )
    ^ ( __ag_ok o t )
}

@ __ag_op_channel_create AgStore st s me Json args i now → AgRes {
    : String name ( __ag_arg_str args `name` )
    : String about ( __ag_arg_str args `about` )
    ? ( ag_name_ok ( string_data name ) ) {} {
        ( string_free name )
        ( string_free about )
        : String m ( string_from `channel name must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( __ag_err_s 400 m )
    }
    ? ( ag_channel_create st ( string_data name ) ( string_data about ) me now ) {} {
        ( string_free about )
        : String m ( string_from `channel '` )
        ( string_push_str m ( string_data name ) )
        ( string_push_str m `' exists already` )
        ( string_free name )
        ^ ( __ag_err_s 409 m )
    }
    ( ag_follow st me ( string_data name ) )
    ( string_free about )
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data name ) ) )
    : String t ( string_from `created and following ` )
    ( string_push_str t ( string_data name ) )
    ( string_push_str t `\n` )
    ( string_free name )
    ^ ( __ag_ok o t )
}

@ __ag_op_follow AgStore st s me Json args i now b on → AgRes {
    : String ch ( __ag_arg_str args `channel` )
    ? == ( string_len ch ) 0 { ( string_free ch ) ^ ( __ag_err 400 `channel is required` ) } {}
    ? ( ag_channel_exists st ( string_data ch ) ) {} {
        : String m ( string_from `no channel '` )
        ( string_push_str m ( string_data ch ) )
        ( string_push_str m `'` )
        ( string_free ch )
        ^ ( __ag_err_s 404 m )
    }
    : b ok ? on ( ag_follow st me ( string_data ch ) ) ( ag_unfollow st me ( string_data ch ) )
    ? ok {} {
        ? on { ( string_free ch ) ^ ( __ag_err 500 `could not follow` ) }
        {
            : String m ( string_from `you were not following ` )
            ( string_push_str m ( string_data ch ) )
            ( string_free ch )
            ^ ( __ag_err_s 409 m )
        }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `channel` ( json_str_lit ( string_data ch ) ) )
    ( json_obj_set o `following` ( json_bool on ) )
    : String t ( string_from ? on `following ` `no longer following ` )
    ( string_push_str t ( string_data ch ) )
    ( string_push_str t `\n` )
    ( string_free ch )
    ^ ( __ag_ok o t )
}

@ __ag_op_task_post AgStore st s me Json args i now → AgRes {
    : String title ( __ag_arg_str args `title` )
    ? == ( string_len title ) 0 { ( string_free title ) ^ ( __ag_err 400 `title is required` ) } {}
    ? > ( string_len title ) 200 { ( string_free title ) ^ ( __ag_err 400 `title: at most 200 characters` ) } {}
    : String body ( __ag_arg_str args `body` )
    ? > ( string_len body ) AG_BODY_MAX { ( string_free title ) ( string_free body ) ^ ( __ag_err 400 `body: at most 16 KiB` ) } {}
    : String rawtags ( __ag_arg_str args `tags` )
    : String tags ( __ag_tags_norm rawtags )
    ( string_free rawtags )
    : i prio ( __ag_clamp ( __ag_arg_int args `priority` 0 ) -100 100 )
    : i id ( ag_task_post st ( string_data title ) ( string_data body ) ( string_data tags ) me prio now )
    ( string_free title )
    ( string_free body )
    ( string_free tags )
    ? == id 0 { ^ ( __ag_err 500 `could not store the task` ) } {}
    : Json o ( __ag_obj_int `id` id )
    : String t ( string_from `task #` )
    ( string_push_int t id )
    ( string_push_str t ` posted — you will hear when it is claimed and done\n` )
    ^ ( __ag_ok o t )
}

@ __ag_op_tasks AgStore st s me Json args i now → AgRes {
    : ~ String which ( __ag_arg_str args `which` )
    ? == ( string_len which ) 0 { ( string_push_str which `open` ) } {}
    : String tag ( __ag_arg_str args `tag` )
    : String ltag ( string_to_lower tag )
    ( string_free tag )
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
    ( ag_tasks_free v )
    ( string_free ltag )
    ( string_free which )
    ^ ( __ag_ok o t )
}

@ __ag_no_task i id → AgRes {
    : String m ( string_from `no task #` )
    ( string_push_int m id )
    ^ ( __ag_err_s 404 m )
}

@ __ag_op_task AgStore st Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    ?? ( ag_task_get st id now ) {
        F _ → { ^ ( __ag_no_task id ) }
        T tk → {
            : Json o ( __ag_task_json tk )
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
            ( ag_task_free tk )
            ^ ( __ag_ok o t )
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
        ^ ( __ag_err_s 409 m )
    } {}
    ? == rc AG_TASK_FAILED { ^ ( __ag_err 500 `could not update the task` ) } {}
    : Json o ( __ag_obj_int `id` id )
    : String t ( string_from `task #` )
    ( string_push_int t id )
    ( string_push_str t ` ` )
    ( string_push_str t did )
    ( string_push_str t `\n` )
    ?? ( ag_task_get st id now ) {
        T tk → {
            ( json_obj_set o `task` ( __ag_task_json tk ) )
            ( ag_task_free tk )
        }
        F _ → {}
    }
    ^ ( __ag_ok o t )
}

@ __ag_lease Json args → i {
    ^ ( __ag_clamp ( __ag_arg_int args `lease_s` AG_DEFAULT_LEASE ) 30 AG_LEASE_MAX )
}

@ __ag_op_task_claim AgStore st s me Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    : i lease ( __ag_lease args )
    : i rc ( ag_task_claim st id me lease now )
    : ~ String did ( string_from `claimed by you, lease ` )
    ( __ag_left did now + now lease )
    ( string_push_str did ` — task_done when finished` )
    : AgRes r ( __ag_task_verdict st rc id ( string_data did ) `is not open (someone holds it, or it is finished) — tasks shows what is` now )
    ( string_free did )
    ^ r
}

@ __ag_op_task_extend AgStore st s me Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    : i lease ( __ag_lease args )
    : i rc ( ag_task_extend st id me lease now )
    : ~ String did ( string_from `lease ` )
    ( __ag_left did now + now lease )
    : AgRes r ( __ag_task_verdict st rc id ( string_data did ) `is not held by you` now )
    ( string_free did )
    ^ r
}

@ __ag_op_task_done AgStore st s me Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    : String result ( __ag_arg_str args `result` )
    ? == ( string_len result ) 0 { ( string_free result ) ^ ( __ag_err 400 `result is required — say what was done` ) } {}
    ? > ( string_len result ) AG_BODY_MAX { ( string_free result ) ^ ( __ag_err 400 `result: at most 16 KiB` ) } {}
    : i rc ( ag_task_done st id me ( string_data result ) now )
    ( string_free result )
    ^ ( __ag_task_verdict st rc id `done — the poster has your result` `is not held by you` now )
}

@ __ag_op_task_release AgStore st s me Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    : String note ( __ag_arg_str args `note` )
    ? > ( string_len note ) AG_BODY_MAX { ( string_free note ) ^ ( __ag_err 400 `note: at most 16 KiB` ) } {}
    : i rc ( ag_task_release st id me ( string_data note ) now )
    ( string_free note )
    ^ ( __ag_task_verdict st rc id `released — open again` `is not held by you` now )
}

@ __ag_op_task_cancel AgStore st s me Json args i now → AgRes {
    : i id ( __ag_arg_int args `id` 0 )
    : i rc ( ag_task_cancel st id me now )
    ^ ( __ag_task_verdict st rc id `cancelled` `is not yours to cancel, or is already finished` now )
}

// The `project` argument of the note ops: '' (global) or a valid name.
@ __ag_arg_project Json args → ?String {
    : String pr ( __ag_arg_str args `project` )
    ? == ( string_len pr ) 0 { ^ @ ?String { T pr } } {}
    ? ( ag_name_ok ( string_data pr ) ) { ^ @ ?String { T pr } } {}
    ( string_free pr )
    ^ @ ?String { F }
}

@ __ag_bad_project → AgRes {
    : String m ( string_from `project must be ` )
    ( string_push_str m AG_NAME_RULE )
    ^ ( __ag_err_s 400 m )
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
    : String key ( __ag_arg_str args `key` )
    ? ( ag_name_ok ( string_data key ) ) {} {
        ( string_free key )
        : String m ( string_from `key must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( __ag_err_s 400 m )
    }
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { ( string_free project ) = project p } F _ → { ( string_free key ) ( string_free project ) ^ ( __ag_bad_project ) } }
    : String body ( __ag_arg_str args `body` )
    ?? ( __ag_body_check body ) { T e → { ( string_free key ) ( string_free project ) ( string_free body ) ^ e } F _ → {} }
    : b ok ( ag_note_set st ( string_data project ) ( string_data key ) ( string_data body ) me now )
    ( string_free body )
    ? ok {} { ( string_free key ) ( string_free project ) ^ ( __ag_err 500 `could not store the note` ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data key ) ) )
    : String t ( string_from `note ` )
    ( __ag_note_ref t ( string_data project ) ( string_data key ) )
    ( string_push_str t ` saved\n` )
    ( string_free key )
    ( string_free project )
    ^ ( __ag_ok o t )
}

@ __ag_no_note String project String key → AgRes {
    : String m ( string_from `no note '` )
    ( __ag_note_ref m ( string_data project ) ( string_data key ) )
    ( string_push_str m `' — notes lists them` )
    ( string_free key )
    ( string_free project )
    ^ ( __ag_err_s 404 m )
}

@ __ag_op_note AgStore st Json args i now → AgRes {
    : String key ( __ag_arg_str args `key` )
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { ( string_free project ) = project p } F _ → { ( string_free key ) ( string_free project ) ^ ( __ag_bad_project ) } }
    ?? ( ag_note_get st ( string_data project ) ( string_data key ) ) {
        F _ → { ^ ( __ag_no_note project key ) }
        T n → {
            : Json o ( __ag_note_json n T )
            : String t ( string_new )
            ( __ag_note_ref t ( string_data . n project ) ( string_data . n key ) )
            ( string_push_str t ` (` )
            ( string_push_str t ( string_data . n author ) )
            ( string_push_str t ` ` )
            ( __ag_age t now . n updated )
            ( string_push_str t `):\n` )
            ( string_push_str t ( string_data . n body ) )
            ( string_push_str t `\n` )
            ( ag_note_free n )
            ( string_free key )
            ( string_free project )
            ^ ( __ag_ok o t )
        }
    }
}

@ __ag_op_notes AgStore st Json args i now → AgRes {
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { ( string_free project ) = project p } F _ → { ( string_free project ) ^ ( __ag_bad_project ) } }
    : b all == ( string_len project ) 0
    : ( Vec AgNote ) v ( ag_notes st ( string_data project ) all F )
    : Json arr ( json_arr_new )
    : String t ( string_new )
    : i n ( vec_len [AgNote] v )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgNote] v i ) {
            T x → {
                ( json_arr_push arr ( __ag_note_json x F ) )
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
    ( ag_notes_free v )
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `notes` arr )
    ( string_free project )
    ^ ( __ag_ok o t )
}

@ __ag_op_note_del AgStore st Json args i now → AgRes {
    : String key ( __ag_arg_str args `key` )
    : ?String pro ( __ag_arg_project args )
    : ~ String project ( string_new )
    ?? pro { T p → { ( string_free project ) = project p } F _ → { ( string_free key ) ( string_free project ) ^ ( __ag_bad_project ) } }
    ? ( ag_note_del st ( string_data project ) ( string_data key ) ) {} { ^ ( __ag_no_note project key ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `project` ( json_str_lit ( string_data project ) ) )
    ( json_obj_set o `key` ( json_str_lit ( string_data key ) ) )
    : String t ( string_from `note ` )
    ( __ag_note_ref t ( string_data project ) ( string_data key ) )
    ( string_push_str t ` deleted\n` )
    ( string_free key )
    ( string_free project )
    ^ ( __ag_ok o t )
}

// ── Dispatch ─────────────────────────────────────────────────────────

// Does the catalog know `name`, and does it need a signed-in caller?
// -1 unknown, 0 open, 1 needs auth.
@ ag_op_auth_kind s name → i {
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : ~ i kind -1
    : i n ( vec_len [AgOpDef] cat )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                ? != 0 ( nurl_str_eq ( string_data . d name ) name ) { = kind ? . d needs_auth 1 0 } {}
            }
            F _ → {}
        }
        = i + i 1
    }
    ( ag_catalog_free cat )
    ^ kind
}

// Run one operation for `c`. `args` is BORROWED (a Json object, or
// anything else for "no arguments").
@ ag_op_call AgStore st AgCaller c s name Json args i now → AgRes {
    : i kind ( ag_op_auth_kind name )
    ? < kind 0 {
        : String m ( string_from `unknown operation '` )
        ( string_push_str m name )
        ( string_push_str m `'` )
        ^ ( __ag_err_s 404 m )
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
    ? != 0 ( nurl_str_eq name `agents` ) { ^ ( __ag_op_agents st now ) } {}
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
    ^ ( __ag_err_s 501 m )
}
