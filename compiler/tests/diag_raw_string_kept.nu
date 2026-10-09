// diag_raw_string_kept.nu — the module-end half of diag_raw_string_in_value
// (docs/MEMORY.md §2.13): a fresh string handed to a parameter its callee
// keeps without taking it over (`vec_push [s]`: the Vec owns none of its
// raw strings — tools/fuzz/holes h128), and a value a call answering per
// call may hand over, stored in a raw string field — both decided once the
// callees' summaries are final. The controls compile: a parameter declared
// `sink`, a call that only lends its argument back.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ kept_by_vec → i {
    : ( Vec s ) v ( vec_new [s] )
    ( vec_push [s] v ( nurl_str_int 42 ) )
    ^ ( vec_len [s] v )
}

// A call that hands its argument back on one path and a fresh string on
// the other: which one it is is known per call.
@ maybe_fresh s x i k → s {
    ? == k 0 { ^ x } {}
    ^ ( nurl_str_cat x `!` )
}

@ maybe_in_literal s a → i {
    : Rec r @ Rec { ( maybe_fresh a 1 ) 1 }
    ^ . r n
}

// A callee that takes the string over says so: no error.
@ adopt sink s x → i {
    : String t ( string_adopt x )
    ^ ( string_len t )
}

@ handed_over → i { ^ ( adopt ( nurl_str_cat `a` `b` ) ) }

// A call that only lends its argument back hands over nothing: no error.
@ lend_back s x → s { ^ x }

@ lent_in_literal s a → i {
    : Rec r @ Rec { ( lend_back a ) 1 }
    ^ ( nurl_str_len . r name )
}

@ main → i { ^ + + + ( kept_by_vec ) ( maybe_in_literal `z` ) ( handed_over ) ( lent_in_literal `q` ) }
