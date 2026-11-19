// loop_over_a_borrow_a_call_forwards_whole_on_one_path_grown_through_it: AGORA-580 (CodeRabbit on github#1972) — `: b ( pickm a c 0 )`, pickm handing `a` back whole on one path and a row of `c` on the other; `~ x b` while `( vec_push a … )` grows a: on the first path b is a
// AGORA-580: refused - a part-lending answer counts for the argument it names, not for every argument of the call
// map: §2.5 | A2 | rejected | - | AGORA-580: a cursor over a call result that forwards one argument whole and lends a part of another
$ `stdlib/core/vec.nu`

@ pickm ( Vec i ) x ( Vec ( Vec i ) ) y i k → ( Vec i ) {
    ? == k 0 { ^ x } {}
    ^ ( vec_at [( Vec i )] y 0 )
}

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    : ( Vec ( Vec ( Vec i ) ) ) vvv ( vec_new [( Vec ( Vec i ) )] )
    ( vec_push [( Vec ( Vec i ) )] vvv ( vec_new [( Vec i )] ) )
    : ( Vec i ) a ( vec_at [( Vec i )] vv 0 )
    : ( Vec ( Vec i ) ) c ( vec_at [( Vec ( Vec i ) )] vvv 0 )
    : ( Vec i ) b ( pickm a c 0 )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        ~ < j 64 { ( vec_push [i] a j ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
