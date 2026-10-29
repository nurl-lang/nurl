// agora/src/auth.nu — who is asking, and whose agora they are in.
//
// Two modes, and they are different products:
//
//   local   No sign-in. One SQLite file is the whole agora and whoever
//           can open it is everybody: a bearer token from `join` over
//           HTTP, `--as NAME` over stdio and the CLI. What agora was
//           before this file, and still the default.
//   oidc    A shared, signed-in, multi-tenant service. Every request
//           carries an OIDC access token (or arrives at /mcp without one
//           and is told where to get one); the token's tenant (`tid`)
//           is the ORGANISATION. Its people are <home>/orgs/<org>.db; its
//           agoras are one file per git REPOSITORY,
//           <home>/orgs/<org>/<host+owner+repo>.db, and everybody of the
//           organisation who names that repository meets everybody else
//           who does. Organisation and repository are implicit in the
//           file, so no query carries either and no query can forget
//           one: two organisations (or two repositories) cannot see each
//           other's agents, messages, tasks or notes because they are
//           not in the same database.
//
// Which organisations may sign in at all is a registry of its own,
// <home>/tenants.db: the owner organisation always may; another is
// recorded as `pending` the first time one of its people knocks, and is
// refused until an admin of the owner organisation allows it (or the
// config lists it under `allowed_tenants`). A multi-tenant service that
// provisions a database for whoever knocks fills its disk with
// strangers.
//
// Token verification is the oauth package's (signature against the
// provider's own JWKS, issuer, audience, expiry). The provider owns one
// HTTP client and a key cache and is NOT thread-safe, and agora serves
// from a worker pool, so it lives behind one mutex — and a verified
// token is remembered (by its SHA-256) for at most a minute and never
// past its own expiry, so an agent calling once per turn costs one
// signature check a minute, not one per call.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/sqlite.nu`
$ `deps/oauth/src/oauth.nu`
$ `manage.nu`
$ `stdlib/core/slice.nu`

// ── Configuration file ───────────────────────────────────────────────
//
// <home>/agora.toml (or --config FILE / $AGORA_CONFIG):
//
//     [auth]
//     mode         = "oidc"
//     issuer       = "https://login.microsoftonline.com/organizations/v2.0"
//     client_id    = "<application (client) id>"
//     audience     = "https://agora.example.com/mcp"   # the MCP resource
//     multi_tenant = true
//     owner_tenant = "<tenant id that administers the service>"
//     allowed_tenants = ["<tenant id>", …]               # optional
//
//     [service]
//     addr       = "0.0.0.0:8830"
//     public_url = "https://agora.example.com"           # behind a proxy
//
// A file that exists and does not parse is an error, not an absence:
// silently ignoring a config somebody wrote is how a service comes up
// unauthenticated and nobody can see why.

: AgConfig {
    b loaded
    String cpath
    String cerr
    TomlValue root
}

@ ag_config_load s path → AgConfig {
    ? > ( nurl_str_len path ) 0 {} { ^ @ AgConfig { F ( string_new ) ( string_new ) @ TomlValue { TBool F } } }
    : !String IoErr r ( read_file path )
    ?? r {
        F _ → { ^ @ AgConfig { F ( string_new ) ( string_new ) @ TomlValue { TBool F } } }
        T txt → {
            ?? ( toml_parse ( string_data txt ) ) {
                T v → { ^ @ AgConfig { T ( string_from path ) ( string_new ) v } }
                F e → {
                    : String msg ( string_from path )
                    ( string_push_str msg `: ` )
                    ( string_push_str msg ( toml_err_name e ) )
                    ^ @ AgConfig { F ( string_from path ) msg @ TomlValue { TBool F } }
                }
            }
        }
    }
}

@ ag_config_str AgConfig c s key s dflt → String {
    ? . c loaded {} { ^ ( string_from dflt ) }
    ?? ( toml_get_path . c root key ) {
        T v → { ?? ( toml_as_str v ) { T s2 → { ^ s2 } F _ → {} } }
        F _ → {}
    }
    ^ ( string_from dflt )
}

@ ag_config_bool AgConfig c s key b dflt → b {
    ? . c loaded {} { ^ dflt }
    ?? ( toml_get_path . c root key ) {
        T v → { ?? ( toml_as_bool v ) { T b2 → { ^ b2 } F _ → {} } }
        F _ → {}
    }
    ^ dflt
}

