// diag_inout_kept_argument_read_after.nu — a callee that keeps its `inout`
// parameter whole (returns it in a literal, pushes it into a container,
// stores it into a field) takes the value over, as it does one passed by
// value: the caller's binding is consumed by the call. Before agora #545 the
// caller stopped releasing the binding but could still read it, after the
// new owner had freed it.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String name }
: Rows { [i items }
: | Msg { One String Two }

@ in_literal inout String p → Holder { ^ @ Holder { p } }
@ in_enum inout String p → Msg { ^ @ Msg { One p } }
@ in_vec inout String p → ( Vec String ) {
    : ~ ( Vec String ) w ( vec_new [String] )
    ( vec_push [String] w p )
    ^ w
}
@ in_field inout String p inout Holder g → v { = . g name p }
@ in_rows inout [i p → Rows { ^ @ Rows { p } }

@ literal → i {
    : ~ String q ( string_from `a long enough string to be on the heap for sure` )
    {
        : Holder g ( in_literal q )
        ( nurl_println ( string_data . g name ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}

@ payload → i {
    : ~ String q ( string_from `a long enough string to be on the heap for sure` )
    {
        : Msg m ( in_enum q )
        ?? m { One t → { ( nurl_println ( string_data t ) ) } Two → {} }
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}

@ pushed → i {
    : ~ String q ( string_from `a long enough string to be on the heap for sure` )
    {
        : ( Vec String ) w ( in_vec q )
        ( nurl_println ( nurl_str_int ( vec_len [String] w ) ) )
    }
    ( nurl_println ( string_data q ) )
    ^ 0
}

@ field → i {
    : ~ String q ( string_from `a long enough string to be on the heap for sure` )
    : ~ Holder g @ Holder { ( string_from `the first long enough string to be on the heap` ) }
    ( in_field q g )
    ( nurl_println ( string_data q ) )
    ( nurl_println ( string_data . g name ) )
    ^ 0
}

@ rows → i {
    : ~ [i q [i | 1 2 3]
    {
        : Rows r ( in_rows q )
        ( nurl_println ( nurl_str_int . . r items length ) )
    }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

@ main → i {
    ( literal ) ( payload ) ( pushed ) ( field ) ( rows )
    ^ 0
}
