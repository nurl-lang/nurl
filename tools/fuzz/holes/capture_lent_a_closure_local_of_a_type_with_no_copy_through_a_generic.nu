// capture_lent_a_closure_local_of_a_type_with_no_copy_through_a_generic: the same through a generic identity, its lends known only at module end
// Closed: a capture by pointer given a lend of a type with no copy is refused - it cannot be given a copy it owns, as an `inout` parameter cannot (gen_assign; resolve_cap_nc_lends where the callee's lends are known only at module end; agora #872).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §7.4 | A2 | rejected | - | AGORA-872: the same through a generic identity, its lends known only at module end
$ `stdlib/core/string.nu`

: R { String s }

% Drop R { @ drop R r → v { ( nurl_println `released` ) } }

@ rid R a → R { ^ a }

@ grid [T] T a → T { ^ a }

@ run i k → v {
    : ~ R o @ R { ( string_from `outer value long enough for the heap here` ) }
    : ~ ( @ v ) f \ → v {
        : R loc @ R { ( string_from `closure local value long enough for heap` ) }
        = o ( grid [R] loc )
    }
    ( f )
    ( nurl_println ( string_data . o s ) )
}

@ main → i {
    ( run 0 )
    ^ 0
}
