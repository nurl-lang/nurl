// diag_defer_break.nu — `break` inside a `;` defer body.
//
// The defer chain runs DURING return, after the loop has already exited.
// A `break` there branched into the loop exit block the chain had just
// come from and re-entered the chain from the top: a program that
// compiled, exited 0 and printed forever. `^` was rejected here for
// exactly this reason; `break` and `continue` were not.

@ main → i {
    : ~ i k 0
    ~ < k 3 {
        ; { break }
        = k + k 1
    }
    ^ 0
}
