// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// tools/mldsa_acvp_gate.nu — run NIST's published ACVP vectors for
// ML-DSA against stdlib/std/mldsa.nu.
//
//   mldsa_acvp_gate <keyGen.json> <sigGen.json> <sigVer.json>
//
// The JSON is NIST's own `internalProjection.json`, carrying expected
// outputs beside the inputs, so every case is a byte-exact comparison.
//
//   keyGen   seed        -> pk, sk
//   sigGen   sk, message -> signature   (deterministic and hedged,
//                                        internal and external, and the
//                                        external-mu interface)
//   sigVer   pk, message, signature -> accept / reject
//
// The sigVer set is the valuable half: only a fifth of its cases are
// valid signatures. The rest are tampered in one of four specific ways
// — modified message, modified commitment c~, modified z, modified
// hint — and a verifier that accepts any of them is broken in a way no
// amount of round-tripping would reveal.
//
// HashML-DSA (the `preHash` groups) is not implemented, so those cases
// are counted as skipped and the count is printed rather than hidden.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/mldsa.nu`

@ __str Json o s key → s {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_str_data v ) } F → { ^ `` } }
}

@ __bool Json o s key → b {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_bool_val v ) } F → { ^ F } }
}

@ __eqhex ( Vec u ) got s want → b {
    ?? ( bytes_from_hex want ) {
        T w → { : b ok ( bytes_eq got w ) ( vec_free [u] w ) ^ ok }
        F _e → { ^ F }
    }
}

@ __hexv s h → ( Vec u ) {
    ? == ( nurl_str_len h ) 0 { ^ ( vec_new [u] ) } {}
    ?? ( bytes_from_hex h ) { T v → { ^ v } F _e → { ^ ( vec_new [u] ) } }
}

@ __level Json g → i {
    : s ps ( __str g `parameterSet` )
    ? != 0 ( nurl_str_eq ps `ML-DSA-65` ) { ^ 65 } {}
    ? != 0 ( nurl_str_eq ps `ML-DSA-87` ) { ^ 87 } {}
    ^ 44
}

@ __load s path → Json {
    : !String IoErr rd ( read_file path )
    : String txt ?? rd { T v → { v } F _e → { ( nurl_print `no file\n` ) ( string_new ) } }
    : Json j ?? ( json_parse ( string_data txt ) ) { T v → { v } F _e → { ( nurl_print `bad json\n` ) ( json_null ) } }
    ( string_free txt )
    ^ j
}

@ __report s what i pass i fail i skip → v {
    : String s ( string_new )
    ( string_push_str s what )
    ( string_push_str s `: ` )
    ( string_push_int s pass )
    ( string_push_str s ` passed, ` )
    ( string_push_int s fail )
    ( string_push_str s ` failed, ` )
    ( string_push_int s skip )
    ( string_push_str s ` skipped\n` )
    ( nurl_print ( string_data s ) )
    ( string_free s )
}

