// capture_given_a_generic_that_lends_another_capture_beside_a_closure_local_runs_clean: a `% Drop` struct: `( gfirst [R] other loc )` lends only the other capture, not the closure local beside it - accepted
// Closed: a capture by pointer given a lend of what dies with the closure is given a copy it owns; a type with no copy is refused only where an argument that dies is lent (gen_assign, resolve_cap_nc_lends; agora #872, CodeRabbit's review of github#1914).
// main 525613db: runs clean (guard).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: a `% Drop` struct: `( gfirst [R] other loc )` lends only the other capture, not the closure local beside it - accepted
$ `stdlib/core/string.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_println `released` ) } }

@ gfirst [T] T a T b → T { ^ a }

@ run i k → v {
    : ~ R o @ R { ( string_from `outer value long enough for the heap here` ) }
    : R other @ R { ( string_from `another outer value long enough for heap` ) }
    : ~ ( @ v ) f \ → v {
        : R loc @ R { ( string_from `closure local value long enough for heap` ) }
        = o ( gfirst [R] other loc )
    }
    ( f )
    ( nurl_println ( string_data . o s ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
