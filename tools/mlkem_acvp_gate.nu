// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// tools/mlkem_acvp_gate.nu — run NIST's published ACVP vectors for
// ML-KEM against stdlib/std/mlkem.nu.
//
//   mlkem_acvp_gate <ML-KEM-keyGen.json> <ML-KEM-encapDecap.json>
//
// The JSON is NIST's own `internalProjection.json`, which carries the
// expected outputs alongside the inputs, so every case is a byte-exact
// comparison rather than a round trip. The three functions covered:
//
//   keyGen           d, z            → ek, dk
//   encapsulation    ek, m           → c, K
//   decapsulation    dk, c           → K   (includes the ciphertexts
//                                           that must implicitly reject)
//
// The `*KeyCheck` groups are input-validation tests for malformed keys
// and are skipped here — they check a rejection API this module does
// not expose. They are counted and reported so the skip is visible.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/mlkem.nu`

@ __die s msg → v {
    ( nurl_print msg ) ( nurl_print `\n` )
    ( nurl_exit 1 )
}

@ __load s path → Json {
    : !String IoErr rd ( read_file path )
    : String txt ?? rd { T v → { v } F _e → { ( __die `cannot read vector file` ) ( string_new ) } }
    : !Json JsonError pr ( json_parse ( string_data txt ) )
    : Json j ?? pr { T v → { v } F _e → { ( __die `cannot parse vector JSON` ) ( json_null ) } }
    ( string_free txt )
    ^ j
}

@ __str Json obj s key → s {
    : ?Json o ( json_obj_get obj key )
    ?? o { T v → { ^ ( json_str_data v ) } F → { ^ `` } }
}

@ __level_of s ps → i {
    ? != 0 ( nurl_str_eq ps `ML-KEM-512` ) { ^ 512 } {}
    ? != 0 ( nurl_str_eq ps `ML-KEM-1024` ) { ^ 1024 } {}
    ? != 0 ( nurl_str_eq ps `ML-KEM-768` ) { ^ 768 } {}
    ^ 0
}

// Decode expected hex and compare. ACVP writes hex in upper case and
// `bytes_to_hex` emits lower, so the comparison is on bytes, never on
// the two spellings of the same value.
@ __eq_hex ( Vec u ) got s wanthex → b {
    : !( Vec u ) ParseErr r ( bytes_from_hex wanthex )
    ?? r {
        T w → {
            : b ok ( bytes_eq got w )
            ( vec_free [u] w )
            ^ ok
        }
        F _e → { ^ F }
    }
}

@ __hexv s h → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex h )
    ?? r { T v → { ^ v } F _e → { ( __die `bad hex in vector file` ) ^ ( vec_new [u] ) } }
}

: Tally {
    i pass
    i fail
    i skip
}

@ __note * Tally t b ok s what i tcid → v {
    ? ok { = . t pass + . t pass 1 } {
        = . t fail + . t fail 1
        : String ln ( string_new )
        ( string_push_str ln `FAIL ` )
        ( string_push_str ln what )
        ( string_push_str ln ` tcId=` )
        ( string_push_int ln tcid )
        ( string_push_str ln `\n` )
        ( nurl_print ( string_data ln ) )
        ( string_free ln )
    }
}

@ __tcid Json t → i {
    : ?Json o ( json_obj_get t `tcId` )
    ?? o { T v → { ^ ?? ( json_num_as_i v ) { T n → { n } F → { 0 } } } F → { ^ 0 } }
}

@ __run_keygen Json doc * Tally t → v {
    : ?Json og ( json_obj_get doc `testGroups` )
    : Json groups ?? og { T v → { v } F → { ( __die `keyGen: no testGroups` ) ( json_null ) } }
    : i ng ( json_arr_len groups )
    : ~ i gi 0
    ~ < gi ng {
        : Json g ?? ( json_arr_get groups gi ) { T v → { v } F → { ( json_null ) } }
        : i level ( __level_of ( __str g `parameterSet` ) )
        : Json tests ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : i nt ( json_arr_len tests )
        : ~ i ti 0
        ~ < ti nt {
            : Json tc ?? ( json_arr_get tests ti ) { T v → { v } F → { ( json_null ) } }
            : ( Vec u ) d ( __hexv ( __str tc `d` ) )
            : ( Vec u ) z ( __hexv ( __str tc `z` ) )
            : *MlkemKeys ks ( mlkem_keygen_derand level d z )
            : b ok & ( __eq_hex ( mlkem_ek ks ) ( __str tc `ek` ) )
            ( __eq_hex ( mlkem_dk ks ) ( __str tc `dk` ) )
            ( __note t ok `keyGen` ( __tcid tc ) )
            ( mlkem_keys_free ks )
            ( vec_free [u] z )
            ( vec_free [u] d )
            = ti + ti 1
        }
        = gi + gi 1
    }
}

