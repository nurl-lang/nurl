// uncopyable_in_param_named_twice_through_a_bound_forwarder_given_a_temporary: `fwd` hands back `: K2 k ( dup p )  ^ k`, where `dup` returns `@ K2 { p p }` of a `% Drop` value with no copy, and the caller hands `fwd` a temporary
// Guard: the forwarder names its parameter twice as well, a part of it, so the temporary is no whole handover: refused, by nurlc, check.py (call_twice) and the engine (FX_CALL_TWICE) alike (AGORA-995, review of github#2298).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a temporary given to a forwarder of a literal naming its parameter twice is no whole handover
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K2 { D a D b }

@ mkd → D { ^ @ D { ( string_from `a value long enough to own a heap buffer here` ) } }

@ dup D p → K2 { ^ @ K2 { p p } }

@ fwd D p → K2 { : K2 k ( dup p ) ^ k }

@ main → i {
    : K2 k ( fwd ( mkd ) )
    ( nurl_println ( string_data . . k a s ) )
    ^ 0
}
