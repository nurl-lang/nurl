// packages/nurllama/src/pull.nu — streaming model download with resume.
//
// The whole transfer is constant-memory: HTTP chunks flow straight to
// disk through file_write_chunk while the incremental sha256 consumes
// the same bytes and a tty-gated progress bar narrates. An interrupted
// pull leaves blobs/<name>.part; the next attempt sends
// `Range: bytes=<size>-` — a 206 re-hashes the existing part
// (streamed) and appends, a 200 (server without Range) restarts
// cleanly. The finished file is renamed to its content address
// (blobs/sha256-<hex>) and a manifest records name → digest.
//
//   ( nl_resolve_url src )        → String   hf.co/ORG/REPO/FILE shorthand
//                                             → the HF resolve URL;
//                                             http(s):// passes through
//   ( nl_default_name src )      → String   basename minus .gguf
//   ( nl_pull root src name )    → !v String

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/ext/http.nu`
$ `src/store.nu`

// hf.co/ORG/REPO/path/to/file.gguf → https://huggingface.co/ORG/REPO/resolve/main/path/to/file.gguf
@ nl_resolve_url s src → String {
    ? | != ( nurl_str_starts src `http://` ) 0 != ( nurl_str_starts src `https://` ) 0 {
        ^ ( string_from src )
    } {}
    ? != ( nurl_str_starts src `hf.co/` ) 0 {
        // split ORG/REPO from the file path: the first two segments
        : i n ( nurl_str_len src )
        : ~ i slashes 0
        : ~ i cut -1
        : ~ i k 6
        ~ & < k n < cut 0 {
            ? == ( nurl_str_get src k ) 47 {
                = slashes + slashes 1
                ? == slashes 2 { = cut k } {}
            } {}
            = k + k 1
        }
        ? > cut 0 {
            : String out ( string_from `https://huggingface.co/` )
            : ~ i j 6
            ~ < j cut {
                ( string_push_char out ( nurl_str_get src j ) )
                = j + j 1
            }
            ( string_push_str out `/resolve/main/` )
            = j + cut 1
            ~ < j n {
                ( string_push_char out ( nurl_str_get src j ) )
                = j + j 1
            }
            ^ out
        } {}
    } {}
    ^ ( string_from src )
}

// last path segment, ".gguf" stripped — the default store name
@ nl_default_name s src → String {
    : i n ( nurl_str_len src )
    : ~ i start 0
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get src k ) 47 { = start + k 1 } {}
        = k + k 1
    }
    : String out ( string_new )
    = k start
    ~ < k n {
        ( string_push_char out ( nurl_str_get src k ) )
        = k + k 1
    }
    ? ( string_ends_with out `.gguf` ) {
        : String cutd ( string_substr out 0 - ( string_len out ) 5 )
        ( string_free out )
        ^ cutd
    } {}
    ^ out
}

// case-insensitive response-header lookup → owned value ("" if absent)
@ __nl_find_header HttpStream st s want → String {
    : ~ String out ( string_new )
    : i hc ( http_stream_header_count st )
    : ~ i k 0
    ~ < k hc {
        : s nm ( http_stream_header_name st k )
        : String low ( string_from nm )
        : String lowc ( string_to_lower low )
        ( string_free low )
        ? ( nurl_str_eq ( string_data lowc ) want ) {
            ( string_free out )
            = out ( string_from ( http_stream_header_value st k ) )
            = k hc
        } { = k + k 1 }
        ( string_free lowc )
    }
    ^ out
}

// Feed the existing .part through the hasher (resume path).
@ __nl_rehash_part * Sha256 h s path → !i String {
    : !File IoErr fr ( file_open path )
    ?? fr {
        T f → {
            : ~ i total 0
            : ~ b more T
            ~ more {
                : !( Vec u ) IoErr cr ( file_read_chunk f 1048576 )
                ?? cr {
                    T piece → {
                        : i pn ( vec_len [u] piece )
                        ? == pn 0 { = more F } {
                            ( sha256_update h piece )
                            = total + total pn
                        }
                        ( vec_free [u] piece )
                    }
                    F _ → { = more F }
                }
            }
            ( file_close f )
            ^ @ !i String { T total }
        }
        F _ → { ^ @ !i String { F ( string_from `nurllama: cannot reopen the partial download` ) } }
    }
}

