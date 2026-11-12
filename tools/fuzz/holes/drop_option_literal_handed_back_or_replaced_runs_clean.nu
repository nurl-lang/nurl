// drop_option_literal_handed_back_or_replaced_runs_clean: `@ g ?Conn p b c → ?Conn { ? c { ^ p } {} ^ @ ?Conn { T ( mk ) } }` handed an option literal over a `% Drop` literal: leaked on the replacing run
// Closed: an option literal over a value with a destructor goes whole, through its twin's drop, as a call's option temporary does (agora #760).
// main ae5e524: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #760: an option literal over a `% Drop` literal handed back or replaced leaked
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

@ g ? Conn p b c → ?Conn { ? c { ^ p } {} ^ @ ?Conn { T ( mk ) } }

@ main → i { : ?Conn a ( g @ ?Conn { T @ Conn { ( string_from `optional literal conn long enough heap` ) 1 } } F ) : ?Conn b ( g @ ?Conn { T @ Conn { ( string_from `optional literal conn two long enough heap` ) 1 } } T ) ^ 0 }
