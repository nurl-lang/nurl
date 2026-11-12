// rc_temporary_handed_back_or_replaced_runs_clean: `@ g ( Rc String ) p b c → ( Rc String ) { ? c { ^ p } {} ^ ( rc_new … ) }` handed `( rc_new … )`: the temporary share leaked on the replacing run
// Closed: a library handle's result is asked precisely whether it may hold a view (__ty_holds_view_p): its own pointer is its share, so the temporary gets the per-call drop word (agora #760).
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: an Rc temporary handed back or replaced leaked on the replacing run
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ mk → Conn { ^ @ Conn { ( string_from `a fresh conn name long enough for heap` ) 2 } }

@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }

@ g ( Rc String ) p b c → ( Rc String ) { ? c { ^ p } {} ^ ( rc_new [String] ( string_from `fresh rc string long enough for heap` ) ) }

@ main → i { : ( Rc String ) a ( g ( rc_new [String] ( string_from `temporary rc string long enough for heap` ) ) F ) ^ 0 }
