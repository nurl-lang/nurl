// map: §2.14 | A2 | rejected | - | AGORA-942: an inout parameter views a local across the release of a temporary whose `% Drop` may panic
// AGORA-942 (closed): refused - `w` views `b`, this function's string, while `D`'s temporary is released; its destructor may panic, the unwind frees `b`, and a `recover`ing caller reads `w` (main 3f08626b: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: W { s v }

@ f inout W w i k → v {
    : String b ( string_from `the function's local string, freed by the unwind, long enough` )
    = w @ W { ( string_data b ) }
    : i m . @ D { k } n
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( f w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
