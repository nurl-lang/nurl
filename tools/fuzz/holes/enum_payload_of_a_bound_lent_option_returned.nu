// enum_payload_of_a_bound_lent_option_returned: agora #279 — an option bound from `vec_get` of a local Vec, an enum payload under it returned from a nested match.
// Closed: a `:` option bound from a call, and an enum payload bound out of such a payload, carry the call's lend key, so handed back they are copied where the call lends out of a local of this frame (mem_note_bound_lend, gen_match); a payload taken through a cursor over an option binding is taken from the option's own slot, where it owns it (mem_enum_take; agora #279).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #279: an enum payload under a bound lent option, returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ first → ( Vec i ) {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ( vec_push [Msg] ms @ Msg { MSome xs } )
    : ?Msg om ( vec_get [Msg] ms 0 )
    ?? om { T m → { ?? m { MSome v → { ^ v } MNone → {} } } F → {} }
    ^ ( vec_new [i] )
}

@ main → i {
    : ( Vec i ) got ( first )
    ( vec_push [i] got 42 )
    ( nurl_println_int ( vec_len [i] got ) )
    ^ 0
}
