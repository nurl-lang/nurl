// drop_option_literal_handed_to_a_reader_runs_its_destructor_runs_clean: an option literal over a `% Drop` literal handed to a reader: the payload's destructor never ran
// Closed: as drop_option_literal_handed_back_or_replaced_runs_clean (agora #760).
// main ae5e524: runs, but no `drop` line.
// map: §7.6 | A2 | runs-clean | - | agora #760: an option literal over a `% Drop` literal handed to a reader never ran the payload's destructor
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

@ ro ? Conn p → i { ^ ?? p { T c → . c fd F → 0 } }

@ main → i { ( nurl_println_int ( ro @ ?Conn { T @ Conn { ( string_from `optional literal read only long enough heap` ) 1 } } ) ) ^ 0 }
