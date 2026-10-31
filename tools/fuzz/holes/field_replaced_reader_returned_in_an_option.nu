// field_replaced_reader_returned_in_an_option: agora #265 — a field of a local bound, replaced, then the binding returned inside an option: the literal emptied the field's new value.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, the reader returned in an option (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ take i k → ?Inner {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v k )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    ( vec_push [i] . . o cur v 9 )
    ^ @ ?Inner { T got }
}

@ main → i {
    ?? ( take 7 ) {
        T k → { ( nurl_print `some ` ) ( nurl_print_int ( vec_at [i] . k v 0 ) ) ( nurl_print `\n` ) }
        F → { ( nurl_print `none\n` ) }
    }
    ^ 0
}
