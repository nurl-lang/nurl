// anomaly/authz.nu — who is asking, and which models they may touch.
//
// The service was single-user by construction: every route reached every
// model in one flat store. This file adds the three things that turns into
// a shared service — an identity, a tenant, and an owner — without moving a
// single stored model.
//
//   identity   An OIDC bearer token, verified by the `oauth` package
//              against the provider's own JWKS. The token names a subject
//              (`sub`) and, on Entra, a tenant (`tid`).
//   tenant     One SQLite database per organisation, at
//              <store>/orgs/<org>.db. The org is implicit in the file, so
//              no query in here carries an org column and no query can
//              forget one.
//   owner      A row in that database binding a model name to a subject.
//              A model with no row is UNOWNED: legacy data that predates
//              authentication, visible to admins so somebody can claim it,
//              never silently absorbed into whoever logged in first.
//
// Two roles: `admin` sees and manages the whole organisation's models and
// its users and keys; `viewer` sees only the models it owns. The first
// subject to authenticate from an organisation becomes its admin — there
// is nobody else who could have granted it, and an org whose only user is
// a viewer would be permanently unadministrable.
//
// API keys are for machines that cannot do an interactive login (the
// Node-RED flows feeding these models). A key carries the identity and
// role of the user who created it, so "you see only your own models" holds
// for a key exactly as it holds for that user's browser. Keys are stored
// as a SHA-256 of the secret; the plaintext exists once, in the response
// that creates it.
//
// EVERYTHING HERE IS OFF BY DEFAULT. With ANOMALY_AUTH unset the resolver
// hands every request an authenticated admin principal and the service
// behaves exactly as it did before this file existed. That is deliberate:
// a deployment upgrades the binary first and turns on authentication when
// its identity provider is configured, not at the same instant.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`
$ `src/config.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_auth.nu`
$ `deps/oauth/src/oauth.nu`

// ── Configuration ─────────────────────────────────────────────────────
//
// Read once at startup from the environment, so a deployment turns
// authentication on by setting variables and restarting, and turns it off
// the same way. Nothing here is patchable at runtime: an auth switch that
// a request can flip is not an auth switch.

: ~ s g_az_root `.`

// Two modes, and they are different products.
//
//   simple  No authentication at all. Anyone who opens the page sees every
//           model, and what the API collects lands in one `public`
//           organisation. This is what the service was before sign-in
//           existed, kept as a mode rather than as a fallback so that a
//           deployment which wants it says so.
//   oidc    Signed in, multi-tenant. A model belongs to an ORGANISATION,
//           and nothing is created or collected without a credential that
//           names one.
: i AZ_MODE_SIMPLE 0
: i AZ_MODE_OIDC 1

// The organisation everything belongs to in simple mode. A real
// organisation with a real database, so the two modes share one shape and
// a deployment can turn sign-in on later without moving data.
: s AZ_PUBLIC_ORG `public`

: ~ i g_az_mode 0  // AZ_MODE_SIMPLE; a global initialiser must be a literal
: ~ b g_az_open_ingest F

// The configured strings, owned. A global can hold a `s` (a borrowed char*)
// but not a String, so the Strings behind these live in one heap block whose
// address is the global; reconfiguring frees the previous block. The obvious
// alternative — hand the globals `( string_data owned )` and never free the
// owned String — is a leak that a long-running service would never notice
// and a test that reconfigures would report every time.
: AzStrings {
    String s_issuer
    String s_client_id
    String s_audience
    String s_allowed
    String s_last_err  // why the last token verification failed
    String s_owner  // the owner tenant: config-only, the trust anchor
}

: ~ i g_az_strs 0

