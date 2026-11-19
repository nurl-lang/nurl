// loop_over_a_container_whose_parent_and_a_sibling_name_their_lenders_in_another_order: AGORA-580 (CodeRabbit on github#1972) — c = ( pick2 r1 r2 0 ) and w = ( pick2 r2 r1 1 ) are one row, lent out of the same two borrows named in another order; `~ x b` over b out of c while w's row grows
// AGORA-580: refused - two borrows lent out of the same storages are siblings whatever order a call named them in
// map: §2.5 | A2 | rejected | - | AGORA-580: lend-parent sets compared in any order
$ `stdlib/core/vec.nu`

@ pick2 ( Vec ( Vec ( Vec i ) ) ) x ( Vec ( Vec ( Vec i ) ) ) y i k → ( Vec ( Vec i ) ) {
    ? == k 0 { ^ ( vec_at [( Vec ( Vec i ) )] x 0 ) } {}
    ^ ( vec_at [( Vec ( Vec i ) )] y 0 )
}

@ main → i {
    : ( Vec ( Vec ( Vec ( Vec i ) ) ) ) o1 ( vec_new [( Vec ( Vec ( Vec i ) ) )] )
    : ( Vec ( Vec ( Vec i ) ) ) vvv ( vec_new [( Vec ( Vec i ) )] )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [( Vec i )] vv v )
    ( vec_push [( Vec ( Vec i ) )] vvv vv )
    ( vec_push [( Vec ( Vec ( Vec i ) ) )] o1 vvv )
    : ( Vec ( Vec ( Vec ( Vec i ) ) ) ) o2 ( vec_new [( Vec ( Vec ( Vec i ) ) )] )
    : ( Vec ( Vec ( Vec i ) ) ) www ( vec_new [( Vec ( Vec i ) )] )
    ( vec_push [( Vec ( Vec i ) )] www ( vec_new [( Vec i )] ) )
    ( vec_push [( Vec ( Vec ( Vec i ) ) )] o2 www )
    : ( Vec ( Vec ( Vec i ) ) ) r1 ( vec_at [( Vec ( Vec ( Vec i ) ) )] o1 0 )
    : ( Vec ( Vec ( Vec i ) ) ) r2 ( vec_at [( Vec ( Vec ( Vec i ) ) )] o2 0 )
    : ( Vec ( Vec i ) ) c ( pick2 r1 r2 0 )
    : ( Vec ( Vec i ) ) w ( pick2 r2 r1 1 )
    : ( Vec i ) b ( vec_at [( Vec i )] c 0 )
    : ~ i n 0
    ~ x b {
        : ~ i j 0
        ~ < j 64 { ( vec_push [i] ( vec_at [( Vec i )] w 0 ) j ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
