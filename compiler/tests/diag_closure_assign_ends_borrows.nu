// diag_closure_assign_ends_borrows.nu — a closure that gives a capture,
// or a field of one, a new value (agora #151). Running it releases what
// the capture held, so a view or an element borrowed before the call is
// gone after it — the call, a closure handed to a helper, or a closure
// run by another closure. A closure that runs one freeing a capture
// frees it too.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }

@ run ( @ v ) f → v { ( f ) }

@ view_across_a_call → v {
    : ~ String x ( mk )
    : ( @ v ) h \ → v { = x ( string_new ) }
    : s v ( string_data x )
    ( h )
    ( nurl_println v )
}

@ view_of_a_field → v {
    : ~ R r @ R { ( mk ) 0 }
    : ( @ v ) h \ → v { = . r s ( string_new ) }
    : s v ( string_data . r s )
    ( h )
    ( nurl_println v )
}

@ element_across_an_inline_closure → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : String e ( vec_at [String] xs 0 )
    ( run \ → v { = xs ( vec_new [String] ) } )
    ( nurl_println ( string_data e ) )
}

@ view_across_a_nested_closure → v {
    : ~ String x ( mk )
    : ( @ v ) h \ → v { = x ( string_new ) }
    : ( @ v ) g \ → v { ( run h ) }
    : s v ( string_data x )
    ( g )
    ( nurl_println v )
}

@ nested_closure_frees_twice → v {
    : ~ String s ( mk )
    : ( @ v ) h \ → v { ( string_free s ) }
    : ( @ v ) g \ → v { ( h ) }
    ( g )
    ( g )
}

@ main → i { ^ 0 }
