// string_owners_rotated_in_a_loop_out_of_one_that_may_own_runs_clean: the #634 rotation (`= t a  = a b  = b t`) where `a` owns its value on one path only (`? == c 1 ( string_from … ) h0`).
// Closed (agora #667): the rotation was refused — `a`, a borrow on some path, kept the cursor path and every name it reached was taken for a borrow handed over as an owner. The handover is a move now, `a`'s run-time flag going with the value, and the rotation runs clean on both paths; the lender keeps its string.
// map: §2.2 | A2 | runs-clean | - | agora #667: a rotation by assignment out of a String that may own its value
$ `stdlib/core/string.nu`

@ rot i c String h0 → i {
    : ~ String a ? == c 1 ( string_from `the first string, long enough for the heap, yes` ) h0
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

@ main → i { : String h ( string_from `the lender string, long enough for the heap, yes` ) ( rot 1 h ) ( rot 0 h ) ( nurl_println ( string_data h ) ) ^ 0 }
