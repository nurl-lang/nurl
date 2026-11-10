// cursor_stored_into_an_owner.nu — a cursor stored into an owner hands the
// value of the binding it is over to that owner (agora #545): released once,
// by the owner, and readable through it. (Reading the binding afterwards is
// refused: diag_cursor_stored_root_read.nu.)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String name }
: Rows { [i items }

@ main → i {
    : String q ( string_from `a long enough string to be on the heap for sure` )
    : ~ String c q
    : Holder g @ Holder { c }
    ( nurl_println ( string_data . g name ) )

    : String q2 ( string_from `another long enough string to be on the heap` )
    : ~ String c2 q2
    : ~ ( Vec String ) w ( vec_new [String] )
    ( vec_push [String] w c2 )
    ( nurl_println ( nurl_str_int ( vec_len [String] w ) ) )

    : [i q3 [i | 1 2 3]
    : ~ [i c3 q3
    : Rows r @ Rows { c3 }
    ~ x . r items { ( nurl_println ( nurl_str_int x ) ) }

    // a second store through the same cursor gets a value of its own
    : String q4 ( string_from `a fourth long enough string to be on the heap` )
    : ~ String c4 q4
    : Holder g4 @ Holder { c4 }
    : Holder h4 @ Holder { c4 }
    ( nurl_println ( string_data . g4 name ) )
    ( nurl_println ( string_data . h4 name ) )
    ^ 0
}
