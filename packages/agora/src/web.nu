// agora/src/web.nu — the signed-in service's HTTP surface.
//
// Three things live here:
//
//   resolution  An HTTP request with an OIDC bearer token → the person
//               (auth.nu) → their organisation. The service keeps no
//               state between calls (MCP 2026-07-28 has no sessions):
//               every agent call names the REPOSITORY it works in
//               (`repo=`, its git remote URL in any spelling) and the
//               AGENT it is there (`as=`). The repository picks the
//               agora — one per repository per organisation, shared by
//               everybody of the organisation who works on it, from any
//               machine — and the name is made on first use.
//   join        Optional in signed-in mode: sets the agent's `about`.
//   /m/…        What the web page does: look at a repository's agora
//               (`?repo=`) a page at a time, write into it, edit, delete
//               and clean up; the organisation's skills; feedback about
//               agora (the owner organisation reads everyone's); manage
//               the organisation's people (admins) and which
//               organisations may sign in (admins of the owner
//               organisation).
//
// In local mode the web page works too, as the one local administrator
// (whoever can reach the port is whoever can open the file); `repo` is
// ignored there — the file is the one agora.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/random.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/mcp_auth.nu`
$ `api.nu`
$ `auth.nu`

// ── Small HTTP helpers ───────────────────────────────────────────────

@ ag_json_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `error` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( response_set_header r `Cache-Control` `no-store` )
    ^ r
}

@ __ag_json_ok Json o → HttpResponse {
    : HttpResponse r ( response_json 200 o )
    ( response_set_header r `Cache-Control` `no-store` )
    ^ r
}

// A header's value, '' when absent.
@ _ag_header HttpRequest req s name → String {
    ?? ( header_get . req headers name ) {
        T v → { ^ ( string_trim v ) }
        F _ → { ^ ( string_new ) }
    }
}

// A query parameter (percent-decoded), '' when absent.
@ __ag_query HttpRequest req s key → String {
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [QueryPair] pairs i ) {
            T qp → { ? != 0 ( nurl_str_eq ( string_data . qp key ) key ) { ^ ( string_from ( string_data . qp value ) ) } {} }
            F _ → {}
        }
        = i + i 1
    }
    ^ ( string_new )
}

@ __ag_param HttpRequest req Params p s key → String {
    ?? ( params_get p key ) { T v → { ^ v } F _ → { ^ ( string_new ) } }
}

// The body as a JSON object ({} when there is none or it is not one).
@ __ag_body_obj HttpRequest req → Json {
    ? > ( vec_len [u] . req body ) 0 {
        ?? ( json_parse_bytes . req body ) {
            T j → { ? ( json_is_obj j ) { ^ j } {} }
            F _ → {}
        }
    } {}
    ^ ( json_obj_new )
}

// A configured string as JSON.
@ __ag_jstr String x → Json { ^ ( json_str_lit ( string_data x ) ) }

// The origin absolute URLs are built on: configured, else the request's.
@ ag_base_url HttpRequest req → String {
    : String pu ( ag_auth_public_url )
    ? > ( string_len pu ) 0 { ^ pu } {}
    ^ ( mcp_auth_base_url req `` )
}

// ── Who is asking ────────────────────────────────────────────────────

: AgWho {
    i status  // 0 = signed in; else the HTTP status to answer with
    AgPrincipal who
    AgStore st  // the organisation's people (local: the one file)
    AgStore rs  // the repository's agora (ag_who_in; local: the one file)
    String repo  // its key ('' outside ag_who_in, and in local mode)
}

@ __ag_no_store → AgStore { ^ @ AgStore { ( string_new ) F @ ?Database { F } } }

// The person behind a request and their organisation. Local mode: the
// one local administrator and the one file.
@ ag_who HttpRequest req i now → AgWho {
    ? ( ag_auth_oidc ) {} { ^ @ AgWho { 0 ( ag_principal_local ) ( ag_store ) ( ag_store ) ( string_new ) } }
    : ~ String tok ( string_new )
    ?? ( mcp_auth_bearer_token req ) { T t → { = tok t } F _ → {} }
    : AgPrincipal p ( ag_auth_principal ( string_data tok ) now )
    ? . p authed {} { ^ @ AgWho { 401 p ( __ag_no_store ) ( __ag_no_store ) ( string_new ) } }
    : AgStore st ( ag_org_store ( string_data . p org ) )
    ? . st ok {} { ^ @ AgWho { 500 p st ( __ag_no_store ) ( string_new ) } }
    ^ @ AgWho { 0 p st ( __ag_no_store ) ( string_new ) }
}

// The same, inside the repository the request's `?repo=` names.
@ ag_who_in HttpRequest req i now → AgWho {
    : AgWho w ( ag_who req now )
    ? | != . w status 0 ! ( ag_auth_oidc ) { ^ w } {}
    : String raw ( __ag_query req `repo` )
    ?? ( ag_repo_key ( string_data raw ) ) {
        F → { ^ @ AgWho { 400 . w who . w st ( __ag_no_store ) ( string_new ) } }
        T k → {
            : AgStore rs ( ag_repo_store ( string_data . . w who org ) ( string_data k ) )
            ? . rs ok {} { ^ @ AgWho { 500 . w who . w st rs k } }
            ^ @ AgWho { 0 . w who . w st rs k }
        }
    }
}

// The answer to a request whose AgWho is not 0.
@ ag_who_deny AgWho w → HttpResponse {
    ? == . w status 401 {
        : s why ( string_data . . w who why )
        : String msg ( string_from ? > ( nurl_str_len why ) 0 `token rejected: ` `sign in first` )
        ? > ( nurl_str_len why ) 0 { ( string_push_str msg why ) } {}
        : HttpResponse r ( ag_json_err 401 ( string_data msg ) )
        ( response_set_header r `WWW-Authenticate` `Bearer realm="agora"` )
        ^ r
    } {}
    ? == . w status 400 { ^ ( ag_json_err 400 `repo= names the repository: a git remote URL or host/owner/repo` ) } {}
    ^ ( ag_json_err . w status `the organisation's database could not be opened` )
}

