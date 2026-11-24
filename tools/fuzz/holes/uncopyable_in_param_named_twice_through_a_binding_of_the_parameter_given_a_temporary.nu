// uncopyable_in_param_named_twice_through_a_binding_of_the_parameter_given_a_temporary: `fwd3` binds `: D q p` and hands back `( dup q )`, where `dup` returns `@ K2 { p p }` of a `% Drop` value with no copy, and the caller hands it a temporary
// Guard: the argument is a binding of the parameter whole, so the forwarder names the parameter twice - refused by nurlc, check.py (the argument's alias) and the engine (AGORA-995, review of github#2299).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a forwarder through a binding of its parameter naming it twice is no whole handover
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K2 { D a D b }

@ mkd → D { ^ @ D { ( string_from `a value long enough to own a heap buffer here` ) } }

@ dup D p → K2 { ^ @ K2 { p p } }

@ fwd3 D p → K2 { : D q p
    ^ ( dup q ) }

@ main → i {
    : K2 k ( fwd3 ( mkd ) )
    ( nurl_println ( string_data . . k a s ) )
    ^ 0
}
