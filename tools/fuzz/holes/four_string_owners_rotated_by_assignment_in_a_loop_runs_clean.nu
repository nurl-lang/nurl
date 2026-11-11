// four_string_owners_rotated_by_assignment_in_a_loop_runs_clean: four String owners rotated by assignment in a loop (`= t a  = a b  = b c  = c t`), `a`, `b` and `c` read after it.
// Closed (agora #634): the rule holds for any rotation length — each assignment out of an owner is a move where it runs, so no round depends on which cursors an earlier line knew of.
// map: §2.2 | A2 | runs-clean | - | agora #634: four String owners rotated by assignment in a loop
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ String c ( string_from `the third string, long enough for the heap, yes` )
    : ~ String t ( string_from `the spare string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 5 {
        = t a
        = a b
        = b c
        = c t
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data c ) )
    ^ 0
}
