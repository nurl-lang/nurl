// loop_over_a_borrow_a_call_forwards_whole_grown_through_its_source: AGORA-580 (CodeRabbit on github#1972) — `: b ( same a )`, same handing its borrowed argument back whole, a a row lent out of an owner; `~ x b` while `( vec_push a … )` grows a: b is a, its buffer moves
// AGORA-580: refused - a forwarded borrow is no part of what it was lent out of, so its own growth ends the cursor
// map: §2.5 | A2 | rejected | - | AGORA-580: a cursor over a borrow a call forwarded whole
$ `stdlib/core/vec.nu`

@ same ( Vec i ) x → ( Vec i ) { ^ x }

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    : ( Vec i ) a ( vec_at [( Vec i )] vv 0 )
    : ( Vec i ) b ( same a )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        ~ < j 64 { ( vec_push [i] a j ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
