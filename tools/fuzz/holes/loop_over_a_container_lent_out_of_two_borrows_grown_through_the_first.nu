// loop_over_a_container_lent_out_of_two_borrows_grown_through_the_first: AGORA-580 (CodeRabbit on github#1972) — `: b ( pick c a 0 )`, pick lending out of either of two borrows of rows of two owners, then `~ x b` while `( vec_at c 0 )` grows: b may be c's row
// AGORA-580: refused - the cursor keeps every lend parent of its container, not only the last a call lent out of
// map: §2.5 | A2 | rejected | - | AGORA-580: a `~` loop over a container a call lent out of two borrows, grown through the first
$ `stdlib/core/vec.nu`

@ pick ( Vec ( Vec i ) ) x ( Vec ( Vec i ) ) y i k → ( Vec i ) {
    ? == k 0 { ^ ( vec_at [( Vec i )] x 0 ) } {}
    ^ ( vec_at [( Vec i )] y 0 )
}

@ main → i {
    : ( Vec ( Vec ( Vec i ) ) ) vvv ( vec_new [( Vec ( Vec i ) )] )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    ( vec_push [( Vec ( Vec i ) )] vvv vv )
    : ( Vec ( Vec ( Vec i ) ) ) www ( vec_new [( Vec ( Vec i ) )] )
    : ( Vec ( Vec i ) ) ww ( vec_new [( Vec i )] )
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 3 )
    ( vec_push [( Vec i )] ww w )
    ( vec_push [( Vec ( Vec i ) )] www ww )
    : ( Vec ( Vec i ) ) c ( vec_at [( Vec ( Vec i ) )] vvv 0 )
    : ( Vec ( Vec i ) ) a ( vec_at [( Vec ( Vec i ) )] www 0 )
    : ( Vec i ) b ( pick c a 0 )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        ~ < j 64 { ( vec_push [i] ( vec_at [( Vec i )] c 0 ) j ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
