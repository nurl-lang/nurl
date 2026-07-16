// registry/db.nu — SQLite persistence: the single source of truth.
//
// Everything the registry knows lives here: users, tokens (peppered
// SHA-256 hashes only — never plaintext), package ownership, immutable
// versions with their tarball checksums, and per-version dependency
// requirements. The wire-facing index JSON (`/index/<name>.json`) is
// RENDERED from these tables on demand — there is no second copy to
// drift out of sync (the Cloudflare Worker this replaces dual-wrote an
// index object next to the DB; this design removes that hazard).
//
// Connections are opened per request (WAL + busy timeout), which makes
// every handler thread-safe at any worker-pool size without a shared
// handle. Opening a SQLite database is microseconds; registry traffic
// doesn't notice.
//
// All query helpers return sentinel values on failure (-1 / "" / F) and
// log nothing — the service layer decides what a failure means on the
// wire (usually a 500).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`

// One statement per exec call — sqlite_exec handles compound SQL, but
// keeping the schema as discrete statements makes a failure traceable.
@ __reg_schema → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `CREATE TABLE IF NOT EXISTS users (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        github_id  INTEGER UNIQUE,
        login      TEXT    NOT NULL UNIQUE,
        created_at INTEGER NOT NULL)` ) )
    ( vec_push [String] out ( string_from `CREATE TABLE IF NOT EXISTS tokens (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id      INTEGER NOT NULL REFERENCES users(id),
        token_hash   TEXT    NOT NULL UNIQUE,
        name         TEXT    NOT NULL,
        created_at   INTEGER NOT NULL,
        last_used_at INTEGER)` ) )
    ( vec_push [String] out ( string_from `CREATE TABLE IF NOT EXISTS packages (
        name          TEXT    PRIMARY KEY,
        owner_user_id INTEGER NOT NULL REFERENCES users(id),
        created_at    INTEGER NOT NULL)` ) )
    // published_at / created_at are epoch SECONDS (__reg_now). The
    // Cloudflare Worker's D1 stores epoch MILLISECONDS — any data
    // migration from D1 into this schema must divide by 1000.
    ( vec_push [String] out ( string_from `CREATE TABLE IF NOT EXISTS versions (
        name         TEXT    NOT NULL REFERENCES packages(name),
        version      TEXT    NOT NULL,
        checksum     TEXT    NOT NULL,
        yanked       INTEGER NOT NULL DEFAULT 0,
        published_by INTEGER NOT NULL REFERENCES users(id),
        published_at INTEGER NOT NULL,
        PRIMARY KEY (name, version))` ) )
    ( vec_push [String] out ( string_from `CREATE TABLE IF NOT EXISTS deps (
        name     TEXT NOT NULL,
        version  TEXT NOT NULL,
        dep_name TEXT NOT NULL,
        dep_req  TEXT NOT NULL,
        FOREIGN KEY (name, version) REFERENCES versions(name, version))` ) )
    ( vec_push [String] out ( string_from `CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id)` ) )
    ( vec_push [String] out ( string_from `CREATE INDEX IF NOT EXISTS idx_versions_name ON versions(name)` ) )
    ( vec_push [String] out ( string_from `CREATE INDEX IF NOT EXISTS idx_deps_nv ON deps(name, version)` ) )
    ^ out
}

