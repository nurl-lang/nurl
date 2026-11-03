// closure_made_assigns_its_capture_in_a_loop_that_may_not_run: a closure assigns its dead capture in a loop that may run no time and reads it after, made after the capture's borrow ended.
// Closed: a closure's capture is read where the closure is made unless the body has given it a value of its own in a block still open at the read — not one in a branch, a loop or a nested closure that has closed, nor another field (agora #444).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #444: a closure assigns its dead capture in a loop that may run no time and reads it after, made after the capture's borrow ended
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
    : ( @ v i ) f \ i k → v { : ~ i n 0 ~ < n k { = w @ W { `fresh` } = n + n 1 } ( nurl_println . w v ) }
    ( f 0 )
    ^ 0
}
