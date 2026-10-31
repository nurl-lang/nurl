// returned_option_of_closure: an option of a capturing closure, built in a function and handed back (`: ?( @ i i ) o @ ?( @ i i ) { T f }` … `^ o`): nothing owned the closure's env inside the option, so the frame's drop of `f` freed it on the way out and the caller called through freed memory. SEGV / heap-use-after-free.
// Closed: an option (or result) of a closure owns the closure's env, as a struct field of one does (docs/MEMORY.md §7.4): it is dropped and copied through its twin like `?String` (__opt_payload); a literal stores its own copy (a literal's or a call's env moves in), and a returned literal lends only what it read out of a parameter's storage.
// main's compiler: compiled; the program crashed (SEGV in the caller).
// map: §7.5 | A2 | runs-clean | h281 | option of a capturing closure handed back; the frame freed the env the option carried
$ `stdlib/core/string.nu`

@ mk String a → ?( @ i i ) {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    : ?( @ i i ) o @ ?( @ i i ) { T f }
    ^ o
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ?( @ i i ) o ( mk a )
    ?? o { T g → { ( nurl_println_int ( g 1 ) ) } F → {} }
    ^ 0
}
