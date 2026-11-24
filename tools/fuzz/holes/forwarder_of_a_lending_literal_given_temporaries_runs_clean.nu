// forwarder_of_a_lending_literal_given_temporaries_runs_clean: a function hands back, as it is, what a literal-building callee makes of temporaries - `^ ( okr @ Val { VS ( string_from … ) } k )`, `^ ( okr @ Val { VI 3 } k )`, `^ ( wrapo ( string_from … ) k )` - beside a scalar it passes on: the caller owns the result and releases it.
// D4c (AGORA-995): the callee lends the temporary whole, so the temporary is the result's; a scalar parameter of safe code is no lend (`scalarp`), a borrow its parameters explain is no borrow of anything else (__via_ret_borrow), and a literal holding nothing a drop releases lends nothing. main 4b154b9d: the option forwarder leaked (LeakSanitizer).
// map: §1 | A2 | runs-clean | - | AGORA-995: a forwarder of a literal-building callee given temporaries owns its result
$ `stdlib/core/string.nu`

: | Val { VS String VI i }
: R { b ok Val v i pos }

@ okr Val v i pos → R { ^ @ R { T v pos } }
@ wrapo String p i n → ? String { ^ @ ?String { T p } }

@ f i k → R { ^ ( okr @ Val { VS ( string_from `a temporary string long enough for the heap` ) } k ) }
@ g i k → R {
    ? == k 0 { ^ ( okr @ Val { VI 3 } k ) } {}
    ^ ( okr @ Val { VS ( string_from `a temporary string long enough for the heap` ) } k )
}
@ h i k → ? String { ^ ( wrapo ( string_from `a temporary string long enough for the heap` ) k ) }

@ main → i {
    : R r ( f 1 )
    : R r2 ( g 1 )
    : R r3 ( g 0 )
    : ? String o ( h 1 )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ - + . r pos . r2 pos 2
}
