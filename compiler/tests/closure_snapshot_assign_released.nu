// closure_snapshot_assign_released.nu — a value a closure assigns over a
// captured String / Vec replaces the binding's, and the one it replaces
// is released.
//
// A closure that assigns a `: ~` binding captures it by reference: the
// write reaches the binding (it used to land on a per-call snapshot and
// vanish, with only a warning). The value replaced — the binding's own,
// or the one an earlier call assigned — is dropped by the assignment, so
// fifty rounds of two calls each leave the live allocation count where it
// was.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

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
    // The bindings hold what the second call assigned.
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