// ── Acting as an agent ───────────────────────────────────────────────

// A repository key from what a caller wrote (ag_project_norm: any remote
// spelling → host/owner/repo); None for anything that is not a
// repository (a plain name, a bad path, nothing).
@ ag_repo_key s raw → ?String {
    ?? ( ag_project_norm raw ) {
        T k → { ? ( string_contains k `/` ) { ^ @ ?String { T k } } {} }
        F → {}
    }
    ^ @ ?String { F }
}

: s AG_REPO_NEEDED `repo is required on every call: the git remote URL of the repository you work in (git remote get-url origin; any spelling, e.g. git@github.com:org/repo.git)`
: s AG_AS_NEEDED `as is required on every call: your agent name in this repository (1-48 of a-z 0-9 . _ -), the same every time — others address you by it`

// Make sure agent `name` exists in this agora (made on first use) and
// mark it seen. A name is not anybody's: whoever in the organisation
// says `as=name` in this repository is that agent.
@ ag_agent_ensure AgStore st s name i now → b {
    ?? ( ag_agent_get st name ) {
        T a → {
            ? ( ag_seen_stale . a seen now ) { ( ag_agent_touch st name now ) } {}
            ^ T
        }
        F → {}
    }
    : String tok ( rand_hex_str 32 )
    : String h ( ag_token_hash ( string_data tok ) )
    ? ( ag_agent_create_from st name `` ( string_data h ) `` now ) { ^ T } {}
    // Lost a race for the name: it exists now, which is all we wanted.
    ?? ( ag_agent_get st name ) { T _ → { ^ T } F → { ^ F } }
}

// The caller a signed-in call acts as: agent `who` in repository `repo`
// of organisation `org`, signed in as `person`, reaching the
// organisation's file (skills) and the service's (feedback) beyond the
// repository.
@ __ag_caller_in s org s repo s person s who → AgCaller {
    : AgStore os ( ag_org_store org )
    : AgStore fs ( ag_feedback_store )
    ^ @ AgCaller { T ( string_from who ) ( string_from org ) ( string_from repo ) ( string_from person )
        ( string_from ( string_data . os path ) ) ( string_from ( string_data . fs path ) ) }
}

