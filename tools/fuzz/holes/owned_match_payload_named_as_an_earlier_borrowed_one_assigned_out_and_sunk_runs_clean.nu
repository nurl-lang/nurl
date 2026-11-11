// owned_match_payload_named_as_an_earlier_borrowed_one_assigned_out_and_sunk_runs_clean: agora #703 — `?? ( vec_get [S] va 0 ) { T v → … }` then `?? ( mko 3 ) { T v → { = a v } }` and `( eat a )`
// The shape the fix must keep: a `??` payload is a fresh binding; an owned one borrows nothing, whatever an earlier payload of its name borrowed.
// main a013bfae9: refused ("'a' is a borrow … released or handed over here as if it owned the value").
// map: §2.2 | A2 | runs-clean | - | agora #703: an owned `??` payload named as an earlier borrowed one is assigned to an outer binding, which is then sunk; the earlier view is read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks i k → S {
    ^ @ S { ( string_from `an owned value long enough for a heap buffer` ) k }
}

@ mko i k → ?S {
    ^ @ ?S { T ( mks k ) }
}

@ eat sink S x → i {
    ^ . x n
}

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks 1 ) )
    : s keep ?? ( vec_get [S] va 0 ) { T v → ( string_data . v name ) F → `` }
    : ~ S a ( mks 0 )
    ?? ( mko 3 ) { T v → { = a v } F → {} }
    : i r ( eat a )
    ( nurl_println keep )
    ^ - r 3
}
