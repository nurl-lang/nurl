// defer_armed_in_an_arm_stores_a_local_view_into_an_inout_holder_at_a_try_exit: the same with the defer armed in a `?` arm (PO b10).
// Closed: as the loop form (agora #407).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #407: the same with the defer armed in a `?` arm (PO b10)
$ `stdlib/core/string.nu`

: W { s v }
: | E { Bad i }

@ may i k → !i E {
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    ? > k 0 { ; { = w @ W { ( string_data b ) } } } {}
    : i x \ ( may k )
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `start` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
