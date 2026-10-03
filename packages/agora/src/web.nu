// agora/src/web.nu — the signed-in service's HTTP surface.
//
// Three things live here, all of them about a PERSON rather than an
// agent:
//
//   resolution  An HTTP request with an OIDC bearer token → the person
//               (auth.nu) → their organisation's store → the agent they
//               act as. Which agent, in order: the `X-Agora-Agent`
//               header (a fixed identity per configured connection);
//               the agent `join` bound to this MCP session; the
//               person's default agent (named after their e-mail). A
//               name is created on first use and is then the person's;
//               somebody else's name is refused, never borrowed.
//   join        In signed-in mode the token is the credential, so `join`
//               hands out no token: it chooses the agent for this MCP
//               session (or, over REST, claims the name for the
//               X-Agora-Agent header).
//   /m/…        What the web page does: look at the organisation's
//               agora, edit and delete. A member may change what their
//               own agents wrote and every note (the notebook is shared
//               by design); an admin may change anything of the
//               organisation's. Direct mail is visible only to the
//               people whose agents sent or received it — whatever
//               their role.
//
// In local mode the web page works too, as the one local administrator
// (whoever can reach the port is whoever can open the file).

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

: i AG_SESSION_KEEP_S 2592000  // an MCP session unused for 30 days is forgotten

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

// The origin absolute URLs are built on: configured, else the request's.
@ ag_base_url HttpRequest req → String {
    : s pu ( ag_auth_public_url )
    ? > ( nurl_str_len pu ) 0 { ^ ( string_from pu ) } {}
    ^ ( mcp_auth_base_url req `` )
}

// ── Who is asking ────────────────────────────────────────────────────

: AgWho {
    i status  // 0 = signed in; else the HTTP status to answer with
    AgPrincipal who
    AgStore st  // the organisation's store (local: the one file)
}

// The person behind a request and their organisation's store. Local
// mode: the one local administrator and the one file.
@ ag_who HttpRequest req i now → AgWho {
    ? ( ag_auth_oidc ) {} { ^ @ AgWho { 0 ( ag_principal_local ) ( ag_store ) } }
    : ~ String tok ( string_new )
    ?? ( mcp_auth_bearer_token req ) { T t → { = tok t } F _ → {} }
    : AgPrincipal p ( ag_auth_principal ( string_data tok ) now )
    ? . p authed {} { ^ @ AgWho { 401 p @ AgStore { ( string_new ) F } } }
    : AgStore st ( ag_org_store ( string_data . p org ) )
    ? . st ok {} { ^ @ AgWho { 500 p st } }
    ^ @ AgWho { 0 p st }
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
    ^ ( ag_json_err . w status `the organisation's database could not be opened` )
}

// ── Acting as an agent ───────────────────────────────────────────────

// Make sure `name` is an agent of `p`: created (theirs) on first use,
// accepted when it is already theirs. 0, or the HTTP status refusing it
// (400 a bad name, 403 somebody else's, 500 the store failed).
@ ag_agent_ensure AgStore st s sub s name i now → i {
    ? ( ag_name_ok name ) {} { ^ 400 }
    ?? ( ag_agent_owner st name ) {
        T o → {
            ? != 0 ( nurl_str_eq ( string_data o ) sub ) {
                ( ag_agent_touch st name now )
                ^ 0
            } {}
            ^ 403
        }
        F → {}
    }
    : String tok ( rand_hex_str 32 )
    : String h ( ag_token_hash ( string_data tok ) )
    ? ( ag_agent_create_from st name `` ( string_data h ) `` now ) {
        ? ( ag_agent_set_owner st name sub ) { ^ 0 } {}
        ^ 500
    } {}
    // Lost a race for the name: whoever won owns it now.
    ?? ( ag_agent_owner st name ) {
        T o2 → { ? != 0 ( nurl_str_eq ( string_data o2 ) sub ) { ^ 0 } {} ^ 403 }
        F → { ^ 500 }
    }
}

