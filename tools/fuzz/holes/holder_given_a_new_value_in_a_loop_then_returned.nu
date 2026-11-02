// holder_given_a_new_value_in_a_loop_then_returned: agora #413 — a holder viewing a local, given a new value in a loop that may run no time, returned
// Closed: the loop is left from its head with the dependencies it held there, joined after the verification walk as its borrow sources are (bck_loop, vdhead; agora #413).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #413: a holder viewing a local, given a new value in a loop that may run no time, returned
$ `stdlib/core/string.nu`

: W { s v }

@ k inout W x String q → v { = x @ W { ( string_data q ) } }

@ mk i n → W {
    : ~ W a @ W { `x` }
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
    ^ a
}

@ main → i {
    : W a ( mk 0 )
    ( nurl_println . a v )
    ^ 0
}
