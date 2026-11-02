// vec_holder_given_a_new_value_in_a_loop_that_runs_no_time: agora #413 — a Vec holding a view of a block local, given a new Vec inside a loop that may run no time
// Closed: the loop is left from its head with the dependencies it held there, joined after the verification walk as its borrow sources are (bck_loop, vdhead; agora #413).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #413: a Vec holding a view of a block local, given a new Vec inside a loop that may run no time
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) hs ( vec_new [s] )
    : ~ i n 0
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( vec_push [s] hs ( string_data t ) )
        : ~ String x ( string_from `a scratch string that the loop frees` )
        : ~ i j 0
        ~ < j n {
            = x ( string_from `the scratch string given again` )
            ( string_free x )
            = hs ( vec_new [s] )
            = j + j 1
        }
    }
    ( nurl_println_int ( vec_len [s] hs ) )
    ?? ( vec_get [s] hs 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}
