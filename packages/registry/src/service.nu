// registry/service.nu — the wire: routes + handlers.
//
// Implements exactly the protocol nurlpkg already drives (see
// stdlib/ext/pkg_fetch.nu + pkg_publish.nu and the Cloudflare Worker
// this replaces):
//
//   GET  /index/<name>.json                     package index (rendered from SQLite)
//   GET  /pkgs/<name>/<name>-<version>.tar.gz   tarball (disk, immutable)
//   POST /api/v1/publish                        Bearer + X-Nurl-Package/-Version/-Deps
//   POST /api/v1/yank | /api/v1/unyank          owner-only version flag
//   POST /api/v1/revoke                         delete the presented token
//   GET  /api/v1/search?q= · /api/v1/stats      JSON
//   GET  / · /packages/<name> · /files/<n>/<v>/<path>   HTML catalog + assets
//   GET  /login · /auth/callback                GitHub OAuth (config-gated)
//
// Every route handler is a top-level function; the router closures are
// one-liners, so the whole service is testable through router_handle
// with no socket (see tests/). Configuration lives in module globals set
// once by reg_service_config before the router is built. Handlers open
// a fresh SQLite connection per request (WAL + busy timeout — see
// db.nu), so the service is safe on a worker pool.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/sqlite.nu`
$ `stdlib/ext/http_cli.nu`
$ `deps/http/src/http.nu`
$ `src/db.nu`
$ `src/auth.nu`
$ `src/store.nu`
$ `src/extract.nu`
$ `src/pages.nu`

// ── Configuration (set once, before serving) ──────────────────────────

: ~ s g_reg_data `./data`  // data dir (tarballs under <data>/pkgs)
: ~ s g_reg_dbpath `./data/registry.db`
: ~ s g_reg_pepper ``  // token-hash pepper (deployment secret)
: ~ s g_reg_base_url ``  // public base URL, for the OAuth redirect
: ~ s g_reg_gh_id ``  // GitHub OAuth app (empty = OAuth disabled)
: ~ s g_reg_gh_secret ``

// The caller OWNS the config strings and must keep them alive for the
// server's lifetime (main holds them; the anomaly service follows the
// same contract).
@ reg_service_config s data s dbpath s pepper s base_url s gh_id s gh_secret → v {
    = g_reg_data data
    = g_reg_dbpath dbpath
    = g_reg_pepper pepper
    = g_reg_base_url base_url
    = g_reg_gh_id gh_id
    = g_reg_gh_secret gh_secret
}

@ __reg_now → i {
    ^ ( time_to_unix ( time_now ) )
}

// ── Response helpers ──────────────────────────────────────────────────

@ __reg_json_resp i status s body → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `application/json` )
    ( response_set_body_str r body )
    ^ r
}

@ __reg_err i status s code → HttpResponse {
    : String b ( string_from `{"error":"` )
    ( string_push_str b code )
    ( string_push_str b `"}` )
    : HttpResponse r ( __reg_json_resp status ( string_data b ) )
    ( string_free b )
    ^ r
}

@ __reg_html_resp i status String html → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_body_str r ( string_data html ) )
    ( string_free html )
    ^ r
}

