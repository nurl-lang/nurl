// diag_loop_container_released_in_body.nu — a `~` loop's container
// released in the loop's body (agora #147): given a new value, handed to
// a callee that takes it, or reassigned by a closure the body runs. The
// loop holds a borrow of the container, so each releases what the loop
// is still reading. And an `inout` callee that hands a field of its
// parameter to a callee that takes it empties the caller's field: a
// borrow of it the caller holds ends at the call. (That callee is itself
// refused now: it hands its parameter back with the field taken, agora
// #280.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { ( Vec String ) xs i n }

@ take_any [T] sink T x → v {}

@ reassigned → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    ~ x xs {
        = xs ( vec_new [String] )
        ( nurl_println ( string_data x ) )
    }
}

@ field_reassigned → v {
    : R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    ~ x . r xs {
        = . r xs ( vec_new [String] )
        ( nurl_println ( string_data x ) )
    }
}

@ field_taken → v {
    : R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    ~ x . r xs {
        ( take_any [( Vec String )] . r xs )
        ( nurl_println ( string_data x ) )
    }
}

@ by_closure → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    ~ x xs {
        ( h )
        ( nurl_println ( string_data x ) )
    }
}

@ g inout R r → v { ( take_any [( Vec String )] . r xs ) }

@ inout_callee_takes_field → v {
    : ~ R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    : String e ( vec_at [String] . r xs 0 )
    ( g r )
    ( nurl_println ( string_data e ) )
}

@ main → i { ^ 0 }
