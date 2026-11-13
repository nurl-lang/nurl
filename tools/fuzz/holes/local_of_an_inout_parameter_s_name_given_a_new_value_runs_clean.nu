// local_of_an_inout_parameter_s_name_given_a_new_value_runs_clean: `: ~ String s …  = s ( fresh )` in an arm of `@ f inout String s`: the local was taken for the caller's slot
// Closed: a new binding of a name already bound resets the facts keyed by the name that say what the outer binding is — an inout parameter, a sink parameter, a capture by reference, a global, mutable, a borrow (__shadow_reset); gen_assign reads the target's before its right-hand side (agora #820).
// main 9a5abbf: AddressSanitizer: heap-use-after-free (the local's old value released by value, then again by its flag).
// map: §7.6 | A2 | runs-clean | - | agora #820: a local of an inout parameter's name
$ `stdlib/core/string.nu`

@ f inout String s → v {
    ? T { : ~ String s ( string_from `local string long enough for a heap` ) = s ( string_from `local again long enough for heap buf` ) ( nurl_println ( string_data s ) ) } {}
    = s ( string_from `new value long enough for a heap buffer` )
}

@ main → i {
    : ~ String a ( string_from `outer string long enough for a heap buffer` )
    ( f a ) ( f a )
    ( nurl_println ( string_data a ) )
    ^ 0
}
