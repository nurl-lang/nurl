// cas — a content-addressed store over BLAKE3, from the command line.
//
//   cas put file.bin                 store bytes        → prints the hash
//   cas hash file.bin                name without storing
//   cas get <hash> [-o out.bin]      fetch + VERIFY (stdout by default)
//   cas snapshot ./dir               whole tree → one manifest hash
//   cas ls <manifest-hash>           list a snapshot
//   cas checkout <manifest-hash> ./dest    materialise + verify
//   cas verify <hash>                deep-prove a blob or a whole snapshot
//
// The store is plain files under --store DIR (default $CAS_STORE, else
// ~/.cas): rsync it, mirror it, cache it — `get`/`checkout`/`verify`
// re-hash everything they touch, so a lying store is an error, never
// silent corruption.

$ `stdlib/core/io.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `cas.nu`
$ `manifest.nu`

@ __cli_store_root ArgParser p → String {
    : ?String ov ( args_value p `store` )
    ?? ov { T v → { ^ v } F → {} }
    : ?String ev ( env_get `CAS_STORE` )
    ?? ev { T v → { ^ v } F → {} }
    : String home ( env_var_or `HOME` `.` )
    : String r ( path_join ( string_data home ) `.cas` )
    ( string_free home )
    ^ r
}

// Raw bytes to stdout (fd 1) — binary-safe, unlike the string printers.
@ __cli_write_stdout ( Vec u ) data → v {
    : i n ( vec_len [u] data )
    ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] data ) n ) } {}
}

@ __cli_err String e → i {
    ( nurl_eprintln ( string_data e ) )
    ( string_free e )
    ^ 1
}

@ main → i {
    : ArgParser p ( args_new `cas` `Content-addressed store over BLAKE3: put/get blobs, snapshot/checkout trees, verify everything.` )
    ( args_opt p `store` 115 `DIR` `store root (default: $CAS_STORE, else ~/.cas)` )
    ( args_opt p `output` 111 `FILE` `for get: write here instead of stdout` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )

    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  put <file> · hash <file> · get <hash> [-o FILE] · snapshot <dir>\n  ls <manifest-hash> · checkout <manifest-hash> <dir> · verify <hash>\n` )
        ( string_free u ) ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print `cas 0.1.0\n` )
        ( args_free p )
        ^ 0
    } {}

    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: cas <put|hash|get|snapshot|ls|checkout|verify> … (cas --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }
    : ~ String a1 ( string_new )
    ? >= ( args_positional_count p ) 2 {
        ?? ( vec_get [String] pos 1 ) { T v → { ( string_free a1 ) = a1 ( string_from ( string_data v ) ) } F → {} }
    } {}
    : ~ String a2 ( string_new )
    ? >= ( args_positional_count p ) 3 {
        ?? ( vec_get [String] pos 2 ) { T v → { ( string_free a2 ) = a2 ( string_from ( string_data v ) ) } F → {} }
    } {}

    // `hash` needs no store at all.
    ? ( nurl_str_eq cmd `hash` ) {
        : !( Vec u ) IoErr r ( read_file_bytes ( string_data a1 ) )
        ?? r {
            T data → {
                : String hex ( cas_hash_hex data )
                ( vec_free [u] data )
                ( nurl_print ( string_data hex ) ) ( nurl_print `\n` )
                ( string_free hex )
                ^ 0
            }
            F _ → { ^ ( __cli_err ( string_from `cas: cannot read the input file` ) ) }
        }
    } {}

    : String root ( __cli_store_root p )
    : !Cas String co ( cas_open ( string_data root ) )
    ( string_free root )
    ?? co {
        T c → {
            : ~ i rc 0
            ? ( nurl_str_eq cmd `put` ) {
                : !String String r ( cas_put_file c ( string_data a1 ) )
                ?? r {
                    T hex → { ( nurl_print ( string_data hex ) ) ( nurl_print `\n` ) ( string_free hex ) }
                    F e → { = rc ( __cli_err e ) }
                }
            } {
                ? ( nurl_str_eq cmd `get` ) {
                    : !( Vec u ) String r ( cas_get c ( string_data a1 ) )
                    ?? r {
                        T data → {
                            : ?String oo ( args_value p `output` )
                            ?? oo {
                                T out → {
                                    : !v IoErr wr ( write_file_bytes ( string_data out ) data )
                                    ?? wr { T _ → {} F _ → { = rc ( __cli_err ( string_from `cas: cannot write the output file` ) ) } }
                                    ( string_free out )
                                }
                                F → { ( __cli_write_stdout data ) }
                            }
                            ( vec_free [u] data )
                        }
                        F e → { = rc ( __cli_err e ) }
                    }
                } {
                    ? ( nurl_str_eq cmd `snapshot` ) {
                        : !String String r ( cas_snapshot c ( string_data a1 ) )
                        ?? r {
                            T hex → { ( nurl_print ( string_data hex ) ) ( nurl_print `\n` ) ( string_free hex ) }
                            F e → { = rc ( __cli_err e ) }
                        }
                    } {
                        ? ( nurl_str_eq cmd `ls` ) {
                            : !( Vec u ) String r ( cas_get c ( string_data a1 ) )
                            ?? r {
                                T data → {
                                    ? ( manifest_is data ) { ( __cli_write_stdout data ) } {
                                        = rc ( __cli_err ( string_from `cas: that object is a blob, not a manifest` ) )
                                    }
                                    ( vec_free [u] data )
                                }
                                F e → { = rc ( __cli_err e ) }
                            }
                        } {
                            ? ( nurl_str_eq cmd `checkout` ) {
                                : !i String r ( cas_checkout c ( string_data a1 ) ( string_data a2 ) )
                                ?? r {
                                    T nfiles → {
                                        : String msg ( string_from `checked out ` )
                                        ( string_push_int msg nfiles )
                                        ( string_push_str msg ` file(s), all verified\n` )
                                        ( nurl_print ( string_data msg ) )
                                        ( string_free msg )
                                    }
                                    F e → { = rc ( __cli_err e ) }
                                }
                            } {
                                ? ( nurl_str_eq cmd `verify` ) {
                                    : !i String r ( cas_verify c ( string_data a1 ) )
                                    ?? r {
                                        T nobj → {
                                            : String msg ( string_from `OK — ` )
                                            ( string_push_int msg nobj )
                                            ( string_push_str msg ` object(s) proven\n` )
                                            ( nurl_print ( string_data msg ) )
                                            ( string_free msg )
                                        }
                                        F e → { = rc ( __cli_err e ) }
                                    }
                                } {
                                    ( nurl_eprintln `cas: unknown command (cas --help)` )
                                    = rc 2
                                } } } } } }
            ( cas_free c )
            ( string_free a1 ) ( string_free a2 ) ( args_free p )
            ^ rc
        }
        F e → {
            ( string_free a1 ) ( string_free a2 ) ( args_free p )
            ^ ( __cli_err e )
        }
    }
}
