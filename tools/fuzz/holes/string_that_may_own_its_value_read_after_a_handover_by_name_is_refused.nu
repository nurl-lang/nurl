// string_that_may_own_its_value_read_after_a_handover_by_name_is_refused: `: ~ String x ? == c 1 ( string_from … ) h0` owns its value on one path only; `= b x` hands it to `b`, and `= d x` reads it after.
// Closed (agora #667): a source whose drop slot owns on some paths only (`dyn`) kept the cursor path — `= b x` made `b` a cursor over `x`, and the walk took it for a copy. `= x …` handed the value to `b` only; `d`, a cursor too, was left reading it after `= b …` freed it (heap-use-after-free). The handover is a move now, as for a source that owns outright (#634): `b` takes the flag `x` has at run time, and the read of `x` before it has a new value is refused.
// map: §2.2 | A2 | rejected | - | agora #667: a handover by name out of a String that may own its value kept the cursor path; a second cursor read it after the first freed it
$ `stdlib/core/string.nu`

@ pick i c String h0 → i {
    : ~ String x ? == c 1 ( string_from `an owned string, long enough for the heap, yes` ) h0
    : ~ String b ( string_from `the b string, long enough for the heap, yes yes` )
    : ~ String d ( string_from `the d string, long enough for the heap, yes yes` )
    = b x
    = d x
    = x ( string_from `a new string, long enough for the heap, yes yes` )
    = b ( string_from `a newer string, long enough for the heap, yes yes` )
    ( nurl_println ( string_data d ) ) ( nurl_println ( string_data b ) ) ( nurl_println ( string_data x ) )
    ^ 0
}

@ main → i { : String h ( string_from `the lender string, long enough for the heap, yes` ) ( pick 1 h ) ( pick 0 h ) ^ 0 }
