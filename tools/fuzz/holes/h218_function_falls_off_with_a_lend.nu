// H218: a function whose body falls off with a value it lends — a parameter (`{ v }`), an element of one (`{ ( vec_at xs 0 ) }`), a field of one, a binding that aliases one — was taken to hand over a value of its own, so every caller released the argument's contents. Written with `^`, the same body was a lend.
// Closed: a body's final value that is a name, a call or a field read returns as `^` returns it (gen_block_ret routes it through gen_ret); the rest — joins, literals, operators — keep the fall-off rules (a join lends as `^` does; a struct literal copies a field it was lent, which is sound too).
// main (before this PR): ASan heap-use-after-free.
$ `stdlib/core/vec.nu`

@ first ( Vec ( Vec i ) ) xs → ( Vec i ) { ( vec_at [( Vec i )] xs 0 ) }

@ main → i {
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    ( vec_push [( Vec i )] outer seed )
    ( vec_push [i] ( first outer ) 1 )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] outer 0 ) ) )
    ^ 0
}
