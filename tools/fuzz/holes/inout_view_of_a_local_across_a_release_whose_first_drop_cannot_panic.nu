// map: §2.14 | A2 | rejected | - | AGORA-942: an inout parameter views a local across a release that runs two destructors, the first of which cannot panic and the second may
// AGORA-942 (closed): refused - releasing `t` runs `A`'s drop, which cannot panic, then `B`'s, which may; the report parked behind `A`'s must not hide the one behind `B`'s (CodeRabbit on github#2183; #2183's first head: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: A { i n }

% Drop A { @ drop A c → v { ( nurl_println `a` ) } }

: B { i n }

% Drop B { @ drop B c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: P { A a B b }

: W { s v }

@ f inout W w i k → v {
    : String s ( string_from `the function's local string, freed by the unwind, long enough` )
    = w @ W { ( string_data s ) }
    { : P t @ P { @ A { 1 } @ B { k } } }
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( f w 3 ) } )
    ( nurl_println . w v )
    ^ 0
}
