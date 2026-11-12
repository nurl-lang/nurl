// A `~` loop's element of a type with its own `% Drop` that cannot be
// copied, handed to a `sink`: it is still in the container the loop walks,
// which drops it, so the callee would release it a second time. Refused,
// naming the cure — take the elements out of the container (vec_pop,
// vec_remove, or move the container to a function that drains it), or have
// the callee borrow (agora #669).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b tag ) ) } }

@ eat sink Bomb b → v { ( nurl_println_int . b boom ) }

@ f ( Vec Bomb ) v → v {
    ~ x v {
        ( eat x )
    }
}

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v @ Bomb { ( string_from `an element bomb` ) 0 } )
    ( f v )
    ^ 0
}
