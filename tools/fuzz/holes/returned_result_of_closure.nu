// returned_result_of_closure: a result of a capturing closure handed back (`^ @ !( @ i i ) s { T f }`, or a `!( @ i i ) s` binding returned): as h281 for options — nothing owned the env inside the result, the frame dropped `f`'s, and the caller called freed memory. SEGV / heap-use-after-free.
// Closed: a result whose Ok payload is a closure owns its env like an option of one (__opt_payload, split nesting-aware: a closure's spelling has commas of its own), dropped and copied through its twin.
// main's compiler: compiled; the program crashed (SEGV).
// map: §7.5 | A2 | runs-clean | h284 | result of a capturing closure handed back; the frame freed the env the result carried
$ `stdlib/core/string.nu`

@ mk String a b ok → !( @ i i ) s {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    ? ok { ^ @ !( @ i i ) s { T f } } {}
    ^ @ !( @ i i ) s { F `nope` }
}

@ mk2 String a → !( @ i i ) s {
    : ( @ i i ) f \ i x → i { ^ * x ( string_len a ) }
    : !( @ i i ) s r @ !( @ i i ) s { T f }
    ^ r
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    ?? ( mk a T ) { T g → { ( nurl_println_int ( g 1 ) ) } F e → { ( nurl_println e ) } }
    ?? ( mk a F ) { T g → { ( nurl_println_int ( g 1 ) ) } F e → { ( nurl_println e ) } }
    : !( @ i i ) s r ( mk2 a )
    ?? r { T g → { ( nurl_println_int ( g 2 ) ) } F e → { ( nurl_println e ) } }
    ^ 0
}
