// map: §2.11 | A2 | rejected | - | agora #864: a closure assigns its borrowed String parameter over a by-pointer capture; run by a callee with a local of its own, the capture borrows a released value
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ once ( @ v String ) f → v {
    : String tmp ( string_from `a string long enough to live on the heap, for sure` )
    ( f tmp )
}

@ borrowed → i {
    : ~ String best ( string_from `first` )
    ( once \ String r → v { = best r } )
    ^ ( string_len best )
}

@ main → i {
    ( nurl_print_int ( borrowed ) ) ( nurl_print `\n` )
    ^ 0
}
