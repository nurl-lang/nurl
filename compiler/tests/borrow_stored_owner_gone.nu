// borrow_stored_owner_gone.nu — a binding placed in a literal lives as long
// as the value that holds it.
//
// `: Hold t @ Hold { a }` moves `a`'s handle into `t`; the name `a` may
// still read it while `t` holds it. Once `t` is consumed, or replaced, the
// handle is gone with it, and a read through `a` is a use-after-move — it
// compiled clean and read freed memory. A literal handed straight to a
// call that consumes it takes its fields along, as a bare argument to that
// call would.
//
// Positive cases error; the controls (the holder still alive, a call that
// only reads the literal, a holder kept in a Vec) do not.

$ `stdlib/core/vec.nu`

: Hold { ( Vec i ) v }

@ keep sink Hold h → i { ^ ( vec_len [i] . h v ) }

@ peek Hold h → i { ^ ( vec_len [i] . h v ) }

@ mk → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ^ v
}

// POSITIVE — the holder was consumed
@ holder_consumed → i {
    : ( Vec i ) a ( mk )
    : Hold t @ Hold { a }
    : i n ( keep t )
    ^ + n ( vec_len [i] a )
}

// POSITIVE — the literal went to a call that consumes it
@ literal_consumed → i {
    : ( Vec i ) a ( mk )
    : i n ( keep @ Hold { a } )
    ^ + n ( vec_len [i] a )
}

// POSITIVE — the holder got a new value; the old one is dropped
@ holder_replaced → i {
    : ( Vec i ) a ( mk )
    : ( Vec i ) b ( mk )
    : ~ Hold t @ Hold { a }
    = t @ Hold { b }
    ^ + ( peek t ) ( vec_len [i] a )
}

// CONTROL — the holder still holds it
@ holder_alive → i {
    : ( Vec i ) a ( mk )
    : Hold t @ Hold { a }
    ^ + ( peek t ) ( vec_len [i] a )
}

// CONTROL — the call only reads the literal
@ literal_read → i {
    : ( Vec i ) a ( mk )
    : i n ( peek @ Hold { a } )
    ^ + n ( vec_len [i] a )
}

// CONTROL — the holder lives on in a Vec
@ holder_kept → i {
    : ( Vec i ) a ( mk )
    : Hold t @ Hold { a }
    : ( Vec Hold ) hs ( vec_new [Hold] )
    ( vec_push [Hold] hs t )
    ^ + ( vec_len [Hold] hs ) ( vec_len [i] a )
}

@ main → i {
    ^ + + + + + ( holder_consumed ) ( literal_consumed ) ( holder_replaced ) ( holder_alive ) ( literal_read ) ( holder_kept )
}
