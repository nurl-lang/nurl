// inout_holder_given_a_new_value_in_a_loop_at_the_exit: agora #413 — an inout holder viewing a callee local, given a new value in a loop that may run no time, at the function's exit
// Closed: the loop is left from its head with the dependencies it held there, joined after the verification walk as its borrow sources are (bck_loop, vdhead; agora #413).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #413: an inout holder viewing a callee local, given a new value in a loop that may run no time, at the function's exit
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ fill inout W a i n → v {
    : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
    ( k a t )
    : ~ String x ( string_from `a scratch string that the loop frees` )
    : ~ i j 0
    ~ < j n {
        = x ( string_from `the scratch string given again` )
        ( string_free x )
        = a @ W { `lit` }
        = j + j 1
    }
}

@ main → i {
    : ~ W a @ W { `x` }
    ( fill a 0 )
    ( nurl_println . a v )
    ^ 0
}