@ __run_encapdecap Json doc * Tally t → v {
    : ?Json og ( json_obj_get doc `testGroups` )
    : Json groups ?? og { T v → { v } F → { ( __die `encapDecap: no testGroups` ) ( json_null ) } }
    : i ng ( json_arr_len groups )
    : ~ i gi 0
    ~ < gi ng {
        : Json g ?? ( json_arr_get groups gi ) { T v → { v } F → { ( json_null ) } }
        : i level ( __level_of ( __str g `parameterSet` ) )
        : s fn ( __str g `function` )
        : b is_encap != 0 ( nurl_str_eq fn `encapsulation` )
        : b is_decap != 0 ( nurl_str_eq fn `decapsulation` )
        : s gdk ( __str g `dk` )
        : Json tests ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : i nt ( json_arr_len tests )
        : ~ i ti 0
        ~ < ti nt {
            : Json tc ?? ( json_arr_get tests ti ) { T v → { v } F → { ( json_null ) } }
            ? is_encap {
                : ( Vec u ) ek ( __hexv ( __str tc `ek` ) )
                : ( Vec u ) m ( __hexv ( __str tc `m` ) )
                : *MlkemEncap en ( mlkem_encaps_derand level ek m )
                : b ok & ( __eq_hex ( mlkem_ct en ) ( __str tc `c` ) )
                ( __eq_hex ( mlkem_ss en ) ( __str tc `k` ) )
                ( __note t ok `encapsulation` ( __tcid tc ) )
                ( mlkem_encap_free en )
                ( vec_free [u] m )
                ( vec_free [u] ek )
            } {}
            ? is_decap {
                // dk may sit on the test or, for some group shapes, on
                // the group; prefer the test's own.
                : s tdk ( __str tc `dk` )
                : ( Vec u ) dk ( __hexv ? > ( nurl_str_len tdk ) 0 tdk gdk )
                : ( Vec u ) ct ( __hexv ( __str tc `c` ) )
                : ( Vec u ) ss ( mlkem_decaps level dk ct )
                ( __note t ( __eq_hex ss ( __str tc `k` ) ) `decapsulation` ( __tcid tc ) )
                ( vec_free [u] ss )
                ( vec_free [u] ct )
                ( vec_free [u] dk )
            } {}
            ? | is_encap is_decap {} { = . t skip + . t skip 1 }
            = ti + ti 1
        }
        = gi + gi 1
    }
}

@ main → i {
    ? < ( nurl_argv_count ) 3 {
        ( nurl_print `usage: mlkem_acvp_gate <keyGen.json> <encapDecap.json>\n` )
        ^ 2
    } {}
    : s p1 ( nurl_argv_get 1 )
    : s p2 ( nurl_argv_get 2 )

    : *Tally t # *Tally ( nurl_alloc Z Tally )
    = . t pass 0
    = . t fail 0
    = . t skip 0

    : Json kg ( __load p1 )
    ( __run_keygen kg t )
    ( json_free kg )

    : Json ed ( __load p2 )
    ( __run_encapdecap ed t )
    ( json_free ed )

    // Assembled as one String: `nurl_print_int` ends its own line, which
    // would break this summary across four of them.
    : String sum ( string_new )
    ( string_push_str sum `ACVP ML-KEM: ` )
    ( string_push_int sum . t pass ) ( string_push_str sum ` passed, ` )
    ( string_push_int sum . t fail ) ( string_push_str sum ` failed, ` )
    ( string_push_int sum . t skip ) ( string_push_str sum ` skipped (key-validation groups)\n` )
    ( nurl_print ( string_data sum ) )
    ( string_free sum )
    : i rc ? == . t fail 0 0 1
    ( nurl_free # s t )
    ^ rc
}
