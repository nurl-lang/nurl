// `= t a` moves `a`'s value where it runs. An `a` that owns its value on
// one path only — a fresh string in one arm, a borrow of the parameter in
// the other — cannot be handed over by name: on the path it owns the
// value, `t` would take it and release it at `= t …`, under the read of
// `a` that follows. Refused as handing over a borrow (agora #634).
$ `stdlib/core/string.nu`

@ pick i c String h0 → i {
    : ~ String a ( string_from `the first string, long enough for the heap` )
    : ~ String t ( string_from `the third string, long enough for the heap` )
    ? == c 1 { = a ? == c 1 ( string_from `an owned string, long enough for the heap` ) h0 } { = a ( string_from `a fresh string, long enough for the heap` ) }
    = t a
    = t ( string_from `a new string, long enough for the heap` )
    ( nurl_println ( string_data t ) )
    ( nurl_println ( string_data a ) )
    ^ 0
}

@ main → i {
    : String h ( string_from `the lender string, long enough for the heap` )
    ( pick 1 h )
    ( pick 0 h )
    ^ 0
}
