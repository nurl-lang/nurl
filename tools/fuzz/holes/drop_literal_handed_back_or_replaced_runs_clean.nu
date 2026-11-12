// drop_literal_handed_back_or_replaced_runs_clean: `@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }` (Conn with its own `% Drop`) handed a struct literal, the run that makes a fresh one: the literal leaked
// Closed: a literal argument the callee may hand back whole gets the per-call drop word a call's temporary has (`f|`): on the runs the callee's answer says the result is its own, the literal goes after the call, whole (agora #760).
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: a `% Drop` struct literal handed to a function that hands it back or replaces it leaked on the replacing run
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ mk → Conn { ^ @ Conn { ( string_from `a fresh conn name long enough for heap` ) 2 } }

@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }

@ main → i { : Conn a ( f @ Conn { ( string_from `literal conn name long enough for heap` ) 1 } F ) ^ 0 }
