// field_replaced_reader_pushed: agora #265 — a field of an `inout` parameter bound, replaced, then the binding pushed into a Vec: the binding's flag still dropped what the Vec held.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, the reader pushed (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ take inout Outer o → i {
    : ( Vec Inner ) out ( vec_new [Inner] )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    ( vec_push [Inner] out got )
    ^ ( vec_len [i] . ( vec_at [Inner] out 0 ) v )
}

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    ( nurl_println_int ( take o ) )
    ^ 0
}
