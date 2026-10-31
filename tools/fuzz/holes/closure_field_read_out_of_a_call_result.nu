// closure_field_read_out_of_a_call_result: a closure field read out of a call's result (`: ( @ i i ) f . ( mk 9 ) inner`) was neither the read's own nor dropped with the temporary: its env leaked, and so did the rest of the temporary (h266's rule covered handle fields, not closures).
// Closed: the field leaves the temporary, whose rest is dropped where it is read; its env is the read's own (taken when the call handed its result over, copied when it lent it), published as an owned closure temporary for the binding, argument, return or store that takes it.
// v0.78.0: accepted; LSan reported the closure env (16 B) and the temporary's String leaked.
// map: §7.4 | A2 | runs-clean | h323 | a closure field read out of a call's result was neither the read's own nor dropped with the temporary, so its env and the temporary's other fields leaked; the field now leaves the temporary as an owned closure temporary and the rest is dropped
$ `stdlib/core/string.nu`

: Wrap {
    ( @ i i ) inner
    String tag
}

@ mk i x → Wrap {
    ^ @ Wrap { \ i y → i { ^ + x y } ( string_from `t` ) }
}

@ main → i {
    : ( @ i i ) f . ( mk 9 ) inner
    ( nurl_println ( nurl_str_int ( f 0 ) ) )
    ^ 0
}
