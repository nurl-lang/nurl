// uncopyable_in_param_named_twice_in_a_returned_literal_given_a_temporary: `dup` hands back `@ K2 { p p }` of a `% Drop` value with no copy, and the caller hands it a temporary
// Guard: a parameter named twice is a part of the argument, not the argument whole, so the temporary is not the result's, and the part cannot be copied out of it: refused, by nurlc, check.py and the engine alike (AGORA-995, review of github#2280).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a temporary given to a literal naming its parameter twice is no whole handover
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K2 { D a D b }

@ mkd → D { ^ @ D { ( string_from `a value long enough to own a heap buffer here` ) } }

@ dup D p → K2 { ^ @ K2 { p p } }

@ main → i {
    : K2 k ( dup ( mkd ) )
    ( nurl_println ( string_data . . k a s ) )
    ^ 0
}
