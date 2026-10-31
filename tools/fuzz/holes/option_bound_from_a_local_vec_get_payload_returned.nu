// option_bound_from_a_local_vec_get_payload_returned: agora #279 — an option bound from `vec_get` of a local Vec (`: ?( Vec i ) o ( vec_get … )`), its payload returned: lent out of the frame.
// Closed: a `:` option bound from a call, and an enum payload bound out of such a payload, carry the call's lend key, so handed back they are copied where the call lends out of a local of this frame (mem_note_bound_lend, gen_match); a payload taken through a cursor over an option binding is taken from the option's own slot, where it owns it (mem_enum_take; agora #279).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #279: an option bound from a local Vec's vec_get, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

@ first → ( Vec i ) {
    : ( Vec ( Vec i ) ) vs ( vec_new [( Vec i )] )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ( vec_push [( Vec i )] vs xs )
    : ?( Vec i ) o ( vec_get [( Vec i )] vs 0 )
    ?? o { T e → { ^ e } F → {} }
    ^ ( vec_new [i] )
}

@ main → i {
    : ( Vec i ) got ( first )
    ( vec_push [i] got 42 )
    ( nurl_println_int ( vec_len [i] got ) )
    ^ 0
}
