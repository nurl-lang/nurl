// closure_read_from_a_vec_in_an_unsafe_function_runs_clean: in an `unsafe`
// function, `: f ( vec_at [( @ i i )] fs 0 )` then `( vec_free fs )` then `( f 10 )`.
// The walk checks no views there, so a lent read would run on the freed env:
// since agora #552 a closure read is lent in safe code only, and here it stays
// a copy.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a Vec in an unsafe function, the Vec then freed: unsafe code gets a copy, the walk checks no views there (agora #552).
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk i n → ( @ u64 u64 ) {
    : ~ String s ( string_new )
    : ~ i j 0
    ~ < j n { ( string_push_char s 97 ) = j + j 1 }
    ^ \ u64 x → u64 { ^ + x # u64 ( string_len s ) }
}

@ mkv i n → ( @ u64 u64 ) {
    : ( Vec u64 ) t ( vec_new [u64] )
    : ~ i j 0
    ~ < j n { ( vec_push [u64] t # u64 j ) = j + j 1 }
    ^ \ u64 x → u64 { ^ + x # u64 * 100 ( vec_len [u64] t ) }
}

@ fill → ( Vec ( @ u64 u64 ) ) {
    : ( Vec ( @ u64 u64 ) ) fs ( vec_new [( @ u64 u64 )] )
    ( vec_push [( @ u64 u64 )] fs ( mk 3 ) )
    ( vec_push [( @ u64 u64 )] fs ( mk 5 ) )
    ( vec_push [( @ u64 u64 )] fs ( mkv 4 ) )
    ^ fs
}

@ pr u64 x → v { ( nurl_println_int # i x ) }

@ mki i n → ( @ i i ) {
    : ~ String s ( string_new )
    : ~ i j 0
    ~ < j n { ( string_push_char s 97 ) = j + j 1 }
    ^ \ i x → i { ^ + x ( string_len s ) }
}

@ filli → ( Vec ( @ i i ) ) {
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs ( mki 3 ) )
    ( vec_push [( @ i i )] fs ( mki 5 ) )
    ( vec_push [( @ i i )] fs ( mki 8 ) )
    ^ fs
}

@ mkw i n → ( @ v ) {
    : ~ String s ( string_new )
    : ~ i j 0
    ~ < j n { ( string_push_char s 97 ) = j + j 1 }
    ^ \ → v { ( nurl_println_int ( string_len s ) ) }
}

@ fillw → ( Vec ( @ v ) ) {
    : ( Vec ( @ v ) ) ws ( vec_new [( @ v )] )
    ( vec_push [( @ v )] ws ( mkw 3 ) )
    ( vec_push [( @ v )] ws ( mkw 5 ) )
    ^ ws
}

unsafe @ work → u64 {
    : ( Vec ( @ u64 u64 ) ) fs ( fill )
    : ( @ u64 u64 ) f ( vec_at [( @ u64 u64 )] fs 1 )
    ( vec_clear [( @ u64 u64 )] fs )
    ^ ( f 10 )
}

@ main → i {
    ( pr ( work ) )
    ^ 0
}
