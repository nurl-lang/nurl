// closure_snapshot_assign_released.nu — a value assigned over a by-value
// capture inside a closure is released when the closure returns.
//
// A String / Vec captured by value is a snapshot: the body may scratch it,
// and the write is discarded on return (the compiler warns). The snapshot
// borrows the env's value, but a fresh value assigned over it had no owner
// and leaked on every call.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ round → i {
    : ~ ( Vec u ) got ( vec_new [u] )
    : ~ String name ( string_from `outer` )
    : ( @ i ) scratch \ → i {
        = got ( vec_new [u] )
        ( vec_push [u] got # u 1 ) ( vec_push [u] got # u 2 )
        = name ( string_from `inner` )
        = name ( string_from `inner again` )
        ^ + ( vec_len [u] got ) ( string_len name )
    }
    : i a ( scratch )
    : i b ( scratch )
    // The captured bindings themselves are untouched.
    ^ + + a b + ( vec_len [u] got ) ( string_len name )
}

@ main → i {
    : i r ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 50 { : i x ( round ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `result ` ( nurl_str_int r ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}
