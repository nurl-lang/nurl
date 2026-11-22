// packages/map-anything/tests/sharpcheck.nu — the focus measure ranks a
// frame above a blurred copy of itself, and sh_pick keeps the sharp one.
//
//   nurl tests/sharpcheck.nu /tmp/sc && /tmp/sc <sharp.jpg> <blurred.jpg> [frame...]
//
// With extra frames it also times sh_score over them.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `src/sharp.nu`

@ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: sharpcheck <sharp.jpg> <blurred.jpg> [frame...]\n` ) ^ 2 } {}
    : f a ( sh_score ( nurl_argv 1 ) )
    : f b ( sh_score ( nurl_argv 2 ) )
    ( nurl_print `sharp ` ) ( nurl_print ( nurl_str_float a ) )
    ( nurl_print `  blurred ` ) ( nurl_print ( nurl_str_float b ) ) ( nurl_print `\n` )
    // both fixtures must decode, or the comparisons below prove nothing
    ? | < a 0.0 < b 0.0 { ( nurl_print `FAIL a fixture did not decode\n` ) ^ 1 } {}
    : ~ i rc 0
    ? > a * 2.0 b { ( nurl_print `PASS the sharp frame scores well above its blurred copy\n` ) } {
        ( nurl_print `FAIL the focus measure does not separate them\n` ) = rc 1
    }
    // a run of [blurred, sharp, blurred] keeps the sharp one
    : ( Vec String ) fr ( vec_new [String] )
    ( vec_push [String] fr ( string_from ( nurl_argv 2 ) ) )
    ( vec_push [String] fr ( string_from ( nurl_argv 1 ) ) )
    ( vec_push [String] fr ( string_from ( nurl_argv 2 ) ) )
    ( sh_pick fr 1 0 )
    : ~ s got ``
    ?? ( vec_get [String] fr 0 ) { T p → { = got ( string_data p ) } F → {} }
    ? == 0 ( nurl_str_cmp got ( nurl_argv 1 ) ) { ( nurl_print `PASS sh_pick keeps the sharp frame of a run\n` ) } {
        ( nurl_print `FAIL sh_pick kept ` ) ( nurl_print got ) ( nurl_print `\n` ) = rc 1
    }
    : i extra - ( nurl_argc ) 3
    ? > extra 0 {
        : i t0 ( now_ms )
        : ~ i k 3
        ~ < k ( nurl_argc ) { : f _s ( sh_score ( nurl_argv k ) ) = k + k 1 }
        : i dt - ( now_ms ) t0
        ( nurl_print `timing ` ) ( nurl_print ( nurl_str_int extra ) )
        ( nurl_print ` frames in ` ) ( nurl_print ( nurl_str_int dt ) )
        ( nurl_print ` ms (` ) ( nurl_print ( nurl_str_int / dt extra ) ) ( nurl_print ` ms each)\n` )
    } {}
    ^ rc
}