// Open (creating on first use), harden, and migrate the registry DB.
@ reg_db_open s path → !Database SqliteErr {
    : !Database SqliteErr dr ( sqlite_open path )
    ?? dr {
        F e → ^ @ !Database SqliteErr { F e }
        T db → {
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA foreign_keys=ON` ) { T _ → {} F _ → {} }
            : ( Vec String ) stmts ( __reg_schema )
            : i n ( vec_len [String] stmts )
            : ~ i k 0
            : ~ b failed F
            ~ < k n {
                : ?String so ( vec_get [String] stmts k )
                ?? so {
                    T sq → {
                        ?? ( sqlite_exec db ( string_data sq ) ) { T _ → {} F _ → { = failed T } }
                        ( string_free sq )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [String] stmts )
            ? failed {
                ^ @ !Database SqliteErr { F # SqliteErr SqliteMisuse }
            } {}
            ^ @ !Database SqliteErr { T db }
        }
    }
}

// ── Small statement helpers ───────────────────────────────────────────

// Run a prepared statement to completion, ignoring rows. Returns T on
// SQLITE_DONE, F on any error. Finalizes the statement.
@ __reg_run Statement st → b {
    : ~ b ok T
    : ~ b more T
    ~ more {
        ?? ( sqlite_step st ) {
            T has → { ? ! has { = more F } {} }
            F _ → { = ok F = more F }
        }
    }
    ^ ok
}

// Step once expecting a row; T = row available.
@ __reg_row Statement st → b {
    ?? ( sqlite_step st ) {
        T has → ^ has
        F _ → ^ F
    }
}

// ── Users & tokens ────────────────────────────────────────────────────

// User id for `login`, or -1.
@ reg_db_user_by_login Database db s login → i {
    : ~ i uid -1
    ?? ( sqlite_prepare db `SELECT id FROM users WHERE login = ?1` ) {
        T st → {
            : String lv ( string_from login )
            ?? ( sqlite_bind_text st 1 lv ) { T _ → {} F _ → {} }
            ( string_free lv )
            ? ( __reg_row st ) { = uid ( sqlite_column_int st 0 ) } {}
        }
        F _ → {}
    }
    ^ uid
}

// Create a local (non-GitHub) user; returns its id, or -1. Idempotent:
// an existing login is returned as-is.
@ reg_db_user_ensure Database db s login i now → i {
    : i have ( reg_db_user_by_login db login )
    ? >= have 0 { ^ have } {}
    : ~ i uid -1
    ?? ( sqlite_prepare db `INSERT INTO users (login, created_at) VALUES (?1, ?2)` ) {
        T st → {
            : String lv ( string_from login )
            ?? ( sqlite_bind_text st 1 lv ) { T _ → {} F _ → {} }
            ( string_free lv )
            ?? ( sqlite_bind_int st 2 now ) { T _ → {} F _ → {} }
            ? ( __reg_run st ) { = uid ( sqlite_last_insert_rowid db ) } {}
        }
        F _ → {}
    }
    ^ uid
}

// Upsert a GitHub identity (github_id is the stable key; login follows
// the GitHub account). Returns the user id, or -1.
@ reg_db_user_upsert_github Database db i github_id s login i now → i {
    ?? ( sqlite_prepare db `INSERT INTO users (github_id, login, created_at) VALUES (?1, ?2, ?3)
        ON CONFLICT(github_id) DO UPDATE SET login = excluded.login` ) {
        T st → {
            ?? ( sqlite_bind_int st 1 github_id ) { T _ → {} F _ → {} }
            : String lv ( string_from login )
            ?? ( sqlite_bind_text st 2 lv ) { T _ → {} F _ → {} }
            ( string_free lv )
            ?? ( sqlite_bind_int st 3 now ) { T _ → {} F _ → {} }
            ? ! ( __reg_run st ) { ^ -1 } {}
        }
        F _ → ^ -1
    }
    : ~ i uid -1
    ?? ( sqlite_prepare db `SELECT id FROM users WHERE github_id = ?1` ) {
        T st → {
            ?? ( sqlite_bind_int st 1 github_id ) { T _ → {} F _ → {} }
            ? ( __reg_row st ) { = uid ( sqlite_column_int st 0 ) } {}
        }
        F _ → {}
    }
    ^ uid
}

// `login` of user `uid`; "" when absent.
@ reg_db_login_of Database db i uid → String {
    : ~ String out ( string_new )
    ?? ( sqlite_prepare db `SELECT login FROM users WHERE id = ?1` ) {
        T st → {
            ?? ( sqlite_bind_int st 1 uid ) { T _ → {} F _ → {} }
            ? ( __reg_row st ) {
                ( string_free out )
                = out ( sqlite_column_text st 0 )
            } {}
        }
        F _ → {}
    }
    ^ out
}

// Store a token hash for a user.
@ reg_db_token_insert Database db i uid s token_hash s label i now → b {
    ?? ( sqlite_prepare db `INSERT INTO tokens (user_id, token_hash, name, created_at) VALUES (?1, ?2, ?3, ?4)` ) {
        T st → {
            ?? ( sqlite_bind_int st 1 uid ) { T _ → {} F _ → {} }
            : String hv ( string_from token_hash )
            ?? ( sqlite_bind_text st 2 hv ) { T _ → {} F _ → {} }
            ( string_free hv )
            : String nv ( string_from label )
            ?? ( sqlite_bind_text st 3 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            ?? ( sqlite_bind_int st 4 now ) { T _ → {} F _ → {} }
            ^ ( __reg_run st )
        }
        F _ → ^ F
    }
}

// Resolve a token hash to its user id (or -1) and bump last_used_at.
@ reg_db_auth Database db s token_hash i now → i {
    : ~ i uid -1
    : ~ i tid -1
    ?? ( sqlite_prepare db `SELECT user_id, id FROM tokens WHERE token_hash = ?1` ) {
        T st → {
            : String hv ( string_from token_hash )
            ?? ( sqlite_bind_text st 1 hv ) { T _ → {} F _ → {} }
            ( string_free hv )
            ? ( __reg_row st ) {
                = uid ( sqlite_column_int st 0 )
                = tid ( sqlite_column_int st 1 )
            } {}
        }
        F _ → {}
    }
    ? >= tid 0 {
        ?? ( sqlite_prepare db `UPDATE tokens SET last_used_at = ?1 WHERE id = ?2` ) {
            T st → {
                ?? ( sqlite_bind_int st 1 now ) { T _ → {} F _ → {} }
                ?? ( sqlite_bind_int st 2 tid ) { T _ → {} F _ → {} }
                : b _ok ( __reg_run st )
            }
            F _ → {}
        }
    } {}
    ^ uid
}

// Delete the token row matching `token_hash`; T when one was deleted.
@ reg_db_token_delete Database db s token_hash → b {
    : ~ b deleted F
    ?? ( sqlite_prepare db `DELETE FROM tokens WHERE token_hash = ?1` ) {
        T st → {
            : String hv ( string_from token_hash )
            ?? ( sqlite_bind_text st 1 hv ) { T _ → {} F _ → {} }
            ( string_free hv )
            ? ( __reg_run st ) {
                ? > ( sqlite_changes db ) 0 { = deleted T } {}
            } {}
        }
        F _ → {}
    }
    ^ deleted
}

// ── Packages & versions ───────────────────────────────────────────────

// Owner user id of `name`, or -1 when the package doesn't exist yet.
@ reg_db_pkg_owner Database db s name → i {
    : ~ i uid -1
    ?? ( sqlite_prepare db `SELECT owner_user_id FROM packages WHERE name = ?1` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            ? ( __reg_row st ) { = uid ( sqlite_column_int st 0 ) } {}
        }
        F _ → {}
    }
    ^ uid
}

@ reg_db_pkg_insert Database db s name i owner_uid i now → b {
    ?? ( sqlite_prepare db `INSERT INTO packages (name, owner_user_id, created_at) VALUES (?1, ?2, ?3)` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            ?? ( sqlite_bind_int st 2 owner_uid ) { T _ → {} F _ → {} }
            ?? ( sqlite_bind_int st 3 now ) { T _ → {} F _ → {} }
            ^ ( __reg_run st )
        }
        F _ → ^ F
    }
}

@ reg_db_version_exists Database db s name s version → b {
    : ~ b found F
    ?? ( sqlite_prepare db `SELECT 1 FROM versions WHERE name = ?1 AND version = ?2` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : String vv ( string_from version )
            ?? ( sqlite_bind_text st 2 vv ) { T _ → {} F _ → {} }
            ( string_free vv )
            ? ( __reg_row st ) { = found T } {}
        }
        F _ → {}
    }
    ^ found
}

@ reg_db_version_insert Database db s name s version s checksum i publisher_uid i now → b {
    ?? ( sqlite_prepare db `INSERT INTO versions (name, version, checksum, yanked, published_by, published_at)
        VALUES (?1, ?2, ?3, 0, ?4, ?5)` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : String vv ( string_from version )
            ?? ( sqlite_bind_text st 2 vv ) { T _ → {} F _ → {} }
            ( string_free vv )
            : String cv ( string_from checksum )
            ?? ( sqlite_bind_text st 3 cv ) { T _ → {} F _ → {} }
            ( string_free cv )
            ?? ( sqlite_bind_int st 4 publisher_uid ) { T _ → {} F _ → {} }
            ?? ( sqlite_bind_int st 5 now ) { T _ → {} F _ → {} }
            ^ ( __reg_run st )
        }
        F _ → ^ F
    }
}

@ reg_db_dep_insert Database db s name s version s dep_name s dep_req → b {
    ?? ( sqlite_prepare db `INSERT INTO deps (name, version, dep_name, dep_req) VALUES (?1, ?2, ?3, ?4)` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : String vv ( string_from version )
            ?? ( sqlite_bind_text st 2 vv ) { T _ → {} F _ → {} }
            ( string_free vv )
            : String dn ( string_from dep_name )
            ?? ( sqlite_bind_text st 3 dn ) { T _ → {} F _ → {} }
            ( string_free dn )
            : String dr ( string_from dep_req )
            ?? ( sqlite_bind_text st 4 dr ) { T _ → {} F _ → {} }
            ( string_free dr )
            ^ ( __reg_run st )
        }
        F _ → ^ F
    }
}

// Flip the yanked flag; T when a row changed.
@ reg_db_version_set_yanked Database db s name s version b yanked → b {
    : ~ b changed F
    ?? ( sqlite_prepare db `UPDATE versions SET yanked = ?1 WHERE name = ?2 AND version = ?3` ) {
        T st → {
            : ~ i yv 0
            ? yanked { = yv 1 } {}
            ?? ( sqlite_bind_int st 1 yv ) { T _ → {} F _ → {} }
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 2 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : String vv ( string_from version )
            ?? ( sqlite_bind_text st 3 vv ) { T _ → {} F _ → {} }
            ( string_free vv )
            ? ( __reg_run st ) {
                ? > ( sqlite_changes db ) 0 { = changed T } {}
            } {}
        }
        F _ → {}
    }
    ^ changed
}

// ── Wire JSON (rendered from the tables) ──────────────────────────────

// Dependency array for one version: [ { "name": n, "req": r }, ... ]
@ reg_db_deps_json Database db s name s version → Json {
    : Json arr ( json_arr_new )
    ?? ( sqlite_prepare db `SELECT dep_name, dep_req FROM deps WHERE name = ?1 AND version = ?2 ORDER BY rowid` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : String vv ( string_from version )
            ?? ( sqlite_bind_text st 2 vv ) { T _ → {} F _ → {} }
            ( string_free vv )
            : ~ b more T
            ~ more {
                ? ( __reg_row st ) {
                    : String dn ( sqlite_column_text st 0 )
                    : String dr ( sqlite_column_text st 1 )
                    : Json dobj ( json_obj_new )
                    : b _a ( json_obj_set dobj `name` ( json_str_lit ( string_data dn ) ) )
                    : b _b ( json_obj_set dobj `req` ( json_str_lit ( string_data dr ) ) )
                    : b _c ( json_arr_push arr dobj )
                    ( string_free dn )
                    ( string_free dr )
                } { = more F }
            }
        }
        F _ → {}
    }
    ^ arr
}

// The package index document the client fetches at /index/<name>.json:
//   { "name": ..., "versions": [ { version, checksum, yanked, deps } ] }
// "" when the package has no versions (the route then 404s).
@ reg_db_index_json Database db s name → String {
    : Json varr ( json_arr_new )
    : ~ i count 0
    ?? ( sqlite_prepare db `SELECT version, checksum, yanked FROM versions WHERE name = ?1 ORDER BY published_at, rowid` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : ~ b more T
            ~ more {
                ? ( __reg_row st ) {
                    : String ver ( sqlite_column_text st 0 )
                    : String sum ( sqlite_column_text st 1 )
                    : i yk ( sqlite_column_int st 2 )
                    : Json vobj ( json_obj_new )
                    : b _a ( json_obj_set vobj `version` ( json_str_lit ( string_data ver ) ) )
                    : b _b ( json_obj_set vobj `checksum` ( json_str_lit ( string_data sum ) ) )
                    : b _c ( json_obj_set vobj `yanked` ( json_bool != yk 0 ) )
                    : b _d ( json_obj_set vobj `deps` ( reg_db_deps_json db name ( string_data ver ) ) )
                    : b _e ( json_arr_push varr vobj )
                    ( string_free ver )
                    ( string_free sum )
                    = count + count 1
                } { = more F }
            }
        }
        F _ → {}
    }
    ? == count 0 {
        ( json_free varr )
        ^ ( string_new )
    } {}
    : Json root ( json_obj_new )
    : b _a ( json_obj_set root `name` ( json_str_lit name ) )
    : b _b ( json_obj_set root `versions` varr )
    : String out ( json_stringify root )
    ( json_free root )
    ^ out
}

// Strip SQL LIKE metacharacters from a raw query (mirrors the Worker:
// the query matches literally, wrapped in %...%).
@ __reg_like_pattern s q → String {
    : String out ( string_with_cap + ( nurl_str_len q ) 2 )
    ( string_push_char out 37 )  // %
    : i n ( nurl_str_len q )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get q k )
        ? | | == c 37 == c 95 == c 92 {} {  // strip % _ \
            ( string_push_char out c )
        }
        = k + k 1
    }
    ( string_push_char out 37 )
    ^ out
}

// Catalog rows as JSON: [ { "name": n, "version": latest-or-null } ]
// `latest` = most recently published non-yanked version (display only).
@ reg_db_catalog_json Database db s q i limit → Json {
    : Json arr ( json_arr_new )
    ?? ( sqlite_prepare db `SELECT p.name,
            (SELECT v.version FROM versions v WHERE v.name = p.name AND v.yanked = 0
              ORDER BY v.published_at DESC, v.rowid DESC LIMIT 1) AS latest
        FROM packages p WHERE p.name LIKE ?1 ORDER BY p.name LIMIT ?2` ) {
        T st → {
            : String pat ( __reg_like_pattern q )
            ?? ( sqlite_bind_text st 1 pat ) { T _ → {} F _ → {} }
            ( string_free pat )
            ?? ( sqlite_bind_int st 2 limit ) { T _ → {} F _ → {} }
            : ~ b more T
            ~ more {
                ? ( __reg_row st ) {
                    : String nm ( sqlite_column_text st 0 )
                    : Json row ( json_obj_new )
                    : b _a ( json_obj_set row `name` ( json_str_lit ( string_data nm ) ) )
                    ? ( sqlite_column_is_null st 1 ) {
                        : b _b ( json_obj_set row `version` ( json_null ) )
                    } {
                        : String lv ( sqlite_column_text st 1 )
                        : b _c ( json_obj_set row `version` ( json_str_lit ( string_data lv ) ) )
                        ( string_free lv )
                    }
                    : b _d ( json_arr_push arr row )
                    ( string_free nm )
                } { = more F }
            }
        }
        F _ → {}
    }
    ^ arr
}

// { "packages": N, "versions": M } (non-yanked versions, like the Worker).
@ reg_db_stats_json Database db → String {
    : ~ i pkgs 0
    : ~ i vers 0
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM packages` ) {
        T st → {
            ? ( __reg_row st ) { = pkgs ( sqlite_column_int st 0 ) } {}
        }
        F _ → {}
    }
    ?? ( sqlite_prepare db `SELECT COUNT(*) FROM versions WHERE yanked = 0` ) {
        T st → {
            ? ( __reg_row st ) { = vers ( sqlite_column_int st 0 ) } {}
        }
        F _ → {}
    }
    : Json root ( json_obj_new )
    : b _a ( json_obj_set root `packages` ( json_int pkgs ) )
    : b _b ( json_obj_set root `versions` ( json_int vers ) )
    : String out ( json_stringify root )
    ( json_free root )
    ^ out
}

// Package detail for the HTML page:
//   { "name", "owner", "versions": [ { "version", "yanked", "login", "date" } ],
//     "latest": version-or-null }
// Versions newest-first (publication order, matching the Worker page).
// "date" is "YYYY-MM-DD" (UTC) from published_at — epoch seconds here.
@ reg_db_pkg_detail_json Database db s name → Json {
    : Json root ( json_obj_new )
    : b _a ( json_obj_set root `name` ( json_str_lit name ) )
    : i owner_uid ( reg_db_pkg_owner db name )
    ? >= owner_uid 0 {
        : String ol ( reg_db_login_of db owner_uid )
        : b _b ( json_obj_set root `owner` ( json_str_lit ( string_data ol ) ) )
        ( string_free ol )
    } {
        : b _c ( json_obj_set root `owner` ( json_null ) )
    }
    : Json varr ( json_arr_new )
    : ~ b have_latest F
    ?? ( sqlite_prepare db `SELECT v.version, v.yanked, u.login, v.published_at
            FROM versions v JOIN users u ON u.id = v.published_by
            WHERE v.name = ?1 ORDER BY v.published_at DESC, v.rowid DESC` ) {
        T st → {
            : String nv ( string_from name )
            ?? ( sqlite_bind_text st 1 nv ) { T _ → {} F _ → {} }
            ( string_free nv )
            : ~ b more T
            ~ more {
                ? ( __reg_row st ) {
                    : String ver ( sqlite_column_text st 0 )
                    : i yk ( sqlite_column_int st 1 )
                    : String lg ( sqlite_column_text st 2 )
                    : i pubts ( sqlite_column_int st 3 )
                    : Json row ( json_obj_new )
                    : b _d ( json_obj_set row `version` ( json_str_lit ( string_data ver ) ) )
                    : b _e ( json_obj_set row `yanked` ( json_bool != yk 0 ) )
                    : b _f ( json_obj_set row `login` ( json_str_lit ( string_data lg ) ) )
                    : Time pt ( time_from_unix pubts )
                    : String dt ( time_format pt `%Y-%m-%d` )
                    : b _f2 ( json_obj_set row `date` ( json_str_lit ( string_data dt ) ) )
                    ( string_free dt )
                    : b _g ( json_arr_push varr row )
                    ? & ! have_latest == yk 0 {
                        : b _h ( json_obj_set root `latest` ( json_str_lit ( string_data ver ) ) )
                        = have_latest T
                    } {}
                    ( string_free ver )
                    ( string_free lg )
                } { = more F }
            }
        }
        F _ → {}
    }
    ? ! have_latest {
        : b _i ( json_obj_set root `latest` ( json_null ) )
    } {}
    : b _j ( json_obj_set root `versions` varr )
    ^ root
}