@ __az_strs → *AzStrings {
    ? != g_az_strs 0 { ^ # *AzStrings g_az_strs } {}
    : *AzStrings a # *AzStrings ( nurl_malloc Z AzStrings )
    = . a s_issuer ( string_new )
    = . a s_client_id ( string_new )
    = . a s_audience ( string_new )
    = . a s_allowed ( string_new )
    = . a s_last_err ( string_new )
    = . a s_owner ( string_new )
    = g_az_strs # i a
    ^ a
}

@ __az_set_str * AzStrings a i which s v → v {
    ? == which 0 { ( string_free . a s_issuer ) = . a s_issuer ( string_from v ) } {}
    ? == which 1 { ( string_free . a s_client_id ) = . a s_client_id ( string_from v ) } {}
    ? == which 2 { ( string_free . a s_audience ) = . a s_audience ( string_from v ) } {}
    ? == which 3 { ( string_free . a s_allowed ) = . a s_allowed ( string_from v ) } {}
    ? == which 4 { ( string_free . a s_last_err ) = . a s_last_err ( string_from v ) } {}
    ? == which 5 { ( string_free . a s_owner ) = . a s_owner ( string_from v ) } {}
}

@ g_az_issuer → s { ^ ( string_data . ( __az_strs ) s_issuer ) }

@ g_az_client_id → s { ^ ( string_data . ( __az_strs ) s_client_id ) }

@ g_az_audience → s { ^ ( string_data . ( __az_strs ) s_audience ) }

@ g_az_allowed → s { ^ ( string_data . ( __az_strs ) s_allowed ) }

// The OWNER TENANT: the organisation whose admins administer the service
// itself — approving other tenants, managing any organisation's users. It
// is set in the configuration file and nowhere else. A tenant that could
// grant itself that from the dashboard would not be an anchor.
@ g_az_owner → s { ^ ( string_data . ( __az_strs ) s_owner ) }

@ anomaly_authz_set_owner_tenant s tid → v { ( __az_set_str ( __az_strs ) 5 tid ) }

// Why the last presented token was refused. A 401 with no reason is what
// turns a one-line configuration mistake — the wrong audience, a clock an
// hour out, a tenant nobody listed — into an afternoon. The service is
// single-threaded, so one slot is the whole story.
@ anomaly_authz_last_error → s { ^ ( string_data . ( __az_strs ) s_last_err ) }

@ __az_set_last_err s v → v { ( __az_set_str ( __az_strs ) 4 v ) }

// The identity provider, discovered lazily and then reused: it owns the
// JWKS cache, and re-fetching a key set per request would turn every
// authenticated call into two network round trips. The service runs
// single-threaded (http_app_listen with no worker pool), which is the
// condition *OidcProvider documents for going unlocked.
//
// Held as an address because a global cannot carry an option of a pointer;
// 0 means "not discovered yet". Discovery happens once and the provider
// then lives for the process, so nothing here frees it.
: ~ i g_az_prov_addr 0

// ── Multi-tenant ──────────────────────────────────────────────────────
//
// A single-tenant application has one issuer, and a token either carries it
// or is refused. A MULTI-tenant one does not: every organisation signs its
// users' tokens with its own issuer, and the provider says so — Entra's
// discovery document at the multi-tenant authority literally publishes
//
//     "issuer": "https://login.microsoftonline.com/{tenantid}/v2.0"
//
// which is a template, not a URL. So there is nothing to pin, and the
// oauth package's discovery refuses it: it cross-checks the document's own
// issuer against the one asked for, correctly, and a template never
// matches.
//
// What is checked instead is what the provider itself documents: the
// token's `iss` must be that template with the token's OWN `tid`
// substituted. Both claims are inside the signature, so an attacker cannot
// move a token between tenants; what the check enforces is that a token
// claiming tenant X was issued by tenant X's issuer, which is the part a
// fixed string would have got wrong.
//
// The trade is that ANY organisation can then sign in and have an
// organisation created for it. `allowed_tenants` is the list that says
// which may; empty means any, which is what "multi-tenant" asks for and
// should be a deliberate answer rather than a default nobody saw.
: ~ b g_az_multi F
: ~ s g_az_iss_tmpl ``

@ anomaly_authz_set_root s root → v {
    = g_az_root root
}

// `on` gates the whole thing; `open_ingest` keeps /detect and /detect_only
// reachable without credentials while a fleet of already-deployed data
// producers is migrated onto keys. It is a migration setting: with it on,
// anyone who can reach the port can write points into any model.
@ anomaly_authz_configure b on b open_ingest s issuer s client_id s audience → v {
    = g_az_mode ? on AZ_MODE_OIDC AZ_MODE_SIMPLE
    = g_az_open_ingest open_ingest
    : *AzStrings a ( __az_strs )
    ( __az_set_str a 0 issuer )
    ( __az_set_str a 1 client_id )
    ( __az_set_str a 2 audience )
}

// Multi-tenant acceptance. `allowed` is a comma-separated tenant list;
// empty admits every organisation the provider will sign for.
@ anomaly_authz_configure_tenancy b multi s allowed → v {
    = g_az_multi multi
    ( __az_set_str ( __az_strs ) 3 allowed )
    // A change of tenancy mode changes what the provider must be built
    // from, so the cached one is no longer the right one.
    = g_az_prov_addr 0
    = g_az_iss_tmpl ``
}

@ anomaly_authz_multi_tenant → b { ^ g_az_multi }

@ anomaly_authz_allowed_tenants → s { ^ ( g_az_allowed ) }

// Resolve the settings from the configuration file and the environment,
// in that order — the file is the persistent baseline, the environment is
// what one run overrides. (A command-line flag beats both, but nothing
// here reads argv: main.nu owns that layer.) Returns T when authentication
// ended up enabled.
//
//   [auth] enabled / issuer / client_id / audience / open_ingest
//   ANOMALY_AUTH   ANOMALY_OIDC_ISSUER   ANOMALY_OIDC_CLIENT_ID
//                  ANOMALY_OIDC_AUDIENCE ANOMALY_OPEN_INGEST
//
// `audience` defaults to `api://<client_id>` — the app-id URI an OIDC
// provider hands out for an API the client registered for itself, which is
// what nearly every deployment wants and none should have to restate.
@ anomaly_authz_apply AnomalyConfig cfg → b {
    // `mode` is the setting; `enabled` is what it was called before there
    // were two modes, and is still read so an existing file keeps working.
    : String mode ( config_str cfg `auth.mode` `` )
    : ~ b want ( config_bool cfg `auth.enabled` F )
    ? > ( string_len mode ) 0 {
        = want == ( nurl_str_eq ( string_data mode ) `oidc` ) 1
    } {}
    ( string_free mode )
    : ~ String iss ( config_str cfg `auth.issuer` `` )
    : ~ String cid ( config_str cfg `auth.client_id` `` )
    : ~ String aud ( config_str cfg `auth.audience` `` )
    // Default DENY. Without a credential naming an organisation there is
    // nothing a point could belong to, and a model created from one would
    // be exactly the unowned model this design refuses to make.
    : ~ b open_ing ( config_bool cfg `auth.open_ingest` F )

    // The environment overlays only where it actually says something, so an
    // unset variable lets the file show through rather than blanking it.
    ?? ( env_get `ANOMALY_MODE` ) {
        T v → { = want == ( nurl_str_eq ( string_data v ) `oidc` ) 1 ( string_free v ) }
        F → {}
    }
    ?? ( env_get `ANOMALY_AUTH` ) {
        T v → { = want ( __az_truthy ( string_data v ) ) ( string_free v ) }
        F → {}
    }
    ?? ( env_get `ANOMALY_OPEN_INGEST` ) {
        T v → { = open_ing ( __az_truthy ( string_data v ) ) ( string_free v ) }
        F → {}
    }
    ?? ( env_get `ANOMALY_OIDC_ISSUER` ) {
        T v → { ( string_free iss ) = iss v }
        F → {}
    }
    ?? ( env_get `ANOMALY_OIDC_CLIENT_ID` ) {
        T v → { ( string_free cid ) = cid v }
        F → {}
    }
    ?? ( env_get `ANOMALY_OIDC_AUDIENCE` ) {
        T v → { ( string_free aud ) = aud v }
        F → {}
    }

    ? > ( string_len aud ) 0 {} {
        ( string_free aud )
        = aud ( string_from `api://` )
        ( string_push_str aud ( string_data cid ) )
    }
    // An issuer and a client id are what verification needs. Turning auth
    // on without them would refuse every request rather than protect
    // anything, so it stays off and the caller reports why.
    : b usable & & want > ( string_len iss ) 0 > ( string_len cid ) 0
    ( anomaly_authz_configure usable open_ing
    ( string_data iss ) ( string_data cid ) ( string_data aud ) )

    : ~ b multi ( config_bool cfg `auth.multi_tenant` F )
    ?? ( env_get `ANOMALY_OIDC_MULTI_TENANT` ) {
        T v → { = multi ( __az_truthy ( string_data v ) ) ( string_free v ) }
        F → {}
    }
    : ~ String allow ( config_str_list cfg `auth.allowed_tenants` `` )
    ?? ( env_get `ANOMALY_OIDC_ALLOWED_TENANTS` ) {
        T v → { ( string_free allow ) = allow v }
        F → {}
    }
    : String allow_lc ( __az_lower ( string_data allow ) )
    ( string_free allow )
    ( anomaly_authz_configure_tenancy multi ( string_data allow_lc ) )

    : ~ String owner ( config_str cfg `auth.owner_tenant` `` )
    ?? ( env_get `ANOMALY_OIDC_OWNER_TENANT` ) {
        T v → { ( string_free owner ) = owner v }
        F → {}
    }
    : String owner_lc ( __az_lower ( string_data owner ) )
    ( string_free owner )
    ( anomaly_authz_set_owner_tenant ( string_data owner_lc ) )
    ( string_free owner_lc )

    // The configured list only ever ADDS to the registry, so a headless
    // deployment can admit tenants without a dashboard and a decision made
    // in the dashboard is never undone by a restart.
    ? usable { ( az_seed_allowed ( g_az_allowed ) ( now_seconds ) ) } {}
    // configure/configure_tenancy copy what they are given, so these are
    // ours to release. (They used to back the globals directly and were
    // deliberately leaked; that was a leak a service would never notice and
    // a test that reconfigures reports every time.)
    ( string_free allow_lc )
    ( string_free aud )
    ( string_free cid )
    ( string_free iss )
    ^ usable
}

// True when authentication was ASKED for — by file or environment — so a
// caller can tell "off because nobody asked" from "off because it was
// asked for without an issuer or a client id".
@ anomaly_authz_requested AnomalyConfig cfg → b {
    : ~ b want ( config_bool cfg `auth.enabled` F )
    ?? ( env_get `ANOMALY_AUTH` ) {
        T v → { = want ( __az_truthy ( string_data v ) ) ( string_free v ) }
        F → {}
    }
    ^ want
}

@ __az_truthy s v → b {
    ? == ( nurl_str_eq v `1` ) 1 { ^ T } {}
    ? == ( nurl_str_eq v `true` ) 1 { ^ T } {}
    ? == ( nurl_str_eq v `yes` ) 1 { ^ T } {}
    ? == ( nurl_str_eq v `on` ) 1 { ^ T } {}
    ^ F
}

@ anomaly_authz_enabled → b { ^ == g_az_mode AZ_MODE_OIDC }

@ anomaly_authz_mode → i { ^ g_az_mode }

@ anomaly_authz_simple → b { ^ == g_az_mode AZ_MODE_SIMPLE }

@ anomaly_authz_owner_tenant → s { ^ ( g_az_owner ) }

@ anomaly_authz_open_ingest → b { ^ g_az_open_ingest }

@ anomaly_authz_issuer → s { ^ ( g_az_issuer ) }

@ anomaly_authz_client_id → s { ^ ( g_az_client_id ) }

@ anomaly_authz_audience → s { ^ ( g_az_audience ) }

// ── The principal ─────────────────────────────────────────────────────

: s AZ_ROLE_ADMIN `admin`
: s AZ_ROLE_VIEWER `viewer`

// A key is a credential, not a person, so it does not carry a person's
// role. A `viewer` is somebody who reads; a machine that reads is pointless
// and a machine that can delete a model it feeds is a hazard. The one thing
// a producer needs is to send points, so that is its own capability.
: s AZ_ROLE_INGEST `ingest`

: Principal {
    b authed
    b via_key  // arrived with an API key rather than a browser token
    String org
    String sub
    String email
    String pname
    String role
    String key_id  // empty unless via_key
}

@ principal_free Principal p → v {
    ( string_free . p org )
    ( string_free . p sub )
    ( string_free . p email )
    ( string_free . p pname )
    ( string_free . p role )
    ( string_free . p key_id )
}

@ principal_anon → Principal {
    ^ @ Principal {
        F F ( string_new ) ( string_new ) ( string_new )
        ( string_new ) ( string_from AZ_ROLE_VIEWER ) ( string_new )
    }
}

// The principal every request gets in simple mode: an admin of the shared
// `public` organisation. A real organisation with a real database, so the
// two modes share one shape and turning sign-in on later does not have to
// move anything.
@ principal_public_admin → Principal {
    ^ @ Principal {
        T F ( string_from AZ_PUBLIC_ORG ) ( string_from AZ_PUBLIC_ORG ) ( string_new )
        ( string_from AZ_PUBLIC_ORG ) ( string_from AZ_ROLE_ADMIN ) ( string_new )
    }
}

@ principal_local_admin → Principal { ^ ( principal_public_admin ) }

@ principal_is_admin Principal p → b {
    ^ & . p authed == ( nurl_str_eq ( string_data . p role ) AZ_ROLE_ADMIN ) 1
}

// An admin of the owner tenant: the one principal that reaches across
// organisations. Everything it can do, an ordinary admin can do inside its
// own organisation and nowhere else.
@ principal_is_owner_admin Principal p → b {
    ? ( principal_is_admin p ) {} { ^ F }
    // In simple mode there is one organisation and its admin is everyone,
    // so there is no service to administer separately.
    ? ( anomaly_authz_enabled ) {} { ^ F }
    : s owner ( g_az_owner )
    ? > ( nurl_str_len owner ) 0 {} { ^ F }
    : String key ( __az_org_key owner )
    : b same == ( nurl_str_eq ( string_data key ) ( string_data . p org ) ) 1
    ( string_free key )
    ^ same
}

// May this credential send points to a model the organisation already has?
//
// An admin may, because an admin may do anything here. A KEY may if it was
// issued to — that is what `ingest` names, and it is the whole point of
// having a separate capability: a production key should be able to feed a
// model without being able to delete it.
//
// A viewer may not. A viewer reads what the models have collected and
// decided; sending points is not reading.
@ principal_may_ingest Principal p → b {
    ? . p authed {} { ^ F }
    ? ( principal_is_admin p ) { ^ T } {}
    ? . p via_key {} { ^ F }
    ^ == ( nurl_str_eq ( string_data . p role ) AZ_ROLE_INGEST ) 1
}

@ principal_json Principal p → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `authenticated` ( json_bool . p authed ) )
    ( json_obj_set o `organization` ( json_str_lit ( string_data . p org ) ) )
    ( json_obj_set o `subject` ( json_str_lit ( string_data . p sub ) ) )
    ( json_obj_set o `email` ( json_str_lit ( string_data . p email ) ) )
    ( json_obj_set o `name` ( json_str_lit ( string_data . p pname ) ) )
    ( json_obj_set o `role` ( json_str_lit ( string_data . p role ) ) )
    ( json_obj_set o `via_api_key` ( json_bool . p via_key ) )
    ( json_obj_set o `owner_admin` ( json_bool ( principal_is_owner_admin p ) ) )
    ^ o
}

