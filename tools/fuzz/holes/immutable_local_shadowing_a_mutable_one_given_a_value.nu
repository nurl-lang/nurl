// immutable_local_shadowing_a_mutable_one_given_a_value: `: String s …` inside a scope where `: ~ String s` is bound, then `= s …`: the inner binding read the outer one's `__mutable`
// Closed: a new binding of a name already bound resets the facts keyed by the name that say what the outer binding is — an inout parameter, a sink parameter, a capture by reference, a global, mutable, a borrow (__shadow_reset); gen_assign reads the target's before its right-hand side (agora #820).
// main 9a5abbf: accepted (an assignment to an immutable binding).
// map: §7.6 | A2 | rejected | - | agora #820: an immutable binding shadowing a mutable one
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    ? T { : String s ( string_from `inner string long enough for a heap buffer` ) = s ( string_from `second inner string long enough heap` ) ( nurl_println ( string_data s ) ) } {}
    ^ 0
}
