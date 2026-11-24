// uncopyable_in_param_named_twice_through_a_join_of_forwarded_calls_given_a_temporary: `fwd2` hands back `? == k 0 ( dup p ) ( dup q )`, where `dup` returns `@ K2 { p p }` of a `% Drop` value with no copy, and the caller hands it temporaries
// Guard: a join's arms add up: the forwarder names both parameters twice, so a temporary is no whole handover - refused by nurlc, check.py and the engine (FX_CALL_TWICE through the join temporary) (AGORA-995, review of github#2299).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a join of forwarded calls naming a parameter twice is no whole handover
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: K2 { D a D b }

@ mkd → D { ^ @ D { ( string_from `a value long enough to own a heap buffer here` ) } }

@ dup D p → K2 { ^ @ K2 { p p } }

@ fwd2 D p D q i k → K2 { ^ ? == k 0 ( dup p ) ( dup q ) }

@ main → i {
    : K2 k ( fwd2 ( mkd ) ( mkd ) 1 )
    ( nurl_println ( string_data . . k a s ) )
    ^ 0
}
