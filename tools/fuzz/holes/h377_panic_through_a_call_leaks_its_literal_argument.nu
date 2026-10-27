// H377: a struct literal handed to a call that panics: the fields the literal made (a String, a closure) are dropped after the call, and a panic unwound past that drop.
// Closed: a literal argument's owned fields are journaled while the call runs, as an argument temporary is (agora #131).
// v0.79.0: accepted; LSan reported the String's buffer and the closure's env leaked.
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: Job { String name ( @ v ) f }

@ run Job j → v { ( nurl_panic `boom` ) }

@ case → v {
    : String a ( string_from `a string long enough to own a heap buffer here` )
    ( run @ Job { ( string_from `another string long enough to own a buffer` ) \ → v { ( nurl_println ( string_data a ) ) } } )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( case ) } )
    ( nurl_println `recovered` )
    ^ 0
}
