// vec_element_lent_back_through_ten_forwarders_declared_below: a `: Conn c ( vec_at cs 0 ) ^ c` element binding (per call: lent) handed back as is through ten forwarders declared bottom-up
// Closed: whether a function decides per call that its result is lent is followed through every callee it hands back, and only an answer from a whole walk is kept (a budget of eight answered "owned", and the memo kept that capped answer, agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | runs-clean | - | agora #721: a Vec element lent back through ten forwarders is not taken for the caller's own
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ f10 ( Vec Conn ) cs → Conn { ^ ( f9 cs ) }

@ f9 ( Vec Conn ) cs → Conn { ^ ( f8 cs ) }

@ f8 ( Vec Conn ) cs → Conn { ^ ( f7 cs ) }

@ f7 ( Vec Conn ) cs → Conn { ^ ( f6 cs ) }

@ f6 ( Vec Conn ) cs → Conn { ^ ( f5 cs ) }

@ f5 ( Vec Conn ) cs → Conn { ^ ( f4 cs ) }

@ f4 ( Vec Conn ) cs → Conn { ^ ( f3 cs ) }

@ f3 ( Vec Conn ) cs → Conn { ^ ( f2 cs ) }

@ f2 ( Vec Conn ) cs → Conn { ^ ( f1 cs ) }

@ f1 ( Vec Conn ) cs → Conn { ^ ( f0 cs ) }

@ f0 ( Vec Conn ) cs → Conn { : Conn c ( vec_at [Conn] cs 0 ) ^ c }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `the first connection, a heap name` ) 3 } )
    : Conn a ( f10 cs )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