@ main → i {
    : ~ i totfail 0

    // ── keyGen ──
    : Json kg ( __load ( nurl_argv_get 1 ) )
    : Json kgg ?? ( json_obj_get kg `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i kp 0
    : ~ i kf 0
    : ~ i gi 0
    ~ < gi ( json_arr_len kgg ) {
        : Json g ?? ( json_arr_get kgg gi ) { T v → { v } F → { ( json_null ) } }
        : i level ( __level g )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            : ( Vec u ) xi ( __hexv ( __str tc `seed` ) )
            : *MldsaKeys ks ( mldsa_keygen_derand level xi )
            ? & ( __eqhex ( mldsa_pk ks ) ( __str tc `pk` ) ) ( __eqhex ( mldsa_sk ks ) ( __str tc `sk` ) )
            { = kp + kp 1 } { = kf + kf 1 }
            ( mldsa_keys_free ks )
            ( vec_free [u] xi )
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free kg )
    ( __report `keyGen` kp kf 0 )
    = totfail + totfail kf

    // ── sigGen: internal interface and external pure only.
    // preHash needs SHA-2, which is a different module's job; those
    // groups are counted as skipped rather than silently ignored.
    : Json sg ( __load ( nurl_argv_get 2 ) )
    : Json sgg ?? ( json_obj_get sg `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i sp 0
    : ~ i sf 0
    : ~ i ss 0
    = gi 0
    ~ < gi ( json_arr_len sgg ) {
        : Json g ?? ( json_arr_get sgg gi ) { T v → { v } F → { ( json_null ) } }
        : i level ( __level g )
        : s iface ( __str g `signatureInterface` )
        : s ph ( __str g `preHash` )
        : b det ( __bool g `deterministic` )
        : b emu ( __bool g `externalMu` )
        : b internal != 0 ( nurl_str_eq iface `internal` )
        : b pure != 0 ( nurl_str_eq ph `pure` )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            ? emu {
                : ( Vec u ) sk ( __hexv ( __str tc `sk` ) )
                : ( Vec u ) mu ( __hexv ( __str tc `mu` ) )
                : ( Vec u ) rnd ? det ( __hexv `0000000000000000000000000000000000000000000000000000000000000000` ) ( __hexv ( __str tc `rnd` ) )
                : ( Vec u ) sig ( mldsa_sign_mu level sk mu rnd )
                ? ( __eqhex sig ( __str tc `signature` ) ) { = sp + sp 1 } { = sf + sf 1 }
                ( vec_free [u] sig ) ( vec_free [u] rnd ) ( vec_free [u] mu ) ( vec_free [u] sk )
            } {
                ? ! | internal pure { = ss + ss 1 } {
                    : ( Vec u ) sk ( __hexv ( __str tc `sk` ) )
                    : ( Vec u ) msg ( __hexv ( __str tc `message` ) )
                    : ( Vec u ) rnd ? det ( __hexv `0000000000000000000000000000000000000000000000000000000000000000` ) ( __hexv ( __str tc `rnd` ) )
                    : ~ ( Vec u ) mp ( vec_new [u] )
                    ? internal {
                        ( vec_free [u] mp )
                        = mp ( bytes_slice msg 0 ( vec_len [u] msg ) )
                    } {
                        : ( Vec u ) ctx ( __hexv ( __str tc `context` ) )
                        ( vec_push [u] mp # u 0 )
                        ( vec_push [u] mp # u ( vec_len [u] ctx ) )
                        ( bytes_extend_bytes mp ctx )
                        ( bytes_extend_bytes mp msg )
                        ( vec_free [u] ctx )
                    }
                    : ( Vec u ) sig ( mldsa_sign_internal level sk mp rnd )
                    ? ( __eqhex sig ( __str tc `signature` ) ) { = sp + sp 1 } { = sf + sf 1 }
                    ( vec_free [u] sig )
                    ( vec_free [u] mp )
                    ( vec_free [u] rnd )
                    ( vec_free [u] msg )
                    ( vec_free [u] sk )
                } }
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free sg )
    ( __report `sigGen` sp sf ss )
    = totfail + totfail sf

    // ── sigVer: the negative cases are the point ──
    : Json sv ( __load ( nurl_argv_get 3 ) )
    : Json svg ?? ( json_obj_get sv `testGroups` ) { T v → { v } F → { ( json_null ) } }
    : ~ i vp 0
    : ~ i vf 0
    : ~ i vs 0
    = gi 0
    ~ < gi ( json_arr_len svg ) {
        : Json g ?? ( json_arr_get svg gi ) { T v → { v } F → { ( json_null ) } }
        : i level ( __level g )
        : s iface ( __str g `signatureInterface` )
        : s ph ( __str g `preHash` )
        : b emu ( __bool g `externalMu` )
        : b internal != 0 ( nurl_str_eq iface `internal` )
        : b pure != 0 ( nurl_str_eq ph `pure` )
        : Json ts ?? ( json_obj_get g `tests` ) { T v → { v } F → { ( json_null ) } }
        : ~ i ti 0
        ~ < ti ( json_arr_len ts ) {
            : Json tc ?? ( json_arr_get ts ti ) { T v → { v } F → { ( json_null ) } }
            ? emu {
                : ( Vec u ) pk ( __hexv ( __str tc `pk` ) )
                : ( Vec u ) mu ( __hexv ( __str tc `mu` ) )
                : ( Vec u ) sig ( __hexv ( __str tc `signature` ) )
                ? == ( mldsa_verify_mu level pk mu sig ) ( __bool tc `testPassed` ) { = vp + vp 1 } { = vf + vf 1 }
                ( vec_free [u] sig ) ( vec_free [u] mu ) ( vec_free [u] pk )
            } {
                ? ! | internal pure { = vs + vs 1 } {
                    : ( Vec u ) pk ( __hexv ( __str tc `pk` ) )
                    : ( Vec u ) msg ( __hexv ( __str tc `message` ) )
                    : ( Vec u ) sig ( __hexv ( __str tc `signature` ) )
                    : ~ ( Vec u ) mp ( vec_new [u] )
                    ? internal {
                        ( vec_free [u] mp )
                        = mp ( bytes_slice msg 0 ( vec_len [u] msg ) )
                    } {
                        : ( Vec u ) ctx ( __hexv ( __str tc `context` ) )
                        ( vec_push [u] mp # u 0 )
                        ( vec_push [u] mp # u ( vec_len [u] ctx ) )
                        ( bytes_extend_bytes mp ctx )
                        ( bytes_extend_bytes mp msg )
                        ( vec_free [u] ctx )
                    }
                    : b got ( mldsa_verify_internal level pk mp sig )
                    : b want ( __bool tc `testPassed` )
                    ? == got want { = vp + vp 1 } { = vf + vf 1 }
                    ( vec_free [u] mp )
                    ( vec_free [u] sig )
                    ( vec_free [u] msg )
                    ( vec_free [u] pk )
                } }
            = ti + ti 1
        }
        = gi + gi 1
    }
    ( json_free sv )
    ( __report `sigVer` vp vf vs )
    = totfail + totfail vf

    ^ ? == totfail 0 0 1
}
