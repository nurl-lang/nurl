// option_vec_owner_given_a_call_that_may_lend_itself_or_another_argument: agora #412 — the same with ?( Vec String ) owners
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: heap-use-after-free (since github#1517).
// AGORA-869: runs clean now - nurlc tells the runs apart by the payload's key, as it does a String's or a Vec's (#419), whichever argument the call hands back; before, the form was refused (#412).
// map: §7.6 | A2 | runs-clean | - | agora #412: the same with ?( Vec String ) owners
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick ? ( Vec String ) a ? ( Vec String ) b i k → ?( Vec String ) { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from t ) )
    ^ @ ?( Vec String ) { T v }
}

@ main → i {
    : ?( Vec String ) other ( mk `another value long enough for the heap` )
    : ~ ? ( Vec String ) o ( mk `a value long enough for the heap` )
    = o ( pick o other 1 )
    ?? o { T v → { ( nurl_println ( string_data ( vec_at [String] v 0 ) ) ) } F → {} }
    ?? other { T v → { ( nurl_println ( string_data ( vec_at [String] v 0 ) ) ) } F → {} }
    ^ 0
}
