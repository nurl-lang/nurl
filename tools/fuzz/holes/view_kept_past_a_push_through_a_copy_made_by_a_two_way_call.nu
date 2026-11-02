// view_kept_past_a_push_through_a_copy_made_by_a_two_way_call: agora #440 — `: ~ String o ( pick x other 1 )`, pick lending either argument, grown while a view of other lives
// Closed: a String or Vec borrowed from bindings of its own type is a copy of one of their handles whole (`cborrow`): a buffer moved through it ends their views at that path (bck_view_end_via, agora #440).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #440: `: ~ String o ( pick x other 1 )`, pick lending either argument, grown while a view of other lives
$ `stdlib/core/string.nu`

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : String x ( string_from `an x string, long enough for the heap` )
    : String other ( string_from `the other string, short` )
    : s v ( string_data other )
    : ~ String o ( pick x other 1 )
    ( string_push_str o ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println v )
    ^ 0
}
