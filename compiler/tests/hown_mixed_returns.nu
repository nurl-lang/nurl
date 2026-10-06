// A function that LENDS on some paths (a global's field, read through a
// pointer) and hands over a FRESH value on others answers per call whether
// its caller owns the result (`@.__nurl_retdyn`). Every consumer has to
// take that answer — a `:` binding, a `?` join of two such calls, and a
// field of a returned literal. Taken for a borrow throughout, each fresh
// result leaked (the signed-in agora leaked its request principal this
// way, ~150 B per call); taken for owned, the global would be freed.
// Run under the sanitizer corpus with leak detection: no leak, and the
// lent global still reads back intact at the end.
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`

: Store {
    String path
    b ok
}

: State {
    Store store
    String name
}

: Who {
    i status
    String sub
    Store st
}

: ~ i g_state 0
: ~ b g_local F

unsafe

@ state → *State { ^ ( rcbox_ptr [State] g_state ) }

unsafe

@ the_store → Store {
    : *State p ( state )
    ^ @ Store { . . p store path . . p store ok }
}

@ owned_store → Store { ^ @ Store { ( string_from `org.db` ) T } }

// struct: lends (mixed literal: a fresh `sub` beside the lent store) or fresh
@ who i st → Who {
    ? g_local { ^ @ Who { 0 ( string_from `local` ) ( the_store ) } } {}
    ^ @ Who { st ( string_from `subject` ) ( owned_store ) }
}

@ who_fresh i st → Who { ^ @ Who { st ( string_from `two` ) ( owned_store ) } }

// handle: lends the global's String, or a fresh one
unsafe

@ name → String {
    ? g_local { ^ . ( state ) name } {}
    ^ ( string_from `fresh` )
}

@ bind_struct i st → i {
    : Who w ( who st )
    ? == . w status 9 { ^ 0 } {}
    ^ ( string_len . . w st path )
}

@ join_struct i st → i {
    : Who w ? == st 7 ( who_fresh st ) ( who st )
    ^ + . w status ( string_len . w sub )
}

@ bind_string → i {
    : String s ( name )
    ^ ( string_len s )
}

@ join_string i st → i {
    : String s ? == st 7 ( string_from `x` ) ( name )
    ^ ( string_len s )
}

@ round i st → i {
    ^ + + ( bind_struct st ) ( join_struct st ) + ( bind_string ) ( join_string st )
}

unsafe

@ main → i {
    = g_state ( rcbox_new [State] @ State { @ Store { ( string_from `agora.db` ) T } ( string_from `global` ) } )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 20 { = acc + acc + ( round 0 ) ( round 7 ) = k + k 1 }
    = g_local T
    = k 0
    ~ < k 20 { = acc + acc + ( round 0 ) ( round 7 ) = k + k 1 }
    : *State p ( state )
    ( nurl_println ( string_data . . p store path ) )
    ( nurl_println ( string_data . p name ) )
    ( nurl_println ( string_data ( string_from ? > acc 0 `ran` `nothing` ) ) )
    ^ 0
}