// First query-string value for `key`; "" when absent.
@ __reg_q_get HttpRequest req s key → String {
    : ( Vec QueryPair ) pairs ( parse_query ( string_data . req query ) )
    : ~ String out ( string_new )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    : ~ b found F
    ~ < k n {
        : ?QueryPair po ( vec_get [QueryPair] pairs k )
        ?? po {
            T pr → {
                ? & ! found != 0 ( nurl_str_eq ( string_data . pr key ) key ) {
                    ( string_free out )
                    = out ( string_from ( string_data . pr value ) )
                    = found T
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( query_pairs_free pairs )
    ^ out
}

// Owned, lowercased copy of a header value; "" when absent.
@ __reg_header_lower HttpRequest req s name → String {
    : ?String ho ( header_get . req headers name )
    ?? ho {
        T hv → {
            : String low ( string_to_lower hv )
            ( string_free hv )
            ^ low
        }
        F → ^ ( string_new )
    }
}

// Owned header value; "" when absent.
@ __reg_header HttpRequest req s name → String {
    : ?String ho ( header_get . req headers name )
    ?? ho {
        T hv → ^ hv
        F → ^ ( string_new )
    }
}

// Authenticated user id from the request's bearer token, or -1.
// (Constant-time comparison is inherent: the token is hashed and the
// hash looked up by equality in SQLite — no secret-dependent scan.)
@ __reg_auth_uid Database db HttpRequest req → i {
    : String auth ( __reg_header req `authorization` )
    : String tok ( reg_bearer_of ( string_data auth ) )
    ( string_free auth )
    ? == ( string_len tok ) 0 {
        ( string_free tok )
        ^ -1
    } {}
    : String hash ( reg_token_hash g_reg_pepper ( string_data tok ) )
    ( string_free tok )
    : i uid ( reg_db_auth db ( string_data hash ) ( __reg_now ) )
    ( string_free hash )
    ^ uid
}

// ── Read path: index + tarballs ───────────────────────────────────────

// GET /index/:file — file is "<name>.json".
@ __reg_h_index HttpRequest req Params p → HttpResponse {
    : ~ String file ( string_new )
    ?? ( params_get p `file` ) {
        T v → { ( string_free file ) = file v }
        F → {}
    }
    ? ! ( string_ends_with file `.json` ) {
        ( string_free file )
        ^ ( __reg_err 400 `invalid_name` )
    } {}
    // strip ".json", lowercase
    : String base ( string_new )
    : i blen - ( string_len file ) 5
    : ~ i k 0
    ~ < k blen {
        ( string_push_char base ( nurl_str_get ( string_data file ) k ) )
        = k + k 1
    }
    ( string_free file )
    : String name ( string_to_lower base )
    ( string_free base )
    ? ! ( reg_name_valid ( string_data name ) ) {
        ( string_free name )
        ^ ( __reg_err 400 `invalid_name` )
    } {}
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → {
            ( string_free name )
            ^ ( __reg_err 500 `db_unavailable` )
        }
        T db → {
            : String body ( reg_db_index_json db ( string_data name ) )
            ( string_free name )
            ? == ( string_len body ) 0 {
                ( string_free body )
                ^ ( __reg_err 404 `not_found` )
            } {}
            : HttpResponse r ( __reg_json_resp 200 ( string_data body ) )
            ( string_free body )
            ( response_set_header r `Cache-Control` `public, max-age=60` )
            ^ r
        }
    }
}

// GET /pkgs/:name/:file — file must be "<name>-<version>.tar.gz".
@ __reg_h_tarball HttpRequest req Params p → HttpResponse {
    : ~ String rawname ( string_new )
    ?? ( params_get p `name` ) {
        T v → { ( string_free rawname ) = rawname v }
        F → {}
    }
    : String name ( string_to_lower rawname )
    ( string_free rawname )
    : ~ String file ( string_new )
    ?? ( params_get p `file` ) {
        T v → { ( string_free file ) = file v }
        F → {}
    }
    ? ! ( reg_name_valid ( string_data name ) ) {
        ( string_free name )
        ( string_free file )
        ^ ( __reg_err 400 `bad_path` )
    } {}
    // expect exactly <name>-<version>.tar.gz
    : String prefix ( string_from ( string_data name ) )
    ( string_push_char prefix 45 )
    : ~ b shape_ok F
    ? & ( string_starts_with file ( string_data prefix ) ) ( string_ends_with file `.tar.gz` ) { = shape_ok T } {}
    : String version ( string_new )
    ? shape_ok {
        : i from ( string_len prefix )
        : i to - ( string_len file ) 7
        ? > to from {
            : ~ i k from
            ~ < k to {
                ( string_push_char version ( nurl_str_get ( string_data file ) k ) )
                = k + k 1
            }
        } { = shape_ok F }
    } {}
    ( string_free prefix )
    ( string_free file )
    ? | ! shape_ok ! ( reg_version_valid ( string_data version ) ) {
        ( string_free name )
        ( string_free version )
        ^ ( __reg_err 400 `bad_path` )
    } {}
    : ( Vec u ) bytes ( reg_tarball_read g_reg_data ( string_data name ) ( string_data version ) )
    ( string_free name )
    ( string_free version )
    ? == ( vec_len [u] bytes ) 0 {
        ( vec_free [u] bytes )
        ^ ( __reg_err 404 `not_found` )
    } {}
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `application/gzip` )
    ( response_set_header r `Cache-Control` `public, max-age=31536000, immutable` )
    ( response_set_body_bytes r bytes )
    ( vec_free [u] bytes )
    ^ r
}

// ── Write path: publish / yank / revoke ───────────────────────────────

// Parse X-Nurl-Deps (JSON [{name,req}]) and insert the rows. Entries
// that aren't {string,string} objects are skipped, like the Worker.
@ __reg_insert_deps Database db s name s version s deps_json → b {
    ? == ( nurl_str_len deps_json ) 0 { ^ T } {}
    : ~ b ok T
    ?? ( json_parse deps_json ) {
        F _ → {}
        T root → {
            ? ( json_is_arr root ) {
                : i n ( json_arr_len root )
                : ~ i k 0
                ~ < k n {
                    : ?Json eo ( json_arr_get root k )
                    ?? eo {
                        T e → {
                            : ?Json no ( json_obj_get e `name` )
                            : ?Json ro ( json_obj_get e `req` )
                            ?? no {
                                T nj → {
                                    ?? ro {
                                        T rj → {
                                            ? & ( json_is_str nj ) ( json_is_str rj ) {
                                                ? ! ( reg_db_dep_insert db name version ( json_as_str nj ) ( json_as_str rj ) ) { = ok F } {}
                                            } {}
                                        }
                                        F → {}
                                    }
                                }
                                F → {}
                            }
                        }
                        F → {}
                    }
                    = k + k 1
                }
            } {}
            ( json_free root )
        }
    }
    ^ ok
}

// POST /api/v1/publish
@ __reg_h_publish HttpRequest req Params p → HttpResponse {
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → ^ ( __reg_err 500 `db_unavailable` )
        T db → {
            : i uid ( __reg_auth_uid db req )
            ? < uid 0 {
                ^ ( __reg_err 401 `unauthorized` )
            } {}
            : String name ( __reg_header_lower req `x-nurl-package` )
            : String version ( __reg_header req `x-nurl-version` )
            ? ! ( reg_name_valid ( string_data name ) ) {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 400 `invalid_name` )
            } {}
            ? ! ( reg_version_valid ( string_data version ) ) {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 400 `invalid_version` )
            } {}
            ? == ( vec_len [u] . req body ) 0 {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 400 `empty_body` )
            } {}
            ? > ( vec_len [u] . req body ) 16777216 {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 413 `too_large` )
            } {}

            // First-publisher ownership + version immutability.
            : i owner ( reg_db_pkg_owner db ( string_data name ) )
            ? & >= owner 0 != owner uid {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 403 `not_owner` )
            } {}
            ? ( reg_db_version_exists db ( string_data name ) ( string_data version ) ) {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 409 `version_exists` )
            } {}

            // Server-side checksum — a client digest is never trusted.
            : ( Vec u ) digest ( sha256_pure . req body )
            : String checksum ( bytes_to_hex digest )
            ( vec_free [u] digest )

            // Tarball first, then the DB rows in one transaction. A
            // failure between the two leaves an orphan file that the
            // (name, version) immutability makes harmless — the next
            // attempt overwrites the identical path.
            ? ! ( reg_tarball_write g_reg_data ( string_data name ) ( string_data version ) . req body ) {
                ( string_free name )
                ( string_free version )
                ( string_free checksum )
                ^ ( __reg_err 500 `store_failed` )
            } {}

            : i now ( __reg_now )
            : ~ b ok T
            ?? ( sqlite_begin db ) { T _ → {} F _ → { = ok F } }
            ? & ok < owner 0 {
                ? ! ( reg_db_pkg_insert db ( string_data name ) uid now ) { = ok F } {}
            } {}
            ? ok {
                ? ! ( reg_db_version_insert db ( string_data name ) ( string_data version ) ( string_data checksum ) uid now ) { = ok F } {}
            } {}
            ? ok {
                : String deps ( __reg_header req `x-nurl-deps` )
                ? ! ( __reg_insert_deps db ( string_data name ) ( string_data version ) ( string_data deps ) ) { = ok F } {}
                ( string_free deps )
            } {}
            ? ok {
                ?? ( sqlite_commit db ) { T _ → {} F _ → { = ok F } }
            } {}
            ? ! ok {
                ?? ( sqlite_rollback db ) { T _ → {} F _ → {} }
            } {}
            ? ! ok {
                ( string_free name )
                ( string_free version )
                ( string_free checksum )
                ^ ( __reg_err 500 `db_write_failed` )
            } {}

            : Json out ( json_obj_new )
            : b _a ( json_obj_set out `ok` ( json_bool T ) )
            : b _b ( json_obj_set out `name` ( json_str_lit ( string_data name ) ) )
            : b _c ( json_obj_set out `version` ( json_str_lit ( string_data version ) ) )
            : b _d ( json_obj_set out `checksum` ( json_str_lit ( string_data checksum ) ) )
            ( string_free name )
            ( string_free version )
            ( string_free checksum )
            : HttpResponse r ( response_new 200 )
            ( response_set_body_json r out )
            ( json_free out )
            ^ r
        }
    }
}