// ── The per-organisation database ─────────────────────────────────────

// An org id becomes a filename, so it is not taken on trust. A tenant GUID
// passes through as itself; anything else is replaced by a digest of it,
// which is collision-free enough to key a database on and cannot contain a
// path separator, a dot-dot, or a NUL by construction.
@ __az_org_key s raw → String {
    : i n ( nurl_str_len raw )
    : ~ b plain > n 0
    ? > n 64 { = plain F } {}
    : ~ i k 0
    ~ & plain < k n {
        : i c ( nurl_str_at raw n k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        : b dash == c 45
        ? | | | digit lower upper dash {} { = plain F }
        = k + k 1
    }
    ? plain { ^ ( __az_lower raw ) } {}
    : ( Vec u ) msg ( bytes_from_str raw )
    : ( Vec u ) dig ( sha256_pure msg )
    ( vec_free [u] msg )
    : String hex ( bytes_to_hex dig )
    ( vec_free [u] dig )
    : String out ( string_new )
    : ~ i j 0
    ~ < j 32 { ( string_push_char out ( string_get hex j ) ) = j + j 1 }
    ( string_free hex )
    ^ out
}

@ __az_lower s raw → String {
    : String out ( string_new )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at raw n k )
        ? & >= c 65 <= c 90 { ( string_push_char out + c 32 ) } { ( string_push_char out c ) }
        = k + k 1
    }
    ^ out
}