// A string array joined with commas; '' when absent or not all strings.
@ ag_config_list AgConfig c s key → String {
    : String out ( string_new )
    ? . c loaded {} { ^ out }
    ?? ( toml_get_path . c root key ) {
        T v → {
            ?? v {
                TArr items → {
                    : i n ( vec_len [TomlValue] items )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [TomlValue] items k ) {
                            T e → {
                                ?? ( toml_as_str e ) {
                                    T sv → {
                                        ? > ( string_len out ) 0 { ( string_push_char out 44 ) } {}
                                        ( string_push_str out ( string_data sv ) )
                                    }
                                    F _ → { ^ ( string_new ) }
                                }
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                }
                _ → {}
            }
        }
        F _ → {}
    }
    ^ out
}

// ── The principal ────────────────────────────────────────────────────

: AgPrincipal {
    b authed
    String org  // the organisation's key (its tenant id); '' = local
    String sub  // the OIDC subject
    String email
    String name
    String role  // admin | member
    String why  // when not authed: why the credential was refused ('' = none was given)
}

@ ag_principal_anon s why → AgPrincipal {
    ^ @ AgPrincipal { F ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_from why ) }
}

// Local mode: one administrator, who is everybody.
@ ag_principal_local → AgPrincipal {
    ^ @ AgPrincipal { T ( string_new ) ( string_from `local` ) ( string_new ) ( string_from `local` ) ( string_from AG_ROLE_ADMIN ) ( string_new ) }
}

@ ag_principal_clone AgPrincipal p → AgPrincipal {
    ^ @ AgPrincipal {
        . p authed
        ( string_from ( string_data . p org ) )
        ( string_from ( string_data . p sub ) )
        ( string_from ( string_data . p email ) )
        ( string_from ( string_data . p name ) )
        ( string_from ( string_data . p role ) )
        ( string_from ( string_data . p why ) )
    }
}

@ ag_principal_is_admin AgPrincipal p → b {
    ^ & . p authed != 0 ( nurl_str_eq ( string_data . p role ) AG_ROLE_ADMIN )
}

// ── Service-wide state ───────────────────────────────────────────────
//
// Set once at startup (ag_auth_configure) and read by every worker: an
// AgConf in g_ag_conf. The parts requests change — the provider, the
// issuer template it was built from, the token cache, the files known to
// be ready — are an AgGuard in g_ag_guard. Both are Locked globals set at
// start, so every worker reaches them in safe code.

: AgAuthHit {
    String hash  // sha256(token), hex
    i until  // forget it at this time
    AgPrincipal who
}

// What the service was configured with: written at start, read by every
// request.
: AgConf {
    b oidc
    b multi
    String home
    String issuer
    String client_id
    String audience
    String owner  // the owner tenant, lowercase
    String allowed  // comma-separated tenant ids, lowercase ('' = only decisions in the registry)
    String public_url
    String webroot  // the web page's directory ('' = none)
}

// What requests change: the provider, the verdict cache, the files known
// to be ready.
: AgGuard {
    String iss_tmpl  // the provider's `{tenantid}` issuer template
    ? OidcProvider prov  // one share of the provider; F = not discovered
    ( Vec AgAuthHit ) hits
    ( Vec String ) ready  // files whose schema is in place
}

@ __ag_conf_blank → ( Locked AgConf ) {
    ^ ( locked_new [AgConf] @ AgConf {
        F F ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new )
    } )
}

@ __ag_guard_blank → ( Locked AgGuard ) {
    ^ ( locked_new [AgGuard] @ AgGuard { ( string_new ) @ ?OidcProvider { F } ( vec_new [AgAuthHit] ) ( vec_new [String] ) } )
}

: ( Locked AgConf ) g_ag_conf ( __ag_conf_blank )
: ( Locked AgGuard ) g_ag_guard ( __ag_guard_blank )

: i AG_AUTH_CACHE_S 60
: i AG_AUTH_CACHE_MAX 512

@ __ag_set String dst s v → v {
    ( string_clear dst )
    ( string_push_str dst v )
}

@ _ag_lower s raw → String {
    : ( Slice u ) raw_v ( slice_of_str raw )
    : String out ( string_new )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte raw_v k )
        ? & >= c 65 <= c 90 { ( string_push_char out + c 32 ) } { ( string_push_char out c ) }
        = k + k 1
    }
    ^ out
}

// The directory everything of a signed-in service lives in.
@ ag_auth_set_home s home → v {
    : ~ AgConf c ( locked_take [AgConf] g_ag_conf )
    ( __ag_set . c home home )
    ( locked_restore [AgConf] g_ag_conf c )
}

@ ag_auth_set_webroot s dir → v {
    : ~ AgConf c ( locked_take [AgConf] g_ag_conf )
    ( __ag_set . c webroot dir )
    ( locked_restore [AgConf] g_ag_conf c )
}

