// Inside a closure body, a closure lent out of a captured Arc (`: ( @ v i )
// run ( arc_get … mine )`) can be run more than once, and in a loop: an
// immutable Arc capture is not given a new value by anything run there,
// and its payload is frozen (agora #644). Prints 2 and 3.
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/io.nu`

@ twice → v {
    : Atomic hits ( atomic_new 0 )
    : ( @ v i ) work \ i k → v { : i before ( atomic_add hits k ) }
    : ( Arc ( @ v i ) ) mine ( arc_new [( @ v i )] work )
    : ( @ v ) body \ → v {
        : ( @ v i ) run ( arc_get [( @ v i )] mine )
        ( run 1 )
        ( run 1 )
    }
    ( body )
    ( nurl_println ( nurl_str_int ( atomic_load hits ) ) )
}

@ thrice → v {
    : Atomic hits ( atomic_new 0 )
    : ( @ v i ) work \ i k → v { : i before ( atomic_add hits k ) }
    : ( Arc ( @ v i ) ) mine ( arc_new [( @ v i )] work )
    : ( @ v ) body \ → v {
        : ( @ v i ) run ( arc_get [( @ v i )] mine )
        : ~ i k 0
        ~ < k 3 { ( run 1 ) = k + k 1 }
    }
    ( body )
    ( nurl_println ( nurl_str_int ( atomic_load hits ) ) )
}

@ main → i {
    ( twice )
    ( thrice )
    ^ 0
}
