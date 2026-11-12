// rc_string_payload_grown_by_a_helper_past_a_view_through_a_clone: a `( Rc ( Vec String ) )` handed to a helper that pushes to the payload's first String, while that String's bytes are viewed through `r2`
// Closed: the same-Rc rule asks the irealloc summary (agora #601 item 2).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #601: an Rc of Strings handed to a helper that grows one of them, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ grow ( Rc String ) a → v {
    : ~ i k 0
    ~ < k 200 { ( string_push_str ( rc_get [String] a ) `more and more text to move the buffer ` ) = k + k 1 }
}

@ main → i {
    : ( Rc String ) r ( rc_new [String] ( string_from `a heap string that is long enough to be on the heap for sure` ) )
    : ( Rc String ) r2 ( rc_clone [String] r )
    : s d ( string_data ( rc_get [String] r2 ) )
    ( grow r )
    ( nurl_println d )
    ^ 0
}
