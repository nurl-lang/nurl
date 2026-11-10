// self_view_kept_by_a_loop_break_before_a_repoint_then_the_field_grown_is_refused: a callee makes the self-view in a loop it may leave by a `break` before the repoint, then the caller grows `. p s`
// Closed: a callee's answer says which fields of a parameter it leaves the parameter viewing (`h>.rel`, g_fn_vkeeps), and the caller ties the argument to those fields of itself (agora #584).
// main a346fcba: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: a callee makes the self-view in a loop it may leave by a `break` before the repoint, then the caller grows `. p s`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → v {
    : ~ i i 0
    ~ < i 2 {
        = . p w @ W { ( string_data . p s ) }
        ? == i 0 { break } {}
        = p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
        = i + i 1
    }
}

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( h p )
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
