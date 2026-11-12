// inout_param_given_a_vec_field_of_a_borrowed_param_runs_clean: `= dst . x v` with dst an `inout ( Vec i )` and x a by-value struct parameter; the caller grows its binding afterwards
// Closed: a field read of a binding is a lend of its owner: stored into an `inout` place it is copied there, the old value going, as `= io . w s` of a local already was (agora #697).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #697: `= dst . x v` with dst an `inout ( Vec i )` and x a by-value struct parameter; the caller grows its binding afterwards
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v i n }

@ refill inout ( Vec i ) dst App x → v { = dst . x v }

@ main → i {
    : App a @ App { ( vec_new [i] ) 1 }
    ( vec_push [i] . a v 7 )
    : ~ ( Vec i ) c ( vec_new [i] )
    ( refill c a )
    ( vec_push [i] c 1 )
    ^ ( vec_len [i] . a v )
}
