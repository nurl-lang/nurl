// enum_payload_of_a_bound_owned_option_returned: agora #279 — an option bound from a call that hands it over (`: ?Msg om ( make )`), an enum payload under it returned: taken from the cursor's copy only, the option still dropped it.
// Closed: a `:` option bound from a call, and an enum payload bound out of such a payload, carry the call's lend key, so handed back they are copied where the call lends out of a local of this frame (mem_note_bound_lend, gen_match); a payload taken through a cursor over an option binding is taken from the option's own slot, where it owns it (mem_enum_take; agora #279).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #279: an enum payload under a bound owned option, returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ make → ?Msg {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ^ @ ?Msg { T @ Msg { MSome xs } }
}

@ first → ( Vec i ) {
    : ?Msg om ( make )
    ?? om { T m → { ?? m { MSome v → { ^ v } MNone → {} } } F → {} }
    ^ ( vec_new [i] )
}

@ main → i {
    : ~ i n 0
    ~ < n 5 {
        : ( Vec i ) got ( first )
        ( vec_push [i] got 42 )
        ( nurl_print_int ( vec_len [i] got ) )
        = n + n 1
    }
    ( nurl_println `` )
    ^ 0
}
