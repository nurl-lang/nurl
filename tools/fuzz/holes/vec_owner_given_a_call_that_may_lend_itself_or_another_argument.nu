// vec_owner_given_a_call_that_may_lend_itself_or_another_argument: agora #419 — `= o ( pick o other k )` with ( Vec i ) owners, both runs
// Closed: the hand-over keeps the old value and its flag only when the result IS that value, compared by handle key at run time; another argument's value is lent, and the old value goes by its flag (agora #419).
// main: accepted; AddressSanitizer reported heap-use-after-free on the run that hands back the other argument's value.
// map: §7.6 | A2 | runs-clean | - | agora #419: `= o ( pick o other k )` with ( Vec i ) owners, both runs
$ `stdlib/core/vec.nu`

@ pick ( Vec i ) a ( Vec i ) b i k → ( Vec i ) { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : ( Vec i ) other ( vec_new [i] )
    : ~ ( Vec i ) o ( vec_new [i] )
    = o ( pick o other k )
    ( nurl_println_int ( vec_len [i] o ) )
    ( nurl_println_int ( vec_len [i] other ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
