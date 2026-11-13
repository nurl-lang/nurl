// closure_literal_growing_an_element_of_its_vec_parameter: a closure literal growing `( vec_at x 0 )` of its own `( Vec ( Vec u ) )` parameter, called with the caller's value
// Closed: a closure literal's own parameters are roots of what its body reads, and the irealloc edges of its body are the literal's summary — the closure called with the caller's value ends the caller's view of the element it grows (agora #789, #797).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #789: a closure literal growing an element of its own Vec parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( @ v ( Vec ( Vec u ) ) ) g \ ( Vec ( Vec u ) ) v → v { ( vec_reserve [u] ( vec_at [( Vec u )] v 0 ) 4096 ) }
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( g w )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
