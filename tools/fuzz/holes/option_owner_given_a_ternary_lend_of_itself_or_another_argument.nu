// option_owner_given_a_ternary_lend_of_itself_or_another_argument: agora #412 — pick hands back ? == k 0 a b
// Closed: = o ( f … ) for an option or result owner o, where f may lend o itself AND another argument, is refused: no per-run answer of whether o's old value is still in use is right on both runs (agora #412, claude-formal's HOLD on github#1517; A2 refuses the form).
// main: heap-use-after-free (since github#1517).
// map: §7.6 | A2 | rejected | - | agora #412: pick hands back ? == k 0 a b
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ^ ? == k 0 a b }

@ main → i {
    : ?String other @ ?String { T ( string_from `another value long enough for the heap` ) }
    : ~ ? String o @ ?String { T ( string_from `a value long enough for the heap` ) }
    = o ( pick o other 1 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ?? other { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
