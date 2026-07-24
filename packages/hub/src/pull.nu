// packages/hub/src/pull.nu — the transfer engine: stream a URL into a
// content-addressed blob, constant-memory and resumable.
//
// HTTP chunks flow straight to disk through file_write_chunk while an
// incremental sha256 consumes the same bytes and a tty-gated progress
// bar narrates. An interrupted pull leaves blobs/<staging>.part; the
// next attempt sends `Range: bytes=<size>-` — a 206 re-hashes the
// existing part (streamed) and appends, a 200 (server without Range)
// restarts cleanly. The finished file is renamed to its content
// address (blobs/sha256-<hex>) and the hex is returned.
//
// When `expected` is a 64-hex sha256 (Hugging Face publishes one for
// every LFS file) two things change: an already-cached blob is returned
// without touching the network, and a completed download whose bytes do
// not hash to `expected` is discarded as corrupt rather than stored.
//
//   ( hub_fetch_blob root url staging expected ) → !String String   (hex)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/ext/http.nu`
// siblings (store: hub_blob_path, _hub_safe_name) are provided by the entry
// point that imports every hub file — see the note in hub.nu.

// case-insensitive response-header lookup → owned value ("" if absent)
@ __hub_find_header HttpStream st s want → String {
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
@ __hub_rehash_part * Sha256 h s path → !i String {
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
        F _ → { ^ @ !i String { F ( string_from `hub: cannot reopen the partial download` ) } }
    }
}

@ hub_fetch_blob String root s url s staging s expected → !String String {
    // already cached? a content-addressed name is its own proof.
    ? == ( nurl_str_len expected ) 64 {
        : String bp0 ( hub_blob_path root expected )
        ? ( file_exists ( string_data bp0 ) ) {
            ( string_free bp0 )
            ^ @ !String String { T ( string_from expected ) }
        } {}
        ( string_free bp0 )
    } {}

    // staging path: blobs/<safe-staging>.part
    : String bdir ( path_join ( string_data root ) `blobs` )
    : String sname ( _hub_safe_name staging )
    : String part0 ( path_join ( string_data bdir ) ( string_data sname ) )
    ( string_free bdir )
    ( string_free sname )
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

    : !HttpStream HttpErr sr ( http_stream_open `GET` url `` ( string_data hdrs ) )
    ( string_free hdrs )
    ?? sr {
        T st → {
            : i status ( http_stream_pump_headers st )
            : ~ b resume F
            ? == status 206 { = resume T } {}
            ? | == status 200 == status 206 {} {
                ( http_stream_close st )
                ( string_free part )
                : String msg ( string_from `hub: download failed (HTTP ` )
                ( string_push_int msg status )
                ( string_push_str msg `)` )
                ^ @ !String String { F msg }
            }

            : String cl ( __hub_find_header st `content-length` )
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

            : ~ i fh_ok 0
            : ~ File f @ File { # s 0 }
            ? resume {
                : !i String rr ( __hub_rehash_part h ( string_data part ) )
                ?? rr {
                    T n → { = done_bytes n }
                    F e → { = failed T ( string_free ferr ) = ferr e }
                }
                ? failed {} {
                    ?? ( file_append ( string_data part ) ) {
                        T fa → { = f fa = fh_ok 1 }
                        F _ → { = failed T ( string_free ferr ) = ferr ( string_from `hub: cannot open the staging file` ) }
                    }
                }
            } {
                ?? ( file_create ( string_data part ) ) {
                    T fa → { = f fa = fh_ok 1 }
                    F _ → { = failed T ( string_free ferr ) = ferr ( string_from `hub: cannot create the staging file` ) }
                }
            }

            : *Progress pg ( progress_new staging total )
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
                                    = ferr ( string_from `hub: disk write failed mid-download` )
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

            ? failed {} {
                : ?HttpErr he ( http_stream_err st )
                ?? he {
                    T _ → {
                        = failed T
                        ( string_free ferr )
                        = ferr ( string_from `hub: transfer aborted — rerun to resume from the partial file` )
                    }
                    F → {}
                }
            }
            ( http_stream_close st )
            : ( Vec u ) dg ( sha256_final h )
            ? failed {
                ( vec_free [u] dg )
                ( string_free part )
                ^ @ !String String { F ferr }
            } {}
            ( string_free ferr )

            ? & > total 0 != done_bytes total {
                ( vec_free [u] dg )
                ( string_free part )
                ^ @ !String String { F ( string_from `hub: transfer ended short — rerun to resume from the partial file` ) }
            } {}

            : String hex ( bytes_to_hex dg )
            ( vec_free [u] dg )

            // integrity: bytes must hash to the sha the source published
            ? & == ( nurl_str_len expected ) 64 == ( nurl_str_eq ( string_data hex ) expected ) 0 {
                ( file_delete ( string_data part ) )
                ( string_free part )
                : String msg ( string_from `hub: INTEGRITY FAILURE — downloaded bytes do not match the published sha256 (` )
                : String short ( string_substr hex 0 12 )
                ( string_push_str msg ( string_data short ) )
                ( string_free short )
                ( string_push_str msg ` vs expected)` )
                ( string_free hex )
                ^ @ !String String { F msg }
            } {}

            : String bp ( hub_blob_path root ( string_data hex ) )
            : !v IoErr mv ( fs_rename ( string_data part ) ( string_data bp ) )
            ( string_free bp )
            ( string_free part )
            ?? mv {
                T _ → { ^ @ !String String { T hex } }
                F _ → {
                    ( string_free hex )
                    ^ @ !String String { F ( string_from `hub: cannot move the finished blob into place` ) }
                }
            }
        }
        F _ → {
            ( string_free part )
            ^ @ !String String { F ( string_from `hub: cannot reach the download URL` ) }
        }
    }
}
