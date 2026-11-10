// holder_viewing_a_string_handed_beside_it_to_a_grower: agora #558 control — `w` already views `s` when both go to `f`, which grows `s`: inside `f` the two are unrelated names, and the growth leaves `w` dangling until `f` repoints it.
// Stays refused: the alias exists as the call is entered.
// map: §2.10 | A2 | rejected | - | agora #558: a holder already viewing the String handed beside it to a callee that grows it
$ `stdlib/core/string.nu`

: W { s v }

@ f inout W w inout String s → v {
    = w @ W { ( string_data s ) }
    ( string_push_str s `and a long tail that makes the buffer move to a new place in memory for sure` )
    = w @ W { ( string_data s ) }
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    = w @ W { ( string_data s ) }
    ( f w s )
    ( nurl_println . w v )
    ^ 0
}
