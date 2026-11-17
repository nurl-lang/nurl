// capture_given_by_name_a_binding_that_lends_another_uncopyable_capture: `: R x ( gfirst [R] other loc )  = o x` in a closure, a `% Drop` struct; the caller then consumes other and reads o
// AGORA-904: refused - x may lend the capture other, and an R has no copy to give o (main 05206020: accepted, heap-use-after-free)
// map: §7.4 | A2 | rejected | - | AGORA-904: `: R x ( gfirst [R] other loc )  = o x` in a closure, a `% Drop` struct; the caller then consumes other and reads o
$ `stdlib/core/string.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_println `released` ) } }

@ eat sink R r → v { ( nurl_println ( string_data . r s ) ) }

@ gfirst [T] T a T b → T { ^ a }

@ run i k → v {
    : ~ R o @ R { ( string_from `outer value long enough for the heap here` ) }
    : R other @ R { ( string_from `another outer value long enough for heap` ) }
    : ~ ( @ v ) f \ → v {
        : R loc @ R { ( string_from `closure local value long enough for heap` ) }
        : R x ( gfirst [R] other loc )
        = o x
    }
    ( f )
    ( eat other )
    ( nurl_println ( string_data . o s ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
