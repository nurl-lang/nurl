// arc_temporary_handed_back_or_replaced_runs_clean: as rc_temporary_handed_back_or_replaced_runs_clean, an Arc
// Closed: a library handle's result is asked precisely whether it may hold a view (__ty_holds_view_p): its own pointer is its share, so the temporary gets the per-call drop word (agora #760).
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: an Arc temporary handed back or replaced leaked
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

@ g ( Arc String ) p b c → ( Arc String ) { ? c { ^ p } {} ^ ( arc_new [String] ( string_from `fresh arc string long enough for heap` ) ) }

@ main → i { : ( Arc String ) a ( g ( arc_new [String] ( string_from `temporary arc string long enough for heap` ) ) F ) : ( Arc String ) b ( g ( arc_new [String] ( string_from `temporary arc string long enough for heap` ) ) T ) ^ 0 }
