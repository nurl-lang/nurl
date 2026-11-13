// literal_of_a_parameter_pushed_into_a_local_vec_then_replaced: `( vec_push ws @ W { h } )` then `( setw ( vec_at ws 0 ) )`
// Closed: a local a parameter that may share an Rc is put into by any of these spellings leads to the parameter in the function's summaries: a field store `= . w a h`, a join or a block that may be a literal, a container that is a field path, a kept field path or literal, a callee of the program keeping it into a later argument (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: a literal of a parameter pushed into a local Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

: W { ( Rc ( Vec u ) ) a }

@ setw W w → v { ( rc_set [( Vec u )] . w a ( vec_new [u] ) ) }

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec W ) ws ( vec_new [W] ) ( vec_push [W] ws @ W { h } ) ( setw ( vec_at [W] ws 0 ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
