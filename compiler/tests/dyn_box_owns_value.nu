// dyn_box_owns_value.nu — `( dyn Trait v )` boxes v, and the `%dyn`
// value owns the box: its drop runs the concrete type's drop through
// vtable slot 0 and frees the box. So boxing is a STORE of v, exactly
// like a struct literal's field (docs/MEMORY.md §7.6 "Stores move"):
//
//   * an owned local moves in — its own drop flag clears (boxing the bare
//     bytes dropped `Dog.name` twice: heap-use-after-free under ASan);
//   * a borrowed value — a parameter, a field read — is copied;
//   * a `%dyn` built right in a call's argument is dropped after the call
//     as a whole (only the box was freed: the boxed value leaked), even
//     when the operand is itself a call;
//   * a struct with a `%dyn` field is dropped with it (nothing was: the
//     box, the boxed value and every sibling field leaked).
//
// Run under compiler/tests/run_san_tests.sh for the memory proof; the
// golden only pins the arithmetic.

$ `stdlib/core/string.nu`

% Speaker [T] {
    @ speak T self i volume → i
}

: Dog { String name i pitch }

% Speaker Dog { @ speak Dog d i volume → i { ^ + ( string_len . d name ) volume } }

: Pair { Dog a i k }
: Kennel { String label % Speaker who }

@ announce %Speaker s i v → i { ^ ( speak s v ) }

@ from_param Dog d → %Speaker { ^ ( dyn Speaker d ) }

@ from_field Pair p → i {
    : %Speaker sp ( dyn Speaker . p a )
    ^ ( speak sp 2 )
}

@ mk_dog i n → Dog { ^ @ Dog { ( string_from `abcd` ) n } }

@ round i n → i {
    : ~ i t 0
    // an owned local moves into the box
    : Dog d0 @ Dog { ( string_from `rexrex` ) n }
    : %Speaker s0 ( dyn Speaker d0 )
    = t + t ( speak s0 1 )
    // a parameter is copied: the caller's Dog stays whole
    : Dog d @ Dog { ( string_from `rex` ) n }
    : %Speaker s1 ( from_param d )
    = t + t ( speak s1 1 )
    = t + t ( string_len . d name )
    // a field read is copied: the Pair keeps its Dog
    : Pair p @ Pair { @ Dog { ( string_from `xy` ) 1 } 3 }
    = t + t ( from_field p )
    = t + t ( string_len . . p a name )
    // a temporary dyn argument, operand a call
    = t + t ( announce ( dyn Speaker ( mk_dog n ) ) 1 )
    // a struct holding a dyn field
    : Dog d2 @ Dog { ( string_from `kennel-dog` ) n }
    : Kennel k @ Kennel { ( string_from `kennel` ) ( dyn Speaker d2 ) }
    = t + t ( speak . k who 1 )
    = t + t ( string_len . k label )
    ^ t
}

@ main → i {
    : ~ i t 0
    : ~ i j 0
    ~ < j 100 { = t + t ( round j ) = j + j 1 }
    ( nurl_println_int t )
    ^ 0
}
