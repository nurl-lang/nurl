// lending_arm_of_a_returned_match_over_a_lending_call_still_lends: `^ ?? ( vec_get [String] p 0 ) { T v → ( gid [String] v ) F → ( string_from … ) }` — the T arm's call lends the payload back; the caller hands p to a sink and reads the result.
// Control for agora #702: an arm whose call lends the payload still makes the result a lend of p.
// map: §2.8 | A2 | rejected | - | agora #702: an arm lending the payload keeps the match a lend of the scrutinee's source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) v → i { ^ ( vec_len [String] v ) }

@ gid [A] A x → A { ^ x }

@ f ( Vec String ) p → String { ^ ?? ( vec_get [String] p 0 ) { T v → ( gid [String] v ) F → ( string_from `none` ) } }

@ main → i {
    : ~ ( Vec String ) p ( vec_new [String] )
    ( vec_push [String] p ( string_from `an element long enough for the heap buffer` ) )
    : String r ( f p )
    : i k ( eat p )
    ( nurl_println ( string_data r ) )
    ^ - k 1
}
