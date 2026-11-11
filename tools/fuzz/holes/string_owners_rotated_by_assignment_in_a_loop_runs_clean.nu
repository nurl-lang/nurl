// string_owners_rotated_by_assignment_in_a_loop_runs_clean: three String owners rotated by assignment in a loop (`= t a  = a b  = b t`), `a` and `b` read after it.
// Closed (agora #634): `= t a` only made `t` a cursor over `a`, and `t` came to own the value at a later `= a …` that found it among `a`'s cursors — the ones made lexically before that `=`. In the loop's second round `= t a` dropped t's value, which `b` held since `= b t` of the round before, a cursor made lexically after: `b` was read freed (heap-use-after-free). Where the walk moves the source, the assignment is a move in the generated code too (`@.__nurl_amv.N`): the flag goes with the value, and there is nothing to hand over later.
// map: §2.2 | A2 | runs-clean | - | agora #634: three String owners rotated by assignment in a loop; the hand-over at a reassignment missed a cursor made later in the loop body
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ String t ( string_from `the third string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
