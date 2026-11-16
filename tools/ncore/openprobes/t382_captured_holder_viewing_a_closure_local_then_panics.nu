// map: §2.14 | A2 | rejected | - | agora #382: the recover closure points a captured non-Drop holder at its own local, then panics before the repoint
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
