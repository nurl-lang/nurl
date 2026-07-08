// registry — the NURL package registry, served by NURL itself.
//
//   registry serve [--host H] [--port N] [--data DIR] [--workers N]
//                  [--log] [--tls-cert PEM --tls-key PEM]
//   registry token new <login> [--data DIR]
//
// `serve` speaks the exact wire protocol nurlpkg drives (index/tarball
// reads, bearer-authenticated publish/yank/revoke, search/stats) plus a
// server-rendered catalog UI. State: SQLite at <data>/registry.db +
// tarballs under <data>/pkgs (see src/db.nu, src/store.nu).
//
// `token new` mints a publish token for a (created-on-first-use) local
// user and prints it ONCE — only the peppered SHA-256 hash is stored.
// The same pepper (REG_TOKEN_PEPPER) must be set for mint and serve.
//
// Environment:
//   REG_TOKEN_PEPPER      token-hash pepper (deployment secret; "" works
//                         but leaves tokens brute-forceable from a DB copy)
//   REG_BASE_URL          public base URL (needed for GitHub OAuth redirect)
//   GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET
//                         enable the /login OAuth flow (optional; without
//                         them /login explains local token minting)

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `src/service.nu`

@ __reg_env_or s name s fallback → String {
    : ?String ev ( env_get name )
    ?? ev {
        T v → ^ v
        F → ^ ( string_from fallback )
    }
}

@ __reg_usage → v {
    ( nurl_print `registry — the NURL package registry, self-hosted\n\n` )
    ( nurl_print `usage:\n` )
    ( nurl_print `  registry serve [--host H] [--port N] [--data DIR] [--workers N] [--log]\n` )
    ( nurl_print `                 [--tls-cert PEM --tls-key PEM]\n` )
    ( nurl_print `  registry token new <login> [--data DIR]\n\n` )
    ( nurl_print `env: REG_TOKEN_PEPPER, REG_BASE_URL, GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET\n` )
}

// Shared: <data>/registry.db
@ __reg_db_path s data → String {
    : String out ( string_from data )
    ( string_push_str out `/registry.db` )
    ^ out
}

@ __cmd_token → i {
    // registry token new <login> [--data DIR]
    : ArgParser p ( args_new `registry token` `mint a publish token` )
    ( args_opt p `data` 100 `DIR` `data directory (default ./data)` )
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 2
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }
    // args_parse BORROWS the token vec (copies what it keeps).
    : b parsed ( args_parse p argv )
    ( vec_free_with [String] argv \ String sv → v { ( string_free sv ) } )
    : ~ i rc 0
    ? parsed {
        : i np ( args_positional_count p )
        : ( Vec String ) pos ( args_positionals p )
        : ~ b shape_ok F
        ? == np 2 {
            : ?String c0 ( vec_get [String] pos 0 )
            ?? c0 {
                T c → {
                    ? != 0 ( nurl_str_eq ( string_data c ) `new` ) { = shape_ok T } {}
                }
                F → {}
            }
        } {}
        ? ! shape_ok {
            ( nurl_eprintln `usage: registry token new <login> [--data DIR]` )
            = rc 2
        } {
            : ~ String login ( string_new )
            : ?String lo ( vec_get [String] pos 1 )
            ?? lo {
                T l → {
                    ( string_free login )
                    = login ( string_from ( string_data l ) )
                }
                F → {}
            }
            : String data ( args_value_or p `data` `./data` )
            ?? ( dir_create_all ( string_data data ) ) { T _ → {} F _ → {} }
            : String dbp ( __reg_db_path ( string_data data ) )
            : String pepper ( __reg_env_or `REG_TOKEN_PEPPER` `` )
            ?? ( reg_db_open ( string_data dbp ) ) {
                F _ → {
                    ( nurl_eprint `registry: cannot open database at ` )
                    ( nurl_eprintln ( string_data dbp ) )
                    = rc 1
                }
                T db → {
                    : i now ( time_to_unix ( time_now ) )
                    : i uid ( reg_db_user_ensure db ( string_data login ) now )
                    ? < uid 0 {
                        ( nurl_eprintln `registry: cannot create user` )
                        = rc 1
                    } {
                        : String token ( reg_token_new )
                        : String hash ( reg_token_hash ( string_data pepper ) ( string_data token ) )
                        ? ( reg_db_token_insert db uid ( string_data hash ) `cli` now ) {
                            // The token itself: stdout, nothing else, so
                            // `NURL_TOKEN=$(registry token new me)` works.
                            ( nurl_print ( string_data token ) )
                            ( nurl_print `\n` )
                            ( nurl_eprint `registry: token minted for ` )
                            ( nurl_eprint ( string_data login ) )
                            ( nurl_eprintln ` (shown once; only its hash is stored)` )
                        } {
                            ( nurl_eprintln `registry: cannot store token` )
                            = rc 1
                        }
                        ( string_free token )
                        ( string_free hash )
                    }
                }
            }
            ( string_free login )
            ( string_free data )
            ( string_free dbp )
            ( string_free pepper )
        }
    } {
        ( nurl_eprintln ( args_error p ) )
        = rc 2
    }
    ( args_free p )
    ^ rc
}

