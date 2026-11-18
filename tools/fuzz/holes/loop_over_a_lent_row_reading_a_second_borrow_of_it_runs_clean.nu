// loop_over_a_lent_row_reading_a_second_borrow_of_it_runs_clean: as loop_over_a_lent_row_grown_through_a_second_borrow_of_it, c only read
// AGORA-580 guard: accepted - reading moves nothing
// map: §2.5 | A2 | runs-clean | - | AGORA-580
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    : ( Vec i ) b ( vec_at [( Vec i )] vv 0 )
    : ( Vec i ) c ( vec_at [( Vec i )] vv 0 )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        = n + n ( vec_len [i] c )
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
