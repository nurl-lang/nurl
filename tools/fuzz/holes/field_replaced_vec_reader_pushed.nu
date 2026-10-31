// field_replaced_vec_reader_pushed: agora #265 — as field_replaced_reader_pushed, the field a Vec.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #265: a Vec field replaced under its reader, the reader pushed (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: S { ( Vec i ) v }

@ take inout S s → i {
    : ( Vec ( Vec i ) ) out ( vec_new [( Vec i )] )
    : ( Vec i ) got . s v
    = . s v ( vec_new [i] )
    ( vec_push [( Vec i )] out got )
    ^ ( vec_len [i] ( vec_at [( Vec i )] out 0 ) )
}

@ main → i {
    : ~ S s @ S { ( vec_new [i] ) }
    ( vec_push [i] . s v 7 )
    ( nurl_println_int ( take s ) )
    ^ 0
}
