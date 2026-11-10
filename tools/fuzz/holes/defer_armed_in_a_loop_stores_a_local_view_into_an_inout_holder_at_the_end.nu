// defer_armed_in_a_loop_stores_a_local_view_into_an_inout_holder_at_the_end: the loop form in a function that falls off its end.
// Closed: as the `\` form (agora #407).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #407: the loop form in a function that falls off its end
$ `stdlib/core/string.nu`

: W { s v }

@ fill inout W w i k → v {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    : ~ i n 0
    ~ < n k {
        ; { = w @ W { ( string_data b ) } }
        = n + n 1
    }
}

@ main → i {
    : ~ W w @ W { `start` }
    ( fill w 1 )
    ( nurl_println . w v )
    ^ 0
}
