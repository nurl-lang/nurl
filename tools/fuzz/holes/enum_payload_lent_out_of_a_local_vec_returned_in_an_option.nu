// enum_payload_lent_out_of_a_local_vec_returned_in_an_option: agora #279 — as enum_payload_lent_out_of_a_local_vec_returned, returned inside an option.
// Closed: a `:` option bound from a call, and an enum payload bound out of such a payload, carry the call's lend key, so handed back they are copied where the call lends out of a local of this frame (mem_note_bound_lend, gen_match); a payload taken through a cursor over an option binding is taken from the option's own slot, where it owns it (mem_enum_take; agora #279).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #279: an enum payload lent out of a local Vec, returned in an option (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ first → ?( Vec i ) {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ( vec_push [Msg] ms @ Msg { MSome xs } )
    ?? ( vec_get [Msg] ms 0 ) {
        T m → { ?? m { MSome v → { ^ @ ?( Vec i ) { T v } } MNone → {} } }
        F → {}
    }
    ^ @ ?( Vec i ) { F }
}

@ main → i {
    ?? ( first ) { T got → { ( nurl_println_int ( vec_len [i] got ) ) } F → {} }
    ^ 0
}
