// result_owner_given_a_call_that_may_lend_itself_or_another_argument: agora #412 — the same with !String i results
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: heap-use-after-free (since github#1517).
// map: §7.6 | A2 | rejected | - | agora #412: the same with !String i results
$ `stdlib/core/string.nu`

@ pick ! String i a ! String i b i k → !String i { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : !String i other @ !String i { T ( string_from `another value long enough for the heap` ) }
    : ~ ! String i o @ !String i { T ( string_from `a value long enough for the heap` ) }
    = o ( pick o other 1 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    ^ 0
}
