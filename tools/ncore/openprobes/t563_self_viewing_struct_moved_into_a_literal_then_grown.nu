// map: §2.10 | A2 | rejected | - | agora #563: a struct whose field views its other field (`= . o v ( slice_from_vec . o buf )`), moved by `@ P { o 0 }` and grown there
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }
: P { S s i n }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    : ~ P p @ P { o 0 }
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . . p s buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . . p s v 1 ) )
    ^ 0
}
