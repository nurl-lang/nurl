// closure_field_store_reaches_capture.nu — a closure that stores into a
// field of a captured `: ~` struct changes the binding itself, whatever
// the struct's field count and however deep the path (agora #356). A
// single-field struct used to be captured by value, so the store landed in
// the env's copy and was lost.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: V { s v }
: N { i n }
: H { V w }
: P { String name }
: B { ( Vec i ) items }
: Q { i x i y }

@ main → i {
    : ~ V w @ V { `before` }
    : ( @ v ) f1 \ → v { = . w v `after` }
    ( f1 )
    ( nurl_println . w v )
    : ~ N k @ N { 1 }
    : ( @ v ) f2 \ → v { = . k n 2 }
    ( f2 )
    ( nurl_println_int . k n )
    : ~ H h @ H { @ V { `nested before` } }
    : ( @ v ) f3 \ → v { = . . h w v `nested after` }
    ( f3 )
    ( nurl_println . . h w v )
    : ~ P p @ P { ( string_from `old name` ) }
    : ( @ v ) f4 \ → v { = . p name ( string_from `new name` ) }
    ( f4 )
    ( nurl_println ( string_data . p name ) )
    : ~ B b @ B { ( vec_new [i] ) }
    : ( @ v ) f5 \ → v {
        = . b items ( vec_new [i] )
        ( vec_push [i] . b items 5 )
    }
    ( f5 )
    ( nurl_println_int ( vec_len [i] . b items ) )
    : ~ Q q @ Q { 1 2 }
    : ( @ v ) f6 \ → v { = . q x 10 }
    ( f6 )
    ( nurl_println_int . q x )
    ^ 0
}
