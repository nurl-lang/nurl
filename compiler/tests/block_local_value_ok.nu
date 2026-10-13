// What a block hands out through its own binding is what that binding
// holds (h216): a copy, a scalar read from a borrow and a fresh value
// owe nothing to `outer`, which may then be released.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] outer seed )
    : ( Vec i ) copy { : ( Vec i ) t ( vec_clone [i] ( vec_at [( Vec i )] outer 0 ) ) t }
    : i n { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) ( vec_len [i] t ) }
    : ( Vec i ) fresh { : ( Vec i ) t ( vec_new [i] ) ( vec_push [i] t 3 ) ( vec_push [i] t 4 ) t }
    ( vec_free [( Vec i )] outer )
    ( nurl_println_int ( vec_len [i] copy ) )
    ( nurl_println_int n )
    ( nurl_println_int ( vec_len [i] fresh ) )
    ^ 0
}
