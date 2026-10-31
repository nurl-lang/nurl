// field_replaced_reader_pushed_from_a_local: agora #265 — as field_replaced_reader_pushed, the struct a local (the shape the fix must keep clean).
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field of a local replaced under its reader, the reader pushed
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ main → i {
    : ( Vec Inner ) out ( vec_new [Inner] )
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    ( vec_push [Inner] out got )
    ( nurl_println_int ( vec_len [i] . ( vec_at [Inner] out 0 ) v ) )
    ^ 0
}
