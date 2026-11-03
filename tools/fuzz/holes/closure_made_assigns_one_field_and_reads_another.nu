// closure_made_assigns_one_field_and_reads_another: a closure assigns one field of its dead capture and reads another, made after the capture's borrow ended.
// Closed: a closure's capture is read where the closure is made unless the body has given it a value of its own in a block still open at the read — not one in a branch, a loop or a nested closure that has closed, nor another field (agora #444).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #444: a closure assigns one field of its dead capture and reads another, made after the capture's borrow ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }

: W2 { s v s u }

@ main → i {
    : ~ W2 w @ W2 { `literal` `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W2 { ( string_data b ) ( string_data b ) }
    }
    : ( @ v ) f \ → v { = . w v `fresh` ( nurl_println . w u ) }
    ( f )
    ^ 0
}
