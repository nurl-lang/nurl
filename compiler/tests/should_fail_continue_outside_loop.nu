// should_fail_continue_outside_loop.nu — `continue` with no iteration.
//
// The sibling of should_fail_break_outside_loop: outside a `~` body
// there is no next iteration to jump to.
//
// Expected: COMPILE FAIL.

@ main → i {
    continue
    ^ 0
}
