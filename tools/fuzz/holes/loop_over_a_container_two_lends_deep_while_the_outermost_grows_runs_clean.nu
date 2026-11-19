// loop_over_a_container_two_lends_deep_while_the_outermost_grows_runs_clean: AGORA-580 guard — `~ x b` with b two lends deep, while the outermost owner grows: b's buffer stays
// map: §2.5 | A2 | runs-clean | - | AGORA-580 guard: `~ x b` with b two lends deep, while the outermost owner grows: b's buffer stays
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec ( Vec i ) ) ) vvv ( vec_new [( Vec ( Vec i ) )] )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    ( vec_push [( Vec ( Vec i ) )] vvv vv )
    : ( Vec ( Vec i ) ) a ( vec_at [( Vec ( Vec i ) )] vvv 0 )
    : ( Vec i ) b ( vec_at [( Vec i )] a 0 )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Vec ( Vec i ) )] vvv ( vec_new [( Vec i )] ) ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
