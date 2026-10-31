// field_replaced_under_its_reader_arc_only: agora #265 — as field_replaced_under_its_reader_arc_first, the struct's only handle an `Arc`.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, an Arc its only handle (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/arc.nu`

: Inner { ( Arc ( Vec i ) ) a i n }
: Outer { Inner cur }

@ take inout Outer o → Inner {
    : Inner got . o cur
    = . o cur @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) 0 }
    ^ got
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ~ Outer o @ Outer { @ Inner { ( arc_new [( Vec i )] xs ) 1 } }
    : Inner g ( take o )
    ( nurl_print_int ( vec_len [i] ( arc_get [( Vec i )] . g a ) ) )
    ( nurl_print `\n` )
    ^ 0
}