@ __az_starts s hay s pre → b {
    : i hn ( nurl_str_len hay )
    : i pn ( nurl_str_len pre )
    ? >= hn pn {} { ^ F }
    : ~ i k 0
    ~ < k pn {
        ? == ( nurl_str_at hay hn k ) ( nurl_str_at pre pn k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __az_orgs_dir → String {
    : String p ( string_from g_az_root )
    ( string_push_str p `/orgs` )
    ^ p
}

@ __az_db_path s org → String {
    : String p ( __az_orgs_dir )
    ( string_push_char p 47 )
    ( string_push_str p org )
    ( string_push_str p `.db` )
    ^ p
}

@ __az_schema → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS users (
        sub TEXT PRIMARY KEY,
        email TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        role TEXT NOT NULL DEFAULT 'viewer',
        created_at INTEGER NOT NULL DEFAULT 0,
        last_seen_at INTEGER NOT NULL DEFAULT 0)` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS models (
        name TEXT PRIMARY KEY,
        owner_sub TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0)` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS api_keys (
        id TEXT PRIMARY KEY,
        secret_hash TEXT NOT NULL,
        owner_sub TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER NOT NULL DEFAULT 0,
        revoked_at INTEGER NOT NULL DEFAULT 0)` ) )
    ( vec_push [String] v ( string_from `CREATE INDEX IF NOT EXISTS models_owner ON models (owner_sub)` ) )
    ( vec_push [String] v ( string_from `CREATE INDEX IF NOT EXISTS keys_owner ON api_keys (owner_sub)` ) )
    // A key records the role it was issued with rather than reading it from
    // its creator: the credential belongs to the organisation, and it must
    // keep working when the person who made it is forgotten. SQLite has no
    // ADD COLUMN IF NOT EXISTS, so the duplicate-column failure on a fresh
    // database (whose CREATE already carries it) is ignored below.
    ( vec_push [String] v ( string_from `ALTER TABLE api_keys ADD COLUMN role TEXT NOT NULL DEFAULT 'ingest'` ) )
    // Keys issued before `ingest` existed defaulted to a person's role. Every
    // one of them was made to feed a model, which is what `ingest` names.
    ( vec_push [String] v ( string_from `UPDATE api_keys SET role = 'ingest' WHERE role = 'viewer'` ) )
    ^ v
}

// The HOME organisation: the first one this store ever created.
//
// Models that predate authentication have no owner and no organisation —
// nothing in them says whose they are. Before multi-tenancy that did not
// matter; with it, "an admin may adopt an unclaimed model" would let a
// stranger who signed in from their own tenant, and so became an admin of
// it, adopt the operator's data. The first organisation to exist is the one
// that set the service up, which is the only defensible answer the store
// can give on its own.
@ __az_home_marker → String {
    : String p ( __az_orgs_dir )
    ( string_push_str p `/.home` )
    ^ p
}

@ az_home_org → String {
    : String p ( __az_home_marker )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r {
        T txt → {
            // string_trim builds a new String; the one read_file handed us
            // is still ours to release.
            : String t ( string_trim txt )
            ( string_free txt )
            ^ t
        }
        F _ → { ^ ( string_new ) }
    }
}

@ az_is_home_org s org → b {
    : String h ( az_home_org )
    // No marker at all — a store from before this existed. Nobody is home,
    // so nothing is adoptable until an operator says so.
    ? > ( string_len h ) 0 {} { ( string_free h ) ^ F }
    : b same == ( nurl_str_eq ( string_data h ) org ) 1
    ( string_free h )
    ^ same
}

@ __az_claim_home_if_unset s org → v {
    // `public` is never home. It is not an operator — it is the bucket
    // ownerless data lands in, and it comes into existence the moment a
    // producer sends a point during the open-ingest window, which on a
    // fresh deployment is BEFORE anybody has signed in. Letting it take the
    // marker would hand the service to the one organisation that has no
    // members, permanently: the marker is written once, and the operator
    // who signs in afterwards could then adopt nothing, ever.
    ? == ( nurl_str_eq org AZ_PUBLIC_ORG ) 1 { ^ } {}
    : String p ( __az_home_marker )
    ? ( file_exists ( string_data p ) ) {} {
        : !v IoErr w ( write_file ( string_data p ) org )
        ?? w { T _ → {} F _ → {} }
    }
    ( string_free p )
}

// Is `name` held by the public organisation — the bucket for points that
// arrived without a credential naming an owner?
@ az_model_in_public s name → b {
    : ~ b there F
    ?? ( az_db_open AZ_PUBLIC_ORG ) {
        F _ → {}
        T db → { = there ( az_model_in_org db name ) }
    }
    ^ there
}

// Release a model from the public organisation, so it can be adopted into
// a real one. Ownerless data is not the public organisation's property; it
// is data nobody has claimed yet, and `public` is where it waits.
@ az_model_release_public s name → b {
    : ~ b ok F
    ?? ( az_db_open AZ_PUBLIC_ORG ) {
        F _ → {}
        T db → {
            ? ( az_model_in_org db name ) {
                ( az_model_forget db name )
                = ok T
            } {}
        }
    }
    ^ ok
}

// Open (creating if absent) the organisation's database with its schema
// applied. The caller owns the handle; it closes at the caller's scope end.
@ az_db_open s org → !Database SqliteErr {
    : String dir ( __az_orgs_dir )
    : !v IoErr mk ( dir_create_all ( string_data dir ) )
    ?? mk { T _ → {} F _ → {} }
    ( string_free dir )
    : String path ( __az_db_path org )
    : !Database SqliteErr dr ( sqlite_open ( string_data path ) )
    ( string_free path )
    ?? dr {
        F e → { ^ @ !Database SqliteErr { F e } }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            : ( Vec String ) stmts ( __az_schema )
            : i n ( vec_len [String] stmts )
            : ~ b failed F
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] stmts k ) {
                    T sq → {
                        : b is_alter ( __az_starts ( string_data sq ) `ALTER` )
                        ?? ( sqlite_exec db ( string_data sq ) ) {
                            T _ → {}
                            F _ → { ? is_alter {} { = failed T } }
                        }
                        ( string_free sq )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [String] stmts )
            ? failed { ^ @ !Database SqliteErr { F # SqliteErr SqliteMisuse } } {}
            ( __az_claim_home_if_unset org )
            ^ @ !Database SqliteErr { T db }
        }
    }
}

// ── The tenant registry ───────────────────────────────────────────────
//
// Which organisations may use this service at all. It lives in a database
// rather than the configuration file because the answer changes at
// runtime: a tenant signs in, is recorded as PENDING, and an owner-tenant
// admin approves it from the dashboard. A config key could not be edited
// by the person doing the approving.
//
// The owner tenant itself is always allowed and is never in this table's
// gift — it is the anchor the approving is done from.
//
//   pending  seen, refused, waiting for a decision
//   allowed  may sign in and have an organisation
//   blocked  refused, and a decision has been made

: s AZ_TENANT_PENDING `pending`
: s AZ_TENANT_ALLOWED `allowed`
: s AZ_TENANT_BLOCKED `blocked`

@ __az_root_db_path → String {
    : String p ( __az_orgs_dir )
    ( string_push_str p `/_root.db` )
    ^ p
}

@ az_root_open → !Database SqliteErr {
    : String dir ( __az_orgs_dir )
    : !v IoErr mk ( dir_create_all ( string_data dir ) )
    ?? mk { T _ → {} F _ → {} }
    ( string_free dir )
    : String path ( __az_root_db_path )
    : !Database SqliteErr dr ( sqlite_open ( string_data path ) )
    ( string_free path )
    ?? dr {
        F e → { ^ @ !Database SqliteErr { F e } }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `CREATE TABLE IF NOT EXISTS tenants (
                tid TEXT PRIMARY KEY,
                state TEXT NOT NULL DEFAULT 'pending',
                label TEXT NOT NULL DEFAULT '',
                first_seen INTEGER NOT NULL DEFAULT 0,
                decided_at INTEGER NOT NULL DEFAULT 0,
                decided_by TEXT NOT NULL DEFAULT '')` ) {
                T _ → {}
                F _ → { ^ @ !Database SqliteErr { F # SqliteErr SqliteMisuse } }
            }
            ^ @ !Database SqliteErr { T db }
        }
    }
}

// The recorded state of `tid`, or "" when it has never been seen.
@ az_tenant_state Database db s tid → String {
    : ~ String st ( string_new )
    ?? ( sqlite_prepare db `SELECT state FROM tenants WHERE tid = ?1` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from tid ) )
            ?? ( sqlite_step q ) {
                T has → { ? has { ( string_free st ) = st ( sqlite_column_text q 0 ) } {} }
                F _ → {}
            }
        }
    }
    ^ st
}

// Record that `tid` knocked. First time: pending. Afterwards the state is
// whatever was decided, and a repeat visit must not undo a decision.
@ az_tenant_note Database db s tid s label i now → String {
    : String have ( az_tenant_state db tid )
    ? > ( string_len have ) 0 { ^ have } {}
    ( string_free have )
    ?? ( sqlite_prepare db `INSERT INTO tenants (tid, state, label, first_seen)
         VALUES (?1, 'pending', ?2, ?3)` ) {
        F _ → {}
        T ins → {
            ( __az_bind_str ins 1 ( string_from tid ) )
            ( __az_bind_str ins 2 ( string_from label ) )
            ?? ( sqlite_bind_int ins 3 now ) { T _ → {} F _ → {} }
            : b _r ( __az_run ins )
        }
    }
    ^ ( string_from AZ_TENANT_PENDING )
}

@ az_tenant_set_state Database db s tid s state s by i now → b {
    : b known | | == ( nurl_str_eq state AZ_TENANT_PENDING ) 1
    == ( nurl_str_eq state AZ_TENANT_ALLOWED ) 1
    == ( nurl_str_eq state AZ_TENANT_BLOCKED ) 1
    ? known {} { ^ F }
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT INTO tenants (tid, state, first_seen, decided_at, decided_by)
         VALUES (?1, ?2, ?3, ?3, ?4)
         ON CONFLICT(tid) DO UPDATE SET state = excluded.state,
             decided_at = excluded.decided_at, decided_by = excluded.decided_by` ) {
        F _ → {}
        T u → {
            ( __az_bind_str u 1 ( string_from tid ) )
            ( __az_bind_str u 2 ( string_from state ) )
            ?? ( sqlite_bind_int u 3 now ) { T _ → {} F _ → {} }
            ( __az_bind_str u 4 ( string_from by ) )
            = ok ( __az_run u )
        }
    }
    ^ ok
}

@ az_tenant_forget Database db s tid → v {
    ?? ( sqlite_prepare db `DELETE FROM tenants WHERE tid = ?1` ) {
        F _ → {}
        T d → {
            ( __az_bind_str d 1 ( string_from tid ) )
            : b _r ( __az_run d )
        }
    }
}

@ az_tenants_json Database db → Json {
    : Json arr ( json_arr_new )
    ?? ( sqlite_prepare db `SELECT tid, state, label, first_seen, decided_at, decided_by
         FROM tenants ORDER BY first_seen ASC` ) {
        F _ → {}
        T q → {
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has {
                            : String tid ( sqlite_column_text q 0 )
                            : String st ( sqlite_column_text q 1 )
                            : String lb ( sqlite_column_text q 2 )
                            : String by ( sqlite_column_text q 5 )
                            : Json o ( json_obj_new )
                            ( json_obj_set o `tenant` ( json_str_lit ( string_data tid ) ) )
                            ( json_obj_set o `state` ( json_str_lit ( string_data st ) ) )
                            ( json_obj_set o `label` ( json_str_lit ( string_data lb ) ) )
                            ( json_obj_set o `first_seen` ( json_int ( sqlite_column_int q 3 ) ) )
                            ( json_obj_set o `decided_at` ( json_int ( sqlite_column_int q 4 ) ) )
                            ( json_obj_set o `decided_by` ( json_str_lit ( string_data by ) ) )
                            ( json_arr_push arr o )
                            ( string_free tid ) ( string_free st )
                            ( string_free lb ) ( string_free by )
                        } { = done T }
                    }
                }
            }
        }
    }
    ^ arr
}

// May this tenant use the service? The owner tenant always may — it is the
// anchor the rest is decided from, and locking it out would leave nobody
// who could unlock anything. Everything else is a recorded decision, and a
// tenant nobody has decided on is recorded as pending and refused.
@ az_tenant_admitted s tid i now → b {
    ? > ( nurl_str_len tid ) 0 {} { ^ F }
    : s owner ( g_az_owner )
    ? > ( nurl_str_len owner ) 0 {
        : String ok ( __az_lower owner )
        : b is_owner == ( nurl_str_eq ( string_data ok ) tid ) 1
        ( string_free ok )
        ? is_owner { ^ T } {}
    } {}
    : ~ b admitted F
    ?? ( az_root_open ) {
        F _ → {}
        T db → {
            : String st ( az_tenant_note db tid `` now )
            = admitted == ( nurl_str_eq ( string_data st ) AZ_TENANT_ALLOWED ) 1
            ( string_free st )
        }
    }
    ^ admitted
}

