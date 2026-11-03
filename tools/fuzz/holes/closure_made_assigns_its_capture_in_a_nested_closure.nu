// closure_made_assigns_its_capture_in_a_nested_closure: a closure reads its dead capture before calling a nested closure that assigns it, made after the capture's borrow ended.
// Closed: a closure's capture is read where the closure is made unless the body has given it a value of its own in a block still open at the read — not one in a branch, a loop or a nested closure that has closed, nor another field (agora #444).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #444: a closure reads its dead capture before calling a nested closure that assigns it, made after the capture's borrow ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
    }
    : ( @ v ) f \ → v { : ( @ v ) g \ → v { = w @ W { `fresh` } } ( nurl_println . w v ) ( g ) }
    ( f )
    ^ 0
}
