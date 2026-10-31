// field_replaced_reader_handed_to_a_sink: agora #265 — a struct field bound, replaced, then the binding handed to a `sink`: the field's new value was emptied with it.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; the new value was emptied — index out of bounds panic.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, the reader handed to a sink (new value lost)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ eat sink Inner x → i { ^ ( vec_at [i] . x v 0 ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    ( vec_push [i] . . o cur v 9 )
    ( nurl_print_int ( eat got ) )
    ( nurl_print_int ( vec_at [i] . . o cur v 0 ) )
    ( nurl_print `\n` )
    ^ 0
}
