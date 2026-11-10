// recursion_rotating_seventeen_strings_settles_runs_clean: a recursion that
// rotates its 17 String parameters by one position a call and pushes a view
// of the first into its Vec at the bottom; the caller frees a String that is
// passed along unchanged (outside the orbit) and reads the result. Each
// round of the component's fixed point adds one parameter to its answer, and
// the walk stopped at 16 rounds and asked "may": the safe program was
// refused ("'r' holds a view of 'z'"). Closed (agora #480): the rounds are
// bounded by the answers' lattice height, so it settles.
// map: §3.3d | A2 | runs-clean | - | a recursion rotating 17 String parameters, the caller freeing one outside the orbit: the walk's fixed point stopped at 16 rounds and refused it (agora #480).
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
    ( string_free z )
    ( nurl_println_int ( vec_len [s] r ) )
    ^ 0
}
