// inout_drop_struct_taken_on_some_paths_runs_clean: a function hands its `inout` parameter of a `% Drop` struct to a `sink` on one path only; the other path returns, and both run.
// Closed (agora #849): the function owns the caller's value where it is summarised as consuming it, and drops it on the way out wherever it was not handed on, as a `sink` is dropped; `= p` drops the old value only while the slot holds one.
// main 1a04cbd6: the caller's value leaks on the path that takes nothing (88 bytes definitely lost; its destructor never runs).
// map: §7.6 | A2 | runs-clean | - | agora #849: an inout % Drop struct handed to a sink on some paths only
$ `stdlib/core/string.nu`

: D { String name i n }

% Drop ( D ) { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eat sink D d → i { ^ . d n }

@ g3 inout D p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

@ g6 inout D p i c → i {
    ? == c 1 { ( eat p ) } {}
    = p @ D { ( string_from `a replaced name long enough to own a heap buffer` ) + 60 c }
    ^ 0
}

@ run i c → v {
    : ~ D w @ D { ( string_from `a name long enough to own a heap buffer` ) + 10 c }
    ( nurl_println_int ( g3 w c ) )
    : ~ D w6 @ D { ( string_from `a name long enough to own a heap buffer` ) + 50 c }
    ( nurl_println_int ( g6 w6 c ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
