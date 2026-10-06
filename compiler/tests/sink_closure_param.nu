// sink_closure_param.nu — a `sink` closure parameter takes the closure over.
//
// A closure parameter was always borrowed, `sink` or not: the callee never
// dropped it and the caller dropped its own afterwards, so a combinator
// capturing its source (`iter_map ( iter_range 0 n ) f`) copied the whole
// chain at every stage and `iter_free` released nothing early. Now a
// temporary handed to a `sink` closure parameter moves in (the caller does
// not drop it), a binding is handed a copy and stays usable, and the callee
// drops what it took unless it moves it on — returned, or captured by a
// closure it returns.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ mk i k → ( @ i i ) {
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st k )
    ^ \ i x → i { ^ + x ( vec_len [i] st ) }
}

// Drops what it took.
@ eat sink ( @ i i ) f → v {}

// Keeps it inside the closure it returns: no copy.
@ wrap sink ( @ i i ) f → ( @ i i ) { ^ \ i x → i { ^ * 2 ( f x ) } }

@ main → i {
    : i l0 ( live )
    : ( @ i i ) e ( mk 1 )
    : i built - ( live ) l0
    ( eat e )
    ( nurl_println ( nurl_str_cat `binding still usable: ` ( nurl_str_int ( e 10 ) ) ) )
    ( nurl_println ? == - ( live ) l0 built `a binding is copied, the copy dropped by the callee` `copy leaked` )
    : i l1 ( live )
    ( eat ( mk 2 ) )
    ( nurl_println ? == ( live ) l1 `a temporary moves in and is dropped by the callee` `temporary leaked` )
    : i l2 ( live )
    : ( @ i i ) w ( wrap ( wrap ( mk 3 ) ) )
    : i grew - ( live ) l2
    ( nurl_println ( nurl_str_cat `wrapped: ` ( nurl_str_int ( w 1 ) ) ) )
    // mk's env and Vec, and one env per wrap: nothing copied along the way.
    ( nurl_println ( nurl_str_cat `allocations for a two-level chain: ` ( nurl_str_int grew ) ) )
    ^ 0
}
