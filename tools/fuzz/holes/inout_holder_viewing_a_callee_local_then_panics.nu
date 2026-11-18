// map: §2.14 | A2 | rejected | - | AGORA-382: an inout non-Drop holder given a callee local's view, then a panic under recover before the repoint
// AGORA-382 (closed): refused - an `inout` parameter (or a capture taken by pointer) may not view a value of this frame across a call that may panic
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ fill inout W w i k → v {
    : String b ( string_from `the callee's local string, freed by the unwind, long enough` )
    = w @ W { ( string_data b ) }
    ? > k 2 { ( panic `unwind` ) } {}
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( fill w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
