// field_replaced_under_a_reader_holding_an_arc_copy: agora #265 — a binding read out of a field, then given a copy of the field's Arc (same control block), then the field replaced: the binding owns its copy and is not handed the old value, which is dropped (the guard formal asked a probe for).
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; ran clean.
// map: §2.12 | A2 | runs-clean | - | agora #265: a reader owning an Arc copy is not handed a replaced field's old value
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/arc.nu`

: Inner { ( Arc ( Vec i ) ) a i n }
: Outer { Inner cur }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ~ Outer o @ Outer { @ Inner { ( arc_new [( Vec i )] xs ) 1 } }
    : ~ Inner got . o cur
    = got @ Inner { ( arc_clone [( Vec i )] . . o cur a ) 2 }
    = . o cur @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) 3 }
    ( nurl_print_int ( vec_len [i] ( arc_get [( Vec i )] . got a ) ) )
    ( nurl_println_int . got n )
    ^ 0
}
