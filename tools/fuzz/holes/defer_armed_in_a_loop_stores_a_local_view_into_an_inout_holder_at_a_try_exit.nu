// defer_armed_in_a_loop_stores_a_local_view_into_an_inout_holder_at_a_try_exit: a defer armed inside a `~` loop body stores a view of a callee local into an inout holder; a `\` hands the failure back (PO b09).
// Closed: at a way out the defers that may run there (armed on some path, or in a loop) are replayed too, on the path where they ran (agora #407).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #407: a defer armed inside a `~` loop body stores a view of a callee local into an inout holder; a `\` hands the failure back (PO b09)
$ `stdlib/core/string.nu`

: W { s v }
: | E { Bad i }

@ may i k → !i E {
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    : ~ i n 0
    ~ < n 1 {
        ; { = w @ W { ( string_data b ) } }
        = n + n 1
    }
    : i x \ ( may k )
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `start` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
