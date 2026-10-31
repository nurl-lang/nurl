// drop_view_holder_without_destructor: agora #224 — a struct of views with no `% Drop` kept past a reallocation of its source: never read, its drop reads nothing (drop_view_holder_without_destructor).
// Kept: a holder whose drop reads nothing is not affected by the rule (agora #224).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #224: a struct of views with no `% Drop` kept past a reallocation of its source: never read, its drop reads nothing
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : ~ String s ( string_from `a view holder with no destructor` )
    : V w @ V { ( string_data s ) }
    ~ < ( string_len s ) 4000 { ( string_push_str s `more and more and more text` ) }
    ^ 0
}
