// drop_literal_handed_to_a_reader_runs_its_destructor_runs_clean: a struct literal of a type with its own `% Drop` handed to a function that only reads it: its fields were released one by one and its destructor never ran
// Closed: a `% Drop` literal argument goes whole — its destructor, then its drop glue — where its fields went (agora #760).
// main ae5e524: runs, but no `drop` line: the destructor never ran.
// map: §7.6 | A2 | runs-clean | - | agora #760: a `% Drop` literal handed to a reader never ran its destructor
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

@ rd Conn p → i { ^ . p fd }

@ main → i { ( nurl_println_int ( rd @ Conn { ( string_from `literal read only long enough for heap` ) 1 } ) ) ^ 0 }