@ ag_agent_refusal i code s name → AgRes {
    : String m ( string_new )
    ? == code 400 {
        ( string_push_str m `agent name must be ` )
        ( string_push_str m AG_NAME_RULE )
        ^ ( _ag_err_s 400 m )
    } {}
    ? == code 403 {
        ( string_push_str m `agent '` )
        ( string_push_str m name )
        ( string_push_str m `' belongs to somebody else in this organisation — join under another name` )
        ^ ( _ag_err_s 403 m )
    } {}
    ^ ( _ag_err 500 `could not record the agent` )
}

// Which agent a request acts as (not yet made sure of): the
// X-Agora-Agent header, the MCP session's joined agent, the default.
@ ag_agent_for HttpRequest req AgStore st AgPrincipal p s session → String {
    : String hdr ( _ag_header req `x-agora-agent` )
    ? > ( string_len hdr ) 0 { ^ ( string_to_lower hdr ) } {}
    ? > ( nurl_str_len session ) 0 {
        : String a ( ag_session_agent st session ( string_data . p sub ) )
        ? > ( string_len a ) 0 { ^ a } {}
    } {}
    ^ ( ag_default_agent st p )
}

// `join` in signed-in mode: choose (and claim) the agent this session
// acts as. No token: the sign-in is the credential.
@ ag_oidc_join AgStore st s sub s session Json args i now → AgRes {
    : String name ( _ag_arg_str args `name` )
    : String about ( _ag_arg_str args `about` )
    ? > ( string_len about ) 1024 { ^ ( _ag_err 400 `about: at most 1024 characters` ) } {}
    : i code ( ag_agent_ensure st sub ( string_data name ) now )
    ? == code 0 {} { ^ ( ag_agent_refusal code ( string_data name ) ) }
    ? > ( string_len about ) 0 { ( ag_agent_set_about st ( string_data name ) ( string_data about ) ) } {}
    : ~ b bound F
    ? > ( nurl_str_len session ) 0 {
        = bound ( ag_session_bind st session sub ( string_data name ) now )
        ( ag_sessions_prune st - now AG_SESSION_KEEP_S )
    } {}
    : Json o ( json_obj_new )
    ( json_obj_set o `agent` ( json_str_lit ( string_data name ) ) )
    ( json_obj_set o `session` ( json_bool bound ) )
    : String t ( string_from `joined as ` )
    ( string_push_str t ( string_data name ) )
    ? bound {
        ( string_push_str t ` — this session acts as ` )
        ( string_push_str t ( string_data name ) )
        ( string_push_str t ` from now on. Call brief.\n` )
    } {
        ( string_push_str t ` — the name is yours; send X-Agora-Agent: ` )
        ( string_push_str t ( string_data name ) )
        ( string_push_str t ` to act as it.\n` )
    }
    ^ ( _ag_ok o t )
}

