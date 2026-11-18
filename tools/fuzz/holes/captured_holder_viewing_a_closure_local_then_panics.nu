// map: §2.14 | A2 | rejected | - | AGORA-382: the recover closure points a captured non-Drop holder at its own local, then panics before the repoint
// AGORA-382 (closed): refused - an `inout` parameter (or a capture taken by pointer) may not view a value of this frame across a call that may panic
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    : ~ i k 3
    : !v PanicInfo r ( recover \ → v {
        : String b ( string_from `the closure's local string, freed by the unwind, long enough` )
        = w @ W { ( string_data b ) }
        ? > k 2 { ( panic `unwind` ) } {}
        = w @ W { `literal again` }
    } )
    ( nurl_println . w v )
    ^ 0
}
