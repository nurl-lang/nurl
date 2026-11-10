// copy_of_a_lent_element_handed_back_runs_clean: agora #462 — a copy made of the lent element's field (string_from) handed back: the caller's own
// Control for agora #462.
// map: §2.10 | A2 | runs-clean | - | agora #462: a copy made of the lent element's field (string_from) handed back: the caller's own
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ g ( Vec Conn ) cs → String { : Conn c ( vec_at [Conn] cs 0 ) ^ ( string_from ( string_data . c name ) ) }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `the first connection, a heap name` ) 3 } )
    : String a ( g cs )
    ( vec_clear [Conn] cs )
    ( nurl_println ( string_data a ) )
    ^ 0
}
