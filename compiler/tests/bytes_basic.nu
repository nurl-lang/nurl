// Test: stdlib/std/bytes.nu — byte-buffer convenience layer over Vec[u].
// Also exercises stdlib/std/fs.nu's binary I/O API.

$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`

@ show_opt_i s label ? i o → v {
    ?? o {
        T x → {
            ( nurl_print label )
            ( nurl_print ` -> ` )
            ( nurl_print ( nurl_str_int x ) )
            ( nurl_print `\n` )
        }
        F _ → {
            ( nurl_print label )
            ( nurl_print ` -> none\n` )
        }
    }
}

@ main → i {
    // ── Vec[u] CRUD via the raw vec_* API works, demonstrating that the
    //    byte buffer IS just a Vec[u] under the hood. ─────────────────
    : ( Vec u ) v ( vec_with_cap [u] 4 )
    ( vec_push [u] v # u 1 )
    ( vec_push [u] v # u 2 )
    ( vec_push [u] v # u 3 )
    ( nurl_print_int ( vec_len [u] v ) )  // 3
    ( vec_free [u] v )

    // ── bytes_from_str / bytes_to_str round-trip ─────────────────────
    : ( Vec u ) hello ( bytes_from_str `hello` )
    ( nurl_print_int ( vec_len [u] hello ) )  // 5
    : String back ( bytes_to_str hello )
    ( nurl_print ( string_data back ) )
    ( nurl_print `\n` )
    ( string_free back )

    // ── bytes_extend_str on top of an existing buffer ────────────────
    ( bytes_extend_str hello ` world` )
    : String hw ( bytes_to_str hello )
    ( nurl_print ( string_data hw ) )
    ( nurl_print `\n` )
    ( string_free hw )

    // ── Hex round-trip — must match canonical lowercase output ───────
    : String hex ( bytes_to_hex hello )
    ( nurl_print ( string_data hex ) )
    ( nurl_print `\n` )

    : !( Vec u ) ParseErr decoded ( bytes_from_hex ( string_data hex ) )
    ?? decoded {
        T dv → {
            ( nurl_print_int ( vec_len [u] dv ) )  // 11
            : b same ( bytes_eq hello dv )
            ? same ( nurl_print `roundtrip ok\n` )
            ( nurl_print `roundtrip MISMATCH\n` )
            ( vec_free [u] dv )
        }
        F _ → ( nurl_print `decode failed\n` )
    }
    ( string_free hex )

    // ── Decode error paths ───────────────────────────────────────────
    : !( Vec u ) ParseErr empty_dec ( bytes_from_hex `` )
    ?? empty_dec {
        T v → { ( nurl_print `WRONG empty ok\n` ) ( vec_free [u] v ) }
        F e → {
            ( nurl_print `empty -> ` )
            ( nurl_print ( parse_err_msg e ) )
            ( nurl_print `\n` )
        }
    }
    : !( Vec u ) ParseErr odd_dec ( bytes_from_hex `abc` )
    ?? odd_dec {
        T v → { ( nurl_print `WRONG odd ok\n` ) ( vec_free [u] v ) }
        F e → {
            ( nurl_print `odd -> ` )
            ( nurl_print ( parse_err_msg e ) )
            ( nurl_print `\n` )
        }
    }
    : !( Vec u ) ParseErr bad_dec ( bytes_from_hex `ZZ` )
    ?? bad_dec {
        T v → { ( nurl_print `WRONG bad ok\n` ) ( vec_free [u] v ) }
        F e → {
            ( nurl_print `bad -> ` )
            ( nurl_print ( parse_err_msg e ) )
            ( nurl_print `\n` )
        }
    }

    // ── bytes_find_byte ──────────────────────────────────────────────
    ( show_opt_i `find('o')` ( bytes_find_byte hello # u 111 ) )
    ( show_opt_i `find('z')` ( bytes_find_byte hello # u 122 ) )

    // ── bytes_index_of (substring search) ────────────────────────────
    : ( Vec u ) world ( bytes_from_str `world` )
    : ( Vec u ) wox ( bytes_from_str `wox` )
    : ( Vec u ) empty ( bytes_from_str `` )
    : ( Vec u ) full ( bytes_from_str `hello world` )
    : ( Vec u ) bang ( bytes_from_str `!` )
    ( show_opt_i `idx 'world'` ( bytes_index_of hello world ) )  // 6
    ( show_opt_i `idx 'wox'` ( bytes_index_of hello wox ) )  // none
    ( show_opt_i `idx ''` ( bytes_index_of hello empty ) )  // 0
    ( show_opt_i `idx 'hello world'` ( bytes_index_of hello full ) )  // 0
    ( show_opt_i `idx '!'` ( bytes_index_of hello bang ) )  // none
    ( vec_free [u] world )
    ( vec_free [u] wox )
    ( vec_free [u] empty )
    ( vec_free [u] full )
    ( vec_free [u] bang )

    // ── bytes_starts_with / bytes_ends_with ──────────────────────────
    : ( Vec u ) pfx_he ( bytes_from_str `he` )
    : ( Vec u ) pfx_no ( bytes_from_str `xx` )
    : ( Vec u ) sfx_ld ( bytes_from_str `ld` )
    : ( Vec u ) sfx_no ( bytes_from_str `Z!` )
    : ( Vec u ) too_long ( bytes_from_str `hello world!` )  // 12 > 11
    : b sw1 ( bytes_starts_with hello pfx_he )
    : b sw2 ( bytes_starts_with hello pfx_no )
    : b sw3 ( bytes_starts_with hello too_long )
    : b ew1 ( bytes_ends_with hello sfx_ld )
    : b ew2 ( bytes_ends_with hello sfx_no )
    : b ew3 ( bytes_ends_with hello too_long )
    ? sw1 ( nurl_print `starts 'he' ok\n` ) ( nurl_print `WRONG starts 'he'\n` )
    ? sw2 ( nurl_print `WRONG starts 'xx'\n` ) ( nurl_print `starts 'xx' ok\n` )
    ? sw3 ( nurl_print `WRONG starts long\n` ) ( nurl_print `starts long ok\n` )
    ? ew1 ( nurl_print `ends 'ld' ok\n` ) ( nurl_print `WRONG ends 'ld'\n` )
    ? ew2 ( nurl_print `WRONG ends 'Z!'\n` ) ( nurl_print `ends 'Z!' ok\n` )
    ? ew3 ( nurl_print `WRONG ends long\n` ) ( nurl_print `ends long ok\n` )
    ( vec_free [u] pfx_he )
    ( vec_free [u] pfx_no )
    ( vec_free [u] sfx_ld )
    ( vec_free [u] sfx_no )
    ( vec_free [u] too_long )

    // ── bytes_slice (copy of half-open range) ────────────────────────
    : ( Vec u ) sl1 ( bytes_slice hello 0 5 )  // "hello"
    : ( Vec u ) sl2 ( bytes_slice hello 6 11 )  // "world"
    : ( Vec u ) sl3 ( bytes_slice hello 3 3 )  // empty
    : ( Vec u ) sl4 ( bytes_slice hello 0 100 )  // clamp to len, full copy
    : ( Vec u ) sl5 ( bytes_slice hello -3 4 )  // clamp from to 0
    : ( Vec u ) sl6 ( bytes_slice hello 8 4 )  // inverted → empty
    : String sl1s ( bytes_to_str sl1 )
    : String sl2s ( bytes_to_str sl2 )
    : String sl4s ( bytes_to_str sl4 )
    : String sl5s ( bytes_to_str sl5 )
    ( nurl_print ( string_data sl1s ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data sl2s ) ) ( nurl_print `\n` )
    ( nurl_print_int ( vec_len [u] sl3 ) )  // 0\n built-in
    ( nurl_print ( string_data sl4s ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data sl5s ) ) ( nurl_print `\n` )
    ( nurl_print_int ( vec_len [u] sl6 ) )  // 0\n built-in
    ( string_free sl1s ) ( string_free sl2s )
    ( string_free sl4s ) ( string_free sl5s )
    ( vec_free [u] sl1 ) ( vec_free [u] sl2 ) ( vec_free [u] sl3 )
    ( vec_free [u] sl4 ) ( vec_free [u] sl5 ) ( vec_free [u] sl6 )

    // ── bytes_push_int / bytes_push_float ────────────────────────────
    : ( Vec u ) num ( vec_with_cap [u] 16 )
    ( bytes_push_int num 42 )
    ( bytes_push_int num -7 )
    ( bytes_push_float num 3.5 )
    : String num_s ( bytes_to_str num )
    ( nurl_print ( string_data num_s ) )
    ( nurl_print `\n` )
    ( string_free num_s )
    ( vec_free [u] num )

    // ── bytes_eq fast path: different lengths ────────────────────────
    : ( Vec u ) h ( bytes_from_str `hi` )
    : b not_eq ( bytes_eq hello h )
    ? not_eq ( nurl_print `WRONG hello==hi\n` )
    ( nurl_print `len-mismatch ok\n` )
    ( vec_free [u] h )

    // ── Binary file I/O round-trip — write hello then read it back ──
    : !v IoErr w_rc ( write_file_bytes `/tmp/_nurl_bytes_test.bin` hello )
    ?? w_rc {
        T _ → ( nurl_print `write ok\n` )
        F e → {
            ( nurl_print `write FAIL ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    : !( Vec u ) IoErr r_rc ( read_file_bytes `/tmp/_nurl_bytes_test.bin` )
    ?? r_rc {
        T rv → {
            : b same ( bytes_eq hello rv )
            ? same ( nurl_print `read ok\n` )
            ( nurl_print `read MISMATCH\n` )
            ( nurl_print_int ( vec_len [u] rv ) )
            ( vec_free [u] rv )
        }
        F e → {
            ( nurl_print `read FAIL ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    // Cleanup test file (best-effort).
    : !v IoErr d_rc ( file_delete `/tmp/_nurl_bytes_test.bin` )
    ?? d_rc {
        T _ → ( nurl_print `delete ok\n` )
        F _ → ( nurl_print `delete failed\n` )
    }

    // Read missing file → IoErr.NotFound
    : !( Vec u ) IoErr miss ( read_file_bytes `/tmp/_nurl_definitely_does_not_exist.bin` )
    ?? miss {
        T v → { ( nurl_print `WRONG missing ok\n` ) ( vec_free [u] v ) }
        F e → {
            ( nurl_print `miss -> ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ( vec_free [u] hello )
    ^ 0
}
