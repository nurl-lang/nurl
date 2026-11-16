// option_struct_owner_given_a_call_that_may_lend_itself_or_another_argument: agora #412 — the same with an ?P struct payload
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: heap-use-after-free (since github#1517).
// map: §7.6 | A2 | rejected | - | agora #412: the same with an ?P struct payload
$ `stdlib/core/string.nu`

: P { String name i n }

@ pick ? P a ? P b i k → ?P { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ?P other @ ?P { T @ P { ( string_from `another value long enough for the heap` ) 1 } }
    : ~ ? P o @ ?P { T @ P { ( string_from `a value long enough for the heap` ) 2 } }
    = o ( pick o other 1 )
    ?? o { T p → { ( nurl_println ( string_data . p name ) ) } F → {} }
    ?? other { T p → { ( nurl_println ( string_data . p name ) ) } F → {} }
    ^ 0
}
