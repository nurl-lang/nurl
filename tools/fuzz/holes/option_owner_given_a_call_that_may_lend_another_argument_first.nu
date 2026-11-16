// option_owner_given_a_call_that_may_lend_another_argument_first: agora #412 — = o ( pick other o 0 ): the other argument first
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: heap-use-after-free (since github#1517).
// AGORA-869: runs clean now - nurlc tells the runs apart by the payload's key, as it does a String's or a Vec's (#419), whichever argument the call hands back; before, the form was refused (#412).
// map: §7.6 | A2 | runs-clean | - | agora #412: = o ( pick other o 0 ): the other argument first
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ?String other @ ?String { T ( string_from `another value long enough for the heap` ) }
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( pick other o 0 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
