// in_param_beside_an_own_field_in_a_returned_literal_taken_over_runs_clean: a literal handed back holds an `in` parameter whole beside a value of its own - bare, nested in another literal, with a `% Drop` type that has no copy: the caller hands its argument in, and the result releases each field once.
// D4c (AGORA-995): a struct is dropped whole, so a lent field beside an own one has no lend: the literal takes the parameter over, as before D4c. Nested in a literal that lends, the lent field is copied (agora #635).
// map: §7.6 | A2 | runs-clean | - | AGORA-995: an `in` parameter beside a field of the literal's own is taken over
$ `stdlib/core/string.nu`

: K2 { String a String b }
: KK2 { K2 k i m }
: Conn { String name i fd }
% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }
: H { Conn c String t }

@ bare String p → K2 { ^ @ K2 { p ( string_from `a fresh string long enough for the heap here` ) } }
@ nested String p → KK2 { ^ @ KK2 { @ K2 { p ( string_from `a fresh string long enough for the heap here` ) } 1 } }
@ nocopy Conn p → H { ^ @ H { p ( string_from `a fresh string long enough for the heap buffer` ) } }

@ main → i {
    : K2 k ( bare ( string_from `a string long enough for the heap buffer here` ) )
    : String s ( string_from `a string long enough for the heap buffer here` )
    : KK2 kk ( nested s )
    : H h ( nocopy @ Conn { ( string_from `a conn name long enough for the heap buffer` ) 3 } )
    ( nurl_println ( string_data . k a ) )
    ( nurl_println ( string_data . . kk k b ) )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data . . h c name ) )
    ^ 0
}
