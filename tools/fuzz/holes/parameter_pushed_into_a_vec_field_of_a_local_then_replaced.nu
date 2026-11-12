// parameter_pushed_into_a_vec_field_of_a_local_then_replaced: `( vec_push . x hs h )` then `( rc_set ( vec_at . x hs 0 ) … )`
// Closed: a local a parameter that may share an Rc is put into by any of these spellings leads to the parameter in the function's summaries: a field store `= . w a h`, a join or a block that may be a literal, a container that is a field path, a kept field path or literal, a callee of the program keeping it into a later argument (agora #786).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #786: a parameter pushed into a local struct's Vec field
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

: K { ( Vec ( Rc ( Vec u ) ) ) hs }

@ ch ( Rc ( Vec u ) ) h → v { : K x @ K { ( vec_new [( Rc ( Vec u ) )] ) } ( vec_push [( Rc ( Vec u ) )] . x hs h ) ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] . x hs 0 ) ( vec_new [u] ) ) }

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
