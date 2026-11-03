// self_recursion_swapping_its_holders: a self-recursion that swaps two holder parameters.
// Closed: a self-recursion that hands one parameter's views on into another holder answers `h>%k` from its own walk, settled as a fixed point.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | Family G review: a self-recursion that swaps two holder parameters
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ rx inout ( Vec s ) d inout ( Vec s ) e ( Vec s ) a i n → v {
    ? > n 0 { ( rx e d a - n 1 ) } { ( vec_extend [s] d a ) }
}

@ main → i {
    : ~ ( Vec s ) w1 ( vec_new [s] )
    : ~ ( Vec s ) w2 ( vec_new [s] )
    : ~ ( Vec s ) t ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( vec_push [s] t ( string_data b ) )
        ( rx w1 w2 t 1 )
    }
    ( nurl_println ( vec_at [s] w2 0 ) )
    ^ 0
}
