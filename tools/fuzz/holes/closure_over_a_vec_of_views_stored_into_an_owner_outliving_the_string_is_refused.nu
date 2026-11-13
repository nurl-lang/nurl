// closure_over_a_vec_of_views_stored_into_an_owner_outliving_the_string_is_refused: a closure over a ( Vec s ) holding a view of a block's String, stored in a struct pushed into an outer Vec, run after the block
// Closed: agora #469, an owner the closure is stored into adopts the copy of the Vec, and the views it holds: the owner depends on the String.
// main ff75baea: accepted; ASan reported heap-use-after-free on 2 runs in 2.
// map: §2.2 | A2 | rejected | - | agora #469: a closure over a Vec of views stored into an owner that outlives the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( @ v ) f i n }

@ main → i {
    : ~ ( Vec H ) hs ( vec_new [H] )
    {
        : String m ( string_from `a heap string long enough to be on the heap for sure` )
        : ~ ( Vec s ) c ( vec_new [s] )
        ( vec_push [s] c ( string_data m ) )
        ( vec_push [H] hs @ H { \ → v { ( nurl_println ( vec_at [s] c 0 ) ) } 0 } )
    }
    ?? ( vec_get [H] hs 0 ) { T h → { : ( @ v ) g . h f ( g ) } F → {} }
    ^ 0
}
