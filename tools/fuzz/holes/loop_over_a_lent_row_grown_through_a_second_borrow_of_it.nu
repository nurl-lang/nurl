// map: §2.5 | A2 | rejected | - | AGORA-580: `~ x b` over `b`, `( vec_at vv 0 )`, grown through `c`, a second `( vec_at vv 0 )` borrow, in the body
// AGORA-580: refused - the loop's cursor over a container lent out of an element is a view of those elements, which the growth ends (main 5c4740fa: accepted, heap-use-after-free)
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
        ~ < j 64 { ( vec_push [i] c j ) = j + j 1 }
        = n + n x
    }
    ( nurl_println_int n )
    ^ 0
}
