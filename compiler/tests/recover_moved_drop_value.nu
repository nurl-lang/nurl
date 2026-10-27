// recover_moved_drop_value.nu — a value with a destructor, moved on, and a
// panic later in the same scope: its destructor runs once.
//
// A binding with a drop flag is journaled with the flag, and the drain
// reads it (h361–h363). Before, the registration read the flag once, when
// it was made: a value moved into a struct literal, handed to a `sink`
// parameter or captured by a closure was dropped by its new owner and then
// again by the drain. For a trait object that is a free of its box twice;
// for `Tag` below, its line printed twice. Each case prints its value's
// drop once, then the panic's message; the trait object cases run clean
// under AddressSanitizer.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Tag { String name }

% Drop Tag {
    @ drop Tag t → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . t name ) ) ) }
}

: Wrap { Tag t }

: Job { ( @ v ) run }

% Peek [T] { @ peek T self → i }

% Peek Tag {
    @ peek Tag t → i { ^ ( string_len . t name ) }
}

: Boxed { % Peek p }

@ take sink Tag t → v { ( nurl_println ( nurl_str_cat `took ` ( string_data . t name ) ) ) }

@ take_dyn sink %Peek d → v { : i _n ( peek d ) }

@ into_a_literal → v {
    : Tag a @ Tag { ( string_from `literal` ) }
    : Wrap w @ Wrap { a }
    ( panic `after a literal` )
}

@ into_a_sink → v {
    : Tag a @ Tag { ( string_from `sink` ) }
    ( take a )
    ( panic `after a sink` )
}

@ into_a_closure → v {
    : Tag a @ Tag { ( string_from `closure` ) }
    : Job j @ Job { \ → v { ( nurl_println ( string_data . a name ) ) } }
    ( panic `after a capture` )
}

@ into_a_name → v {
    : Tag a @ Tag { ( string_from `name` ) }
    : ~ Tag b @ Tag { ( string_from `old` ) }
    = b a
    ( panic `after an assignment` )
}

@ dyn_into_a_literal → v {
    : %Peek d ( dyn Peek @ Tag { ( string_from `dyn literal` ) } )
    : Boxed bx @ Boxed { d }
    ( panic `after a dyn literal` )
}

@ dyn_into_a_sink → v {
    : %Peek d ( dyn Peek @ Tag { ( string_from `dyn sink` ) } )
    ( take_dyn d )
    ( panic `after a dyn sink` )
}

@ dyn_into_a_closure → v {
    : %Peek d ( dyn Peek @ Tag { ( string_from `dyn closure` ) } )
    : Job j @ Job { \ → v { : i _n ( peek d ) } }
    ( panic `after a dyn capture` )
}

@ say ! v PanicInfo r → v {
    ?? r {
        T _ → { ( nurl_println `no panic` ) }
        F e → { ( nurl_println ( string_data . e msg ) ) }
    }
}

@ main → i {
    ( say ( recover \ → v { ( into_a_literal ) } ) )
    ( say ( recover \ → v { ( into_a_sink ) } ) )
    ( say ( recover \ → v { ( into_a_closure ) } ) )
    ( say ( recover \ → v { ( into_a_name ) } ) )
    ( say ( recover \ → v { ( dyn_into_a_literal ) } ) )
    ( say ( recover \ → v { ( dyn_into_a_sink ) } ) )
    ( say ( recover \ → v { ( dyn_into_a_closure ) } ) )
    ^ 0
}