// Switch the signed-in mode on (or off). `audience` '' = api://<client id>.
@ ag_auth_configure b on b multi s issuer s client_id s audience s owner s allowed s public_url → v {
    : ( Slice u ) public_url_v ( slice_of_str public_url )
    : String ow ( _ag_lower owner )
    : String al ( _ag_lower allowed )
    // No trailing '/': paths are appended to it.
    : ~ i pn ( nurl_str_len public_url )
    ~ & > pn 0 == ( slice_byte public_url_v - pn 1 ) 47 { = pn - pn 1 }
    : String pu ( string_substr ( string_from public_url ) 0 pn )
    : ~ AgConf c ( locked_take [AgConf] g_ag_conf )
    = . c oidc on
    = . c multi multi
    ( __ag_set . c issuer issuer )
    ( __ag_set . c client_id client_id )
    ? > ( nurl_str_len audience ) 0 { ( __ag_set . c audience audience ) } {
        ( __ag_set . c audience `api://` )
        ( string_push_str . c audience client_id )
    }
    ( __ag_set . c owner ( string_data ow ) )
    ( __ag_set . c allowed ( string_data al ) )
    ( __ag_set . c public_url ( string_data pu ) )
    ( locked_restore [AgConf] g_ag_conf c )
    : ~ AgGuard g ( locked_take [AgGuard] g_ag_guard )
    = . g prov @ ?OidcProvider { F }
    ( string_clear . g iss_tmpl )
    ( vec_clear [AgAuthHit] . g hits )
    ( locked_restore [AgGuard] g_ag_guard g )
}

// Read [auth] and [service].public_url from `cfg`, the environment
// overriding the file where it says something. T when signed-in mode is
// on; F with `why` set when it was asked for and cannot be (no issuer,
// no client id).
@ ag_auth_apply AgConfig cfg String why → b {
    : ~ String mode ( ag_config_str cfg `auth.mode` `local` )
    ?? ( env_get `AGORA_AUTH_MODE` ) { T v → { = mode v } F → {} }
    : b want != 0 ( nurl_str_eq ( string_data mode ) `oidc` )
    : ~ String iss ( ag_config_str cfg `auth.issuer` `` )
    ?? ( env_get `AGORA_OIDC_ISSUER` ) { T v → { = iss v } F → {} }
    : ~ String cid ( ag_config_str cfg `auth.client_id` `` )
    ?? ( env_get `AGORA_OIDC_CLIENT_ID` ) { T v → { = cid v } F → {} }
    : ~ String aud ( ag_config_str cfg `auth.audience` `` )
    ?? ( env_get `AGORA_OIDC_AUDIENCE` ) { T v → { = aud v } F → {} }
    : ~ String owner ( ag_config_str cfg `auth.owner_tenant` `` )
    ?? ( env_get `AGORA_OIDC_OWNER_TENANT` ) { T v → { = owner v } F → {} }
    : ~ String allowed ( ag_config_list cfg `auth.allowed_tenants` )
    ?? ( env_get `AGORA_OIDC_ALLOWED_TENANTS` ) { T v → { = allowed v } F → {} }
    : b multi ( ag_config_bool cfg `auth.multi_tenant` T )
    : ~ String pub_url ( ag_config_str cfg `service.public_url` `` )
    ?? ( env_get `AGORA_PUBLIC_URL` ) { T v → { = pub_url v } F → {} }
    ? want {} {
        ( ag_auth_configure F F `` `` `` `` `` ( string_data pub_url ) )
        ^ F
    }
    ? & > ( string_len iss ) 0 > ( string_len cid ) 0 {} {
        ( __ag_set why `auth.mode = "oidc" needs auth.issuer and auth.client_id` )
        ^ F
    }
    ( ag_auth_configure T multi ( string_data iss ) ( string_data cid ) ( string_data aud )
    ( string_data owner ) ( string_data allowed ) ( string_data pub_url ) )
    ( ag_tenants_seed ( string_data allowed ) ( now_seconds ) )
    ^ T
}

@ ag_auth_oidc → b {
    : AgConf c ( locked_take [AgConf] g_ag_conf )
    : b on . c oidc
    ( locked_restore [AgConf] g_ag_conf c )
    ^ on
}

@ ag_auth_multi → b {
    : AgConf c ( locked_take [AgConf] g_ag_conf )
    : b on . c multi
    ( locked_restore [AgConf] g_ag_conf c )
    ^ on
}

// One configured string, copied: 0 home, 1 webroot, 2 issuer, 3 client
// id, 4 audience, 5 owner, 6 public url.
@ __ag_conf_str i which → String {
    : AgConf c ( locked_take [AgConf] g_ag_conf )
    : String out ( string_from ( string_data
    ? == which 0 . c home ? == which 1 . c webroot ? == which 2 . c issuer
    ? == which 3 . c client_id ? == which 4 . c audience ? == which 5 . c owner . c public_url ) )
    ( locked_restore [AgConf] g_ag_conf c )
    ^ out
}