@ nl_pull String root s src s name_override → !v String {
    : !v String ir ( nl_store_init root )
    ?? ir {
        T _ → {}
        F e → { ^ @ !v String { F e } }
    }
    : String url ( nl_resolve_url src )
    : ~ String name ( string_new )
    ? > ( nurl_str_len name_override ) 0 {
        ( string_free name )
        = name ( string_from name_override )
    } {
        ( string_free name )
        = name ( nl_default_name src )
    }
    ? > ( string_len name ) 0 {} {
        ( string_free name )
        ( string_free url )
        ^ @ !v String { F ( string_from `nurllama: cannot derive a model name — pass --name` ) }
    }

    // staging path: blobs/<safe-name>.part
    : String bdir ( path_join ( string_data root ) `blobs` )
    : String part0 ( path_join ( string_data bdir ) ( string_data name ) )
    ( string_free bdir )
    : String part ( string_from ( string_data part0 ) )
    ( string_push_str part `.part` )
    ( string_free part0 )

    // resume offset = existing partial size
    : ~ i off 0
    ?? ( file_size ( string_data part ) ) {
        T sz → { = off sz }
        F _ → {}
    }
    : String hdrs ( string_new )
    ? > off 0 {
        ( string_push_str hdrs `Range: bytes=` )
        ( string_push_int hdrs off )
        ( string_push_str hdrs `-\r\n` )
    } {}

    : !HttpStream HttpErr sr ( http_stream_open `GET` ( string_data url ) `` ( string_data hdrs ) )
    ( string_free hdrs )
    ?? sr {
        T st → {
            : i status ( http_stream_pump_headers st )
            : ~ b resume F
            ? == status 206 { = resume T } {}
            ? | == status 200 == status 206 {} {
                ( http_stream_close st )
                ( string_free part ) ( string_free name ) ( string_free url )
                : String msg ( string_from `nurllama: download failed (HTTP ` )
                ( string_push_int msg status )
                ( string_push_str msg `)` )
                ^ @ !v String { F msg }
            }

            // total size for the bar: Content-Length (+ resume offset)
            : String cl ( __nl_find_header st `content-length` )
            : ~ i total 0
            ?? ( string_to_int cl ) {
                T v → { = total v }
                F _ → {}
            }
            ( string_free cl )
            ? & resume > total 0 { = total + total off } {}

            : *Sha256 h ( sha256_init )
            : ~ i done_bytes 0
            : ~ b failed F
            : ~ String ferr ( string_new )

            // open the staging file: append on a true 206, else truncate
            : ~ i fh_ok 0
            : ~ File f @ File { # s 0 }
            ? resume {
                : !i String rr ( __nl_rehash_part h ( string_data part ) )
                ?? rr {
                    T n → { = done_bytes n }
                    F e → {
                        = failed T
                        ( string_free ferr )
                        = ferr e
                    }
                }
                ? failed {} {
                    ?? ( file_append ( string_data part ) ) {
                        T fa → { = f fa = fh_ok 1 }
                        F _ → { = failed T ( string_free ferr ) = ferr ( string_from `nurllama: cannot open the staging file` ) }
                    }
                }
            } {
                ?? ( file_create ( string_data part ) ) {
                    T fa → { = f fa = fh_ok 1 }
                    F _ → { = failed T ( string_free ferr ) = ferr ( string_from `nurllama: cannot create the staging file` ) }
                }
            }

            : *Progress pg ( progress_new ( string_data name ) total )
            ? > done_bytes 0 { ( progress_set pg done_bytes ) } {}
            : ~ b more ! failed
            ~ more {
                : ?( Vec u ) ch ( http_stream_next_bytes st )
                ?? ch {
                    T piece → {
                        : i pn ( vec_len [u] piece )
                        ? > pn 0 {
                            ?? ( file_write_chunk f piece ) {
                                T _ → {
                                    ( sha256_update h piece )
                                    = done_bytes + done_bytes pn
                                    ( progress_add pg pn )
                                }
                                F _ → {
                                    = failed T
                                    = more F
                                    ( string_free ferr )
                                    = ferr ( string_from `nurllama: disk write failed mid-download` )
                                }
                            }
                        } {}
                        ( vec_free [u] piece )
                    }
                    F → { = more F }
                }
            }
            ? == fh_ok 1 { ( file_close f ) } {}
            ( progress_done pg )

            // did the transfer itself fail?
            ? failed {} {
                : ?HttpErr he ( http_stream_err st )
                ?? he {
                    T _ → {
                        = failed T
                        ( string_free ferr )
                        = ferr ( string_from `nurllama: transfer aborted — rerun to resume from the partial file` )
                    }
                    F → {}
                }
            }
            ( http_stream_close st )
            : ( Vec u ) dg ( sha256_final h )
            ? failed {
                ( vec_free [u] dg )
                ( string_free part ) ( string_free name ) ( string_free url )
                ^ @ !v String { F ferr }
            } {}
            ( string_free ferr )

            // content-length sanity: a short body is a broken download
            ? & > total 0 != done_bytes total {
                ( vec_free [u] dg )
                ( string_free part ) ( string_free name ) ( string_free url )
                ^ @ !v String { F ( string_from `nurllama: transfer ended short — rerun to resume from the partial file` ) }
            } {}

            : String hex ( bytes_to_hex dg )
            ( vec_free [u] dg )
            : String bp ( nl_blob_path root ( string_data hex ) )
            : !v IoErr mv ( fs_rename ( string_data part ) ( string_data bp ) )
            ?? mv {
                T _ → {}
                F _ → {
                    ( string_free hex ) ( string_free bp )
                    ( string_free part ) ( string_free name ) ( string_free url )
                    ^ @ !v String { F ( string_from `nurllama: cannot move the finished blob into place` ) }
                }
            }
            : !v String ar ( nl_store_add root ( string_data name ) ( string_data url ) ( string_data hex ) done_bytes )
            ( string_free bp )
            ?? ar {
                T _ → {}
                F e → {
                    ( string_free hex ) ( string_free part ) ( string_free name ) ( string_free url )
                    ^ @ !v String { F e }
                }
            }
            : String msg ( string_from `pulled ` )
            ( string_push_str msg ( string_data name ) )
            ( string_push_str msg ` (sha256:` )
            : String short ( string_substr hex 0 12 )
            ( string_push_str msg ( string_data short ) )
            ( string_free short )
            ( string_push_str msg `…, ` )
            : String hs ( progress_human done_bytes )
            ( string_push_str msg ( string_data hs ) )
            ( string_free hs )
            ( string_push_str msg `)` )
            ( nurl_print ( string_data msg ) )
            ( nurl_print `\n` )
            ( string_free msg )
            ( string_free hex )
            ( string_free part ) ( string_free name ) ( string_free url )
            ^ @ !v String { T 0 }
        }
        F _ → {
            ( string_free part ) ( string_free name ) ( string_free url )
            ^ @ !v String { F ( string_from `nurllama: cannot reach the download URL` ) }
        }
    }
}
