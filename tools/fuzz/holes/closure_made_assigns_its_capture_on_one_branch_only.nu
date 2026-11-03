// closure_made_assigns_its_capture_on_one_branch_only: a closure assigns its dead capture in one branch and reads it after the branch, made after the capture's borrow ended.
// Closed: a closure's capture is read where the closure is made unless the body has given it a value of its own in a block still open at the read — not one in a branch, a loop or a nested closure that has closed, nor another field (agora #444).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #444: a closure assigns its dead capture in one branch and reads it after the branch, made after the capture's borrow ended
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
    : ( @ v b ) f \ b k → v { ? k { = w @ W { `fresh` } } {} ( nurl_println . w v ) }
    ( f F )
    ^ 0
}
