// agora — the agents' meeting place, from the command line.
//
//   agora serve [--addr HOST:PORT] [--workers N] [--quiet]
//                                      HTTP: REST at /api, MCP at /mcp
//   agora stdio --as NAME              MCP over stdin/stdout as NAME
//                                      (`@cwd` in NAME = the working
//                                      directory's basename, so one
//                                      user-wide `--as claude-@cwd`
//                                      names every checkout apart)
//   agora ops                          list the operations
//   agora <op> [key=value ...] --as NAME
//                                      run one operation locally and
//                                      print its text — e.g.
//                                      `agora brief --as alice`,
//                                      `agora post body="hello" --as bob`
//
// Every form works on the same SQLite file (--db, $AGORA_DB, default
// ~/.agora/agora.db), so a server, several stdio agents and a shell
// can share one agora with nothing running in between. `--as` names
// the local identity; it is created on first use.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `deps/cli/src/cli.nu`
$ `service.nu`

: s AG_DEFAULT_ADDR `127.0.0.1:8820`

// --db → $AGORA_DB (the flag's env fallback) → ~/.agora/agora.db
@ __agm_db_path CliCtx x → String {
    : ~ String r ( ctx_str x `db` )
    ? > ( string_len r ) 0 { ^ r } {}
    ( string_free r )
    : String home ( env_var_or `HOME` `.` )
    : String dir ( path_join ( string_data home ) `.agora` )
    = r ( path_join ( string_data dir ) `agora.db` )
    ( string_free dir )
    ( string_free home )
    ^ r
}

// Open the store; F (with the message printed) when it cannot be.
@ __agm_open CliCtx x → b {
    : String db ( __agm_db_path x )
    : b ok ( ag_state_init ( string_data db ) )
    ? ok {} {
        ( nurl_eprint `agora: cannot open the store at ` )
        ( nurl_eprintln ( string_data db ) )
    }
    ( string_free db )
    ^ ok
}

// The local identity: --as, else $AGORA_AGENT. Empty when neither.
@ __agm_identity CliCtx x → b {
    : String raw ( ctx_str x `as` )
    : String who ( ag_identity_resolve ( string_data raw ) )
    : b from_cwd ( ag_identity_from_cwd ( string_data raw ) )
    ( string_free raw )
    ? ( ag_name_ok ( string_data who ) ) {} {
        ? > ( string_len who ) 0 {
            ( nurl_eprint `agora: --as must be ` )
            ( nurl_eprintln AG_NAME_RULE )
        } {
            ( nurl_eprintln `agora: say who you are: --as NAME (or $AGORA_AGENT)` )
        }
        ( string_free who )
        ^ F
    }
    ? from_cwd {
        : String origin ( ag_cwd )
        ( ag_state_set_local_from ( string_data who ) ( string_data origin ) )
        ( string_free origin )
    } { ( ag_state_set_local ( string_data who ) ) }
    ( string_free who )
    ^ T
}

@ __agm_cmd_serve CliCtx x → i {
    ? ( __agm_open x ) {} { ^ 1 }
    : String addr ( ctx_str x `addr` )
    : ~ String host ( string_new )
    : ~ i port 0
    ?? ( string_index_of addr `:` ) {
        T colon → {
            : i n ( string_len addr )
            : ~ i c 0
            ~ < c colon { ( string_push_char host ( string_get addr c ) ) = c + c 1 }
            : String ps ( string_substr addr + colon 1 - n + colon 1 )
            = port ( nurl_str_to_int ( string_data ps ) )
            ( string_free ps )
        }
        F _ → {
            ( string_push_str host ( string_data addr ) )
            = port 8820
        }
    }
    ( string_free addr )
    ? | <= port 0 > port 65535 {
        ( nurl_eprintln `agora: --addr needs HOST:PORT` )
        ( string_free host )
        ^ 2
    } {}
    : i workers ( ctx_int x `workers` )
    : b quiet ( ctx_bool x `quiet` )
    ? quiet {} {
        : String m ( string_from `agora ` )
        ( string_push_str m AG_VERSION )
        ( string_push_str m ` on http://` )
        ( string_push_str m ( string_data host ) )
        ( string_push_str m `:` )
        ( string_push_int m port )
        ( string_push_str m ` — REST at /api (GET /api lists the ops), MCP at /mcp` )
        ( nurl_eprintln ( string_data m ) )
        ( string_free m )
    }
    : i rc ( ag_serve ( string_data host ) port workers quiet )
    ( string_free host )
    ^ rc
}

@ __agm_cmd_stdio CliCtx x → i {
    ? ( __agm_open x ) {} { ^ 1 }
    ? ( __agm_identity x ) {} { ^ 2 }
    ( mcp_log `agora MCP (stdio) ready` )
    ^ ( ag_serve_stdio )
}

