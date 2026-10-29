// dyn_holds_what_its_operand_held_ok.nu — the trait objects agora #156's
// rules accept: one over a struct of views used while what it views lives,
// over an owner (boxed directly or by a wrapper that takes it), and over a
// closure that captured by value.

$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

: O { String s i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

% Show O { @ len O o → i { ^ ( string_len . o s ) } }

% Runner [T] {
    @ run T self → i
}

: B { ( @ i ) cb i pad }

% Runner B { @ run B b → i { : ( @ i ) c . b cb ^ ( c ) } }

@ wrap_owner sink O o → %Show { ^ ( dyn Show o ) }

@ wrap B b → %Runner { ^ ( dyn Runner b ) }

@ owner → %Show {
    : O o @ O { ( string_from `a string long enough to own a heap buffer here` ) 0 }
    ^ ( dyn Show o )
}

@ owner_through_a_wrapper → %Show {
    : O o @ O { ( string_from `another string long enough to own a buffer` ) 0 }
    : %Show r ( wrap_owner o )
    ^ r
}

@ by_value i x → %Runner {
    : ( @ i ) f \ → i { ^ + x 1 }
    : B b @ B { f 0 }
    : %Runner r ( wrap b )
    ^ r
}

@ main → i {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    : V v @ V { ( string_data s ) 0 }
    : %Show a ( dyn Show v )
    : %Show b ( dyn Show @ V { ( string_data s ) 1 } )
    : %Show c ( owner )
    : %Show d ( owner_through_a_wrapper )
    : %Runner e ( by_value 40 )
    ( nurl_println_int + + ( len a ) ( len b ) + ( len c ) ( len d ) )
    ( nurl_println_int ( run e ) )
    ^ 0
}
