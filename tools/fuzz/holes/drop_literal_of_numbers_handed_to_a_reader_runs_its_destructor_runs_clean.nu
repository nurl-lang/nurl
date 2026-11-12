// drop_literal_of_numbers_handed_to_a_reader_runs_its_destructor_runs_clean: as drop_literal_handed_to_a_reader_runs_its_destructor_runs_clean, a `% Drop` struct of numbers only: nothing was dropped at all
// Closed: as that probe (agora #760).
// main ae5e524: runs, but no `drop tok` line.
// map: §7.6 | A2 | runs-clean | - | agora #760: a `% Drop` literal of numbers handed to a reader never ran its destructor
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

: Tok { i a i b }

% Drop Tok { @ drop Tok t → v { ( nurl_println `drop tok` ) } }

@ rt Tok t → i { ^ . t a }

@ main → i { ( nurl_println_int ( rt @ Tok { 4 5 } ) ) ^ 0 }