@ ag_auth_home → String { ^ ( __ag_conf_str 0 ) }

@ ag_auth_webroot → String { ^ ( __ag_conf_str 1 ) }

@ ag_auth_issuer → String { ^ ( __ag_conf_str 2 ) }

@ ag_auth_client_id → String { ^ ( __ag_conf_str 3 ) }

@ ag_auth_audience → String { ^ ( __ag_conf_str 4 ) }

@ ag_auth_owner → String { ^ ( __ag_conf_str 5 ) }

@ ag_auth_public_url → String { ^ ( __ag_conf_str 6 ) }

// The OAuth scope a client asks for: <audience>/access_as_user.
@ ag_auth_scope → String {
    : String s ( ag_auth_audience )
    ( string_push_str s `/access_as_user` )
    ^ s
}

// ── Organisations: their files ───────────────────────────────────────

// A tenant id is a GUID and passes through (lowercased). Anything else
// (a provider without `tid`, keyed on its issuer) becomes a digest, which
// cannot contain a path separator, a dot-dot or a NUL by construction.
@ ag_org_key s raw → String {
    : ( Slice u ) raw_v ( slice_of_str raw )
    : i n ( nurl_str_len raw )
    : ~ b plain & > n 0 <= n 64
    : ~ i k 0
    ~ & plain < k n {
        : i c ( slice_byte raw_v k )
        ? | | | & >= c 48 <= c 57 & >= c 97 <= c 122 & >= c 65 <= c 90 == c 45 {} { = plain F }
        = k + k 1
    }
    ? plain { ^ ( _ag_lower raw ) } {}
    : ( Vec u ) msg ( vec_new [u] )
    ( bytes_extend_str msg raw )
    : String hex ( bytes_to_hex ( sha256_pure msg ) )
    : String out ( string_substr hex 0 32 )
    ^ out
}

@ ag_org_path s org → String {
    : String home ( ag_auth_home )
    : String dir ( path_join ( string_data home ) `orgs` )
    : String f ( string_from org )
    ( string_push_str f `.db` )
    : String p ( path_join ( string_data dir ) ( string_data f ) )
    ^ p
}

// The directory of an organisation's repository files.
@ ag_org_repo_dir s org → String {
    : String home ( ag_auth_home )
    : String dir ( path_join ( string_data home ) `orgs` )
    : String p ( path_join ( string_data dir ) org )
    ^ p
}

// `repo` is a normalised repository key (api.nu's ag_project_norm: a-z
// 0-9 . _ - and '/', no '.' or '..' segment): its file swaps each '/'
// for '+', which the key cannot contain, so the name is the key, read
// back by swapping again.
@ ag_repo_path s org s repo → String {
    : ( Slice u ) repo_v ( slice_of_str repo )
    : String f ( string_new )
    : i n ( nurl_str_len repo )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte repo_v k )
        ( string_push_char f ? == c 47 43 c )
        = k + k 1
    }
    ( string_push_str f `.db` )
    : String dir ( ag_org_repo_dir org )
    : String p ( path_join ( string_data dir ) ( string_data f ) )
    ^ p
}

// Is `path` among the files whose schema this process made sure of?
@ __ag_ready s path → b {
    : ~ b ready F
    : AgGuard g ( locked_take [AgGuard] g_ag_guard )
    : i n ( vec_len [String] . g ready )
    : ~ i k 0
    ~ & ! ready < k n {
        ?? ( vec_get [String] . g ready k ) {
            T p → { = ready != 0 ( nurl_str_eq ( string_data p ) path ) }
            F _ → {}
        }
        = k + k 1
    }
    ( locked_restore [AgGuard] g_ag_guard g )
    ^ ready
}

@ __ag_mark_ready s path → v {
    : AgGuard g ( locked_take [AgGuard] g_ag_guard )
    ( vec_push [String] . g ready ( string_from path ) )
    ( locked_restore [AgGuard] g_ag_guard g )
}

// The organisation's file of people, its schema made sure of once per
// process. Opening happens outside the lock: it is idempotent (CREATE …
// IF NOT EXISTS under WAL and a busy timeout), and a first request of
// one organisation must not hold up everyone else's.
@ ag_org_store s org → AgStore {
    : String path ( ag_org_path org )
    ? ( __ag_ready ( string_data path ) ) { ^ @ AgStore { path T @ ?Database { F } } } {}
    : AgStore st ( ag_orgdb_open ( string_data path ) )
    ? . st ok { ( __ag_mark_ready ( string_data path ) ) } {}
    ^ st
}

