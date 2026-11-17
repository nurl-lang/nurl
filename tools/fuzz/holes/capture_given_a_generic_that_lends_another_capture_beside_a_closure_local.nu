// capture_given_a_generic_that_lends_another_capture_beside_a_closure_local: a `% Drop` struct: `( gfirst [R] other loc )` lends the other capture `other`, which the by-pointer capture `o` cannot be given a copy of
// AGORA-904: refused - the caller's `o` would borrow `other` where nothing in the caller follows it (released first, then read: heap-use-after-free; capture_lends_another_capture_then_that_one_is_consumed). Was AGORA-872's runs-clean guard (main 525613db..05206020: accepted).
// map: §7.4 | A2 | rejected | - | AGORA-904: a by-pointer capture given a call's lend of another capture, of a type with no copy
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