// Run op `name` for `person`, signed in to organisation `org`: the
// repository and the agent come from the call's own arguments.
@ ag_oidc_call s org s person Json args s name i now → AgRes {
    ? < ( ag_op_auth_kind name ) 0 {
        ^ ( ag_op_call ( __ag_no_store ) ( ag_caller_anon ) name args now )
    } {}
    : String raw_repo ( _ag_arg_str args `repo` )
    : ~ String repo ( string_new )
    ?? ( ag_repo_key ( string_data raw_repo ) ) {
        T k → { = repo k }
        F → { ^ ( _ag_err 400 AG_REPO_NEEDED ) }
    }
    : String raw_as ( _ag_arg_str args `as` )
    : String who ( string_to_lower raw_as )
    ? == ( string_len who ) 0 { ^ ( _ag_err 400 AG_AS_NEEDED ) } {}
    ? ( ag_name_ok ( string_data who ) ) {} {
        : String m ( string_from `as must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( _ag_err_s 400 m )
    }
    // One connection for the whole call: the agent's row and the op.
    : AgStore st ( ag_store_conn ( ag_repo_store org ( string_data repo ) ) )
    ? . st ok {} { ^ ( _ag_err 500 `the repository's agora could not be opened` ) }
    ? ( ag_agent_ensure st ( string_data who ) now ) {} { ^ ( _ag_err 500 `could not record the agent` ) }
    ? != 0 ( nurl_str_eq name `join` ) {
        : String about ( _ag_arg_str args `about` )
        ? > ( string_len about ) 1024 { ^ ( _ag_err 400 `about: at most 1024 characters` ) } {}
        ? > ( string_len about ) 0 { ( ag_agent_set_about st ( string_data who ) ( string_data about ) ) } {}
        : Json o ( json_obj_new )
        ( json_obj_set o `agent` ( json_str_lit ( string_data who ) ) )
        ( json_obj_set o `repo` ( json_str_lit ( string_data repo ) ) )
        : String t ( string_from `you are ` )
        ( string_push_str t ( string_data who ) )
        ( string_push_str t ` in ` )
        ( string_push_str t ( string_data repo ) )
        ( string_push_str t ` — pass repo=` )
        ( string_push_str t ( string_data repo ) )
        ( string_push_str t ` as=` )
        ( string_push_str t ( string_data who ) )
        ( string_push_str t ` on every call. Call brief.\n` )
        ^ ( _ag_ok o t )
    } {}
    : AgCaller c ( __ag_caller_in org ( string_data repo ) person ( string_data who ) )
    : ~ AgRes r ( ag_op_call st c name args now )
    ? & < . r status 400 != 0 ( nurl_str_eq name `whoami` ) {
        ( string_push_str . r text `repo: ` )
        ( string_push_str . r text ( string_data repo ) )
        ( string_push_str . r text `\n` )
        ( json_obj_set . r body `repo` ( json_str_lit ( string_data repo ) ) )
    } {}
    ^ r
}

// ── OAuth discovery ──────────────────────────────────────────────────

// GET /.well-known/oauth-protected-resource[/mcp] (RFC 9728): who issues
// tokens for /mcp and which scope to ask for. 404 in local mode.
@ ag_h_resource_metadata HttpRequest req Params p → HttpResponse {
    ? ( ag_auth_oidc ) {} { ^ ( response_text 404 `not found\n` ) }
    : String base ( ag_base_url req )
    : String resource ( string_from ( string_data base ) )
    ( string_push_str resource `/mcp` )
    : String scope ( ag_auth_scope )
    : String iss ( ag_auth_issuer )
    : Json md ( mcp_auth_resource_metadata ( string_data resource ) ( string_data iss ) ( string_data scope ) )
    : HttpResponse r ( mcp_auth_metadata_response md )
    ^ r
}

// The 401 an MCP client follows to sign in.
@ ag_mcp_challenge HttpRequest req AgPrincipal p → HttpResponse {
    : String base ( ag_base_url req )
    : String md ( string_from ( string_data base ) )
    : String mdp ( mcp_auth_metadata_path `/mcp` )
    ( string_push_str md ( string_data mdp ) )
    : s why ( string_data . p why )
    : b had > ( nurl_str_len why ) 0
    : HttpResponse r ( mcp_auth_challenge ( string_data md ) ? had `invalid_token` `unauthorized`
    ? had why `sign in to agora` )
    ^ r
}

// GET /auth/config — what the page needs to start a sign-in. Public:
// a client id and an issuer are in the browser's redirect anyway.
@ ag_h_auth_config HttpRequest req Params p → HttpResponse {
    : Json o ( json_obj_new )
    : b on ( ag_auth_oidc )
    ( json_obj_set o `enabled` ( json_bool on ) )
    ( json_obj_set o `mode` ( json_str_lit ? on `oidc` `local` ) )
    ( json_obj_set o `issuer` ( __ag_jstr ( ag_auth_issuer ) ) )
    ( json_obj_set o `client_id` ( __ag_jstr ( ag_auth_client_id ) ) )
    ( json_obj_set o `audience` ( __ag_jstr ( ag_auth_audience ) ) )
    : String scope ( string_from `openid profile email ` )
    : String api ( ag_auth_scope )
    ( string_push_str scope ( string_data api ) )
    ( json_obj_set o `scope` ( json_str_lit ( string_data scope ) ) )
    ( json_obj_set o `redirect_path` ( json_str_lit `/oauth/callback` ) )
    : String base ( ag_base_url req )
    : String mcp ( string_from ( string_data base ) )
    ( string_push_str mcp `/mcp` )
    ( json_obj_set o `mcp_url` ( json_str_lit ( string_data mcp ) ) )
    ( json_obj_set o `version` ( json_str_lit AG_VERSION ) )
    ^ ( __ag_json_ok o )
}

// ── /m: the web page's API ───────────────────────────────────────────

// Inside a repository's agora everybody of the organisation may change
// anything — it is one shared room. Administration (people,
// organisations) is the admins'.

@ __ag_is_owner_admin AgWho w → b {
    ? ( ag_auth_oidc ) {} { ^ F }
    ? ( ag_principal_is_admin . w who ) {} { ^ F }
    : String owner ( ag_auth_owner )
    ^ != 0 ( nurl_str_eq ( string_data . . w who org ) ( string_data owner ) )
}

// Of the organisation that runs the service — who reads and answers the
// feedback. Locally: the one administrator, who runs it.
@ __ag_is_owner_member AgWho w → b {
    ? ( ag_auth_oidc ) {} { ^ T }
    : String owner ( ag_auth_owner )
    ^ != 0 ( nurl_str_eq ( string_data . . w who org ) ( string_data owner ) )
}

// The agent name a person writes as from the web page unless they say
// otherwise: the local part of their e-mail made a name (`ann.b` for
// Ann.B@x.example); `web` when that leaves nothing (and locally).
@ __ag_web_name AgWho w → String {
    : String out ( string_new )
    : s e ( string_data . . w who email )
    : ( Slice u ) ev ( slice_of_str e )
    : i n ( nurl_str_len e )
    : ~ i i 0
    ~ & & < i n != ( slice_byte ev i ) 64 < ( string_len out ) AG_NAME_MAX {
        : i c0 ( slice_byte ev i )
        : i c ? & >= c0 65 <= c0 90 + c0 32 c0
        : b ok | | & >= c 97 <= c 122 & >= c 48 <= c 57 | | == c 45 == c 46 == c 95
        ( string_push_char out ? ok c 45 )
        = i + i 1
    }
    ? == ( string_len out ) 0 { ^ ( string_from `web` ) } {}
    ^ out
}

// A query parameter as a whole number; `dflt` when absent, kept to lo…hi.
@ __ag_query_int HttpRequest req s key i dflt i lo i hi → i {
    : String v ( __ag_query req key )
    : ~ i x dflt
    ? > ( string_len v ) 0 { = x ( nurl_str_to_int ( string_data v ) ) } {}
    ? < x lo { ^ lo } {}
    ? > x hi { ^ hi } {}
    ^ x
}

// A query parameter that is true when it says `1` or `true`.
@ __ag_query_on HttpRequest req s key → b {
    : String v ( __ag_query req key )
    ^ | != 0 ( nurl_str_eq ( string_data v ) `1` ) != 0 ( nurl_str_eq ( string_data v ) `true` )
}

// Answer what an operation answered: its JSON body on success, its text
// as the error otherwise.
@ __ag_res_http sink AgRes r → HttpResponse {
    ? >= . r status 400 { ^ ( ag_json_err . r status ( string_data . r text ) ) } {}
    : HttpResponse h ( response_json 200 . r body )
    ( response_set_header h `Cache-Control` `no-store` )
    ^ h
}

// Run op `op` with `args` as the agent the web page writes as — `as`, or
// the person's default name (__ag_web_name) — made on first use, as an
// agent's own call would make it.
@ __ag_web_act AgWho w Json args s op i now → HttpResponse {
    : String raw ( _ag_arg_str args `as` )
    : ~ String who ( string_to_lower raw )
    ? == ( string_len who ) 0 { = who ( __ag_web_name w ) } {}
    ? ( ag_name_ok ( string_data who ) ) {} { ^ ( ag_json_err 400 `as must be 1–48 of a-z 0-9 . _ -` ) }
    : AgStore st ( ag_store_conn . w rs )
    ? ( ag_agent_ensure st ( string_data who ) now ) {} { ^ ( ag_json_err 500 `could not record the agent` ) }
    : ~ AgRes r ( ag_op_call st ( ag_caller_as ( string_data who ) ) op args now )
    ? < . r status 400 { ( json_obj_set . r body `as` ( json_str_lit ( string_data who ) ) ) } {}
    ^ ( __ag_res_http r )
}

// GET /m/me[?repo=] — who is signed in; with a repository, its counts.
@ ag_h_me HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : b in_repo | ! ( ag_auth_oidc ) > ( string_len ( __ag_query req `repo` ) ) 0
    : AgWho w ? in_repo ( ag_who_in req now ) ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json o ( json_obj_new )
    ( json_obj_set o `mode` ( json_str_lit ? ( ag_auth_oidc ) `oidc` `local` ) )
    ( json_obj_set o `org` ( json_str_lit ( string_data . . w who org ) ) )
    ( json_obj_set o `subject` ( json_str_lit ( string_data . . w who sub ) ) )
    ( json_obj_set o `email` ( json_str_lit ( string_data . . w who email ) ) )
    ( json_obj_set o `name` ( json_str_lit ( string_data . . w who name ) ) )
    ( json_obj_set o `role` ( json_str_lit ( string_data . . w who role ) ) )
    ( json_obj_set o `is_admin` ( json_bool ( ag_principal_is_admin . w who ) ) )
    ( json_obj_set o `is_owner_admin` ( json_bool ( __ag_is_owner_admin w ) ) )
    ( json_obj_set o `can_triage` ( json_bool ( __ag_is_owner_member w ) ) )
    ( json_obj_set o `web_as` ( json_str_lit ( string_data ( __ag_web_name w ) ) ) )
    ( json_obj_set o `repo` ( json_str_lit ( string_data . w repo ) ) )
    : Json tj ( json_obj_new )
    ? in_repo {
        : AgTotals t ( ag_totals . w rs )
        ( json_obj_set tj `agents` ( json_int . t agents ) )
        ( json_obj_set tj `channels` ( json_int . t channels ) )
        ( json_obj_set tj `messages` ( json_int . t messages ) )
        ( json_obj_set tj `tasks_open` ( json_int . t tasks_open ) )
        ( json_obj_set tj `tasks` ( json_int . t tasks ) )
        ( json_obj_set tj `notes` ( json_int . t notes ) )
        ( json_obj_set tj `rules` ( json_int . t rules ) )
    } {}
    ( json_obj_set tj `users` ( json_int ( vec_len [AgUser] ( ag_users . w st ) ) ) )
    ( json_obj_set tj `skills` ( json_int ( ag_skill_count . w st ) ) )
    ( json_obj_set o `totals` tj )
    ( json_obj_set o `version` ( json_str_lit AG_VERSION ) )
    ^ ( __ag_json_ok o )
}

// GET /m/repos — the repositories the organisation has an agora for.
@ ag_h_repos HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json arr ( json_arr_new )
    : Json out ( json_obj_new )
    ? ( ag_auth_oidc ) {
        : ( Vec String ) v ( ag_org_repos ( string_data . . w who org ) )
        : i n ( vec_len [String] v )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [String] v k ) { T r → { ( json_arr_push arr ( json_str_lit ( string_data r ) ) ) } F _ → {} }
            = k + k 1
        }
    } { ( json_obj_set out `local` ( json_bool T ) ) }
    ( json_obj_set out `repos` arr )
    ^ ( __ag_json_ok out )
}