// A repository's agora within an organisation (made on first use).
@ ag_repo_store s org s repo → AgStore {
    : String path ( ag_repo_path org repo )
    ? ( __ag_ready ( string_data path ) ) { ^ @ AgStore { path T @ ?Database { F } } } {}
    : AgStore st ( ag_store_open ( string_data path ) )
    ? . st ok { ( __ag_mark_ready ( string_data path ) ) } {}
    ^ st
}

// The service's one file of feedback, <home>/feedback.db: what every
// organisation's agents and people tell the operators about agora
// itself. Made on first use, its schema made sure of once per process.
@ ag_feedback_store → AgStore {
    : String home ( ag_auth_home )
    : String path ( path_join ( string_data home ) `feedback.db` )
    ? ( __ag_ready ( string_data path ) ) { ^ @ AgStore { path T @ ?Database { F } } } {}
    : AgStore st ( ag_feedback_db_open ( string_data path ) )
    ? . st ok { ( __ag_mark_ready ( string_data path ) ) } {}
    ^ st
}

// The repositories an organisation has an agora for, sorted.
@ ag_org_repos s org → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String dir ( ag_org_repo_dir org )
    ?? ( dir_list ( string_data dir ) ) {
        F _ → {}
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T f → {
                        : i fl ( string_len f )
                        ? & > fl 3 ( string_ends_with f `.db` ) {
                            : String r ( string_new )
                            : ~ i j 0
                            ~ < j - fl 3 {
                                : i c ( string_get f j )
                                ( string_push_char r ? == c 43 47 c )
                                = j + j 1
                            }
                            // Sorted as they come: an organisation has few.
                            : ~ i m ( vec_len [String] out )
                            : ~ i at 0
                            ~ < at m {
                                ?? ( vec_get [String] out at ) {
                                    T x → { ? > ( nurl_str_cmp ( string_data x ) ( string_data r ) ) 0 { = m at } { = at + at 1 } }
                                    F _ → { = at + at 1 }
                                }
                            }
                            ( vec_insert [String] out at r )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
    }
    ^ out
}

// ── Organisations: who may sign in ───────────────────────────────────

: s AG_TENANT_PENDING `pending`
: s AG_TENANT_ALLOWED `allowed`
: s AG_TENANT_BLOCKED `blocked`

@ __ag_tenants_open → !Database SqliteErr {
    : String home ( ag_auth_home )
    ?? ( dir_create_all ( string_data home ) ) { T _ → {} F _ → {} }
    : String path ( path_join ( string_data home ) `tenants.db` )
    ?? ( sqlite_open ( string_data path ) ) {
        F e → { ^ @ !Database SqliteErr { F e } }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS tenants (tid TEXT PRIMARY KEY, state TEXT NOT NULL DEFAULT 'pending', label TEXT NOT NULL DEFAULT '', first_seen INTEGER NOT NULL DEFAULT 0, decided_at INTEGER NOT NULL DEFAULT 0, decided_by TEXT NOT NULL DEFAULT '')` ) {
                T _ → {}
                F _ → { ^ @ !Database SqliteErr { F # SqliteErr SqliteMisuse } }
            }
            ^ @ !Database SqliteErr { T db }
        }
    }
}

@ __ag_tenant_state_on Database db s tid → String {
    : ~ String st ( string_new )
    ?? ( sqlite_prepare db `SELECT state FROM tenants WHERE tid = ?1` ) {
        F _ → {}
        T q → {
            ( _ag_bind_s q 1 tid )
            ? ( _ag_row q ) { = st ( sqlite_column_text q 0 ) } {}
        }
    }
    ^ st
}

// Is a sign-in from `tid` admitted? The owner organisation always is —
// locking it out would leave nobody who could let anyone in. Any other
// is a recorded decision; one never seen before is recorded as pending
// (with `label`, e.g. the e-mail of who knocked) and refused.
@ ag_tenant_admitted s tid s label i now → b {
    ? > ( nurl_str_len tid ) 0 {} { ^ F }
    : String owner ( ag_auth_owner )
    ? != 0 ( nurl_str_eq tid ( string_data owner ) ) { ^ T } {}
    : ~ b ok F
    ?? ( __ag_tenants_open ) {
        F _ → {}
        T db → {
            : String st ( __ag_tenant_state_on db tid )
            ? == ( string_len st ) 0 {
                ?? ( sqlite_prepare db `INSERT OR IGNORE INTO tenants (tid, state, label, first_seen) VALUES (?1, 'pending', ?2, ?3)` ) {
                    F _ → {}
                    T q → {
                        ( _ag_bind_s q 1 tid )
                        ( _ag_bind_s q 2 label )
                        ( _ag_bind_i q 3 now )
                        ( _ag_run q )
                    }
                }
            } {
                = ok != 0 ( nurl_str_eq ( string_data st ) AG_TENANT_ALLOWED )
            }
        }
    }
    ^ ok
}

@ ag_tenant_set_state s tid s state s by i now → b {
    : b known | | != 0 ( nurl_str_eq state AG_TENANT_PENDING ) != 0 ( nurl_str_eq state AG_TENANT_ALLOWED )
    != 0 ( nurl_str_eq state AG_TENANT_BLOCKED )
    ? known {} { ^ F }
    : ~ b ok F
    ?? ( __ag_tenants_open ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `INSERT INTO tenants (tid, state, first_seen, decided_at, decided_by) VALUES (?1, ?2, ?3, ?3, ?4) ON CONFLICT(tid) DO UPDATE SET state = excluded.state, decided_at = excluded.decided_at, decided_by = excluded.decided_by` ) {
                F _ → {}
                T q → {
                    ( _ag_bind_s q 1 tid )
                    ( _ag_bind_s q 2 state )
                    ( _ag_bind_i q 3 now )
                    ( _ag_bind_s q 4 by )
                    = ok ( _ag_run q )
                }
            }
        }
    }
    // A decision takes effect now, not when cached verdicts run out.
    ( ag_auth_forget_all )
    ^ ok
}

@ ag_tenants_json → Json {
    : Json arr ( json_arr_new )
    ?? ( __ag_tenants_open ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT tid, state, label, first_seen, decided_at, decided_by FROM tenants ORDER BY first_seen` ) {
                F _ → {}
                T q → {
                    ~ ( _ag_row q ) {
                        : Json o ( json_obj_new )
                        : String tid ( sqlite_column_text q 0 )
                        : String st ( sqlite_column_text q 1 )
                        : String lb ( sqlite_column_text q 2 )
                        : String by ( sqlite_column_text q 5 )
                        ( json_obj_set o `tenant` ( json_str_lit ( string_data tid ) ) )
                        ( json_obj_set o `state` ( json_str_lit ( string_data st ) ) )
                        ( json_obj_set o `label` ( json_str_lit ( string_data lb ) ) )
                        ( json_obj_set o `first_seen` ( json_int ( sqlite_column_int q 3 ) ) )
                        ( json_obj_set o `decided_at` ( json_int ( sqlite_column_int q 4 ) ) )
                        ( json_obj_set o `decided_by` ( json_str_lit ( string_data by ) ) )
                        ( json_arr_push arr o )
                    }
                }
            }
        }
    }
    ^ arr
}