// POST /api/v1/yank + /api/v1/unyank
@ __reg_h_yank HttpRequest req Params p b yank → HttpResponse {
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → ^ ( __reg_err 500 `db_unavailable` )
        T db → {
            : i uid ( __reg_auth_uid db req )
            ? < uid 0 {
                ^ ( __reg_err 401 `unauthorized` )
            } {}
            : String name ( __reg_header_lower req `x-nurl-package` )
            : String version ( __reg_header req `x-nurl-version` )
            ? ! ( reg_name_valid ( string_data name ) ) {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 400 `invalid_name` )
            } {}
            ? ! ( reg_version_valid ( string_data version ) ) {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 400 `invalid_version` )
            } {}
            : i owner ( reg_db_pkg_owner db ( string_data name ) )
            ? < owner 0 {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 404 `not_found` )
            } {}
            ? != owner uid {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 403 `not_owner` )
            } {}
            : b changed ( reg_db_version_set_yanked db ( string_data name ) ( string_data version ) yank )
            ? ! changed {
                ( string_free name )
                ( string_free version )
                ^ ( __reg_err 404 `version_not_found` )
            } {}
            : Json out ( json_obj_new )
            : b _a ( json_obj_set out `ok` ( json_bool T ) )
            : b _b ( json_obj_set out `name` ( json_str_lit ( string_data name ) ) )
            : b _c ( json_obj_set out `version` ( json_str_lit ( string_data version ) ) )
            : b _d ( json_obj_set out `yanked` ( json_bool yank ) )
            ( string_free name )
            ( string_free version )
            : HttpResponse r ( response_new 200 )
            ( response_set_body_json r out )
            ( json_free out )
            ^ r
        }
    }
}

