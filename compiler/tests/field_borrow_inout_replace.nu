// A callee handed a struct `inout` is summarised by the fields it may give
// a new value (g_fn_replaces: `k.f`), so a borrow of another field of the
// struct survives the call — the GPU code's `: GpuKit kit . pg kit`, then
// helpers that rebuild `pg`'s launch records. Replacing the borrowed field
// itself ends the borrow (diag_field_borrow_inout_replaced).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Prog {
    String name
    ( Vec i ) recs
}

// Gives `recs` a new value; `name` is left alone.
@ rebuild inout Prog p → v {
    : ~ ( Vec i ) fresh ( vec_new [i] )
    ( vec_push [i] fresh 7 )
    = . p recs fresh
}

// …and through a helper: the summary follows the call.
@ rebuild_twice inout Prog p → v {
    ( rebuild p )
    ( rebuild p )
}

@ main → i {
    : ~ Prog p @ Prog { ( string_from `kit` ) ( vec_new [i] ) }
    : String nm . p name
    ( rebuild_twice p )
    ( nurl_println ( string_data nm ) )
    ( nurl_println ( nurl_str_int ( vec_at [i] . p recs 0 ) ) )
    ^ 0
}