// Run op `name` for a signed-in person acting as `agent`.
@ ag_oidc_call AgStore st s sub s agent s session s name Json args i now → AgRes {
    ? != 0 ( nurl_str_eq name `join` ) { ^ ( ag_oidc_join st sub session args now ) } {}
    : i kind ( ag_op_auth_kind name )
    ? == kind 1 {
        : i code ( ag_agent_ensure st sub agent now )
        ? == code 0 {} { ^ ( ag_agent_refusal code agent ) }
    } {}
    : AgCaller c @ AgCaller { T ( string_from agent ) }
    : AgRes r ( ag_op_call st c name args now )
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
    : Json md ( mcp_auth_resource_metadata ( string_data resource ) ( ag_auth_issuer ) ( string_data scope ) )
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
    ( json_obj_set o `issuer` ( json_str_lit ( ag_auth_issuer ) ) )
    ( json_obj_set o `client_id` ( json_str_lit ( ag_auth_client_id ) ) )
    ( json_obj_set o `audience` ( json_str_lit ( ag_auth_audience ) ) )
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

// Does `sub` own agent `agent`? (Local mode: the administrator owns all.)
@ __ag_owns ( Vec String ) mine s agent → b {
    : i n ( vec_len [String] mine )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] mine k ) {
            T a → { ? != 0 ( nurl_str_eq ( string_data a ) agent ) { ^ T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// May `w`'s person change something an agent named `author` made?
@ __ag_may_change AgWho w s author → b {
    ? ( ag_principal_is_admin . w who ) { ^ T } {}
    : ( Vec String ) mine ( ag_agents_owned . w st ( string_data . . w who sub ) )
    ^ ( __ag_owns mine author )
}

@ __ag_forbidden → HttpResponse {
    ^ ( ag_json_err 403 `not yours: a member changes what their own agents made (and any note); an admin changes anything of the organisation's` )
}

@ __ag_is_owner_admin AgWho w → b {
    ? ( ag_auth_oidc ) {} { ^ F }
    ? ( ag_principal_is_admin . w who ) {} { ^ F }
    ^ != 0 ( nurl_str_eq ( string_data . . w who org ) ( ag_auth_owner ) )
}

// GET /m/me
@ ag_h_me HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
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
    : ( Vec String ) mine ( ag_agents_owned . w st ( string_data . . w who sub ) )
    : Json arr ( json_arr_new )
    : i n ( vec_len [String] mine )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] mine k ) { T a → { ( json_arr_push arr ( json_str_lit ( string_data a ) ) ) } F _ → {} }
        = k + k 1
    }
    ( json_obj_set o `agents` arr )
    ? ( ag_auth_oidc ) {
        : String dflt ( ag_default_agent . w st . w who )
        ( json_obj_set o `default_agent` ( json_str_lit ( string_data dflt ) ) )
    } {}
    : AgTotals t ( ag_totals . w st )
    : Json tj ( json_obj_new )
    ( json_obj_set tj `agents` ( json_int . t agents ) )
    ( json_obj_set tj `channels` ( json_int . t channels ) )
    ( json_obj_set tj `messages` ( json_int . t messages ) )
    ( json_obj_set tj `tasks_open` ( json_int . t tasks_open ) )
    ( json_obj_set tj `tasks` ( json_int . t tasks ) )
    ( json_obj_set tj `notes` ( json_int . t notes ) )
    ( json_obj_set tj `users` ( json_int . t users ) )
    ( json_obj_set o `totals` tj )
    ( json_obj_set o `version` ( json_str_lit AG_VERSION ) )
    ^ ( __ag_json_ok o )
}