@ __reg_h_yank_on HttpRequest req Params p → HttpResponse {
    ^ ( __reg_h_yank req p T )
}

@ __reg_h_yank_off HttpRequest req Params p → HttpResponse {
    ^ ( __reg_h_yank req p F )
}

// POST /api/v1/revoke — delete the presented token.
@ __reg_h_revoke HttpRequest req Params p → HttpResponse {
    : String auth ( __reg_header req `authorization` )
    : String tok ( reg_bearer_of ( string_data auth ) )
    ( string_free auth )
    ? == ( string_len tok ) 0 {
        ( string_free tok )
        ^ ( __reg_err 401 `unauthorized` )
    } {}
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → {
            ( string_free tok )
            ^ ( __reg_err 500 `db_unavailable` )
        }
        T db → {
            : String hash ( reg_token_hash g_reg_pepper ( string_data tok ) )
            ( string_free tok )
            : b deleted ( reg_db_token_delete db ( string_data hash ) )
            ( string_free hash )
            ? ! deleted { ^ ( __reg_err 401 `unknown_token` ) } {}
            ^ ( __reg_json_resp 200 `{"ok":true,"revoked":true}` )
        }
    }
}

// ── JSON API: search + stats ──────────────────────────────────────────

@ __reg_h_search HttpRequest req Params p → HttpResponse {
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → ^ ( __reg_err 500 `db_unavailable` )
        T db → {
            : String qraw ( __reg_q_get req `q` )
            : String q ( string_to_lower qraw )
            ( string_free qraw )
            : Json results ( reg_db_catalog_json db ( string_data q ) 50 )
            ( string_free q )
            : Json out ( json_obj_new )
            : b _a ( json_obj_set out `results` results )
            : HttpResponse r ( response_new 200 )
            ( response_set_body_json r out )
            ( json_free out )
            ^ r
        }
    }
}

@ __reg_h_stats HttpRequest req Params p → HttpResponse {
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → ^ ( __reg_err 500 `db_unavailable` )
        T db → {
            : String body ( reg_db_stats_json db )
            : HttpResponse r ( __reg_json_resp 200 ( string_data body ) )
            ( string_free body )
            ( response_set_header r `Access-Control-Allow-Origin` `*` )
            ( response_set_header r `Cache-Control` `public, max-age=300` )
            ^ r
        }
    }
}

// ── HTML: catalog + package page + tarball assets ─────────────────────

