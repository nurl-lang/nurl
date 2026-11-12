// drop_temporary_handed_back_whole_or_replaced_lent_run_runs_clean: agora #739 — as drop_temporary_handed_back_whole_or_replaced_by_a_fresh_one_runs_clean, the run that hands the temporary back: dropped once
// Closed: as for agora #625 — a lend of a parameter's field or part beside a fresh value answers per call (__hown_mixed); a temporary of a type with a `% Drop` of its own handed back whole on some runs is dropped on the runs the call's answer says its result is its own (agora #739, #457).
// main b64e33a1: accepted, runs clean (the guard).
// map: §7.6 | A2 | runs-clean | - | agora #739: as drop_temporary_handed_back_whole_or_replaced_by_a_fresh_one_runs_clean, the run that hands the temporary back: dropped once
$ `stdlib/core/string.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ mk → Conn { ^ @ Conn { ( string_from `a fresh connection, long enough for the heap` ) 0 } }

@ f Conn p b c → Conn { ? c { ^ p } {} ^ ( mk ) }

@ main → i {
    : Conn a ( f ( mk ) T )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
