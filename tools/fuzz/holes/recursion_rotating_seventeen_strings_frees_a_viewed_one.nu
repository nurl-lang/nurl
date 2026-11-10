// recursion_rotating_seventeen_strings_frees_a_viewed_one: the twin of
// recursion_rotating_seventeen_strings_settles_runs_clean whose caller frees
// a String in the orbit, which the result may view: still refused once the
// fixed point settles (agora #480).
// map: §3.3d | A2 | rejected | - | a recursion rotating 17 String parameters, the caller freeing one the result may view: refused once the walk's fixed point settles (agora #480).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ rot ( Vec s ) h String z String a0 String a1 String a2 String a3 String a4 String a5 String a6 String a7 String a8 String a9 String a10 String a11 String a12 String a13 String a14 String a15 String a16 i d → ( Vec s ) {
    ? == d 0 { ( vec_push [s] h ( string_data a0 ) ) ^ h } { ^ ( rot h z a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a0 - d 1 ) }
}

@ main → i {
    : String s0 ( string_from `string number 0 long enough` )
    : String s1 ( string_from `string number 1 long enough` )
    : String s2 ( string_from `string number 2 long enough` )
    : String s3 ( string_from `string number 3 long enough` )
    : String s4 ( string_from `string number 4 long enough` )
    : String s5 ( string_from `string number 5 long enough` )
    : String s6 ( string_from `string number 6 long enough` )
    : String s7 ( string_from `string number 7 long enough` )
    : String s8 ( string_from `string number 8 long enough` )
    : String s9 ( string_from `string number 9 long enough` )
    : String s10 ( string_from `string number 10 long enough` )
    : String s11 ( string_from `string number 11 long enough` )
    : String s12 ( string_from `string number 12 long enough` )
    : String s13 ( string_from `string number 13 long enough` )
    : String s14 ( string_from `string number 14 long enough` )
    : String s15 ( string_from `string number 15 long enough` )
    : String s16 ( string_from `string number 16 long enough` )
    : String z ( string_from `outside the orbit, long enough` )
    : ( Vec s ) h0 ( vec_new [s] )
    : ( Vec s ) r ( rot h0 z s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 3 )
    ( string_free s3 )
    ( nurl_println_int ( vec_len [s] r ) )
    ^ 0
}