@ __reg_h_catalog HttpRequest req Params p → HttpResponse {
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → ^ ( __reg_err 500 `db_unavailable` )
        T db → {
            : String qraw ( __reg_q_get req `q` )
            : String q ( string_to_lower qraw )
            ( string_free qraw )
            : Json items ( reg_db_catalog_json db ( string_data q ) 200 )
            : Json ctx ( json_obj_new )
            : b _a ( json_obj_set ctx `title` ( json_str_lit `NURL registry` ) )
            : b _b ( json_obj_set ctx `q` ( json_str_lit ( string_data q ) ) )
            : b _c ( json_obj_set ctx `items` items )
            ( string_free q )
            : String html ( reg_page_catalog ctx )
            ( json_free ctx )
            ^ ( __reg_html_resp 200 html )
        }
    }
}

@ __reg_notfound_page s name → HttpResponse {
    : Json ctx ( json_obj_new )
    : b _a ( json_obj_set ctx `title` ( json_str_lit `not found` ) )
    : b _b ( json_obj_set ctx `name` ( json_str_lit name ) )
    : String html ( reg_page_notfound ctx )
    ( json_free ctx )
    ^ ( __reg_html_resp 404 html )
}

@ __reg_h_pkg_detail HttpRequest req Params p → HttpResponse {
    : ~ String rawname ( string_new )
    ?? ( params_get p `name` ) {
        T v → { ( string_free rawname ) = rawname v }
        F → {}
    }
    : String name ( string_to_lower rawname )
    ( string_free rawname )
    ? ! ( reg_name_valid ( string_data name ) ) {
        : HttpResponse r ( __reg_notfound_page ( string_data name ) )
        ( string_free name )
        ^ r
    } {}
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → {
            ( string_free name )
            ^ ( __reg_err 500 `db_unavailable` )
        }
        T db → {
            : Json ctx ( reg_db_pkg_detail_json db ( string_data name ) )
            // no versions at all → 404
            : ~ i nvers 0
            ?? ( json_obj_get ctx `versions` ) {
                T va → { = nvers ( json_arr_len va ) }
                F → {}
            }
            ? == nvers 0 {
                ( json_free ctx )
                : HttpResponse r ( __reg_notfound_page ( string_data name ) )
                ( string_free name )
                ^ r
            } {}
            : b _t ( json_obj_set ctx `title` ( json_str_lit ( string_data name ) ) )
            // latest → install requirement, deps, README, repository
            : ~ String latest ( string_new )
            ?? ( json_obj_get ctx `latest` ) {
                T lj → {
                    ? ( json_is_str lj ) {
                        ( string_free latest )
                        = latest ( string_from ( json_as_str lj ) )
                    } {}
                }
                F → {}
            }
            ? > ( string_len latest ) 0 {
                : String reqs ( string_from `^` )
                ( string_push_str reqs ( string_data latest ) )
                : b _r ( json_obj_set ctx `req` ( json_str_lit ( string_data reqs ) ) )
                ( string_free reqs )
                : b _d ( json_obj_set ctx `deps` ( reg_db_deps_json db ( string_data name ) ( string_data latest ) ) )
                : ( Vec u ) gz ( reg_tarball_read g_reg_data ( string_data name ) ( string_data latest ) )
                ? > ( vec_len [u] gz ) 0 {
                    : String repo ( reg_targz_repository gz )
                    ? ( string_starts_with repo `http` ) {
                        : b _p ( json_obj_set ctx `repository` ( json_str_lit ( string_data repo ) ) )
                    } {}
                    ( string_free repo )
                    : String md ( reg_targz_readme gz )
                    ? & > ( string_len md ) 0 <= ( string_len md ) 524288 {
                        : String rh ( reg_readme_html ( string_data md ) ( string_data name ) ( string_data latest ) )
                        : b _m ( json_obj_set ctx `readme` ( json_str_lit ( string_data rh ) ) )
                        ( string_free rh )
                    } {}
                    ( string_free md )
                } {}
                ( vec_free [u] gz )
            } {
                : b _r2 ( json_obj_set ctx `req` ( json_str_lit `*` ) )
            }
            ( string_free latest )
            ( string_free name )
            : String html ( reg_page_detail ctx )
            ( json_free ctx )
            ^ ( __reg_html_resp 200 html )
        }
    }
}

