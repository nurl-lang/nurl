// stdlib/ext/credentials.nu — per-registry auth tokens in ~/.nurl/credentials.
//
// `nurlpkg login` stores a registry's publish token here so `publish` /
// `yank` don't need $NURL_TOKEN in the environment (and out of shell
// history). The file is one record per line, TAB-separated:
//
//   <registry-url>\t<token>\n
//
// chmod 600 on write (owner-only). Token lookup order in the CLI is
// $NURL_TOKEN first, then this file keyed by the exact registry URL.
//
// API:
//   ( creds_path )                      → String   ~/.nurl/credentials
//   ( creds_get registry )              → String   token, or "" if none
//   ( creds_set registry token )        → ! v IoErr   (upsert, chmod 600)
//   ( creds_remove registry )           → ! v IoErr

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

@ __creds_home → String {
    : ?String h ( env_get `HOME` )
    ^ ?? h {
        T hv → { ? > ( string_len hv ) 0 hv { ( string_free hv ) ( string_from `.` ) } }
        F → ( string_from `.` )
    }
}

@ __creds_dir → String {
    : String d ( __creds_home )
    ( string_push_str d `/.nurl` )
    ^ d
}

@ creds_path → String {
    : String p ( __creds_dir )
    ( string_push_str p `/credentials` )
    ^ p
}

// Rebuild `content` with every line for `registry` removed (and blank
// lines dropped). Used by both set (then append) and remove.
@ __creds_without String content s registry → String {
    : String out ( string_new )
    : ( Vec String ) lines ( string_split content `\n` )
    : i n ( vec_len [String] lines )
    : ~ i k 0
    ~ < k n {
        : ?String lo ( vec_get [String] lines k )
        ?? lo {
            T line → {
                ? > ( string_len line ) 0 {
                    : ?i tab ( string_index_of line `\t` )
                    : ~ i keep 1
                    ?? tab {
                        T ti → {
                            : String reg ( string_substr line 0 ti )
                            ? != 0 ( nurl_str_eq ( string_data reg ) registry ) { = keep 0 } {}
                            ( string_free reg )
                        }
                        F → {}
                    }
                    ? != keep 0 {
                        ( string_push_str out ( string_data line ) )
                        ( string_push_char out 10 )
                    } {}
                } {}
                ( string_free line )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free [String] lines )
    ^ out
}

@ creds_get s registry → String {
    : String path ( creds_path )
    : !String IoErr rr ( read_file ( string_data path ) )
    ( string_free path )
    : ~ String out ( string_new )
    ?? rr {
        T content → {
            : ( Vec String ) lines ( string_split content `\n` )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ < k n {
                : ?String lo ( vec_get [String] lines k )
                ?? lo {
                    T line → {
                        : ?i tab ( string_index_of line `\t` )
                        ?? tab {
                            T ti → {
                                : String reg ( string_substr line 0 ti )
                                ? != 0 ( nurl_str_eq ( string_data reg ) registry ) {
                                    ( string_free out )
                                    = out ( string_substr line + ti 1 - ( string_len line ) + ti 1 )
                                } {}
                                ( string_free reg )
                            }
                            F → {}
                        }
                        ( string_free line )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [String] lines )
            ( string_free content )
        }
        F → {}
    }
    ^ out
}

@ creds_set s registry s token → !v IoErr {
    : String dir ( __creds_dir )
    : !v IoErr dr ( dir_create_all ( string_data dir ) )
    ( string_free dir )
    ?? dr { T _ → {} F e → { ^ @ !v IoErr { F e } } }

    : String path ( creds_path )
    : ~ String body ( string_new )
    : !String IoErr rr ( read_file ( string_data path ) )
    ?? rr {
        T content → {
            ( string_free body )
            = body ( __creds_without content registry )
            ( string_free content )
        }
        F → {}
    }
    ( string_push_str body registry )
    ( string_push_char body 9 )  // TAB
    ( string_push_str body token )
    ( string_push_char body 10 )  // \n
    : !v IoErr wr ( write_file ( string_data path ) ( string_data body ) )
    : !v IoErr _cm ( set_permissions ( string_data path ) 384 )  // 0600
    ( string_free body )
    ( string_free path )
    ^ wr
}

@ creds_remove s registry → !v IoErr {
    : String path ( creds_path )
    : !String IoErr rr ( read_file ( string_data path ) )
    : ~ i rc 0
    ?? rr {
        T content → {
            : String body ( __creds_without content registry )
            : !v IoErr wr ( write_file ( string_data path ) ( string_data body ) )
            ?? wr { T _ → {} F _ → { = rc 1 } }
            : !v IoErr _cm ( set_permissions ( string_data path ) 384 )
            ( string_free body )
            ( string_free content )
        }
        F → {}  // no file → nothing to remove
    }
    ( string_free path )
    ? != rc 0 { ^ @ !v IoErr { F # IoErr WriteFailed } } {}
    ^ @ !v IoErr { T 0 }
}
