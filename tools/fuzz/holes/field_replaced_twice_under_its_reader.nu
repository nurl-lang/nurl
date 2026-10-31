// field_replaced_twice_under_its_reader: agora #265 — a field replaced twice under a binding read out of it, an `Arc` first.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced twice under its reader (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/arc.nu`

: Inner { ( Arc ( Vec i ) ) a ( Vec i ) v }
: Outer { Inner cur }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner got . o cur
    = . o cur @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) ( vec_new [i] ) }
    ( vec_push [i] . . o cur v 8 )
    = . o cur @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) ( vec_new [i] ) }
    ( vec_push [i] . . o cur v 9 )
    ( nurl_print_int ( vec_at [i] . got v 0 ) )
    ( nurl_println_int ( vec_at [i] . . o cur v 0 ) )
    ^ 0
}
