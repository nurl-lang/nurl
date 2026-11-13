// fresh_arms_of_a_returned_match_over_a_lending_call_lend_nothing_runs_clean: `^ ?? ( vec_get [String] p 0 ) { T v → ( string_clone v ) F → ( string_from … ) }` in expression form — both arms hand over a value of their own; the caller then hands p to a sink and reads the result.
// Agora #702: the join published its scrutinee's lend key (`vec_get p`) whatever its arms were, so the result was summarised as borrowing p; the statement and bound forms were exact. Every arm a call whose own answer says what it lends: the key is published empty.
// map: §2.8 | A2 | runs-clean | - | agora #702: a returned match whose arms are fresh calls lends nothing of its scrutinee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) v → i { ^ ( vec_len [String] v ) }

@ f ( Vec String ) p → String { ^ ?? ( vec_get [String] p 0 ) { T v → ( string_clone v ) F → ( string_from `none` ) } }

@ main → i {
    : ~ ( Vec String ) p ( vec_new [String] )
    ( vec_push [String] p ( string_from `an element long enough for the heap buffer` ) )
    : String r ( f p )
    : i k ( eat p )
    ( nurl_println ( string_data r ) )
    ^ - k 1
}