// Seed the registry from the configuration file. Only ever ADDS: a
// deployment that lists tenants in its config gets them admitted without a
// dashboard, and a decision made in the dashboard is never undone by a
// restart.
@ az_seed_allowed s csv i now → v {
    ? > ( nurl_str_len csv ) 0 {} { ^ }
    : String list ( string_from csv )
    : ( Vec String ) parts ( string_split list `,` )
    ( string_free list )
    ?? ( az_root_open ) {
        F _ → {}
        T db → {
            : i n ( vec_len [String] parts )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] parts k ) {
                    T x → {
                        : String t ( __az_lower ( string_data x ) )
                        ? > ( string_len t ) 0 {
                            : String cur ( az_tenant_state db ( string_data t ) )
                            ? == ( nurl_str_eq ( string_data cur ) AZ_TENANT_ALLOWED ) 1 {} {
                                : b _r ( az_tenant_set_state db ( string_data t )
                                AZ_TENANT_ALLOWED `config` now )
                            }
                            ( string_free cur )
                        } {}
                        ( string_free t )
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
    }
    ( vec_free_with [String] parts \ String x → v { ( string_free x ) } )
}

// Bind an owned String and free it — sqlite_bind_text copies immediately,
// so the two belong together and separating them is how a leak gets in.
@ __az_bind_str Statement st i idx String v → v {
    ?? ( sqlite_bind_text st idx v ) { T _ → {} F _ → {} }
    ( string_free v )
}

// Run a statement to completion, discarding rows. T when it did not error.
@ __az_run Statement st → b {
    : ~ b ok T
    : ~ b done F
    ~ ! done {
        ?? ( sqlite_step st ) {
            F _ → { = ok F = done T }
            T has → { ? has {} { = done T } }
        }
    }
    ^ ok
}

// ── Users and roles ───────────────────────────────────────────────────

@ az_user_count Database db → i {
    : ~ i n 0
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM users` ) {
        F _ → {}
        T q → {
            ?? ( sqlite_step q ) {
                T has → { ? has { = n ( sqlite_column_int q 0 ) } {} }
                F _ → {}
            }
        }
    }
    ^ n
}

// The role recorded for `sub`, or "" when the organisation has never seen
// them.
@ az_user_role Database db s sub → String {
    : ~ String role ( string_new )
    ?? ( sqlite_prepare db `SELECT role FROM users WHERE sub = ?1` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from sub ) )
            ?? ( sqlite_step q ) {
                T has → {
                    ? has {
                        ( string_free role )
                        = role ( sqlite_column_text q 0 )
                    } {}
                }
                F _ → {}
            }
        }
    }
    ^ role
}

// Record that `sub` was here, and return the role they hold. The FIRST
// subject an organisation ever sees becomes its admin: there is nobody
// else who could grant it, and an organisation whose every user is a
// viewer can never appoint one.
@ az_user_touch Database db s sub s email s name i now → String {
    : String have ( az_user_role db sub )
    ? > ( string_len have ) 0 {
        ?? ( sqlite_prepare db `UPDATE users SET email = ?1, name = ?2, last_seen_at = ?3 WHERE sub = ?4` ) {
            F _ → {}
            T u → {
                ( __az_bind_str u 1 ( string_from email ) )
                ( __az_bind_str u 2 ( string_from name ) )
                ?? ( sqlite_bind_int u 3 now ) { T _ → {} F _ → {} }
                ( __az_bind_str u 4 ( string_from sub ) )
                : b _r ( __az_run u )
            }
        }
        ^ have
    } {}
    ( string_free have )
    : ~ s role AZ_ROLE_VIEWER
    ? == ( az_user_count db ) 0 { = role AZ_ROLE_ADMIN } {}
    ?? ( sqlite_prepare db `INSERT INTO users (sub, email, name, role, created_at, last_seen_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?5)` ) {
        F _ → {}
        T ins → {
            ( __az_bind_str ins 1 ( string_from sub ) )
            ( __az_bind_str ins 2 ( string_from email ) )
            ( __az_bind_str ins 3 ( string_from name ) )
            ( __az_bind_str ins 4 ( string_from role ) )
            ?? ( sqlite_bind_int ins 5 now ) { T _ → {} F _ → {} }
            : b _r ( __az_run ins )
        }
    }
    ^ ( string_from role )
}

@ az_user_set_role Database db s sub s role → b {
    ? | == ( nurl_str_eq role AZ_ROLE_ADMIN ) 1 == ( nurl_str_eq role AZ_ROLE_VIEWER ) 1 {} { ^ F }
    // The last admin may not demote themselves: an organisation with no
    // admin cannot appoint one, and the only repair is editing the
    // database by hand.
    ? == ( nurl_str_eq role AZ_ROLE_VIEWER ) 1 {
        : String cur ( az_user_role db sub )
        : b was_admin == ( nurl_str_eq ( string_data cur ) AZ_ROLE_ADMIN ) 1
        ( string_free cur )
        ? & was_admin <= ( az_admin_count db ) 1 { ^ F } {}
    } {}
    : ~ b ok F
    ?? ( sqlite_prepare db `UPDATE users SET role = ?1 WHERE sub = ?2` ) {
        F _ → {}
        T u → {
            ( __az_bind_str u 1 ( string_from role ) )
            ( __az_bind_str u 2 ( string_from sub ) )
            = ok ( __az_run u )
            ? ok { = ok > ( sqlite_changes db ) 0 } {}
        }
    }
    ^ ok
}

@ az_admin_count Database db → i {
    : ~ i n 0
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM users WHERE role = 'admin'` ) {
        F _ → {}
        T q → {
            ?? ( sqlite_step q ) {
                T has → { ? has { = n ( sqlite_column_int q 0 ) } {} }
                F _ → {}
            }
        }
    }
    ^ n
}

@ az_users_json Database db → Json {
    : Json arr ( json_arr_new )
    ?? ( sqlite_prepare db `SELECT sub, email, name, role, created_at, last_seen_at
         FROM users ORDER BY created_at ASC` ) {
        F _ → {}
        T q → {
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has {
                            : String sub ( sqlite_column_text q 0 )
                            : String em ( sqlite_column_text q 1 )
                            : String nm ( sqlite_column_text q 2 )
                            : String rl ( sqlite_column_text q 3 )
                            : Json o ( json_obj_new )
                            ( json_obj_set o `subject` ( json_str_lit ( string_data sub ) ) )
                            ( json_obj_set o `email` ( json_str_lit ( string_data em ) ) )
                            ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) )
                            ( json_obj_set o `role` ( json_str_lit ( string_data rl ) ) )
                            ( json_obj_set o `created_at` ( json_int ( sqlite_column_int q 4 ) ) )
                            ( json_obj_set o `last_seen_at` ( json_int ( sqlite_column_int q 5 ) ) )
                            ( json_arr_push arr o )
                            ( string_free sub ) ( string_free em )
                            ( string_free nm ) ( string_free rl )
                        } { = done T }
                    }
                }
            }
        }
    }
    ^ arr
}

// ── Model ownership ───────────────────────────────────────────────────

// The owner of `name`, or "" when the model has no row — UNOWNED, which is
// what every model created before this file existed looks like.
@ az_model_owner Database db s name → String {
    : ~ String owner ( string_new )
    ?? ( sqlite_prepare db `SELECT owner_sub FROM models WHERE name = ?1` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from name ) )
            ?? ( sqlite_step q ) {
                T has → {
                    ? has {
                        ( string_free owner )
                        = owner ( sqlite_column_text q 0 )
                    } {}
                }
                F _ → {}
            }
        }
    }
    ^ owner
}

// Claim `name` for `sub`. `force` reassigns a model that already has an
// owner (admin territory); without it an owned model is left alone and the
// call reports F.
@ az_model_claim Database db s name s sub i now b force → b {
    : b owned ( az_model_in_org db name )
    ? & owned ! force { ^ F } {}
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT INTO models (name, owner_sub, created_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(name) DO UPDATE SET owner_sub = excluded.owner_sub` ) {
        F _ → {}
        T ins → {
            ( __az_bind_str ins 1 ( string_from name ) )
            ( __az_bind_str ins 2 ( string_from sub ) )
            ?? ( sqlite_bind_int ins 3 now ) { T _ → {} F _ → {} }
            = ok ( __az_run ins )
        }
    }
    ^ ok
}

@ az_model_forget Database db s name → v {
    ?? ( sqlite_prepare db `DELETE FROM models WHERE name = ?1` ) {
        F _ → {}
        T d → {
            ( __az_bind_str d 1 ( string_from name ) )
            : b _r ( __az_run d )
        }
    }
}

// The model names `sub` owns. The listing route needs the whole set at
// once: asking per model would reopen the database once per row.
@ az_owned_names Database db s sub → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT name FROM models WHERE owner_sub = ?1` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from sub ) )
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                    }
                }
            }
        }
    }
    ^ out
}

// Every model name this organisation claims, owned by anyone in it. This is
// the admin's whole world: the store is flat and global, so "every model" is
// every model of every ORGANISATION, and an admin of one tenant must never
// be shown another's.
@ az_org_model_names Database db → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( sqlite_prepare db `SELECT name FROM models` ) {
        F _ → {}
        T q → {
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                    }
                }
            }
        }
    }
    ^ out
}

// Every model the organisation has a row for, owned by anyone. An admin
// listing needs this only to know which stored models are still unclaimed.
@ az_all_owned_json Database db → Json {
    : Json o ( json_obj_new )
    ?? ( sqlite_prepare db `SELECT name, owner_sub FROM models` ) {
        F _ → {}
        T q → {
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has {
                            : String nm ( sqlite_column_text q 0 )
                            : String ow ( sqlite_column_text q 1 )
                            ( json_obj_set o ( string_data nm ) ( json_str_lit ( string_data ow ) ) )
                            ( string_free nm ) ( string_free ow )
                        } { = done T }
                    }
                }
            }
        }
    }
    ^ o
}

