// field_binding_stored_back_leaks: a binding read out of a field took the field's value over when the field was replaced (h196), and storing it back copied it as a borrow: the value it owned was never dropped (`: ( Vec i ) c . s v = . s v ( vec_new ) … = . s v c`).
// Closed: a store of such a binding moves it when its flag says it owns the value, and copies it only while it still borrows.
// main's compiler: LeakSanitizer, detected memory leaks.
// map: §7.6 | A2 | runs-clean | h257 | binding taken from a replaced field stored back as a borrow; owned Vec leaks
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: S { ( Vec i ) v }

@ work inout S s ( Vec i ) c → v { ( vec_push [i] c 5 ) }

@ f inout S s → v {
    : ( Vec i ) c . s v
    = . s v ( vec_new [i] )
    ( work s c )
    = . s v c
}

@ main → i {
    : ~ S s @ S { ( vec_new [i] ) }
    ( f s )
    ( f s )
    ( nurl_println_int ( vec_len [i] . s v ) )
    ^ 0
}
