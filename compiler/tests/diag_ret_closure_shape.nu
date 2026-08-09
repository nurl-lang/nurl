// diag_ret_closure_shape.nu — returning a '( @ f f )' closure out of a
// function declared '→ ( @ i i )'. Unlike the option-shape dual this
// ASSEMBLES — the aggregates are both { ptr, ptr } at the store level —
// and every later invoke through the declared type reinterprets its
// argument and return bit patterns (an i64 read as a double).
@ make → ( @ i i ) {
    : ( @ f f ) g \ f a → f { ^ a }
    ^ g
}

@ main → i {
    : ( @ i i ) h ( make )
    ^ ( h 3 )
}
