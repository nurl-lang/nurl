// capture_given_a_join_over_droppable_struct_locals_bound_then_assigned: `: R e ? == k 0 ( idr a ) ( idr b )  = o e` in a closure, R a struct with a `% Drop` of its own, a built by a literal; both runs.
// Closed (AGORA-965): a whole value with a key (a struct by its first owned field) is a cursor over the local an arm's call lends; `= o e` takes over the one the join selected.
// main c4c0f35: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | runs-clean | - | AGORA-965: a capture given by name a `:` join over droppable struct locals
$ `stdlib/core/vec.nu`

: R { ( Vec i ) buf }

% Drop R {
    @ drop R r → v { ( vec_free [i] . r buf ) }
}

@ mkr i k → R {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v k )
    ^ @ R { v }
}

@ idr R r → R { ^ r }

@ run i k → v {
    : ~ R o ( mkr 7 )
    : ~ ( @ v ) f \ → v {
        : R a @ R { ( vec_new [i] ) }
        ( vec_push [i] . a buf 1 )
        : R b ( mkr 2 )
        : R e ? == k 0 ( idr a ) ( idr b )
        = o e
    }
    ( f )
    ( nurl_println_int ( vec_len [i] . o buf ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
