// drop_literal_with_a_binding_handed_back_or_replaced_runs_clean: as drop_literal_handed_back_or_replaced_runs_clean, the literal's String a binding moved in
// Closed: a literal argument the callee may hand back whole gets the per-call drop word a call's temporary has (`f|`): on the runs the callee's answer says the result is its own, the literal goes after the call, whole (agora #760).
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: as drop_literal_handed_back_or_replaced_runs_clean, a binding's String moved into the literal
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ mk → Conn { ^ @ Conn { ( string_from `a fresh conn name long enough for heap` ) 2 } }

@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }

@ main → i { : String nm ( string_from `binding name long enough for the heap buffer` ) : Conn a ( f @ Conn { nm 1 } F ) ^ 0 }
