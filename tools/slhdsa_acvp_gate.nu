// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// tools/slhdsa_acvp_gate.nu — run NIST's published ACVP vectors for
// SLH-DSA against stdlib/std/slhdsa.nu.
//
//   slhdsa_acvp_gate <keyGen.json> <sigGen.json> <sigVer.json> <per-group-cap>
//
// Unlike the ML-KEM and ML-DSA gates, this one caps how many cases it
// runs per group, because SLH-DSA signing is slow *by construction*: a
// `128s` signature rebuilds 512 WOTS+ key pairs on each of seven
// hypertree layers. Running all 624 published sigGen cases would take
// hours, so the cap is a parameter and the number of cases it skipped
// is printed. A gate that quietly truncated its own corpus would read
// as full coverage.
//
// Key generation is not capped — it is the cheap half and all 60 cases
// run.
//
// Only the SHAKE parameter sets are implemented; the SHA-2 sets are
// counted as skipped and reported separately from the cap.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/slhdsa.nu`

@ __str Json o s key → s {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_str_data v ) } F → { ^ `` } }
}

@ __bool Json o s key → b {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_bool_val v ) } F → { ^ F } }
}

@ __hexv s h → ( Vec u ) {
    ? == ( nurl_str_len h ) 0 { ^ ( vec_new [u] ) } {}
    ?? ( bytes_from_hex h ) { T v → { ^ v } F _e → { ^ ( vec_new [u] ) } }
}

@ __eqhex ( Vec u ) got s want → b {
    ?? ( bytes_from_hex want ) {
        T w → { : b ok ( bytes_eq got w ) ( vec_free [u] w ) ^ ok }
        F _e → { ^ F }
    }
}

