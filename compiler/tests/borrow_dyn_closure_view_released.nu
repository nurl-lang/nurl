// agora #148: a dyn method returning a closure that captured its
// argument hands back a view of that argument (retclo), exactly as a
// direct call does. Releasing the argument before the closure runs is
// a use of freed memory, and is refused at the call of the closure.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

% Maker [T] {
    @ make T self String s → ( @ v )
}

: M { i k }

% Maker M { @ make M m String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } } }

@ main → i {
    : M m @ M { 1 }
    : %Maker d ( dyn Maker m )
    : String t ( mk )
    : ( @ v ) g ( make d t )
    ( string_free t )
    ( g )
    ^ 0
}
