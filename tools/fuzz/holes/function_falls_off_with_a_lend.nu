// function_falls_off_with_a_lend: a function whose body falls off with a value it lends — a parameter (`{ v }`), an element of one (`{ ( vec_at xs 0 ) }`), a field of one, a binding that aliases one — was taken to hand over a value of its own, so every caller released the argument's contents. Written with `^`, the same body was a lend.
// Closed: a body's final value that is a name, a call, a field read or a literal `@ T { … }` returns as `^` returns it (gen_block_ret routes it through gen_ret); joins already lent as `^` does, and operators hand back scalars.
// main (before this PR): ASan heap-use-after-free.
// map: FnOK | A1 | runs-clean | h218 | fn tail returns vec_at lend of param but treated as owned by caller
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