@ __cmd_serve → i {
    : ArgParser p ( args_new `registry serve` `serve the package registry` )
    ( args_opt p `host` 72 `HOST` `bind address (default 127.0.0.1)` )
    ( args_opt p `port` 80 `PORT` `port (default 8914)` )
    ( args_opt p `data` 100 `DIR` `data directory (default ./data)` )
    ( args_opt p `workers` 119 `N` `worker threads (default 0 = single-threaded)` )
    ( args_opt p `tls-cert` 67 `PEM` `TLS certificate (with --tls-key)` )
    ( args_opt p `tls-key` 75 `PEM` `TLS private key` )
    ( args_flag p `log` 108 `access log to stderr` )
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 2
    ~ < ai ac {
        ( vec_push [String] argv ( env_arg ai ) )
        = ai + ai 1
    }
    : b parsed ( args_parse p argv )
    ( vec_free_with [String] argv \ String sv → v { ( string_free sv ) } )
    : ~ i rc 0
    ? parsed {
        : String host ( args_value_or p `host` `127.0.0.1` )
        : String ports ( args_value_or p `port` `8914` )
        : i port ( nurl_str_to_int ( string_data ports ) )
        ( string_free ports )
        : String data ( args_value_or p `data` `./data` )
        : String workers_s ( args_value_or p `workers` `0` )
        : i workers ( nurl_str_to_int ( string_data workers_s ) )
        ( string_free workers_s )
        ?? ( dir_create_all ( string_data data ) ) { T _ → {} F _ → {} }
        : String dbp ( __reg_db_path ( string_data data ) )
        : String pepper ( __reg_env_or `REG_TOKEN_PEPPER` `` )
        : String base ( __reg_env_or `REG_BASE_URL` `` )
        : String ghid ( __reg_env_or `GITHUB_CLIENT_ID` `` )
        : String ghsec ( __reg_env_or `GITHUB_CLIENT_SECRET` `` )

        // Fail fast when the DB can't be opened/migrated — not per request.
        ?? ( reg_db_open ( string_data dbp ) ) {
            F _ → {
                ( nurl_eprint `registry: cannot open database at ` )
                ( nurl_eprintln ( string_data dbp ) )
                = rc 1
            }
            T db → {}  // auto-drop closes the probe handle
        }

        ? == rc 0 {
            ( reg_service_config ( string_data data ) ( string_data dbp ) ( string_data pepper )
            ( string_data base ) ( string_data ghid ) ( string_data ghsec ) )
            : *HttpApp app ( http_app_new )
            ( http_app_use_router app ( reg_service_router ) )
            // The publish endpoint accepts tarballs up to 16 MiB — the
            // wire contract the Worker set. head stays at the default.
            ( http_app_body_max app 16777216 )
            ( http_app_workers app workers )
            ? ( args_present p `log` ) { ( http_app_logging app ) } {}
            : ~ String cert ( string_new )
            : ~ String key ( string_new )
            ?? ( args_value p `tls-cert` ) { T v → { ( string_free cert ) = cert v } F → {} }
            ?? ( args_value p `tls-key` ) { T v → { ( string_free key ) = key v } F → {} }
            ? & > ( string_len cert ) 0 > ( string_len key ) 0 {
                = rc ( http_app_listen_tls app ( string_data host ) port ( string_data cert ) ( string_data key ) )
            } {
                = rc ( http_app_listen app ( string_data host ) port )
            }
            ( string_free cert )
            ( string_free key )
            ( http_app_free app )
        } {}

        ( string_free host )
        ( string_free data )
        ( string_free dbp )
        ( string_free pepper )
        ( string_free base )
        ( string_free ghid )
        ( string_free ghsec )
    } {
        ( nurl_eprintln ( args_error p ) )
        = rc 2
    }
    ( args_free p )
    ^ rc
}

@ main → i {
    : i ac ( env_args_count )
    ? < ac 2 {
        ( __reg_usage )
        ^ 2
    } {}
    : String sub ( env_arg 1 )
    : s s_sub ( string_data sub )
    : ~ i rc 0
    ? != 0 ( nurl_str_eq s_sub `serve` ) {
        = rc ( __cmd_serve )
    } {
        ? != 0 ( nurl_str_eq s_sub `token` ) {
            = rc ( __cmd_token )
        } {
            ( __reg_usage )
            = rc 2
        }
    }
    ( string_free sub )
    ^ rc
}
