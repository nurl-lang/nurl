// string_owners_rotated_by_assignment_in_a_nested_loop_runs_clean: three String owners rotated by assignment in the inner of two loops, and back by one in the outer one, read after both.
// Closed (agora #634): a back edge of either loop reaches `= t a` with `b` holding what `t` owns; the assignments are moves where they run.
// map: §2.2 | A2 | runs-clean | - | agora #634: three String owners rotated by assignment in a nested loop
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ String t ( string_from `the third string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 3 {
        : ~ i j 0
        ~ < j 2 {
            = t a
            = a b
            = b t
            = j + j 1
        }
        = t b
        = b a
        = a t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
