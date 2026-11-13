// string_owners_rotated_by_assignment_in_an_unsafe_function_runs_clean: the #634 rotation (`= t a  = a b  = b t` in a loop) inside an `unsafe` function.
// Closed (agora #667 item 4): code the walk does not check — `unsafe`, a trusted file — kept the cursor path for a handover by name, and the second round's `= t a` dropped the value `b` held since the round before (heap-use-after-free). The move is made there too; only the walk's row is not told.
// map: §2.2 | A2 | runs-clean | - | agora #667: the #634 rotation in an unsafe function kept the cursor path
$ `stdlib/core/string.nu`

unsafe @ rot → i {
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

@ main → i { ( rot ) ^ 0 }