// May this principal see the model at all? Admins see the whole
// organisation, including the unowned models nobody has claimed yet;
// a viewer sees exactly what it owns.
// A model belongs to an ORGANISATION, not to a person. Everyone in the
// organisation sees the same models; what differs is what they may do to
// them. That is the shape a shared service actually has — a colleague
// leaving must not take a production model with them — and it is why
// `models` has no owner column any more, only the database it sits in.
@ az_may_see Database db Principal p s name → b {
    ? . p authed {} { ^ F }
    // The store is FLAT: one directory of models for every organisation.
    // Membership is the whole scope. A model this organisation has not
    // claimed is not this organisation's, whoever is asking.
    ^ ( az_model_in_org db name )
}

// Does this organisation hold this model?
//
// Row EXISTENCE, not a non-empty creator: the two are different questions
// and conflating them means forgetting a person also forgets which
// organisation their models belonged to. `owner_sub` survives only as an
// audit trail of who first sent a point, and is blanked when they leave.
@ az_model_in_org Database db s name → b {
    : ~ b there F
    ?? ( sqlite_prepare db `SELECT 1 FROM models WHERE name = ?1` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from name ) )
            ?? ( sqlite_step q ) {
                T has → { = there has }
                F _ → {}
            }
        }
    }
    ^ there
}

// May this principal CHANGE it? Only an admin. A viewer sees the
// organisation's models and the data they have collected — that is what a
// viewer is for — but retraining rewrites forests, a margin edit changes
// every verdict, and a reset destroys history. None of that is viewing.
@ az_may_write Database db Principal p s name → b {
    ? ( principal_is_admin p ) {} { ^ F }
    ^ ( az_may_see db p name )
}

// ── Leaving ───────────────────────────────────────────────────────────
//
// A person may be forgotten. What that costs the organisation depends on
// who is left: an organisation with other members carries on without them,
// and an organisation whose last member leaves has nobody it could belong
// to, so it goes — database, models and keys.

@ az_user_delete Database db s sub → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `DELETE FROM users WHERE sub = ?1` ) {
        F _ → {}
        T d → {
            ( __az_bind_str d 1 ( string_from sub ) )
            = ok ( __az_run d )
            ? ok { = ok > ( sqlite_changes db ) 0 } {}
        }
    }
    ? ok {} { ^ F }
    // The keys they issued keep working: they are the ORGANISATION's
    // credentials, and a colleague leaving must not stop the data arriving.
    // What goes is the personal identifier attached to them, which is what
    // being forgotten means.
    ?? ( sqlite_prepare db `UPDATE api_keys SET owner_sub = '' WHERE owner_sub = ?1` ) {
        F _ → {}
        T u → {
            ( __az_bind_str u 1 ( string_from sub ) )
            : b _r ( __az_run u )
        }
    }
    ?? ( sqlite_prepare db `UPDATE models SET owner_sub = '' WHERE owner_sub = ?1` ) {
        F _ → {}
        T u2 → {
            ( __az_bind_str u2 1 ( string_from sub ) )
            : b _r ( __az_run u2 )
        }
    }
    ^ T
}

// Every model name this organisation holds, so a caller deleting the
// organisation knows what to remove from the store.
@ az_org_models_before_delete Database db → ( Vec String ) {
    ^ ( az_org_model_names db )
}

// Delete the organisation's database outright. The models themselves live
// in the shared store and are the caller's to remove — this only forgets
// who they belonged to, and doing both in one place would put a model
// deletion inside a function whose name says "database".
@ az_org_drop s org → b {
    : String p ( __az_db_path org )
    : ~ b ok T
    : !v IoErr r ( file_delete ( string_data p ) )
    ?? r { T _ → {} F _ → { = ok F } }
    // WAL and shared-memory sidecars, if the last writer left them.
    : String wal ( string_from ( string_data p ) )
    ( string_push_str wal `-wal` )
    : !v IoErr rw ( file_delete ( string_data wal ) )
    ?? rw { T _ → {} F _ → {} }
    ( string_free wal )
    : String shm ( string_from ( string_data p ) )
    ( string_push_str shm `-shm` )
    : !v IoErr rs ( file_delete ( string_data shm ) )
    ?? rs { T _ → {} F _ → {} }
    ( string_free shm )
    ( string_free p )
    ^ ok
}

// ── API keys ──────────────────────────────────────────────────────────
//
// Format: anok_<16 hex id>_<64 hex secret>. The id is a lookup handle and
// is stored in the clear; only a SHA-256 of the secret is persisted, so the
// database cannot hand anyone a working key.

: s AZ_KEY_PREFIX `anok_`

@ __az_hash_hex s secret → String {
    : ( Vec u ) msg ( bytes_from_str secret )
    : ( Vec u ) dig ( sha256_pure msg )
    ( vec_free [u] msg )
    : String hex ( bytes_to_hex dig )
    ( vec_free [u] dig )
    ^ hex
}

// Constant-time-ish comparison: equal lengths, and every byte examined
// whatever the first mismatch says. A hex digest is not a secret worth
// timing, but the habit is cheap and the alternative teaches the wrong one.
@ __az_hex_eq String a String b → b {
    : i n ( string_len a )
    ? == n ( string_len b ) {} { ^ F }
    : ~ i diff 0
    : ~ i k 0
    ~ < k n {
        ? == ( string_get a k ) ( string_get b k ) {} { = diff 1 }
        = k + k 1
    }
    ^ == diff 0
}

: KeyIssue {
    String key_id
    String secret  // the plaintext, which exists only here and in the response
}

@ key_issue_free KeyIssue k → v {
    ( string_free . k key_id )
    ( string_free . k secret )
}

@ az_key_create Database db s sub s label s role i now → KeyIssue {
    : String id ( rand_hex_str 16 )
    : String secret ( rand_hex_str 64 )
    : String hash ( __az_hash_hex ( string_data secret ) )
    ?? ( sqlite_prepare db `INSERT INTO api_keys (id, secret_hash, owner_sub, label, created_at, role)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)` ) {
        F _ → {}
        T ins → {
            ( __az_bind_str ins 1 ( string_from ( string_data id ) ) )
            ( __az_bind_str ins 2 hash )
            ( __az_bind_str ins 3 ( string_from sub ) )
            ( __az_bind_str ins 4 ( string_from label ) )
            ?? ( sqlite_bind_int ins 5 now ) { T _ → {} F _ → {} }
            ( __az_bind_str ins 6 ( string_from role ) )
            : b _r ( __az_run ins )
        }
    }
    // The token the caller presents: prefix, id, secret.
    : String token ( string_from AZ_KEY_PREFIX )
    ( string_push_str token ( string_data id ) )
    ( string_push_char token 95 )
    ( string_push_str token ( string_data secret ) )
    ( string_free secret )
    ^ @ KeyIssue { id token }
}

// Revoke one of the organisation's keys. No owner check: the key is the
// organisation's, and whoever happened to press the button that created it
// has no more claim on it than any other admin.
@ az_key_revoke Database db s id i now → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `UPDATE api_keys SET revoked_at = ?1
         WHERE id = ?2 AND revoked_at = 0` ) {
        F _ → {}
        T u → {
            ?? ( sqlite_bind_int u 1 now ) { T _ → {} F _ → {} }
            ( __az_bind_str u 2 ( string_from id ) )
            = ok ( __az_run u )
            ? ok { = ok > ( sqlite_changes db ) 0 } {}
        }
    }
    ^ ok
}

// The keys `sub` may see: their own, or every one in the organisation when
// `all` is set (an admin listing). Secrets are never in here.
// The organisation's keys. There is no per-person view of them, because
// there is no per-person ownership: a key is the ORGANISATION's credential,
// and only its admins have any business seeing that one exists.
@ az_keys_json Database db → Json {
    : Json arr ( json_arr_new )
    ?? ( sqlite_prepare db `SELECT id, owner_sub, label, created_at, last_used_at, revoked_at, role
         FROM api_keys ORDER BY created_at DESC` ) {
        F _ → {}
        T q → {
            : ~ b done F
            ~ ! done {
                ?? ( sqlite_step q ) {
                    F _ → { = done T }
                    T has → {
                        ? has {
                            : String id ( sqlite_column_text q 0 )
                            : String ow ( sqlite_column_text q 1 )
                            : String lb ( sqlite_column_text q 2 )
                            : Json o ( json_obj_new )
                            : String rl ( sqlite_column_text q 6 )
                            ( json_obj_set o `id` ( json_str_lit ( string_data id ) ) )
                            ( json_obj_set o `role` ( json_str_lit ( string_data rl ) ) )
                            ( json_obj_set o `created_by` ( json_str_lit ( string_data ow ) ) )
                            ( json_obj_set o `label` ( json_str_lit ( string_data lb ) ) )
                            ( json_obj_set o `created_at` ( json_int ( sqlite_column_int q 3 ) ) )
                            ( json_obj_set o `last_used_at` ( json_int ( sqlite_column_int q 4 ) ) )
                            ( json_obj_set o `revoked` ( json_bool > ( sqlite_column_int q 5 ) 0 ) )
                            ( json_arr_push arr o )
                            ( string_free id ) ( string_free ow )
                            ( string_free lb ) ( string_free rl )
                        } { = done T }
                    }
                }
            }
        }
    }
    ^ arr
}

