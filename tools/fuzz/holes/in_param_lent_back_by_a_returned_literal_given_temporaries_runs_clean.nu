// in_param_lent_back_by_a_returned_literal_given_temporaries_runs_clean: a literal that lends an `in` parameter whole is handed temporaries - a call's String, a literal of a `% Drop` type with no copy: each is the result's, released once with it.
// D4c (AGORA-995): the lend is whole (lend kind 1, `retlend`), so the caller's temporary IS what the result holds and goes with it: nothing is copied, nothing released twice.
// map: §1 | A2 | runs-clean | - | AGORA-995: temporaries handed to a literal that lends its parameter whole are the result's
$ `stdlib/core/string.nu`

: Conn { String name i fd }
% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }
: H { Conn c i n }
: K { String a i n }

@ wrap Conn p → H { ^ @ H { p 0 } }
@ keep String p i n → K { ^ @ K { p n } }

@ main → i {
    : K k ( keep ( string_from `a temporary string long enough for the heap` ) 7 )
    : H h ( wrap @ Conn { ( string_from `a temporary conn name long enough for the heap` ) 4 } )
    ( nurl_println ( string_data . k a ) )
    ( nurl_println ( string_data . . h c name ) )
    ^ - . k n 7
}
