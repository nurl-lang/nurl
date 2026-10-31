// agora #148: a dyn method returning a closure was refused at the call:
// its fn-ptr type starts with the returned closure's `{`, and the arity
// check read the parameter list from inside the return type (0 params).
// The call type-checks now, and the closure it hands back works.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

% Maker [T] {
    @ make T self String s → ( @ v )
    @ adder T self i k → ( @ i i )
}

: M { i k }

% Maker M {
    @ make M m String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } }
    @ adder M m i k → ( @ i i ) { : i base + . m k k ^ \ i x → i { ^ + x base } }
}

@ main → i {
    : M m @ M { 1 }
    : %Maker d ( dyn Maker m )
    : String t ( mk )
    : ( @ v ) g ( make d t )
    ( g )
    ( string_free t )
    : ( @ i i ) add ( adder d 10 )
    ( nurl_println ( nurl_str_int ( add 31 ) ) )
    ^ 0
}
