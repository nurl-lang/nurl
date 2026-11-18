// outer_option_and_a_slice_of_its_inner_options_payload_handed_to_one_growing_call: `?? o { T inner → ?? inner { T q → { : sl ( slice_from_vec q )  ( wr o sl ) } … } … }`, wr growing the inner payload through o
// AGORA-842 (CodeRabbit on github#1967): refused - the slice's sources reach o through both payload cursors
// map: §2.10 | A2 | rejected | - | AGORA-842
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ wr inout ? ? ( Vec i ) o ( Slice i ) sl → v {
    ?? o { T inner → { ?? inner { T q → { : ~ i k 0 ~ < k 1000 { ( vec_push [i] q k ) = k + k 1 } } F → {} } } F → {} }
    ( nurl_println_int ( slice_at [i] sl 1 ) )
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ~ ? ? ( Vec i ) o @ ?? ( Vec i ) { T @ ?( Vec i ) { T xs } }
    ?? o {
        T inner → {
            ?? inner {
                T q → {
                    : ( Slice i ) sl ( slice_from_vec [i] q )
                    ( wr o sl )
                }
                F → {}
            }
        }
        F → {}
    }
    ^ 0
}