// GET /m/agents?repo= — every agent of the repository's agora.
@ ag_h_agents HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ( Vec AgAgent ) v ( ag_agents . w rs )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgAgent] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgAgent] v k ) {
            T a → {
                : Json o ( json_obj_new )
                ( json_obj_set o `id` ( json_str_lit ( string_data . a id ) ) )
                ( json_obj_set o `about` ( json_str_lit ( string_data . a about ) ) )
                ( json_obj_set o `status` ( json_str_lit ( string_data . a status ) ) )
                ( json_obj_set o `status_at` ( json_int . a status_at ) )
                ( json_obj_set o `created` ( json_int . a created ) )
                ( json_obj_set o `seen` ( json_int . a seen ) )
                ( json_obj_set o `may_change` ( json_bool T ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `agents` arr )
    ^ ( __ag_json_ok out )
}

// PUT /m/agents/:id {about}  ·  DELETE /m/agents/:id
@ ag_h_agent_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String id ( __ag_param req p `id` )
    : Json b ( __ag_body_obj req )
    : String about ( _ag_arg_str b `about` )
    ? > ( string_len about ) 1024 { ^ ( ag_json_err 400 `about: at most 1024 characters` ) } {}
    ? ( ag_agent_set_about . w rs ( string_data id ) ( string_data about ) ) {} { ^ ( ag_json_err 404 `no such agent` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

@ ag_h_agent_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String id ( __ag_param req p `id` )
    ? ( ag_agent_delete . w rs ( string_data id ) now ) {} { ^ ( ag_json_err 404 `no such agent` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// GET /m/channels
@ ag_h_channels HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ( Vec AgChannel ) v ( ag_channels . w rs )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgChannel] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgChannel] v k ) {
            T c → {
                : Json o ( json_obj_new )
                ( json_obj_set o `name` ( json_str_lit ( string_data . c name ) ) )
                ( json_obj_set o `about` ( json_str_lit ( string_data . c about ) ) )
                ( json_obj_set o `created_by` ( json_str_lit ( string_data . c created_by ) ) )
                ( json_obj_set o `created` ( json_int . c created ) )
                ( json_obj_set o `messages` ( json_int . c count ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `channels` arr )
    ^ ( __ag_json_ok out )
}

// DELETE /m/channels?repo=&name= — the channel and everything in it. (A
// query parameter: a channel may have '/' in its name.)
@ ag_h_channel_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String name ( __ag_query req `name` )
    ? != 0 ( nurl_str_eq ( string_data name ) `public` ) { ^ ( ag_json_err 400 `public cannot be deleted: every agent follows it` ) } {}
    : ( Vec AgChannel ) v ( ag_channels . w rs )
    : i n ( vec_len [AgChannel] v )
    : ~ b found F
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgChannel] v k ) {
            T c → { ? != 0 ( nurl_str_eq ( string_data . c name ) ( string_data name ) ) { = found T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ? found {} { ^ ( ag_json_err 404 `no such channel` ) }
    ? ( ag_channel_delete . w rs ( string_data name ) ) {} { ^ ( ag_json_err 500 `could not delete the channel` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// GET /m/messages?channel=&from=&q=&before=&limit=&offset=&order= — a
// page, newest first (`order=oldest`: oldest first), with how many match
// (`total`).
@ ag_h_messages HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String channel ( __ag_query req `channel` )
    : String from ( __ag_query req `from` )
    : String q ( __ag_query req `q` )
    : i before ( __ag_query_int req `before` 0 0 9223372036854775807 )
    : i limit ( __ag_query_int req `limit` 100 1 500 )
    : i offset ( __ag_query_int req `offset` 0 0 1000000000 )
    : String order ( __ag_query req `order` )
    : b oldest != 0 ( nurl_str_eq ( string_data order ) `oldest` )
    : ( Vec AgMsg ) v ( ag_messages_page . w rs ( string_data channel ) ( string_data from ) ( string_data q ) before oldest limit offset )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgMsg] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgMsg] v k ) {
            T m → {
                : Json o ( _ag_msg_json m 0 )
                ( json_obj_set o `may_change` ( json_bool T ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `messages` arr )
    ( json_obj_set out `total` ( json_int ( ag_messages_count . w rs ( string_data channel ) ( string_data from ) ( string_data q ) ) ) )
    ^ ( __ag_json_ok out )
}

// POST /m/messages?repo= {as, channel | to, body, reply_to} — a person
// writes into the room as an agent of it: `to` sends direct mail, else it
// is a post (to `public` unless `channel` says otherwise).
@ ag_h_message_new HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : String to ( _ag_arg_str b `to` )
    ^ ( __ag_web_act w b ? > ( string_len to ) 0 `send` `post` now )
}

// PUT /m/messages/:id {body}  ·  DELETE /m/messages/:id
@ ag_h_message_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_msg_get . w rs id ) {
        F _ → { ^ ( ag_json_err 404 `no such message` ) }
        T m → {
            : Json b ( __ag_body_obj req )
            : String body ( _ag_arg_str b `body` )
            ? == ( string_len body ) 0 { ^ ( ag_json_err 400 `body is empty — delete the message instead` ) } {}
            ? > ( string_len body ) AG_BODY_MAX { ^ ( ag_json_err 400 `body: at most 16 KiB` ) } {}
            ? ( ag_msg_set_body . w rs id ( string_data body ) ) {} { ^ ( ag_json_err 500 `could not save the message` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

@ ag_h_message_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_msg_get . w rs id ) {
        F _ → { ^ ( ag_json_err 404 `no such message` ) }
        T m → {
            ? ( ag_msg_delete . w rs id ) {} { ^ ( ag_json_err 500 `could not delete the message` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

// GET /m/tasks?status=&holder=&q=&hide_done=&sort=&dir=&limit=&offset= —
// a page of tasks: `status` open | claimed | done | cancelled ('' or
// `all` = any), `holder` the agent holding (or that finished) it,
// `hide_done=1` leaves done and cancelled out; sorted by `sort` (id,
// title, status, poster, owner, priority, created, updated — the
// default), `dir=asc` or newest first; `total` is how many match.
@ ag_h_tasks HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ~ String status ( __ag_query req `status` )
    ? != 0 ( nurl_str_eq ( string_data status ) `all` ) { = status ( string_new ) } {}
    : String holder ( __ag_query req `holder` )
    : String q ( __ag_query req `q` )
    : b hide ( __ag_query_on req `hide_done` )
    : String sort ( __ag_query req `sort` )
    : String dir ( __ag_query req `dir` )
    : b desc == 0 ( nurl_str_eq ( string_data dir ) `asc` )
    : i limit ( __ag_query_int req `limit` 50 1 500 )
    : i offset ( __ag_query_int req `offset` 0 0 1000000000 )
    : ( Vec AgTask ) v ( ag_tasks_page . w rs ( string_data status ) ( string_data holder ) ( string_data q ) hide ( string_data sort ) desc limit offset now )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgTask] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgTask] v k ) {
            T t → {
                : Json o ( _ag_task_json t )
                ( json_obj_set o `may_change` ( json_bool T ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `tasks` arr )
    ( json_obj_set out `total` ( json_int ( ag_tasks_count . w rs ( string_data status ) ( string_data holder ) ( string_data q ) hide ) ) )
    ^ ( __ag_json_ok out )
}

// POST /m/tasks?repo= {as, title, body, tags, priority} — a person offers
// work as an agent of the room; that agent's mail hears of every step.
@ ag_h_task_new HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    ^ ( __ag_web_act w b `task_post` now )
}

// PUT /m/tasks/:id {title, body, tags, priority, status}  ·  DELETE
@ ag_h_task_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_task_get . w rs id now ) {
        F _ → { ^ ( ag_json_err 404 `no such task` ) }
        T t → {
            : Json b ( __ag_body_obj req )
            : ~ String title ( _ag_arg_str b `title` )
            ? == ( string_len title ) 0 { = title ( string_from ( string_data . t title ) ) } {}
            ? > ( string_len title ) 200 { ^ ( ag_json_err 400 `title: at most 200 characters` ) } {}
            : ~ String body ( string_from ( string_data . t body ) )
            ?? ( json_obj_get b `body` ) { T _ → { = body ( _ag_arg_str b `body` ) } F _ → {} }
            ? > ( string_len body ) AG_BODY_MAX { ^ ( ag_json_err 400 `body: at most 16 KiB` ) } {}
            : ~ String tags ( string_from ( string_data . t tags ) )
            ?? ( json_obj_get b `tags` ) {
                T _ → {
                    : String raw ( _ag_arg_str b `tags` )
                    = tags ( _ag_tags_norm raw )
                }
                F _ → {}
            }
            : i prio ( _ag_arg_int b `priority` . t priority )
            : ~ String status ( _ag_arg_str b `status` )
            ? == ( string_len status ) 0 { = status ( string_from ( string_data . t status ) ) } {}
            ? ( ag_task_edit . w rs id ( string_data title ) ( string_data body ) ( string_data tags ) prio ( string_data status ) now ) {} {
                ^ ( ag_json_err 400 `status must be open, claimed, done or cancelled` )
            }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

@ ag_h_task_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_task_get . w rs id now ) {
        F _ → { ^ ( ag_json_err 404 `no such task` ) }
        T t → {
            ? ( ag_task_delete . w rs id ) {} { ^ ( ag_json_err 500 `could not delete the task` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

// GET /m/notes?repo=&q=&kind=&sort=&limit=&offset= — a page of notes with
// bodies, every project's: `kind` rules | notes ('' = both), `q` in key
// or body, rules first then by key (`sort=updated`: newest first);
// `total` is how many match.
@ ag_h_notes HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String q ( __ag_query req `q` )
    : String kind ( __ag_query req `kind` )
    : String sort ( __ag_query req `sort` )
    : i limit ( __ag_query_int req `limit` 50 1 500 )
    : i offset ( __ag_query_int req `offset` 0 0 1000000000 )
    : ( Vec AgNote ) v ( ag_notes_page . w rs ( string_data q ) ( string_data kind ) ( string_data sort ) limit offset )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgNote] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgNote] v k ) { T x → { ( json_arr_push arr ( _ag_note_json x T ) ) } F _ → {} }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `notes` arr )
    ( json_obj_set out `total` ( json_int ( ag_notes_count . w rs ( string_data q ) ( string_data kind ) ) ) )
    ^ ( __ag_json_ok out )
}

// PUT /m/notes?repo= {key, body, project?} — the author is the person.
@ ag_h_note_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : String key ( _ag_arg_str b `key` )
    ? ( ag_name_ok ( string_data key ) ) {} { ^ ( ag_json_err 400 `key must be 1–48 of a-z 0-9 . _ -` ) }
    : String raw ( _ag_arg_str b `project` )
    : ~ String project ( string_new )
    ?? ( ag_project_norm ( string_data raw ) ) { T pr → { = project pr } F → { ^ ( ag_json_err 400 `bad project` ) } }
    : String body ( _ag_arg_str b `body` )
    ? > ( string_len body ) AG_BODY_MAX { ^ ( ag_json_err 400 `body: at most 16 KiB` ) } {}
    : ~ String author ( string_from `web` )
    ? ( ag_auth_oidc ) { = author ( string_from ( string_data . . w who email ) ) } {}
    ? ( ag_note_set . w rs ( string_data project ) ( string_data key ) ( string_data body ) ( string_data author ) now ) {} {
        ^ ( ag_json_err 500 `could not save the note` )
    }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// DELETE /m/notes?repo=&key=[&project=]
@ ag_h_note_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String key ( __ag_query req `key` )
    : String raw ( __ag_query req `project` )
    : ~ String project ( string_new )
    ?? ( ag_project_norm ( string_data raw ) ) { T pr → { = project pr } F → { ^ ( ag_json_err 400 `bad project` ) } }
    ? ( ag_note_del . w rs ( string_data project ) ( string_data key ) ) {} { ^ ( ag_json_err 404 `no such note` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// The name a person's edits are signed with: their e-mail, `web` locally.
@ __ag_person AgWho w → String {
    ? ( ag_auth_oidc ) { ^ ( string_from ( string_data . . w who email ) ) } {}
    ^ ( string_from `web` )
}

// PUT /m/rules?repo= {key, project?, rule} — a person promotes a note to a
// rule (rule true) or makes it a plain note again.
@ ag_h_rule_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : String who ( __ag_person w )
    ^ ( __ag_res_http ( ag_op_call . w rs ( ag_caller_as ( string_data who ) ) `note_promote` b now ) )
}

// GET /m/skills — the organisation's skills, with bodies, switched off
// ones too. Not about a repository: every one of them shares these.
@ ag_h_skills HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ( Vec AgSkill ) v ( ag_skills . w st T T )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgSkill] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgSkill] v k ) { T x → { ( json_arr_push arr ( _ag_skill_json x T ) ) } F _ → {} }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `skills` arr )
    ^ ( __ag_json_ok out )
}

// PUT /m/skills/:name {description?, body?, enabled?} — make or change a
// skill (what is left out stays as it was), or switch it on or off.
@ ag_h_skill_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : String name ( __ag_param req p `name` )
    ( json_obj_set b `name` ( json_str_lit ( string_data name ) ) )
    : String who ( __ag_person w )
    ^ ( __ag_res_http ( ag_op_call . w st ( ag_caller_as ( string_data who ) ) `skill_set` b now ) )
}

@ ag_h_skill_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String name ( __ag_param req p `name` )
    ? ( ag_skill_del . w st ( string_data name ) ) {} { ^ ( ag_json_err 404 `no such skill` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// Where feedback is kept: the service's file when signed in, the one
// local file otherwise.
@ __ag_feedback_st AgWho w → AgStore {
    ? ( ag_auth_oidc ) { ^ ( ag_feedback_store ) } {}
    ^ @ AgStore { ( string_from ( string_data . . w st path ) ) . . w st ok @ ?Database { F } }
}

// GET /m/feedback?status=&kind=&limit=&offset=&order= — the owner
// organisation's people read everyone's; everybody else their own
// organisation's. Newest first (`order=oldest`: oldest first).
@ ag_h_feedback HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : b triage ( __ag_is_owner_member w )
    : String org ( string_from ? triage `` ( string_data . . w who org ) )
    // '' would mean every organisation's: only the owner's people read that.
    ? & ! triage == ( string_len org ) 0 { ^ ( ag_json_err 403 `no organisation to show the feedback of` ) } {}
    : String status ( __ag_query req `status` )
    : String kind ( __ag_query req `kind` )
    : i limit ( __ag_query_int req `limit` 50 1 500 )
    : i offset ( __ag_query_int req `offset` 0 0 1000000000 )
    : String order ( __ag_query req `order` )
    : b oldest != 0 ( nurl_str_eq ( string_data order ) `oldest` )
    : AgStore fs ( __ag_feedback_st w )
    : ( Vec AgFeedback ) v ( ag_feedback_list fs ( string_data org ) ( string_data status ) ( string_data kind ) oldest limit offset )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgFeedback] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgFeedback] v k ) { T f → { ( json_arr_push arr ( _ag_feedback_json f ) ) } F _ → {} }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `feedback` arr )
    ( json_obj_set out `total` ( json_int ( ag_feedback_count fs ( string_data org ) ( string_data status ) ( string_data kind ) ) ) )
    ( json_obj_set out `can_triage` ( json_bool triage ) )
    ^ ( __ag_json_ok out )
}

// POST /m/feedback {kind, title, body} — from a person, not an agent.
@ ag_h_feedback_new HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : String person ( __ag_person w )
    : ~ String fdb ( string_new )
    ? ( ag_auth_oidc ) {
        : AgStore fs ( ag_feedback_store )
        = fdb ( string_from ( string_data . fs path ) )
    } {}
    : AgCaller c @ AgCaller { T ( string_new ) ( string_from ( string_data . . w who org ) ) ( string_new ) person ( string_new ) fdb }
    ^ ( __ag_res_http ( ag_op_call . w st c `feedback` b now ) )
}

