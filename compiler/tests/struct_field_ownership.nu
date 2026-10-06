// struct_field_ownership.nu — what a struct's fields own goes where the
// struct goes, and is released once.
//
// A closure in a struct field is the struct's (docs/MEMORY.md §7.4), like
// a String field. Each shape below was wrong before, in turn:
//   - `( keep kept @ Inner { name \ → i { ^ k } } )`: the call site took the
//     literal's env for its own temporary closure argument and released it
//     after the call, so the kept closure read freed memory;
//   - the same shape one level down, `@ Outer { ( keep kept @ Inner { … } )
//     7 }`, read Inner's owned fields as paths into Outer's field 0
//     (`extractvalue %Outer …, 0, 1`: invalid IR, rejected by clang);
//   - a bound Inner moved into a Vec the function returns: the closure's
//     env was released with the BINDING (a per-binding field list), so the
//     returned Vec held a dangling env; the struct's drop never touched it;
//   - `= . p name ( string_from … )` on a struct this scope owns leaked the
//     String it replaced.
// Every round must also leave the live allocation count where it found it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Inner { String name ( @ i ) f }

: Outer { i handle i id }

@ keep ( Vec Inner ) kept Inner x → i {
    ( vec_push [Inner] kept x )
    ^ ( vec_len [Inner] kept )
}

@ sum_calls ( Vec Inner ) kept → i {
    : ~ i acc 0
    : ~ i j 0
    ~ < j ( vec_len [Inner] kept ) {
        ?? ( vec_get [Inner] kept j ) {
            T x → { : ( @ i ) f . x f = acc + acc + ( f ) ( string_len . x name ) }
            F → {}
        }
        = j + j 1
    }
    ^ acc
}

// A bound struct moved into the Vec this function hands back.
@ build i k → ( Vec Inner ) {
    : ( Vec Inner ) kept ( vec_new [Inner] )
    : Inner x @ Inner { ( string_from `bound` ) \ → i { ^ * k 100 } }
    ( vec_push [Inner] kept x )
    ^ kept
}

// Replaced fields: the old String and the old closure are released.
@ reassign i k → i {
    : ~ Inner p @ Inner { ( string_from `one` ) \ → i { ^ k } }
    = . p name ( string_from `three` )
    = . p f \ → i { ^ + k 1 }
    : ( @ i ) f . p f
    ^ + ( f ) ( string_len . p name )
}

@ round i k → i {
    : ( Vec Inner ) kept ( vec_new [Inner] )
    : i n ( keep kept @ Inner { ( string_from `direct` ) \ → i { ^ k } } )
    : Outer o @ Outer { ( keep kept @ Inner { ( string_from `nested` ) \ → i { ^ * k 10 } } ) 7 }
    : ( Vec Inner ) built ( build k )
    ^ + + ( sum_calls kept ) ( sum_calls built ) + + n + . o handle . o id ( reassign k )
}

@ main → i {
    : i first ( round 5 )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 50 { ( round k ) = k + k 1 }
    : i l1 ( live )
    // (5 + 6) + (50 + 6) + (500 + 5) + 1 + 2 + 7 + (6 + 5)
    ( nurl_println ( nurl_str_cat `sum ` ( nurl_str_int first ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
