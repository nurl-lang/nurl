// Test: handle-based streaming writes + seeking (stdlib/std/fs.nu).
// file_create/file_write_chunk build a file in pieces (binary-safe,
// NULs included); file_append extends it; file_seek/file_tell/
// file_read_at give random access — the primitives under resumable
// downloads and large exports.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`

: s TPATH `/tmp/nurl_fswh_test.bin`

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ main → i {
    ( file_delete TPATH )

    // create + two chunks, the first with an embedded NUL
    : ( Vec u ) c1 ( vec_new [u] )
    ( bytes_extend_str c1 `hello` )
    ( vec_push [u] c1 # u 0 )
    ( bytes_extend_str c1 `world` )
    : ( Vec u ) c2 ( vec_new [u] )
    ( bytes_extend_str c2 `-streamed` )
    ?? ( file_create TPATH ) {
        T f → {
            : ~ b ok T
            ?? ( file_write_chunk f c1 ) { T _ → {} F _ → { = ok F } }
            ?? ( file_flush f ) { T _ → {} F _ → { = ok F } }
            ?? ( file_write_chunk f c2 ) { T _ → {} F _ → { = ok F } }
            // tell: 11 + 9 = 20
            ?? ( file_tell f ) {
                T posn → { ( ck & ok == posn 20 `create + chunks + tell` ) }
                F _ → { ( ck F `create + chunks + tell` ) }
            }
            ( file_close f )
        }
        F _ → { ( ck F `create + chunks + tell` ) }
    }
    ( vec_free [u] c1 )

    // append a third chunk
    ?? ( file_append TPATH ) {
        T f → {
            ?? ( file_write_chunk f c2 ) {
                T _ → { ( ck T `append` ) }
                F _ → { ( ck F `append` ) }
            }
            ( file_close f )
        }
        F _ → { ( ck F `append` ) }
    }
    ( vec_free [u] c2 )

    // whole-file read back: 29 bytes, NUL intact at index 5
    ?? ( read_file_bytes TPATH ) {
        T all → {
            : ~ i b5 -1
            ?? ( vec_get [u] all 5 ) { T x → { = b5 # i x } F → {} }
            ( ck & == ( vec_len [u] all ) 29 == b5 0 `binary round-trip (29 B, NUL kept)` )
            ( vec_free [u] all )
        }
        F _ → { ( ck F `binary round-trip` ) }
    }

    // random access on a read handle: seek END for size, read_at
    ?? ( file_open TPATH ) {
        T f → {
            ?? ( file_seek f 0 FS_SEEK_END ) {
                T sz → { ( ck == sz 29 `seek END reports size` ) }
                F _ → { ( ck F `seek END reports size` ) }
            }
            ?? ( file_read_at f 6 5 ) {
                T v → {
                    : String got ( bytes_to_str v )
                    ( ck ( string_eq_s got `world` ) `read_at mid-file` )
                    ( string_free got )
                    ( vec_free [u] v )
                }
                F _ → { ( ck F `read_at mid-file` ) }
            }
            // relative seek: CUR is at 11 now; +9 → 20, then read tail
            ?? ( file_seek f 9 FS_SEEK_CUR ) {
                T posn → { ( ck == posn 20 `seek CUR` ) }
                F _ → { ( ck F `seek CUR` ) }
            }
            ?? ( file_read_chunk f 64 ) {
                T v → {
                    : String got ( bytes_to_str v )
                    ( ck ( string_eq_s got `-streamed` ) `tail after seek` )
                    ( string_free got )
                    ( vec_free [u] v )
                }
                F _ → { ( ck F `tail after seek` ) }
            }
            ( file_close f )
        }
        F _ → { ( ck F `read handle` ) }
    }

    // error path: writing to a directory path fails cleanly
    ?? ( file_create `/tmp` ) {
        T f → {
            ( file_close f )
            ( ck F `create on a directory rejects` )
        }
        F _ → { ( ck T `create on a directory rejects` ) }
    }

    ( file_delete TPATH )
    ^ 0
}

@ string_eq_s String a s raw → b {
    ^ ? ( nurl_str_eq ( string_data a ) raw ) T F
}
