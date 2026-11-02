// inout_holder_given_a_callee_local_view_then_a_try_exit: agora #379 — an inout holder given a view of a callee local, then a \ try that hands the failure back before the holder is pointed back
// Closed: a \ that hands a failure back records a tryret row; the walk runs a way out's checks there (bck_param_view_check, bck_ret_drop_check, the inout exit check, after the defers) and goes on along the success path (agora #379).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #379: an inout holder given a view of a callee local, then a \ try that hands the failure back before the holder is pointed back
$ `stdlib/core/string.nu`

: | E { Bad }

: W { s v }

@ may i k → !i E {
    ? == k 1 { ^ @ !i E { F Bad } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    = w @ W { ( string_data b ) }
    : i x \ ( may k )
    = w @ W { `literal` }
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `literal` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
