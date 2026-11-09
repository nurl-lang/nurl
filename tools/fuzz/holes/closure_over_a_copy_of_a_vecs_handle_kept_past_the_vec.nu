// closure_over_a_copy_of_a_vecs_handle_kept_past_the_vec: agora #483 — a closure over `cur`, a copy of `t`'s own handle (`: ~ … cur t`), kept past `t`'s block and run after
// Closed: a borrow whose bytes are its owner's own is a copy of that owner's handle, `~R`, which the owner's end ends (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a copy of a Vec's handle kept past the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
        : ~ ( Vec String ) cur t
        = f \ → i { ^ ( strlen ( string_data ( vec_at [String] cur 0 ) ) ) }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