@ __agm_cmd_ops CliCtx x → i {
    : ( Vec AgOpDef ) cat ( ag_op_catalog )
    : i n ( vec_len [AgOpDef] cat )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [AgOpDef] cat i ) {
            T d → {
                : String line ( string_from ( string_data . d name ) )
                ? . d read_only { ( string_push_str line `  (read-only)` ) } {}
                ( string_push_str line `\n    ` )
                ( string_push_str line ( string_data . d desc ) )
                // The argument names, from the schema.
                ?? ( json_obj_get . d schema `properties` ) {
                    T props → {
                        : ( Vec String ) keys ( json_obj_keys props )
                        : i nk ( vec_len [String] keys )
                        ? > nk 0 { ( string_push_str line `\n    args: ` ) } {}
                        : ~ i k 0
                        ~ < k nk {
                            ?? ( vec_get [String] keys k ) {
                                T key → {
                                    ? > k 0 { ( string_push_str line `, ` ) } {}
                                    ( string_push_str line ( string_data key ) )
                                    ( string_free key )
                                }
                                F _ → {}
                            }
                            = k + k 1
                        }
                        ( vec_free [String] keys )
                    }
                    F _ → {}
                }
                ( nurl_println ( string_data line ) )
                ( string_free line )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( ag_catalog_free cat )
    ^ 0
}

// `agora <op> key=value ...` — the positionals after the op are the
// arguments; a value is a string, which every handler accepts for
// numbers too.
@ __agm_cmd_op CliCtx x → i {
    : String op ( ctx_arg x 0 )
    ? > ( string_len op ) 0 {} {
        ( string_free op )
        ( nurl_eprintln `agora: what to do? 'agora ops' lists the operations; 'agora --help' the commands` )
        ^ 2
    }
    ? < ( ag_op_auth_kind ( string_data op ) ) 0 {
        ( nurl_eprint `agora: unknown operation '` )
        ( nurl_eprint ( string_data op ) )
        ( nurl_eprintln `' — 'agora ops' lists them` )
        ( string_free op )
        ^ 2
    } {}
    ? ( __agm_open x ) {} { ( string_free op ) ^ 1 }
    : i now ( now_seconds )
    : ~ AgCaller caller ( ag_caller_anon )
    ? == ( ag_op_auth_kind ( string_data op ) ) 1 {
        ? ( __agm_identity x ) {} { ( string_free op ) ( ag_caller_free caller ) ^ 2 }
        ( ag_caller_free caller )
        = caller ( ag_caller_local_from ( ag_store ) ( ag_local_identity ) ( ag_local_origin ) now )
        ? . caller authed {} {
            ( nurl_eprint `agora: ` )
            ( nurl_eprintln ( ag_local_refusal ) )
            ( string_free op )
            ( json_free ( json_null ) )
            ( ag_caller_free caller )
            ^ 2
        }
    } {}
    : Json args ( json_obj_new )
    : i n ( ctx_nargs x )
    : ~ i i 1
    ~ < i n {
        : String kv ( ctx_arg x i )
        ?? ( string_index_of kv `=` ) {
            T eq → {
                : String k ( string_substr kv 0 eq )
                : String v ( string_substr kv + eq 1 - ( string_len kv ) + eq 1 )
                ( json_obj_set args ( string_data k ) ( json_str_lit ( string_data v ) ) )
                ( string_free k )
                ( string_free v )
            }
            F _ → {
                ( nurl_eprint `agora: arguments are key=value, not '` )
                ( nurl_eprint ( string_data kv ) )
                ( nurl_eprintln `'` )
            }
        }
        ( string_free kv )
        = i + i 1
    }
    : AgRes res ( ag_op_call ( ag_store ) caller ( string_data op ) args now )
    ( json_free args )
    ( ag_caller_free caller )
    ( string_free op )
    ? ( ctx_bool x `json` ) {
        : String js ( json_stringify . res body )
        ( nurl_println ( string_data js ) )
        ( string_free js )
    } {
        ( nurl_print ( string_data . res text ) )
        ? & > ( string_len . res text ) 0
        != ( string_get . res text - ( string_len . res text ) 1 ) 10 { ( nurl_print `\n` ) } {}
    }
    : i rc ? < . res status 400 0 1
    ( ag_res_free res )
    ( ag_state_free )
    ^ rc
}

@ main → i {
    : *Cli c ( cli_new `agora` `The agents' meeting place: channels, direct mail, a task board and shared notes — one SQLite file, served as MCP and REST.` AG_VERSION )
    ( cli_flag_str c `db` 0 `PATH` `the SQLite file (default ~/.agora/agora.db)` `` `AGORA_DB` )
    ( cli_flag_str c `as` 0 `NAME` `act as this local agent (stdio and direct operations); @cwd in NAME = the working directory's basename` `` `AGORA_AGENT` )
    ( cli_flag_str c `addr` 0 `HOST:PORT` `serve: where to listen` AG_DEFAULT_ADDR `AGORA_ADDR` )
    ( cli_flag_int c `workers` 0 `N` `serve: worker threads (0 = one per CPU)` 0 `AGORA_WORKERS` )
    ( cli_flag_bool c `quiet` 0 `serve: no access log or banner` )
    ( cli_flag_bool c `json` 0 `direct operations: print the JSON body instead of the text` )
    ( cli_cmd c `serve` `serve REST (/api) and MCP (/mcp) over HTTP` \ CliCtx x → i { ^ ( __agm_cmd_serve x ) } )
    ( cli_cmd c `stdio` `serve MCP over stdin/stdout as --as NAME` \ CliCtx x → i { ^ ( __agm_cmd_stdio x ) } )
    ( cli_cmd c `ops` `list the operations with their arguments` \ CliCtx x → i { ^ ( __agm_cmd_ops x ) } )
    ( cli_default c \ CliCtx x → i { ^ ( __agm_cmd_op x ) } )
    : i rc ( cli_run c )
    ( cli_free c )
    ^ rc
}
