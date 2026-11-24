// local_handed_back_whole_through_a_lending_call_runs_clean: a function hands back what a call lends out of its own local whole - `^ ( id s )`, `^ ( wrap s )`, `: K k ( wrap s ) ^ k`, and the same with a `% Drop` type that has no copy.
// D4c (AGORA-995): the local's value IS the result on the runs the call lent, so it is handed over - its flag cleared, nothing copied. Before it `^ ( id s )` copied the String and released the local, and a value with no copy was refused (agora #187).
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a local the call hands back whole is handed over, not copied or refused
$ `stdlib/core/string.nu`

: K { String a i n }
: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: H { Conn c i n }

@ id String p → String { ^ p }

@ wrap String p → K { ^ @ K { p 0 } }

@ hold Conn p → H { ^ @ H { p 0 } }

@ idc Conn p → Conn { ^ p }

@ mk1 → String { : String s ( string_from `a local string long enough for the heap buffer` ) ^ ( id s ) }

@ mk2 → K { : String s ( string_from `a local string long enough for the heap buffer` ) ^ ( wrap s ) }

@ mk3 → K { : String s ( string_from `a local string long enough for the heap buffer` ) : K k ( wrap s ) ^ k }

@ mk4 → H { : Conn c @ Conn { ( string_from `a local conn name long enough for the heap` ) 3 } ^ ( hold c ) }

@ mk5 → Conn { : Conn c @ Conn { ( string_from `another local conn name long enough for it` ) 5 } ^ ( idc c ) }

@ main → i {
    : String r ( mk1 )
    : K k2 ( mk2 )
    : K k3 ( mk3 )
    : H h ( mk4 )
    : Conn c ( mk5 )
    ( nurl_println ( string_data r ) )
    ( nurl_println ( string_data . k2 a ) )
    ( nurl_println ( string_data . k3 a ) )
    ( nurl_println ( string_data . . h c name ) )
    ( nurl_println ( string_data . c name ) )
    ^ 0
}