// Split "anok_<id>_<secret>" into its two halves. F when the token is not
// of that shape, which is also how the resolver tells an API key from a JWT.
: KeyParts { b ok String kp_id String kp_secret }

@ __az_key_split s token → KeyParts {
    : i pn ( nurl_str_len AZ_KEY_PREFIX )
    : i n ( nurl_str_len token )
    : ~ b pre > n pn
    : ~ i k 0
    ~ & pre < k pn {
        ? == ( nurl_str_at token n k ) ( nurl_str_at AZ_KEY_PREFIX pn k ) {} { = pre F }
        = k + k 1
    }
    ? pre {} { ^ @ KeyParts { F ( string_new ) ( string_new ) } }
    : String id ( string_new )
    : ~ i j pn
    ~ & < j n != ( nurl_str_at token n j ) 95 {
        ( string_push_char id ( nurl_str_at token n j ) )
        = j + j 1
    }
    ? < j n {} {
        ( string_free id )
        ^ @ KeyParts { F ( string_new ) ( string_new ) }
    }
    = j + j 1
    : String sec ( string_new )
    ~ < j n { ( string_push_char sec ( nurl_str_at token n j ) ) = j + j 1 }
    ? & > ( string_len id ) 0 > ( string_len sec ) 0 {} {
        ( string_free id ) ( string_free sec )
        ^ @ KeyParts { F ( string_new ) ( string_new ) }
    }
    ^ @ KeyParts { T id sec }
}

@ key_parts_free KeyParts k → v {
    ( string_free . k kp_id )
    ( string_free . k kp_secret )
}

// Resolve a presented key against one organisation's database. The
// principal comes back unauthenticated when the id is unknown, the secret
// does not match, the key is revoked, or its owner has since been removed.
@ az_key_principal Database db s org KeyParts kp i now → Principal {
    : String want ( __az_hash_hex ( string_data . kp kp_secret ) )
    : ~ Principal out ( principal_anon )
    ?? ( sqlite_prepare db `SELECT secret_hash, owner_sub, '', '', role
         FROM api_keys WHERE id = ?1 AND revoked_at = 0` ) {
        F _ → {}
        T q → {
            ( __az_bind_str q 1 ( string_from ( string_data . kp kp_id ) ) )
            ?? ( sqlite_step q ) {
                T has → {
                    ? has {
                        : String got ( sqlite_column_text q 0 )
                        ? ( __az_hex_eq got want ) {
                            ( principal_free out )
                            = out @ Principal {
                                T T
                                ( string_from org )
                                ( sqlite_column_text q 1 )
                                ( sqlite_column_text q 2 )
                                ( sqlite_column_text q 3 )
                                ( sqlite_column_text q 4 )
                                ( string_from ( string_data . kp kp_id ) )
                            }
                        } {}
                        ( string_free got )
                    } {}
                }
                F _ → {}
            }
        }
    }
    ( string_free want )
    ? . out authed {
        ?? ( sqlite_prepare db `UPDATE api_keys SET last_used_at = ?1 WHERE id = ?2` ) {
            F _ → {}
            T u → {
                ?? ( sqlite_bind_int u 1 now ) { T _ → {} F _ → {} }
                ( __az_bind_str u 2 ( string_from ( string_data . kp kp_id ) ) )
                : b _r ( __az_run u )
            }
        }
    } {}
    ^ out
}