// Image MIME by lowercased extension; "" = not an allowed asset type.
// (Images only: keeps the asset route from doubling as a file host.)
@ __reg_asset_mime s path → s {
    : String pl_s ( string_from path )
    : String pl ( string_to_lower pl_s )
    ( string_free pl_s )
    : ~ s mime ``
    ? ( string_ends_with pl `.png` ) { = mime `image/png` } {}
    ? ( string_ends_with pl `.jpg` ) { = mime `image/jpeg` } {}
    ? ( string_ends_with pl `.jpeg` ) { = mime `image/jpeg` } {}
    ? ( string_ends_with pl `.gif` ) { = mime `image/gif` } {}
    ? ( string_ends_with pl `.webp` ) { = mime `image/webp` } {}
    ? ( string_ends_with pl `.svg` ) { = mime `image/svg+xml` } {}
    ? ( string_ends_with pl `.ico` ) { = mime `image/x-icon` } {}
    ? ( string_ends_with pl `.bmp` ) { = mime `image/bmp` } {}
    ? ( string_ends_with pl `.avif` ) { = mime `image/avif` } {}
    ( string_free pl )
    ^ mime
}

// GET /files/:name/:version/*rest — a README-referenced image, straight
// from the published tarball. Version-pinned → immutable-cacheable.
@ __reg_h_file HttpRequest req Params p → HttpResponse {
    : ~ String rawname ( string_new )
    ?? ( params_get p `name` ) {
        T v → { ( string_free rawname ) = rawname v }
        F → {}
    }
    : String name ( string_to_lower rawname )
    ( string_free rawname )
    : ~ String version ( string_new )
    ?? ( params_get p `version` ) {
        T v → { ( string_free version ) = version v }
        F → {}
    }
    : ~ String rest ( string_new )
    ?? ( params_get p `rest` ) {
        T v → { ( string_free rest ) = rest v }
        F → {}
    }
    ? | ! ( reg_name_valid ( string_data name ) ) ! ( reg_version_valid ( string_data version ) ) {
        ( string_free name )
        ( string_free version )
        ( string_free rest )
        ^ ( __reg_err 400 `bad_path` )
    } {}
    : String safe ( reg_relpath_norm ( string_data rest ) )
    ( string_free rest )
    ? == ( string_len safe ) 0 {
        ( string_free name )
        ( string_free version )
        ( string_free safe )
        ^ ( __reg_err 400 `bad_path` )
    } {}
    : s mime ( __reg_asset_mime ( string_data safe ) )
    ? == ( nurl_str_len mime ) 0 {
        ( string_free name )
        ( string_free version )
        ( string_free safe )
        ^ ( __reg_err 415 `unsupported_type` )
    } {}
    : ( Vec u ) gz ( reg_tarball_read g_reg_data ( string_data name ) ( string_data version ) )
    ( string_free name )
    ( string_free version )
    ? == ( vec_len [u] gz ) 0 {
        ( vec_free [u] gz )
        ( string_free safe )
        ^ ( __reg_err 404 `not_found` )
    } {}
    : ( Vec u ) data ( reg_targz_member gz ( string_data safe ) )
    ( vec_free [u] gz )
    ( string_free safe )
    ? == ( vec_len [u] data ) 0 {
        ( vec_free [u] data )
        ^ ( __reg_err 404 `not_found` )
    } {}
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` mime )
    ( response_set_header r `Cache-Control` `public, max-age=31536000, immutable` )
    ( response_set_header r `X-Content-Type-Options` `nosniff` )
    // Neutralise any script an SVG might carry, even on direct navigation.
    ( response_set_header r `Content-Security-Policy` `default-src 'none'; style-src 'unsafe-inline'; sandbox` )
    ( response_set_body_bytes r data )
    ( vec_free [u] data )
    ^ r
}

// ── GitHub OAuth (token bootstrap; config-gated) ──────────────────────

@ __reg_oauth_enabled → b {
    ^ & > ( nurl_str_len g_reg_gh_id ) 0 > ( nurl_str_len g_reg_gh_secret ) 0
}

// GET /login
@ __reg_h_login HttpRequest req Params p → HttpResponse {
    ? ! ( __reg_oauth_enabled ) {
        : Json ctx ( json_obj_new )
        : b _a ( json_obj_set ctx `title` ( json_str_lit `NURL registry — tokens` ) )
        : b _b ( json_obj_set ctx `data` ( json_str_lit g_reg_data ) )
        : String html ( reg_page_login_help ctx )
        ( json_free ctx )
        ^ ( __reg_html_resp 200 html )
    } {}
    : String state ( rand_hex_str 24 )
    : String loc ( string_from `https://github.com/login/oauth/authorize?client_id=` )
    ( string_push_str loc g_reg_gh_id )
    ( string_push_str loc `&scope=read%3Auser&redirect_uri=` )
    : String cb ( string_from g_reg_base_url )
    ( string_push_str cb `/auth/callback` )
    : String cbe ( percent_encode ( string_data cb ) )
    ( string_free cb )
    ( string_push_str loc ( string_data cbe ) )
    ( string_free cbe )
    ( string_push_str loc `&state=` )
    ( string_push_str loc ( string_data state ) )
    : HttpResponse r ( response_new 302 )
    ( response_set_header r `Location` ( string_data loc ) )
    ( string_free loc )
    : String ck ( string_from `nurlreg_state=` )
    ( string_push_str ck ( string_data state ) )
    ( string_push_str ck `; HttpOnly; SameSite=Lax; Path=/; Max-Age=600` )
    ? ( __reg_base_is_https ) { ( string_push_str ck `; Secure` ) } {}
    ( response_set_header r `Set-Cookie` ( string_data ck ) )
    ( string_free ck )
    ( string_free state )
    ^ r
}

