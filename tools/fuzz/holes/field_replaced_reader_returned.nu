// field_replaced_reader_returned: agora #265 — a field of a local bound, replaced, then the binding returned: the return copied the value the binding had taken over.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, the reader returned (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ take i k → Inner {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v k )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    ^ got
}

@ main → i {
    : Inner g ( take 7 )
    ( nurl_print_int ( vec_at [i] . g v 0 ) )
    ( nurl_print `\n` )
    ^ 0
}
