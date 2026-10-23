// stdlib/ext/credentials.nu — per-registry auth tokens in ~/.nurl/credentials.
//
// `nurlpkg login` stores a registry's publish token here so `publish` /
// `yank` don't need $NURL_TOKEN in the environment (and out of shell
// history). The file is one record per line, TAB-separated:
//
//   <registry-url>\t<token>\n
//
// Written with write_file_private: created owner-only (0600 on POSIX; on
// Windows under the user profile, whose ACL is owner-only) and renamed into
// place, so the token is never readable by others, not even for the moment
// between a write and a chmod. Token lookup order in the CLI is $NURL_TOKEN
// first, then this file keyed by the exact registry URL.
//
// "~" is env_home_dir (std/ext/env.nu): $HOME on POSIX, the user profile on
// Windows. When the platform names no home there is no file: creds_path is
// "", creds_get finds nothing and creds_set / creds_remove fail with
// NotFound — a token is never written relative to the working directory.
//
// API:
//   ( creds_path )                      → String   ~/.nurl/credentials, "" if no home
//   ( creds_get registry )              → String   token, or "" if none
//   ( creds_set registry token )        → ! v IoErr   (upsert, owner-only)
//   ( creds_remove registry )           → ! v IoErr

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`

// ~/.nurl, or "" when there is no home.
@ __creds_dir → String {
    : String d ( env_home_dir )
    ? == ( string_len d ) 0 { ^ d } {}
    ( string_push_str d `/.nurl` )
    ^ d
}

@ creds_path → String {
    : String p ( __creds_dir )
    ? == ( string_len p ) 0 { ^ p } {}
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
                        }
                        F → {}
                    }
                    ? != keep 0 {
                        ( string_push_str out ( string_data line ) )
                        ( string_push_char out 10 )
                    } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ creds_get s registry → String {
    : String path ( creds_path )
    ? == ( string_len path ) 0 { ^ ( string_new ) } {}
    : !String IoErr rr ( read_file ( string_data path ) )
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
                                    = out ( string_substr line + ti 1 - ( string_len line ) + ti 1 )
                                } {}
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
    ^ out
}

@ creds_set s registry s token → !v IoErr {
    : String dir ( __creds_dir )
    ? == ( string_len dir ) 0 { ^ @ !v IoErr { F # IoErr NotFound } } {}
    : !v IoErr dr ( dir_create_all ( string_data dir ) )
    ?? dr { T _ → {} F e → { ^ @ !v IoErr { F e } } }

    : String path ( creds_path )
    : ~ String body ( string_new )
    : !String IoErr rr ( read_file ( string_data path ) )
    ?? rr {
        T content → {
            = body ( __creds_without content registry )
        }
        F → {}
    }
    ( string_push_str body registry )
    ( string_push_char body 9 )  // TAB
    ( string_push_str body token )
    ( string_push_char body 10 )  // \n
    ^ ( write_file_private ( string_data path ) ( string_data body ) )
}

@ creds_remove s registry → !v IoErr {
    : String path ( creds_path )
    ? == ( string_len path ) 0 { ^ @ !v IoErr { F # IoErr NotFound } } {}
    : !String IoErr rr ( read_file ( string_data path ) )
    ?? rr {
        T content → {
            : String body ( __creds_without content registry )
            ^ ( write_file_private ( string_data path ) ( string_data body ) )
        }
        F → {}  // no file → nothing to remove
    }
    ^ @ !v IoErr { T 0 }
}
