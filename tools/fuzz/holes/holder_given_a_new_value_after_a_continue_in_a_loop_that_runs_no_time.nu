// holder_given_a_new_value_after_a_continue_in_a_loop_that_runs_no_time: agora #413 — as holder_given_a_new_value_in_a_loop_that_runs_no_time, the new value after a `continue`
// Closed: the loop is left from its head with the dependencies it held there, joined after the verification walk as its borrow sources are (bck_loop, vdhead; agora #413).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #413: as holder_given_a_new_value_in_a_loop_that_runs_no_time, the new value after a `continue`
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 0
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        : ~ String x ( string_from `a scratch string that the loop frees` )
        : ~ i j 0
        ~ < j n {
            = j + j 1
            ? == j 1 { continue } {}
            = x ( string_from `the scratch string given again` )
            ( string_free x )
            = a @ W { `lit` }
        }
    }
    ( nurl_println . a v )
    ^ 0
}
