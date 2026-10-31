// field_replaced_vec_reader_kept_in_an_option: agora #265 — a Vec field bound to a local, replaced, then the binding put in an option.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | - | agora #265: a Vec field replaced under its reader, the reader kept in an option (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: S { ( Vec i ) v i n }

@ main → i {
    : ~ S s @ S { ( vec_new [i] ) 0 }
    ( vec_push [i] . s v 7 )
    : ( Vec i ) got . s v
    = . s v ( vec_new [i] )
    : ?( Vec i ) keep @ ?( Vec i ) { T got }
    ?? keep { T k → { ( nurl_println_int ( vec_len [i] k ) ) } F → {} }
    ( nurl_println_int ( vec_len [i] . s v ) )
    ^ 0
}
