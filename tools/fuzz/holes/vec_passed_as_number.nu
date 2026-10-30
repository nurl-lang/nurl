// vec_passed_as_number: a struct passed where a parameter is a number — in safe code a `( Vec u )` into an `i` parameter — compiled to an ill-typed call: the callee read the Vec's control-block address as the number. The reverse (a number where a struct is declared, h188) was rejected; this direction was not (onnx's parse_dump checksummed a weight block's control block, and its bytes past it, that way).
// Closed: a struct passed by value where the parameter is an integer or a float is rejected (an enum keeps its tag conversion).
// main's compiler: the "length" is an address — a loop that long runs off the end of the buffer.
// map: §6.2 | B | rejected | h269 | Vec handle passed where an integer parameter is expected
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

@ sum_first ( Vec u ) v i n → i {
    : ~ i s 0
    : ~ i k 0
    ~ < k n {
        = s + s ?? ( vec_get [u] v k ) { T x → # i x F _ → 0 }
        = k + k 1
    }
    ^ s
}

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    ( vec_push [u] v # u 2 )
    ( nurl_println_int ( sum_first v v ) )
    ^ 0
}