// Every organisation database in the store, by org id. An API key names no
// organisation — the id alone would have to be globally unique to do that
// without a second index — so a presented key is tried against each. There
// is one database per tenant and a key arrives a few times a minute, so
// the scan is cheaper than a second source of truth that could disagree.
@ __az_org_ids → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String dir ( __az_orgs_dir )
    : !( Vec String ) IoErr r ( dir_list ( string_data dir ) )
    ( string_free dir )
    ?? r {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : i ln ( string_len nm )
                        ? > ln 3 {
                            : b isdb & & == ( string_get nm - ln 3 ) 46
                            == ( string_get nm - ln 2 ) 100
                            == ( string_get nm - ln 1 ) 98
                            ? isdb {
                                : String base ( string_new )
                                : ~ i j 0
                                ~ < j - ln 3 { ( string_push_char base ( string_get nm j ) ) = j + j 1 }
                                ( vec_push [String] out base )
                            } {}
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ^ out
}

// ── Resolving a request ───────────────────────────────────────────────

// The provider, discovered on first use. None when discovery fails, which
// makes every token unverifiable — a closed door, not an open one.
@ __az_provider → ?*OidcProvider {
    ? != g_az_prov_addr 0 {
        ^ @ ?*OidcProvider { T # *OidcProvider g_az_prov_addr }
    } {}
    ? g_az_multi { ^ ( __az_provider_multi ) } {}
    ?? ( oidc_provider_discover ( g_az_issuer ) ) {
        T p → {
            = g_az_prov_addr # i p
            ^ @ ?*OidcProvider { T p }
        }
        F _ → { ^ @ ?*OidcProvider { F } }
    }
}

// The multi-tenant provider. The discovery document is read here rather
// than through oidc_discover, because that call cross-checks the
// document's issuer against the one asked for and a `{tenantid}` template
// can never match. Two fields are taken from it: the issuer template every
// token's `iss` is then measured against, and the JWKS URI. Nothing about
// any particular provider is hardcoded — the template and the key set both
// come from the provider's own document.
@ __az_provider_multi → ?*OidcProvider {
    : String url ( oidc_discovery_url ( g_az_issuer ) )
    : *HttpClient hc ( http_client_new )
    : ~ String body ( string_new )
    : ~ b got F
    ?? ( http_client_get hc ( string_data url ) ) {
        T r → {
            ? & >= . r status 200 < . r status 300 {
                ( string_free body )
                = body ( bytes_to_str . r body )
                = got T
            } {}
            ( http_response_free r )
        }
        F _ → {}
    }
    ( http_client_free hc )
    ( string_free url )
    ? got {} { ( string_free body ) ^ @ ?*OidcProvider { F } }

    : ~ String tmpl ( string_new )
    : ~ String jwks ( string_new )
    ?? ( json_parse ( string_data body ) ) {
        T j → {
            ?? ( json_obj_get j `issuer` ) {
                T v → { ? ( json_is_str v ) { ( string_free tmpl ) = tmpl ( string_from ( json_str_data v ) ) } {} }
                F _ → {}
            }
            ?? ( json_obj_get j `jwks_uri` ) {
                T v → { ? ( json_is_str v ) { ( string_free jwks ) = jwks ( string_from ( json_str_data v ) ) } {} }
                F _ → {}
            }
            ( json_free j )
        }
        F _ → {}
    }
    ( string_free body )
    ? & > ( string_len tmpl ) 0 > ( string_len jwks ) 0 {} {
        ( string_free tmpl ) ( string_free jwks )
        ^ @ ?*OidcProvider { F }
    }

    : *OidcProvider p ( oidc_provider_new ( g_az_issuer ) )
    ( oidc_provider_set_jwks_uri p ( string_data jwks ) )
    ( string_free jwks )
    // tmpl backs g_az_iss_tmpl for the process's lifetime; not freed.
    = g_az_iss_tmpl ( string_data tmpl )
    = g_az_prov_addr # i p
    ^ @ ?*OidcProvider { T p }
}

// The issuer a token from tenant `tid` must carry: the provider's own
// template with `{tenantid}` replaced. Empty when there is no template or
// no tenant, which is a refusal rather than a wildcard.
@ __az_issuer_for s tid → String {
    : i tn ( nurl_str_len g_az_iss_tmpl )
    ? & > tn 0 > ( nurl_str_len tid ) 0 {} { ^ ( string_new ) }
    : s needle `{tenantid}`
    : i nn ( nurl_str_len needle )
    : String out ( string_new )
    : ~ i k 0
    : ~ b hit F
    ~ < k tn {
        : ~ b here <= + k nn tn
        ? here {
            : ~ i j 0
            ~ & here < j nn {
                ? == ( nurl_str_at g_az_iss_tmpl tn + k j ) ( nurl_str_at needle nn j ) {} { = here F }
                = j + j 1
            }
        } {}
        ? here {
            ( string_push_str out tid )
            = k + k nn
            = hit T
        } {
            ( string_push_char out ( nurl_str_at g_az_iss_tmpl tn k ) )
            = k + k 1
        }
    }
    ? hit {} { ( string_free out ) ^ ( string_new ) }
    ^ out
}

// Is this tenant admitted? An empty allowlist admits every one — what
// "multi-tenant" asks for, and a deliberate setting rather than a default
// nobody saw.
@ __az_tenant_allowed s tid → b {
    : i n ( nurl_str_len ( g_az_allowed ) )
    ? > n 0 {} { ^ T }
    : String list ( string_from ( g_az_allowed ) )
    : ( Vec String ) parts ( string_split list `,` )
    ( string_free list )
    : ~ b ok F
    : i np ( vec_len [String] parts )
    : ~ i k 0
    ~ < k np {
        ?? ( vec_get [String] parts k ) {
            T x → {
                : String t ( __az_lower ( string_data x ) )
                ? == ( nurl_str_eq ( string_data t ) tid ) 1 { = ok T } {}
                ( string_free t )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String x → v { ( string_free x ) } )
    ^ ok
}

// The `tid` a token claims, read WITHOUT verifying it. Safe only for
// choosing which issuer to then demand: the verification that follows
// enforces that the token really carries that issuer, and both claims sit
// inside the same signature.
@ __az_unverified_tid s token → String {
    ?? ( jws_payload_unverified token ) {
        T j → {
            : ~ String tid ( string_new )
            ?? ( json_obj_get j `tid` ) {
                T v → { ? ( json_is_str v ) { ( string_free tid ) = tid ( string_from ( json_str_data v ) ) } {} }
                F _ → {}
            }
            ( json_free j )
            ^ tid
        }
        F _ → { ^ ( string_new ) }
    }
}

// Verify a bearer JWT and turn it into a principal, creating the
// organisation's database and its first admin on the way.
//
// The audience is tried twice: the configured one (an access token for
// this API) and then the client id (the id token the same sign-in
// produced). A dashboard that sends either is a dashboard that works, and
// the two are equally ours — the alternative is a 401 whose only clue is
// which of two GUIDs the token happened to name.
@ __az_token_principal s token i now → Principal {
    // The allowlist first: whether this service admits the token's tenant
    // at all needs no provider, no network and no key set. Asking the
    // identity provider before refusing is a round trip spent on an answer
    // already known — and, in a test, a lookup that fails for the wrong
    // reason.
    ? g_az_multi {
        : String tid_pre ( __az_unverified_tid token )
        // The registry decides, and a tenant nobody has decided on is
        // recorded as pending and refused. Auto-provisioning an
        // organisation for whoever knocks is how a multi-tenant service
        // fills a disk with strangers.
        : b ok_pre ( az_tenant_admitted ( string_data tid_pre ) now )
        ( string_free tid_pre )
        ? ok_pre {} {
            ( __az_set_last_err `this organisation is not approved for this service yet` )
            ^ ( principal_anon )
        }
    } {}
    ?? ( __az_provider ) {
        F → {
            ( __az_set_last_err `the identity provider could not be reached` )
            ^ ( principal_anon )
        }
        T p → {
            // Which issuer this token must carry. Single-tenant: the one
            // configured. Multi-tenant: the provider's own template with
            // the token's tenant substituted — the configured value is
            // then an AUTHORITY (.../organizations/v2.0), which no token
            // ever names, so comparing against it refuses everything.
            : ~ String want_iss ( string_from ( g_az_issuer ) )
            ? g_az_multi {
                : String tid0 ( __az_unverified_tid token )
                ( string_free want_iss )
                = want_iss ( __az_issuer_for ( string_data tid0 ) )
                ( string_free tid0 )
            } {}
            ? > ( string_len want_iss ) 0 {} {
                ( __az_set_last_err `the token names no tenant to derive an issuer from` )
                ( string_free want_iss )
                ^ ( principal_anon )
            }

            // Two spellings of this application are ours, and which one a
            // token carries is the provider's choice: an Entra v2 access
            // token names the bare client id, while the app-id URI is what
            // the scope was requested under. Trying both is the difference
            // between a dashboard that works and a 401 whose only clue is
            // which spelling the token happened to use.
            : ~ ? OidcIdentity got @ ?OidcIdentity { F }
            : ~ i attempt 0
            ~ < attempt 2 {
                : ~ s aud ( g_az_audience )
                ? == attempt 1 { = aud ( g_az_client_id ) } {}
                : *OidcPolicy pol ( oidc_policy_new ( string_data want_iss ) aud )
                ?? ( oidc_verify_token p pol token ) {
                    T id → {
                        = got @ ?OidcIdentity { T id }
                        ( __az_set_last_err `` )
                        = attempt 2
                    }
                    F e → {
                        // Keep the LAST failure: the first is usually just
                        // the audience spelling we did not try first.
                        : String why ( string_from ( oauth_err_name e ) )
                        ( string_push_str why `: ` )
                        ( string_push_str why ( oidc_provider_last_error p ) )
                        ( __az_set_last_err ( string_data why ) )
                        ( string_free why )
                        = attempt + attempt 1
                    }
                }
                ( oidc_policy_free pol )
            }
            ( string_free want_iss )
            ?? got {
                F → { ^ ( principal_anon ) }
                T id → {
                    // The tenant is the organisation. A provider that
                    // publishes none puts every one of its users in one
                    // organisation keyed on the issuer, which is the
                    // honest reading of "this provider is the org".
                    : String tid ( oidc_identity_claim id `tid` )
                    // Re-check the allowlist against the VERIFIED tenant.
                    // The earlier check only chose which issuer to demand;
                    // this is the reading with a signature behind it.
                    ? g_az_multi {
                        ? ( az_tenant_admitted ( string_data tid ) now ) {} {
                            ( __az_set_last_err `this organisation is not approved for this service yet` )
                            ( string_free tid )
                            ( oidc_identity_free id )
                            ^ ( principal_anon )
                        }
                    } {}
                    : ~ String orgsrc ( string_new )
                    ? > ( string_len tid ) 0 {
                        ( string_free orgsrc )
                        = orgsrc ( string_from ( string_data tid ) )
                    } {
                        ( string_free orgsrc )
                        = orgsrc ( string_from ( string_data . id issuer ) )
                    }
                    ( string_free tid )
                    : String org ( __az_org_key ( string_data orgsrc ) )
                    ( string_free orgsrc )

                    : ~ Principal out ( principal_anon )
                    ?? ( az_db_open ( string_data org ) ) {
                        F _ → {}
                        T db → {
                            : String role ( az_user_touch db ( string_data . id subject )
                            ( string_data . id email ) ( string_data . id name ) now )
                            ( principal_free out )
                            = out @ Principal {
                                T F
                                ( string_from ( string_data org ) )
                                ( string_from ( string_data . id subject ) )
                                ( string_from ( string_data . id email ) )
                                ( string_from ( string_data . id name ) )
                                role
                                ( string_new )
                            }
                        }
                    }
                    ( string_free org )
                    ( oidc_identity_free id )
                    ^ out
                }
            }
        }
    }
}

// An API key names no organisation, so every organisation is asked.
@ __az_key_principal_any KeyParts kp i now → Principal {
    : ( Vec String ) orgs ( __az_org_ids )
    : ~ Principal out ( principal_anon )
    : i n ( vec_len [String] orgs )
    : ~ i k 0
    ~ < k n {
        ? . out authed {} {
            ?? ( vec_get [String] orgs k ) {
                T org → {
                    ?? ( az_db_open ( string_data org ) ) {
                        F _ → {}
                        T db → {
                            : Principal cand ( az_key_principal db ( string_data org ) kp now )
                            ? . cand authed {
                                ( principal_free out )
                                = out cand
                            } { ( principal_free cand ) }
                        }
                    }
                }
                F _ → {}
            }
        }
        = k + k 1
    }
    ( vec_free_with [String] orgs \ String x → v { ( string_free x ) } )
    ^ out
}

// The one entry point the service uses: turn a request into a principal.
// With authentication off this is an admin of the `local` organisation,
// which is what keeps every existing deployment working unchanged.
@ authz_principal_at HttpRequest req i now → Principal {
    ? ( anomaly_authz_enabled ) {} { ^ ( principal_public_admin ) }
    : ~ String tok ( string_new )
    ?? ( parse_bearer_auth req ) {
        T t → { ( string_free tok ) = tok t }
        F → {
            // A key may also arrive in its own header, because an
            // Authorization header is awkward to set in some of the
            // producers that will carry one.
            ?? ( header_get . req headers `x-api-key` ) {
                T v → { ( string_free tok ) = tok v }
                F → {}
            }
        }
    }
    ? > ( string_len tok ) 0 {} {
        ( string_free tok )
        ^ ( principal_anon )
    }
    : KeyParts kp ( __az_key_split ( string_data tok ) )
    : ~ Principal out ( principal_anon )
    ? . kp ok {
        ( principal_free out )
        = out ( __az_key_principal_any kp now )
    } {
        ( principal_free out )
        = out ( __az_token_principal ( string_data tok ) now )
    }
    ( key_parts_free kp )
    ( string_free tok )
    ^ out
}

@ authz_principal HttpRequest req → Principal {
    ^ ( authz_principal_at req ( now_seconds ) )
}
