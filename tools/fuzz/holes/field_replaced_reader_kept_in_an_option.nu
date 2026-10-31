// field_replaced_reader_kept_in_an_option: agora #265 — a struct field bound to a local, replaced, then the binding put in an option: the literal copied the value the binding had taken over.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced under its reader, the reader kept in an option (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner got . o cur
    = . o cur @ Inner { ( vec_new [i] ) }
    : ?Inner keep @ ?Inner { T got }
    ?? keep {
        T k → { ( nurl_print `some ` ) ( nurl_print_int ( vec_len [i] . k v ) ) ( nurl_print `\n` ) }
        F → { ( nurl_print `none\n` ) }
    }
    ^ 0
}
