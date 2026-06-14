// ptr_field_name_shadow.nu — regression: field access on a struct POINTER
// must read the FIELD even when the field name matches an in-scope integer
// variable (parameter or local). Previously `. p state` with an `i state`
// parameter mis-routed to the pointer array-index path and loaded the
// variable as an index → a silent miscompile (clang caught the type
// mismatch). A struct field always wins over a same-named variable.

: Box { i state  i other }

// field name `state` collides with the parameter `state`
@ via_ptr *Box bx i state → i { ^ + . bx state * 100 state }

// same collision, struct passed BY VALUE (was already correct — guard it)
@ via_val Box bx i state → i { ^ + . bx state * 100 state }

// field name collides with a LOCAL binding, not a parameter
@ via_local *Box bx → i {
    : i state 9
    ^ + . bx state state    // field(.) + local — field must win on the left
}

@ main → i {
    : *Box p # *Box ( nurl_alloc Z Box )
    = . p state 7
    = . p other 0

    : Box v @ Box { 7 0 }

    ( nurl_print_int ( via_ptr p 3 ) )    // field 7 + 100*3 = 307
    ( nurl_print_int ( via_val v 3 ) )    // 307
    ( nurl_print_int ( via_local p ) )    // field 7 + local 9 = 16
    ( nurl_free # s p )
    ^ 0
}
