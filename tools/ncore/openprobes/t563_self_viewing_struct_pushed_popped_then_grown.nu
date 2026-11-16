// map: §2.10 | A2 | rejected | - | agora #563: a struct whose field views its other field, pushed into a Vec, popped, and grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    : ~ ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs o )
    ?? ( vec_pop [S] vs ) {
        T x → {
            : ~ S y x
            : ~ i k 0
            ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
            ( nurl_println_int ( slice_at [i] . y v 1 ) )
        }
        F → {}
    }
    ^ 0
}
