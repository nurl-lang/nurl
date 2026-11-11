// slice_owners_rotated_by_assignment_in_a_loop_runs_clean: three owned slices rotated by assignment in a loop (`= t a  = a b  = b t`), `a` and `b` read after it.
// Closed (agora #634): `= t a` freed t's buffer and took `a` off the list of slice owners — a list of the compiler's, put back as it was where the loop body ended. In the second round `= t a` freed the buffer `b` held, and the function's end freed all three names (attempting double-free). The move is made where it runs now: the source's slot is left empty and stays an owner, of nothing.
// map: §2.2 | A2 | runs-clean | - | agora #634: three owned slices rotated by assignment in a loop; the move was a compile-time list entry, undone at the loop body's end
@ main → i {
    : ~ [i a [i | 1 2]
    : ~ [i b [i | 3 4 5]
    : ~ [i t [i | 6]
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    : ~ i sum 0
    ~ x a { = sum + sum x }
    ~ y b { = sum + sum * 10 y }
    ( nurl_println_int sum )
    ^ 0
}