// The configured list only ever ADDS: a deployment admits tenants
// without the web page, and a decision made on the page is never undone
// by a restart.
@ ag_tenants_seed s csv i now → v {
    ? > ( nurl_str_len csv ) 0 {} { ^ }
    : String list ( _ag_lower csv )
    : ( Vec String ) parts ( string_split list `,` )
    : i n ( vec_len [String] parts )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] parts k ) {
            T t → {
                : String tt ( string_trim t )
                ? > ( string_len tt ) 0 { ( ag_tenant_set_state ( string_data tt ) AG_TENANT_ALLOWED `config` now ) } {}
            }
            F _ → {}
        }
        = k + k 1
    }
}

// ── Verifying a token ────────────────────────────────────────────────

@ __ag_token_hash s token → String {
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_str raw token )
    : String hex ( bytes_to_hex ( sha256_pure raw ) )
    ^ hex
}

// A remembered verdict for this token, if one is still good.
@ __ag_cache_get String h i now → ?AgPrincipal {
    : AgGuard a ( locked_take [AgGuard] g_ag_guard )
    : ~ ? AgPrincipal out @ ?AgPrincipal { F }
    : i n ( vec_len [AgAuthHit] . a hits )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [AgAuthHit] . a hits k ) {
            T e → {
                ? & > . e until now != 0 ( nurl_str_eq ( string_data . e hash ) ( string_data h ) ) {
                    = out @ ?AgPrincipal { T ( ag_principal_clone . e who ) }
                    = k n
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( locked_restore [AgGuard] g_ag_guard a )
    ^ out
}

@ __ag_cache_put String h i until AgPrincipal p → v {
    : AgGuard a ( locked_take [AgGuard] g_ag_guard )
    // Full: start over. Every entry is at most a minute old, so the cost
    // is one more signature check per live token, once.
    ? >= ( vec_len [AgAuthHit] . a hits ) AG_AUTH_CACHE_MAX { ( vec_clear [AgAuthHit] . a hits ) } {}
    ( vec_push [AgAuthHit] . a hits @ AgAuthHit { ( string_from ( string_data h ) ) until ( ag_principal_clone p ) } )
    ( locked_restore [AgGuard] g_ag_guard a )
}

// Remember `p` as the verified owner of `token` until `until` — what a
// successful verification does. Public for tests (and for a deployment
// that verifies tokens some other way, e.g. by introspection), which can
// then drive the signed-in service without an identity provider.
@ _ag_auth_seed s token AgPrincipal p i until → v {
    : String h ( __ag_token_hash token )
    ( __ag_cache_put h until p )
}

// Forget every remembered verdict (a role or a tenant decision changed).
@ ag_auth_forget_all → v {
    : AgGuard a ( locked_take [AgGuard] g_ag_guard )
    ( vec_clear [AgAuthHit] . a hits )
    ( locked_restore [AgGuard] g_ag_guard a )
}

// The provider; discovered on first use, by whoever holds the guard
// (`a`, taken from g_ag_guard), for the configured `issuer`.
@ __ag_provider_in inout AgGuard a s issuer b multi → ?OidcProvider {
    ?? . a prov { T pv → { ^ @ ?OidcProvider { T ( OidcProvider_share pv ) } } F → {} }
    ? multi {
        // Multi-tenant: the discovery document's issuer is a template
        // ("…/{tenantid}/v2.0"), which oidc_discover's issuer check can
        // never match. Read the template and the JWKS URI from the
        // document directly; every token's `iss` is later measured
        // against the template with the token's own `tid` in it.
        : String url ( oidc_discovery_url issuer )
        : HttpClient hc ( http_client_new )
        : ~ String body ( string_new )
        ?? ( http_client_get hc ( string_data url ) ) {
            T r → { ? & >= . r status 200 < . r status 300 { = body ( bytes_to_str . r body ) } {} }
            F _ → {}
        }
        : ~ String tmpl ( string_new )
        : ~ String jwks ( string_new )
        ?? ( json_parse ( string_data body ) ) {
            T j → {
                ?? ( json_obj_get j `issuer` ) { T v → { ? ( json_is_str v ) { = tmpl ( string_from ( json_str_data v ) ) } {} } F _ → {} }
                ?? ( json_obj_get j `jwks_uri` ) { T v → { ? ( json_is_str v ) { = jwks ( string_from ( json_str_data v ) ) } {} } F _ → {} }
            }
            F _ → {}
        }
        ? & > ( string_len tmpl ) 0 > ( string_len jwks ) 0 {} { ^ @ ?OidcProvider { F } }
        : OidcProvider p ( oidc_provider_new issuer )
        ( oidc_provider_set_jwks_uri p ( string_data jwks ) )
        ( __ag_set . a iss_tmpl ( string_data tmpl ) )
        = . a prov @ ?OidcProvider { T ( OidcProvider_share p ) }
        ^ @ ?OidcProvider { T p }
    } {}
    ?? ( oidc_provider_discover issuer ) {
        T p → {
            = . a prov @ ?OidcProvider { T ( OidcProvider_share p ) }
            ^ @ ?OidcProvider { T p }
        }
        F _ → { ^ @ ?OidcProvider { F } }
    }
}

// Discover the provider now (startup), so the first person to call does
// not wait for discovery and the key set. F when it cannot be reached
// (it is retried on the next request).
@ ag_auth_warm → b {
    : String iss ( ag_auth_issuer )
    : b multi ( ag_auth_multi )
    : ~ AgGuard a ( locked_take [AgGuard] g_ag_guard )
    : ~ b ok F
    ?? ( __ag_provider_in a ( string_data iss ) multi ) {
        T p → {
            ?? ( oidc_fetch_jwks p ) { T _ → {} F → { = ok T } }
        }
        F → {}
    }
    ( locked_restore [AgGuard] g_ag_guard a )
    ^ ok
}

// The issuer template with `{tenantid}` replaced by `tid`; '' when there
// is no template or no tenant — a refusal, never a wildcard.
@ __ag_issuer_for s tmpl s tid → String {
    : ( Slice u ) tmpl_v ( slice_of_str tmpl )
    : i tn ( nurl_str_len tmpl )
    : String out ( string_new )
    ? & > tn 0 > ( nurl_str_len tid ) 0 {} { ^ out }
    : s needle `{tenantid}`
    : ( Slice u ) needle_v ( slice_of_str needle )
    : i nn ( nurl_str_len needle )
    : ~ b hit F
    : ~ i k 0
    ~ < k tn {
        : ~ b here & ! hit <= + k nn tn
        : ~ i j 0
        ~ & here < j nn {
            ? == ( slice_byte tmpl_v + k j ) ( slice_byte needle_v j ) {} { = here F }
            = j + j 1
        }
        ? here {
            ( string_push_str out tid )
            = k + k nn
            = hit T
        } {
            ( string_push_char out ( slice_byte tmpl_v k ) )
            = k + k 1
        }
    }
    ? hit {} { ^ ( string_new ) }
    ^ out
}

// The `tid` a token claims, read WITHOUT verifying it — only to pick
// which issuer to demand and to refuse an unadmitted organisation before
// any network round trip. The verdict re-reads it from the verified
// claims.
@ __ag_unverified_tid s token → String {
    ?? ( jws_payload_unverified token ) {
        T j → {
            ?? ( json_obj_get j `tid` ) { T v → { ? ( json_is_str v ) { ^ ( _ag_lower ( json_str_data v ) ) } {} } F _ → {} }
        }
        F _ → {}
    }
    ^ ( string_new )
}

// Verify `token`; on success, the person, with their organisation's
// database and their row in it made sure of.
@ __ag_verify s token i now → AgPrincipal {
    ? ( ag_auth_multi ) {
        : String tid0 ( __ag_unverified_tid token )
        ? ( ag_tenant_admitted ( string_data tid0 ) `` now ) {} {
            ^ ( ag_principal_anon `this organisation is not approved for this agora yet — an administrator of the service has to allow it` )
        }
    } {}
    : AgConf c ( locked_get [AgConf] g_ag_conf )
    : ~ AgGuard a ( locked_take [AgGuard] g_ag_guard )
    : ~ ? OidcIdentity got @ ?OidcIdentity { F }
    : ~ String why ( string_new )
    ?? ( __ag_provider_in a ( string_data . c issuer ) . c multi ) {
        F → { ( __ag_set why `the identity provider could not be reached` ) }
        T p → {
            : ~ String want_iss ( string_from ( string_data . c issuer ) )
            ? . c multi {
                : String tid ( __ag_unverified_tid token )
                = want_iss ( __ag_issuer_for ( string_data . a iss_tmpl ) ( string_data tid ) )
            } {}
            ? > ( string_len want_iss ) 0 {
                // An Entra v2 access token names the bare client id as its
                // audience; the scope was asked for under the resource URI.
                // Both spellings are this application.
                : ~ i attempt 0
                ~ < attempt 2 {
                    : s aud ? == attempt 0 ( string_data . c audience ) ( string_data . c client_id )
                    : OidcPolicy pol ( oidc_policy_new ( string_data want_iss ) aud )
                    ?? ( oidc_verify_access_token_at p pol token now ) {
                        T id → {
                            = got @ ?OidcIdentity { T id }
                            = attempt 2
                        }
                        F e → {
                            ( __ag_set why ( oauth_err_name e ) )
                            ( string_push_str why `: ` )
                            ( string_push_str why ( oidc_provider_last_error p ) )
                            = attempt + attempt 1
                        }
                    }
                }
            } { ( __ag_set why `the token names no tenant to derive an issuer from` ) }
        }
    }
    ( locked_restore [AgGuard] g_ag_guard a )
    ?? got {
        F → { ^ ( ag_principal_anon ( string_data why ) ) }
        T id → {
            : String tid ( _ag_lower ( string_data ( oidc_identity_claim id `tid` ) ) )
            ? ( ag_auth_multi ) {
                : String label ( string_from ( string_data . id email ) )
                ? ( ag_tenant_admitted ( string_data tid ) ( string_data label ) now ) {} {
                    ^ ( ag_principal_anon `this organisation is not approved for this agora yet — an administrator of the service has to allow it` )
                }
            } {}
            : String org ( ag_org_key ? > ( string_len tid ) 0 ( string_data tid ) ( string_data . id issuer ) )
            : AgStore st ( ag_org_store ( string_data org ) )
            ? . st ok {} { ^ ( ag_principal_anon `the organisation's database could not be opened` ) }
            : ~ String email ( string_from ( string_data . id email ) )
            ? == ( string_len email ) 0 { = email ( string_from ( string_data . id username ) ) } {}
            : String role ( ag_user_touch st ( string_data . id subject ) ( string_data email ) ( string_data . id name ) now )
            ? == ( string_len role ) 0 { ^ ( ag_principal_anon `could not record the sign-in` ) } {}
            : AgPrincipal p @ AgPrincipal {
                T org ( string_from ( string_data . id subject ) ) email
                ( string_from ( string_data . id name ) ) role ( string_new )
            }
            // Remembered for a minute, never past the token's own expiry.
            : ~ i until + now AG_AUTH_CACHE_S
            ? & > . id expires_at 0 < . id expires_at until { = until . id expires_at } {}
            : String h ( __ag_token_hash token )
            ( __ag_cache_put h until p )
            ^ p
        }
    }
}

// The principal behind a bearer token. Local mode never gets here.
@ ag_auth_principal s token i now → AgPrincipal {
    ? > ( nurl_str_len token ) 0 {} { ^ ( ag_principal_anon `` ) }
    : String h ( __ag_token_hash token )
    ?? ( __ag_cache_get h now ) {
        T p → { ^ p }
        F → {}
    }
    ^ ( __ag_verify token now )
}
