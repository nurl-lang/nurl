// option_that_may_own_its_value_read_after_a_handover_by_name_is_refused: `: ~ ?String a ? == c 1 @ ?String { T … } h0` owns its value on one path only; `= t a`, `= t …`, then `a` is read.
// Closed (agora #667): the generated code moves the flag of an option handed over by name, but the walk took it for a copy of a borrow, so `a` stayed readable after `= t …` released the value it took (heap-use-after-free). The walk is told it is a move now (amv_open), for a value of any type: the read of `a` before it has a new value is refused.
// map: §2.2 | A2 | rejected | - | agora #667: a handover by name out of an option that may own its value; the walk took the move the generated code makes for a copy
$ `stdlib/core/string.nu`

@ pick i c ? String h0 → i {
    : ~ ? String a ? == c 1 @ ?String { T ( string_from `an owned option string, long enough for the heap` ) } h0
    : ~ ? String t @ ?String { T ( string_from `the t option string, long enough for the heap yes` ) }
    = t a
    = t @ ?String { T ( string_from `a new t option string, long enough for the heap` ) }
    ?? a { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}

@ main → i { : ?String h @ ?String { T ( string_from `the lender option string, long enough heap` ) } ( pick 1 h ) ( pick 0 h ) ^ 0 }