@ __reg_base_is_https → b {
    : String b ( string_from g_reg_base_url )
    : b out ( string_starts_with b `https://` )
    ( string_free b )
    ^ out
}

// The nurlreg_state cookie value; "" when absent.
@ __reg_state_cookie HttpRequest req → String {
    : String ck ( __reg_header req `cookie` )
    : s raw ( string_data ck )
    : i n ( nurl_str_len raw )
    : String out ( string_new )
    : s want `nurlreg_state=`
    : i wlen 14
    : ~ i k 0
    : ~ b found F
    ~ & < k n ! found {
        // token boundary: start of string or after "; "
        : ~ b at_start F
        ? == k 0 { = at_start T } {}
        ? > k 0 { ? | == ( nurl_str_get raw - k 1 ) 59 == ( nurl_str_get raw - k 1 ) 32 { = at_start T } {} } {}
        ? & at_start <= + k wlen n {
            : ~ i w 0
            : ~ b m T
            ~ & < w wlen m {
                ? != ( nurl_str_get raw + k w ) ( nurl_str_get want w ) { = m F } {}
                = w + w 1
            }
            ? m {
                : ~ i e + k wlen
                ~ & < e n != ( nurl_str_get raw e ) 59 {
                    ( string_push_char out ( nurl_str_get raw e ) )
                    = e + e 1
                }
                = found T
            } {}
        } {}
        = k + k 1
    }
    ( string_free ck )
    ^ out
}

// POST https://github.com/login/oauth/access_token → access token, "" on failure.
@ __reg_gh_exchange s code → String {
    : Json body ( json_obj_new )
    : b _a ( json_obj_set body `client_id` ( json_str_lit g_reg_gh_id ) )
    : b _b ( json_obj_set body `client_secret` ( json_str_lit g_reg_gh_secret ) )
    : b _c ( json_obj_set body `code` ( json_str_lit code ) )
    : String cb ( string_from g_reg_base_url )
    ( string_push_str cb `/auth/callback` )
    : b _d ( json_obj_set body `redirect_uri` ( json_str_lit ( string_data cb ) ) )
    ( string_free cb )
    : String bs ( json_stringify body )
    ( json_free body )
    : String out ( string_new )
    : !HttpcResp HttpcErr rr ( httpc_request `POST` `https://github.com/login/oauth/access_token` ( string_data bs ) `Content-Type: application/json\r\nAccept: application/json\r\n` )
    ( string_free bs )
    ?? rr {
        F _ → ^ out
        T resp → {
            ? == ( httpc_status resp ) 200 {
                ?? ( json_parse ( httpc_body_str resp ) ) {
                    T j → {
                        : ?Json to ( json_obj_get j `access_token` )
                        ?? to {
                            T tj → {
                                ? ( json_is_str tj ) { ( string_push_str out ( json_as_str tj ) ) } {}
                            }
                            F → {}
                        }
                        ( json_free j )
                    }
                    F _ → {}
                }
            } {}
            ( httpc_resp_free resp )
            ^ out
        }
    }
}

