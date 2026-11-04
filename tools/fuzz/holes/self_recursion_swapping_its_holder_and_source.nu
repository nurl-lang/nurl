// self_recursion_swapping_its_holder_and_source: a self-recursion over vec_extend that swaps its holder and source parameters.
// Closed: a self-recursion that hands one parameter's views on into another holder answers `h>%k` from its own walk, settled as a fixed point.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | Family G review: a self-recursion over vec_extend that swaps its holder and source parameters
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ rx inout ( Vec s ) d ( Vec s ) a ( Vec s ) c i n → v {
    ? > n 0 { ( rx d c a - n 1 ) } { ( vec_extend [s] d a ) }
}

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( Vec s ) lit ( vec_new [s] )
    ( vec_push [s] lit `literal` )
    : ~ ( Vec s ) t ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( vec_push [s] t ( string_data b ) )
        ( rx ws lit t 1 )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
