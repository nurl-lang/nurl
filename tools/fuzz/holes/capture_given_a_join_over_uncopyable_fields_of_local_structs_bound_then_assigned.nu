// capture_given_a_join_over_uncopyable_fields_of_local_structs_bound_then_assigned: as capture_given_a_join_over_fields_of_local_structs_bound_then_assigned, the field an R with a `% Drop` of its own and no copy.
// Closed (AGORA-967): refused, as a field of a struct dying before its holder is (__nc_outlive_die).
// main c4c0f35: LeakSanitizer: both structs taken over whole.
// map: §7.4 | A2 | rejected | - | AGORA-967: a capture given by name a `:` join over uncopyable fields lent out of local structs
$ `stdlib/core/vec.nu`

: R { ( Vec i ) buf }

% Drop R {
    @ drop R r → v { ( vec_free [i] . r buf ) }
}

: P { R x R y }

@ mkr i k → R {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    ^ @ R { v }
}

@ mk i k → P { ^ @ P { ( mkr k ) ( mkr + k 1 ) } }

@ ey P p → R { ^ . p y }

@ run i k → v {
    : ~ R o ( mkr 7 )
    : ~ ( @ v ) f \ → v {
        : P a ( mk 1 )
        : P b ( mk 2 )
        : R e ? == k 0 ( ey a ) ( ey b )
        = o e
    }
    ( f )
    ( nurl_println_int ( vec_at [i] . o buf 0 ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
