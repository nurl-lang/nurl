// slice_field_of_a_struct_held_by_a_slice_an_option_or_a_vec_never_freed: agora #510 — a struct whose field is a slice owned nothing by its type: only a struct literal bound in the function that wrote it had the field tracked, so the same struct as a slice element, an option payload, a Vec element or a call's result leaked the field (and the Strings in it).
// Closed: a struct with a slice field is an owning struct: its drop releases the slice, elements first, wherever the struct is held.
// main (before this PR): LeakSanitizer, every inner buffer and its Strings.
// map: §7.6 | A2 | runs-clean | - | agora #510: a slice field of a struct held by a slice, an option or a Vec, or handed back by a call, was never freed (leak)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { [String names i n }

@ mkh i n → H {
    ^ @ H { [String | ( string_from `a long enough string to be on the heap for sure` )] n }
}

@ main → i {
    : [H hs [H | ( mkh 1 ) ( mkh 2 )]
    ~ h hs { ( nurl_println ( nurl_str_int . h n ) ) }
    : ?H o @ ?H { T ( mkh 3 ) }
    ?? o {
        T h → { ( nurl_println ( nurl_str_int . h n ) ) }
        F → {}
    }
    : ~ ( Vec H ) vs ( vec_new [H] )
    ( vec_push [H] vs ( mkh 4 ) )
    ( nurl_println ( nurl_str_int ( vec_len [H] vs ) ) )
    : H one ( mkh 5 )
    ( nurl_println ( nurl_str_int . one n ) )
    ^ 0
}
