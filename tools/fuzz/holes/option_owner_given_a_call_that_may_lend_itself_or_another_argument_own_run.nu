// option_owner_given_a_call_that_may_lend_itself_or_another_argument_own_run: agora #412 — = o ( pick o other 0 ): the run that hands back o's own value
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: ran clean (github#1517's gate); before it, heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #412: = o ( pick o other 0 ): the run that hands back o's own value
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ?String other @ ?String { T ( string_from `another value long enough for the heap` ) }
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( pick o other 0 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
