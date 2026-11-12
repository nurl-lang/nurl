// drop_literal_replaced_in_a_loop_runs_clean: as drop_literal_handed_back_or_replaced_runs_clean, in a loop, replaced on some rounds and handed back on the last
// Closed: a literal argument the callee may hand back whole gets the per-call drop word a call's temporary has (`f|`): on the runs the callee's answer says the result is its own, the literal goes after the call, whole (agora #760). Each `drop` line is printed once per value.
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: a `% Drop` literal handed back or replaced in a loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/box.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ mk → Conn { ^ @ Conn { ( string_from `a fresh conn name long enough for heap` ) 2 } }

@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }

@ main → i { : ~ i k 0 ~ < k 3 { : Conn a ( f @ Conn { ( string_from `loop literal conn long enough for heap` ) k } ? > k 1 T F ) = k + k 1 } ^ 0 }
