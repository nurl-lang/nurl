// closure_made_reads_its_capture_on_an_early_return_path: a closure reads its dead capture on an early-return path before the assignment on the other, made after the capture's borrow ended.
// Closed: a closure's capture is read where the closure is made unless the body has given it a value of its own in a block still open at the read — not one in a branch, a loop or a nested closure that has closed, nor another field (agora #444).
// main's compiler: rejected it already — the read comes first in the text, which #358 follows; kept beside the path-scoped rule as its control.
// map: §2.4 | A2 | rejected | - | agora #444: a closure reads its dead capture on an early-return path before the assignment on the other, made after the capture's borrow ended
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
    : ( @ v b ) f \ b k → v { ? k { ( nurl_println . w v ) ^ } {} = w @ W { `fresh` } }
    ( f T )
    ^ 0
}