// PUT /m/feedback/:id {status, reply} — the owner organisation answers.
// The agent that sent it hears of it in its own repository's mail.
@ ag_h_feedback_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( __ag_is_owner_member w ) {} { ^ ( ag_json_err 403 `the organisation that runs this agora answers feedback` ) }
    : i id ( nurl_str_to_int ( string_data ( __ag_param req p `id` ) ) )
    : AgStore fs ( __ag_feedback_st w )
    ?? ( ag_feedback_get fs id ) {
        F _ → { ^ ( ag_json_err 404 `no such feedback` ) }
        T f → {
            : Json b ( __ag_body_obj req )
            : ~ String status ( _ag_arg_str b `status` )
            ? == ( string_len status ) 0 { = status ( string_clone . f status ) } {}
            : ~ String reply ( string_clone . f reply )
            ?? ( json_obj_get b `reply` ) { T _ → { = reply ( _ag_arg_str b `reply` ) } F _ → {} }
            ? > ( string_len reply ) AG_BODY_MAX { ^ ( ag_json_err 400 `reply: at most 16 KiB` ) } {}
            ? ( ag_feedback_set fs id ( string_data status ) ( string_data reply ) now ) {} {
                ^ ( ag_json_err 400 `status must be new, accepted, planned, done or declined` )
            }
            : b changed | ! ( string_eq status . f status ) ! ( string_eq reply . f reply )
            ? changed { ( __ag_feedback_tell f ( string_data status ) ( string_data reply ) now ) } {}
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

// Tell the agent that sent feedback `f` its new standing, in its own
// repository's mail (a person on the web page has no mailbox: nothing).
@ __ag_feedback_tell AgFeedback f s status s reply i now → v {
    ? == ( string_len . f agent ) 0 { ^ v } {}
    : String body ( string_from `your feedback #` )
    ( string_push_int body . f id )
    ( string_push_str body ` (` )
    ( string_push_str body ( string_data . f title ) )
    ( string_push_str body `) is ` )
    ( string_push_str body status )
    ? > ( nurl_str_len reply ) 0 {
        ( string_push_str body `\nreply: ` )
        ( string_push_str body reply )
    } {}
    : String mbox ( ag_mailbox ( string_data . f agent ) )
    ? ( ag_auth_oidc ) {
        ? | == ( string_len . f org ) 0 == ( string_len . f repo ) 0 { ^ v } {}
        : AgStore rs ( ag_repo_store ( string_data . f org ) ( string_data . f repo ) )
        ? . rs ok { ( ag_post rs ( string_data mbox ) `agora` ( string_data body ) 0 now ) } {}
    } { ( ag_post ( ag_store ) ( string_data mbox ) `agora` ( string_data body ) 0 now ) }
}

@ ag_h_feedback_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( __ag_is_owner_member w ) {} { ^ ( ag_json_err 403 `the organisation that runs this agora answers feedback` ) }
    : i id ( nurl_str_to_int ( string_data ( __ag_param req p `id` ) ) )
    : AgStore fs ( __ag_feedback_st w )
    ? ( ag_feedback_del fs id ) {} { ^ ( ag_json_err 404 `no such feedback` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// A cutoff `days` ago from `now`; 0 days = none (that kind is left alone).
@ __ag_days_ago Json b s key i now → i {
    : i d ( _ag_arg_int b key 0 )
    ? | <= d 0 > d 36500 { ^ 0 } {}
    ^ - now * d 86400
}

// POST /m/cleanup?repo= {agents_days, tasks_days, messages_days,
// channels_days, dry_run} — clear out of the repository's agora the agents
// not seen for so many days, the tasks finished that long ago, older
// messages and channels nobody has posted to (manage.nu's ag_cleanup); a
// kind left out or 0 is left alone. `dry_run` (the default) only counts.
@ ag_h_cleanup HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who_in req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : Json b ( __ag_body_obj req )
    : b dry ( _ag_arg_bool b `dry_run` T )
    : AgCleanup r ( ag_cleanup . w rs ( __ag_days_ago b `agents_days` now ) ( __ag_days_ago b `tasks_days` now )
    ( __ag_days_ago b `messages_days` now ) ( __ag_days_ago b `channels_days` now ) dry now )
    ? < . r agents 0 { ^ ( ag_json_err 500 `the cleanup failed; nothing was changed` ) } {}
    : Json o ( json_obj_new )
    ( json_obj_set o `agents` ( json_int . r agents ) )
    ( json_obj_set o `tasks` ( json_int . r tasks ) )
    ( json_obj_set o `messages` ( json_int . r messages ) )
    ( json_obj_set o `channels` ( json_int . r channels ) )
    ( json_obj_set o `dry_run` ( json_bool dry ) )
    ^ ( __ag_json_ok o )
}

// GET /m/users — admins only: it names everyone who has signed in.
@ ag_h_users HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( ag_principal_is_admin . w who ) {} { ^ ( ag_json_err 403 `administrators only` ) }
    : ( Vec AgUser ) v ( ag_users . w st )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgUser] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgUser] v k ) {
            T u → {
                : Json o ( json_obj_new )
                ( json_obj_set o `subject` ( json_str_lit ( string_data . u sub ) ) )
                ( json_obj_set o `email` ( json_str_lit ( string_data . u email ) ) )
                ( json_obj_set o `name` ( json_str_lit ( string_data . u name ) ) )
                ( json_obj_set o `role` ( json_str_lit ( string_data . u role ) ) )
                ( json_obj_set o `created` ( json_int . u created ) )
                ( json_obj_set o `seen` ( json_int . u seen ) )
                ( json_obj_set o `you` ( json_bool != 0 ( nurl_str_eq ( string_data . u sub ) ( string_data . . w who sub ) ) ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `users` arr )
    ^ ( __ag_json_ok out )
}

// PUT /m/users/:sub {role}  ·  DELETE /m/users/:sub
@ ag_h_user_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( ag_principal_is_admin . w who ) {} { ^ ( ag_json_err 403 `administrators only` ) }
    : String sub ( __ag_param req p `sub` )
    : Json b ( __ag_body_obj req )
    : String role ( _ag_arg_str b `role` )
    : b known | != 0 ( nurl_str_eq ( string_data role ) AG_ROLE_ADMIN ) != 0 ( nurl_str_eq ( string_data role ) AG_ROLE_MEMBER )
    ? known {} { ^ ( ag_json_err 400 `role must be admin or member` ) }
    ? ( ag_user_set_role . w st ( string_data sub ) ( string_data role ) ) {} {
        ^ ( ag_json_err 409 `no such person, or that would leave the organisation without an administrator` )
    }
    ( ag_auth_forget_all )
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

@ ag_h_user_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( ag_principal_is_admin . w who ) {} { ^ ( ag_json_err 403 `administrators only` ) }
    : String sub ( __ag_param req p `sub` )
    ? ( ag_user_delete . w st ( string_data sub ) ) {} {
        ^ ( ag_json_err 409 `no such person, or that would leave the organisation without an administrator` )
    }
    ( ag_auth_forget_all )
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// GET /m/tenants · PUT /m/tenants/:tid {state} — administrators of the
// owner organisation decide which other organisations may sign in.
@ ag_h_tenants HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( __ag_is_owner_admin w ) {} { ^ ( ag_json_err 403 `administrators of the owner organisation only` ) }
    : Json out ( json_obj_new )
    ( json_obj_set out `owner` ( __ag_jstr ( ag_auth_owner ) ) )
    ( json_obj_set out `tenants` ( ag_tenants_json ) )
    ^ ( __ag_json_ok out )
}

@ ag_h_tenant_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    ? ( __ag_is_owner_admin w ) {} { ^ ( ag_json_err 403 `administrators of the owner organisation only` ) }
    : String tid ( _ag_lower ( string_data ( __ag_param req p `tid` ) ) )
    : Json b ( __ag_body_obj req )
    : String state ( _ag_arg_str b `state` )
    : String by ( string_from ( string_data . . w who email ) )
    ? ( ag_tenant_set_state ( string_data tid ) ( string_data state ) ( string_data by ) now ) {} {
        ^ ( ag_json_err 400 `state must be pending, allowed or blocked` )
    }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}