// GET /m/agents — every agent of the organisation, with whose it is.
@ ag_h_agents HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ( Vec AgUser ) users ( ag_users . w st )
    : ( Vec AgAgent ) v ( ag_agents . w st )
    : b admin ( ag_principal_is_admin . w who )
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
                : ~ String owner_email ( string_new )
                : i nu ( vec_len [AgUser] users )
                : ~ i j 0
                ~ < j nu {
                    ?? ( vec_get [AgUser] users j ) {
                        T u → { ? != 0 ( nurl_str_eq ( string_data . u sub ) ( string_data . a owner ) ) { = owner_email ( string_from ( string_data . u email ) ) } {} }
                        F _ → {}
                    }
                    = j + j 1
                }
                ( json_obj_set o `owner` ( json_str_lit ( string_data owner_email ) ) )
                : b mine & > ( string_len . a owner ) 0 != 0 ( nurl_str_eq ( string_data . a owner ) ( string_data . . w who sub ) )
                ( json_obj_set o `mine` ( json_bool mine ) )
                ( json_obj_set o `may_change` ( json_bool | admin mine ) )
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
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String id ( __ag_param req p `id` )
    ? ( __ag_may_change w ( string_data id ) ) {} { ^ ( __ag_forbidden ) }
    : Json b ( __ag_body_obj req )
    : String about ( _ag_arg_str b `about` )
    ? > ( string_len about ) 1024 { ^ ( ag_json_err 400 `about: at most 1024 characters` ) } {}
    ? ( ag_agent_set_about . w st ( string_data id ) ( string_data about ) ) {} { ^ ( ag_json_err 404 `no such agent` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

@ ag_h_agent_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String id ( __ag_param req p `id` )
    ? ( __ag_may_change w ( string_data id ) ) {} { ^ ( __ag_forbidden ) }
    ? ( ag_agent_delete . w st ( string_data id ) now ) {} { ^ ( ag_json_err 404 `no such agent` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// GET /m/channels
@ ag_h_channels HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ( Vec AgChannel ) v ( ag_channels . w st )
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

// DELETE /m/channels?name= — the channel and everything in it. (A query
// parameter: a repository's channel has '/' in its name.)
@ ag_h_channel_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String name ( __ag_query req `name` )
    ? != 0 ( nurl_str_eq ( string_data name ) `public` ) { ^ ( ag_json_err 400 `public cannot be deleted: every agent follows it` ) } {}
    : ~ String by ( string_new )
    : ( Vec AgChannel ) v ( ag_channels . w st )
    : i n ( vec_len [AgChannel] v )
    : ~ b found F
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgChannel] v k ) {
            T c → { ? != 0 ( nurl_str_eq ( string_data . c name ) ( string_data name ) ) { = by ( string_from ( string_data . c created_by ) ) = found T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ? found {} { ^ ( ag_json_err 404 `no such channel` ) }
    ? ( __ag_may_change w ( string_data by ) ) {} { ^ ( __ag_forbidden ) }
    ? ( ag_channel_delete . w st ( string_data name ) ) {} { ^ ( ag_json_err 500 `could not delete the channel` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// GET /m/messages?channel=&q=&before=&limit= — newest first.
@ ag_h_messages HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String channel ( __ag_query req `channel` )
    : String q ( __ag_query req `q` )
    : String bs ( __ag_query req `before` )
    : String ls ( __ag_query req `limit` )
    : i before ( nurl_str_to_int ( string_data bs ) )
    : ~ i limit ( nurl_str_to_int ( string_data ls ) )
    ? | <= limit 0 > limit 500 { = limit 100 } {}
    : b all ! ( ag_auth_oidc )
    : ( Vec AgMsg ) v ( ag_messages_for . w st ( string_data . . w who sub ) all ( string_data channel ) ( string_data q ) before limit )
    : b admin ( ag_principal_is_admin . w who )
    : ( Vec String ) mine ( ag_agents_owned . w st ( string_data . . w who sub ) )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgMsg] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgMsg] v k ) {
            T m → {
                : Json o ( _ag_msg_json m 0 )
                ( json_obj_set o `may_change` ( json_bool | admin ( __ag_owns mine ( string_data . m sender ) ) ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `messages` arr )
    ^ ( __ag_json_ok out )
}

// May `w` see message `m`? Channel posts: yes. Mail: only the people
// whose agents sent or received it (local mode: the administrator).
@ __ag_may_see AgWho w AgMsg m → b {
    ? ( ag_auth_oidc ) {} { ^ T }
    : s ch ( string_data . m channel )
    ? == ( nurl_str_get ch 0 ) 64 {} { ^ T }
    : ( Vec String ) mine ( ag_agents_owned . w st ( string_data . . w who sub ) )
    ? ( __ag_owns mine ( string_data . m sender ) ) { ^ T } {}
    : String to ( string_substr . m channel 1 - ( string_len . m channel ) 1 )
    ^ ( __ag_owns mine ( string_data to ) )
}

// PUT /m/messages/:id {body}  ·  DELETE /m/messages/:id
@ ag_h_message_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_msg_get . w st id ) {
        F _ → { ^ ( ag_json_err 404 `no such message` ) }
        T m → {
            ? ( __ag_may_see w m ) {} { ^ ( ag_json_err 404 `no such message` ) }
            ? ( __ag_may_change w ( string_data . m sender ) ) {} { ^ ( __ag_forbidden ) }
            : Json b ( __ag_body_obj req )
            : String body ( _ag_arg_str b `body` )
            ? == ( string_len body ) 0 { ^ ( ag_json_err 400 `body is empty — delete the message instead` ) } {}
            ? > ( string_len body ) AG_BODY_MAX { ^ ( ag_json_err 400 `body: at most 16 KiB` ) } {}
            ? ( ag_msg_set_body . w st id ( string_data body ) ) {} { ^ ( ag_json_err 500 `could not save the message` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

@ ag_h_message_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_msg_get . w st id ) {
        F _ → { ^ ( ag_json_err 404 `no such message` ) }
        T m → {
            ? ( __ag_may_see w m ) {} { ^ ( ag_json_err 404 `no such message` ) }
            ? ( __ag_may_change w ( string_data . m sender ) ) {} { ^ ( __ag_forbidden ) }
            ? ( ag_msg_delete . w st id ) {} { ^ ( ag_json_err 500 `could not delete the message` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

// GET /m/tasks?status=all|open|done|…
@ ag_h_tasks HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : ~ String which ( __ag_query req `status` )
    ? == ( string_len which ) 0 { = which ( string_from `all` ) } {}
    : ( Vec AgTask ) v ( ag_tasks . w st ( string_data which ) `` `` 500 now )
    : b admin ( ag_principal_is_admin . w who )
    : ( Vec String ) mine ( ag_agents_owned . w st ( string_data . . w who sub ) )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgTask] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgTask] v k ) {
            T t → {
                : Json o ( _ag_task_json t )
                ( json_obj_set o `may_change` ( json_bool | admin ( __ag_owns mine ( string_data . t poster ) ) ) )
                ( json_arr_push arr o )
            }
            F _ → {}
        }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `tasks` arr )
    ^ ( __ag_json_ok out )
}

// PUT /m/tasks/:id {title, body, tags, priority, status}  ·  DELETE
@ ag_h_task_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_task_get . w st id now ) {
        F _ → { ^ ( ag_json_err 404 `no such task` ) }
        T t → {
            ? ( __ag_may_change w ( string_data . t poster ) ) {} { ^ ( __ag_forbidden ) }
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
            ? ( ag_task_edit . w st id ( string_data title ) ( string_data body ) ( string_data tags ) prio ( string_data status ) now ) {} {
                ^ ( ag_json_err 400 `status must be open, claimed, done or cancelled` )
            }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

@ ag_h_task_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String ids ( __ag_param req p `id` )
    : i id ( nurl_str_to_int ( string_data ids ) )
    ?? ( ag_task_get . w st id now ) {
        F _ → { ^ ( ag_json_err 404 `no such task` ) }
        T t → {
            ? ( __ag_may_change w ( string_data . t poster ) ) {} { ^ ( __ag_forbidden ) }
            ? ( ag_task_delete . w st id ) {} { ^ ( ag_json_err 500 `could not delete the task` ) }
            ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
        }
    }
}

// GET /m/notes?project= — with bodies; no project = every note.
@ ag_h_notes HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String raw ( __ag_query req `project` )
    : b all == ( string_len raw ) 0
    : ~ String project ( string_new )
    ? all {} {
        ?? ( ag_project_norm ( string_data raw ) ) { T pr → { = project pr } F → { ^ ( ag_json_err 400 `bad project` ) } }
    }
    : ( Vec AgNote ) v ( ag_notes . w st ( string_data project ) all T )
    : Json arr ( json_arr_new )
    : i n ( vec_len [AgNote] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgNote] v k ) { T x → { ( json_arr_push arr ( _ag_note_json x T ) ) } F _ → {} }
        = k + k 1
    }
    : Json out ( json_obj_new )
    ( json_obj_set out `notes` arr )
    ^ ( __ag_json_ok out )
}

// PUT /m/notes {project, key, body} — the shared notebook: any member.
// The author becomes the person's default agent.
@ ag_h_note_put HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
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
    ? ( ag_auth_oidc ) {
        = author ( ag_default_agent . w st . w who )
        : i code ( ag_agent_ensure . w st ( string_data . . w who sub ) ( string_data author ) now )
        ? == code 0 {} { = author ( string_from `web` ) }
    } {}
    ? ( ag_note_set . w st ( string_data project ) ( string_data key ) ( string_data body ) ( string_data author ) now ) {} {
        ^ ( ag_json_err 500 `could not save the note` )
    }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
}

// DELETE /m/notes?project=&key=
@ ag_h_note_del HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : AgWho w ( ag_who req now )
    ? == . w status 0 {} { ^ ( ag_who_deny w ) }
    : String key ( __ag_query req `key` )
    : String raw ( __ag_query req `project` )
    : ~ String project ( string_new )
    ?? ( ag_project_norm ( string_data raw ) ) { T pr → { = project pr } F → { ^ ( ag_json_err 400 `bad project` ) } }
    ? ( ag_note_del . w st ( string_data project ) ( string_data key ) ) {} { ^ ( ag_json_err 404 `no such note` ) }
    ^ ( __ag_json_ok ( _ag_obj_int `ok` 1 ) )
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
    ( json_obj_set out `owner` ( json_str_lit ( ag_auth_owner ) ) )
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
