// owned_slice_moved_by_assignment_in_an_arm_runs_clean: an owned slice assigned to another in one arm of a `?` (`? c { = t a } {}`), `t` read after it.
// Closed (agora #634): `= t a` freed t's buffer and took `a` off the list of slice owners for the rest of the arm only; past the arm `a` was an owner again, and the function's end freed the buffer through `t` and through `a` (attempting double-free). The move is made where it runs: `a`'s slot is left empty on the path that moved it.
// map: §2.2 | A2 | runs-clean | - | agora #634: an owned slice moved by assignment in one arm of a `?`, freed through both names
@ main → i {
    : ~ [i a [i | 1 2]
    : ~ [i t [i | 6]
    : ~ i k 0
    ? == k 0 { = t a } {}
    : ~ i sum 0
    ~ x t { = sum + sum x }
    ( nurl_println_int sum )
    ^ 0
}