// "SLH-DSA-SHAKE-128f" → the set integer this module takes; 0 for the
// SHA-2 family, which is not implemented.
@ __set_of s ps → i {
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-128s` ) { ^ 128 } {}
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-128f` ) { ^ 129 } {}
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-192s` ) { ^ 192 } {}
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-192f` ) { ^ 193 } {}
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-256s` ) { ^ 256 } {}
    ? != 0 ( nurl_str_eq ps `SLH-DSA-SHAKE-256f` ) { ^ 257 } {}
    ^ 0
}

@ __load s path → Json {
    : !String IoErr rd ( read_file path )
    : String txt ?? rd { T v → { v } F _e → { ( nurl_print `cannot read vector file\n` ) ( string_new ) } }
    : Json j ?? ( json_parse ( string_data txt ) ) { T v → { v } F _e → { ( nurl_print `cannot parse vector JSON\n` ) ( json_null ) } }
    ( string_free txt )
    ^ j
}

// Three reasons a case does not run, reported apart. Rolling them into
// one "skipped" number would hide which of them is a decision (the cap),
// which is a gap (SHA-2), and which is out of scope (the external
// interfaces, covered by the ML-DSA gate's equivalent path).
@ __report s what i pass i fail i capped i sha2 i iface → v {
    : String s ( string_new )
    ( string_push_str s what )
    ( string_push_str s `: ` )
    ( string_push_int s pass )
    ( string_push_str s ` passed, ` )
    ( string_push_int s fail )
    ( string_push_str s ` failed` )
    ? > capped 0 {
        ( string_push_str s `, ` )
        ( string_push_int s capped )
        ( string_push_str s ` past the per-group cap` )
    } {}
    ? > sha2 0 {
        ( string_push_str s `, ` )
        ( string_push_int s sha2 )
        ( string_push_str s ` SHA-2 sets (not implemented)` )
    } {}
    ? > iface 0 {
        ( string_push_str s `, ` )
        ( string_push_int s iface )
        ( string_push_str s ` non-internal interface` )
    } {}
    ( string_push_str s `\n` )
    ( nurl_print ( string_data s ) )
    ( string_free s )
}

@ main → i {
    ? < ( nurl_argv_count ) 5 {
        ( nurl_print `usage: slhdsa_acvp_gate <keyGen> <sigGen> <sigVer> <cap>\n` )
        ^ 2
    } {}
    : i cap ( nurl_str_to_int ( nurl_argv_get 4 ) )
    : ~ i totfail 0

    // ── keyGen: every case, uncapped ──
    : Json kg ( __load ( nurl_argv_get 1 ) )
    : Json kgg ?? ( json_obj_get kg `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i kp 0
    : ~ i kf 0
    : ~ i ks 0
    : ~ i gi 0
    ~ < gi ( json_arr_len kgg ) {
        : Json g ?? ( json_arr_get kgg gi ) { T v → { v } F → { ( json_null ) } }
        : i set ( __set_of ( __str g `parameterSet` ) )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            ? == set 0 { = ks + ks 1 } {
                : ( Vec u ) a ( __hexv ( __str tc `skSeed` ) )
                : ( Vec u ) b2 ( __hexv ( __str tc `skPrf` ) )
                : ( Vec u ) c ( __hexv ( __str tc `pkSeed` ) )
                : *SlhKeys k ( slhdsa_keygen_derand set a b2 c )
                ? & ( __eqhex ( slhdsa_pk k ) ( __str tc `pk` ) ) ( __eqhex ( slhdsa_sk k ) ( __str tc `sk` ) )
                { = kp + kp 1 } { = kf + kf 1 }
                ( slhdsa_keys_free k )
                ( vec_free [u] c ) ( vec_free [u] b2 ) ( vec_free [u] a )
            }
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free kg )
    ( __report `keyGen` kp kf 0 ks 0 )
    = totfail + totfail kf

    // ── sigGen: internal interface, capped per group ──
    : Json sg ( __load ( nurl_argv_get 2 ) )
    : Json sgg ?? ( json_obj_get sg `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i sp 0
    : ~ i sf 0
    : ~ i sc 0
    : ~ i ss2 0
    : ~ i si2 0
    = gi 0
    ~ < gi ( json_arr_len sgg ) {
        : Json g ?? ( json_arr_get sgg gi ) { T v → { v } F → { ( json_null ) } }
        : i set ( __set_of ( __str g `parameterSet` ) )
        : b det ( __bool g `deterministic` )
        : b internal != 0 ( nurl_str_eq ( __str g `signatureInterface` ) `internal` )
        : b pure != 0 ( nurl_str_eq ( __str g `preHash` ) `pure` )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            ? == set 0 { = ss2 + ss2 1 } {
                ? & ! internal ! pure { = si2 + si2 1 } {
                    ? >= ti cap { = sc + sc 1 } {
                        : ( Vec u ) sk ( __hexv ( __str tc `sk` ) )
                        : ( Vec u ) raw ( __hexv ( __str tc `message` ) )
                        : ( Vec u ) ctx ( __hexv ( __str tc `context` ) )
                        // The external interface signs 0x00 | |ctx| | ctx | M;
                        // the internal one signs M as given.
                        : ~ ( Vec u ) msg ( vec_new [u] )
                        ? internal {
                            ( vec_free [u] msg )
                            = msg ( bytes_slice raw 0 ( vec_len [u] raw ) )
                        } {
                            ( vec_push [u] msg # u 0 )
                            ( vec_push [u] msg # u ( vec_len [u] ctx ) )
                            ( bytes_extend_bytes msg ctx )
                            ( bytes_extend_bytes msg raw )
                        }
                        : i n / ( vec_len [u] sk ) 4
                        : ( Vec u ) rnd ? det ( bytes_slice sk * 2 n * 3 n ) ( __hexv ( __str tc `additionalRandomness` ) )
                        : ( Vec u ) sig ( slhdsa_sign_internal set sk msg rnd )
                        ? ( __eqhex sig ( __str tc `signature` ) ) { = sp + sp 1 } {
                            = sf + sf 1
                            : String fl ( string_new )
                            ( string_push_str fl `  FAIL sigGen ` )
                            ( string_push_str fl ( __str g `parameterSet` ) )
                            ( string_push_str fl ? det ` deterministic` ` hedged` )
                            ( string_push_str fl `\n` )
                            ( nurl_print ( string_data fl ) )
                            ( string_free fl )
                        }
                        ( vec_free [u] sig ) ( vec_free [u] rnd )
                        ( vec_free [u] msg ) ( vec_free [u] ctx )
                        ( vec_free [u] raw ) ( vec_free [u] sk )
                    }
                }
            }
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free sg )
    ( __report `sigGen` sp sf sc ss2 si2 )
    = totfail + totfail sf

    // ── sigVer: internal interface, capped per group ──
    : Json sv ( __load ( nurl_argv_get 3 ) )
    : Json svg ?? ( json_obj_get sv `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i vp 0
    : ~ i vf 0
    : ~ i vc 0
    : ~ i vs 0
    : ~ i vi 0
    = gi 0
    ~ < gi ( json_arr_len svg ) {
        : Json g ?? ( json_arr_get svg gi ) { T v → { v } F → { ( json_null ) } }
        : i set ( __set_of ( __str g `parameterSet` ) )
        : b internal != 0 ( nurl_str_eq ( __str g `signatureInterface` ) `internal` )
        : b pure != 0 ( nurl_str_eq ( __str g `preHash` ) `pure` )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            ? == set 0 { = vs + vs 1 } {
                ? & ! internal ! pure { = vi + vi 1 } {
                    ? >= ti cap { = vc + vc 1 } {
                        : ( Vec u ) pk ( __hexv ( __str tc `pk` ) )
                        : ( Vec u ) raw ( __hexv ( __str tc `message` ) )
                        : ( Vec u ) ctx ( __hexv ( __str tc `context` ) )
                        : ~ ( Vec u ) msg ( vec_new [u] )
                        ? internal {
                            ( vec_free [u] msg )
                            = msg ( bytes_slice raw 0 ( vec_len [u] raw ) )
                        } {
                            ( vec_push [u] msg # u 0 )
                            ( vec_push [u] msg # u ( vec_len [u] ctx ) )
                            ( bytes_extend_bytes msg ctx )
                            ( bytes_extend_bytes msg raw )
                        }
                        : ( Vec u ) sig ( __hexv ( __str tc `signature` ) )
                        ? == ( slhdsa_verify_internal set pk msg sig ) ( __bool tc `testPassed` )
                        { = vp + vp 1 } { = vf + vf 1 }
                        ( vec_free [u] sig ) ( vec_free [u] msg )
                        ( vec_free [u] ctx ) ( vec_free [u] raw ) ( vec_free [u] pk )
                    }
                }
            }
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free sv )
    ( __report `sigVer` vp vf vc vs vi )
    = totfail + totfail vf

    ^ ? == totfail 0 0 1
}
