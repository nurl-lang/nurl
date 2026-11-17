// capture_lends_another_capture_then_that_one_is_consumed: `= o ( gfirst [R] other loc )` in a closure, a `% Drop` struct; the caller then consumes `other` and reads `o`
// AGORA-904: refused - `o` would be a lend of `other`, which the caller never learns (main 05206020: accepted, heap-use-after-free)
// map: §7.4 | A2 | rejected | - | AGORA-904
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
        = o ( gfirst [R] other loc )
    }
    ( f )
    ( eat other )
    ( nurl_println ( string_data . o s ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
