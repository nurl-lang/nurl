// closure_assign_effects_ok.nu — closures that give a capture a new value
// (agora #151): a view taken after the call, a view no longer read when
// the closure runs, a field of a struct, and a loop over another
// container. Each runs clean.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ String x ( string_from `first` )
    : ( @ v ) h \ → v { = x ( string_from `second` ) }
    : s before ( string_data x )
    ( nurl_println before )
    ( h )
    : s after ( string_data x )
    ( nurl_println after )
    : ~ R r @ R { ( string_from `field` ) 0 }
    : ( @ v ) g \ → v { = . r s ( string_from `field again` ) }
    ( run g )
    ( nurl_println ( string_data . r s ) )
    : ~ ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `a` ) )
    ( vec_push [String] names ( string_from `b` ) )
    ~ n names {
        ( h )
        ( nurl_println ( string_data n ) )
    }
    ( vec_free [String] names )
    ^ 0
}
