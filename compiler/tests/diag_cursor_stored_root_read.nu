// diag_cursor_stored_root_read.nu — a cursor (`: ~ T c q`) borrows `q`, so
// storing the cursor into an owner stores q's value there: q is that owner's
// from then on, as if it had been stored by name (docs/MEMORY.md §7.6). Before
// agora #545 only the cursor was marked, and q read its buffer after the
// owner had released it — for a String, a Vec and a slice alike.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String name }
: Rows { [i items }

@ in_a_literal → i {
    : String q ( string_from `a long enough string to be on the heap for sure` )
    : ~ String c q
    {
        : Holder g @ Holder { c }
        ( nurl_println ( string_data . g name ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}

@ pushed → i {
    : String q ( string_from `a long enough string to be on the heap for sure` )
    : ~ String c q
    {
        : ~ ( Vec String ) w ( vec_new [String] )
        ( vec_push [String] w c )
        ( nurl_println ( nurl_str_int ( vec_len [String] w ) ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}

@ a_slice → i {
    : [i q [i | 1 2 3]
    : ~ [i c q
    {
        : Rows g @ Rows { c }
        ( nurl_println ( nurl_str_int . . g items length ) )
    }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ main → i {
    ( in_a_literal ) ( pushed ) ( a_slice )
    ^ 0
}
