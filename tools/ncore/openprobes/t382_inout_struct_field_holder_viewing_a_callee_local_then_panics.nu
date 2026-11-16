// map: §2.14 | A2 | rejected | - | agora #382: an inout struct's non-Drop field given a callee local's view, then a panic under recover before the repoint
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }
: O { W w i n }

@ fill inout O o i k → v {
    : String b ( string_from `the callee's local string, freed by the unwind, long enough` )
    = . o w @ W { ( string_data b ) }
    ? > k 2 { ( panic `unwind` ) } {}
    = . o w @ W { `literal again` }
}

@ main → i {
    : ~ O o @ O { @ W { `literal` } 1 }
    : !v PanicInfo r ( recover \ → v { ( fill o 3 ) } )
    ( nurl_println . . o w v )
    ^ 0
}
