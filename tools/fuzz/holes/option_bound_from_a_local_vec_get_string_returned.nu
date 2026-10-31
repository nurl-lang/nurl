// option_bound_from_a_local_vec_get_string_returned: agora #279 — as option_bound_from_a_local_vec_get_payload_returned, a String.
// Closed: a `:` option bound from a call, and an enum payload bound out of such a payload, carry the call's lend key, so handed back they are copied where the call lends out of a local of this frame (mem_note_bound_lend, gen_match); a payload taken through a cursor over an option binding is taken from the option's own slot, where it owns it (mem_enum_take; agora #279).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #279: an option of a String bound from a local Vec's vec_get, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ first → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `a heap string long enough to be heap allocated` ) )
    : ?String o ( vec_get [String] vs 0 )
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String got ( first )
    ( nurl_println ( string_data got ) )
    ^ 0
}
