// holder_given_a_new_value_in_a_loop_beside_a_vec_scratch: agora #413 — as holder_given_a_new_value_in_a_loop_that_runs_no_time, the scratch owner a ( Vec i ) the loop frees
// Closed: the loop is left from its head with the dependencies it held there, joined after the verification walk as its borrow sources are (bck_loop, vdhead; agora #413).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #413: as holder_given_a_new_value_in_a_loop_that_runs_no_time, the scratch owner a ( Vec i ) the loop frees
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ main → i {
    : ~ W a @ W { `x` }
    : ~ i n 0
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( k a t )
        : ~ ( Vec i ) x ( vec_new [i] )
        : ~ i j 0
        ~ < j n {
            = x ( vec_new [i] )
            ( vec_free [i] x )
            = a @ W { `lit` }
            = j + j 1
        }
    }
    ( nurl_println . a v )
    ^ 0
}
