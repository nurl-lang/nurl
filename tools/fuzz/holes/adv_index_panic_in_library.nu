// map: §2.14 | A2 | rejected | - | adversarial: a library call that may panic (an index past the end) while the inout holder views a local
// AGORA-382 (closed): refused - an `inout` parameter (or a capture taken by pointer) may not view a value of this frame across a call that may panic
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ fill inout W w i k → v {
    : String b ( string_from `the callee's local string, freed by the unwind, long enough` )
    : ( Vec i ) xs ( vec_new [i] )
    = w @ W { ( string_data b ) }
    ( nurl_println_int ( vec_at [i] xs k ) )
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( fill w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