// GET /auth/callback?code&state
@ __reg_h_callback HttpRequest req Params p → HttpResponse {
    ? ! ( __reg_oauth_enabled ) { ^ ( __reg_err 404 `not_found` ) } {}
    : String code ( __reg_q_get req `code` )
    : String state ( __reg_q_get req `state` )
    : String cookie ( __reg_state_cookie req )
    : ~ b state_ok F
    ? & & > ( string_len code ) 0 > ( string_len state ) 0 > ( string_len cookie ) 0 {
        ? != 0 ( nurl_str_eq ( string_data state ) ( string_data cookie ) ) { = state_ok T } {}
    } {}
    ( string_free state )
    ( string_free cookie )
    ? ! state_ok {
        ( string_free code )
        ^ ( __reg_err 400 `bad_oauth_state` )
    } {}
    : String ghtok ( __reg_gh_exchange ( string_data code ) )
    ( string_free code )
    ? == ( string_len ghtok ) 0 {
        ( string_free ghtok )
        ^ ( __reg_err 502 `oauth_exchange_failed` )
    } {}
    // GET the GitHub user behind the token.
    : String hb ( string_from `Authorization: Bearer ` )
    ( string_push_str hb ( string_data ghtok ) )
    ( string_push_str hb `\r\nUser-Agent: nurl-registry\r\nAccept: application/json\r\n` )
    ( string_free ghtok )
    : ~ i gh_id -1
    : String login ( string_new )
    : !HttpcResp HttpcErr ur ( httpc_request `GET` `https://api.github.com/user` `` ( string_data hb ) )
    ( string_free hb )
    ?? ur {
        F _ → {}
        T resp → {
            ? == ( httpc_status resp ) 200 {
                ?? ( json_parse ( httpc_body_str resp ) ) {
                    T j → {
                        : ?Json io ( json_obj_get j `id` )
                        ?? io {
                            T ij → {
                                : ?i iv ( json_num_as_i ij )
                                ?? iv { T n → { = gh_id n } F → {} }
                            }
                            F → {}
                        }
                        : ?Json lo ( json_obj_get j `login` )
                        ?? lo {
                            T lj → {
                                ? ( json_is_str lj ) { ( string_push_str login ( json_as_str lj ) ) } {}
                            }
                            F → {}
                        }
                        ( json_free j )
                    }
                    F _ → {}
                }
            } {}
            ( httpc_resp_free resp )
        }
    }
    ? | < gh_id 0 == ( string_len login ) 0 {
        ( string_free login )
        ^ ( __reg_err 502 `github_user_failed` )
    } {}
    ?? ( reg_db_open g_reg_dbpath ) {
        F _ → {
            ( string_free login )
            ^ ( __reg_err 500 `db_unavailable` )
        }
        T db → {
            : i now ( __reg_now )
            : i uid ( reg_db_user_upsert_github db gh_id ( string_data login ) now )
            ? < uid 0 {
                ( string_free login )
                ^ ( __reg_err 500 `db_write_failed` )
            } {}
            : String token ( reg_token_new )
            : String hash ( reg_token_hash g_reg_pepper ( string_data token ) )
            : b ins ( reg_db_token_insert db uid ( string_data hash ) `cli` now )
            ( string_free hash )
            ? ! ins {
                ( string_free login )
                ( string_free token )
                ^ ( __reg_err 500 `db_write_failed` )
            } {}
            : Json ctx ( json_obj_new )
            : b _a ( json_obj_set ctx `title` ( json_str_lit `NURL registry — token` ) )
            : b _b ( json_obj_set ctx `login` ( json_str_lit ( string_data login ) ) )
            : b _c ( json_obj_set ctx `token` ( json_str_lit ( string_data token ) ) )
            ( string_free login )
            ( string_free token )
            : String html ( reg_page_token ctx )
            ( json_free ctx )
            ^ ( __reg_html_resp 200 html )
        }
    }
}

// ── Router ────────────────────────────────────────────────────────────

@ reg_service_router → Router {
    : Router r ( router_new )
    ( router_get r `/` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_catalog req p ) } )
    ( router_get r `/login` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_login req p ) } )
    ( router_get r `/auth/callback` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_callback req p ) } )
    ( router_get r `/index/:file` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_index req p ) } )
    ( router_get r `/pkgs/:name/:file` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_tarball req p ) } )
    ( router_get r `/packages/:name` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_pkg_detail req p ) } )
    ( router_get r `/files/:name/:version/*rest` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_file req p ) } )
    ( router_get r `/api/v1/search` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_search req p ) } )
    ( router_get r `/api/v1/stats` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_stats req p ) } )
    ( router_post r `/api/v1/publish` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_publish req p ) } )
    ( router_post r `/api/v1/yank` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_yank_on req p ) } )
    ( router_post r `/api/v1/unyank` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_yank_off req p ) } )
    ( router_post r `/api/v1/revoke` \ HttpRequest req Params p → HttpResponse { ^ ( __reg_h_revoke req p ) } )
    ^ r
}
