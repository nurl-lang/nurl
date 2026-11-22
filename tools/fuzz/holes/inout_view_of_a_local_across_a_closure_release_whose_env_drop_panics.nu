// map: §2.14 | A2 | rejected | - | AGORA-952: an inout parameter views a local across '= c c2', which releases a closure whose environment's `% Drop` may panic
// AGORA-952 (closed): refused - `w` views `s` while the old closure's `D` is released; its drop may panic, the unwind frees `s` and a `recover`ing caller reads `w` (main 3f08626b: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: W { s v }

@ mkf sink D d → ( @ i ) { ^ \ → i { ^ . d n } }

@ f inout W w i k → v {
    : ~ ( @ i ) c ( mkf @ D { k } )
    : ( @ i ) c2 ( mkf @ D { 1 } )
    : String s ( string_from `the function's local string, freed by the unwind, long enough` )
    = w @ W { ( string_data s ) }
    = c c2
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( f w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
