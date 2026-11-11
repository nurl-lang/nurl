// string_owners_rotated_by_assignment_outside_a_loop_runs_clean: the three assignments of a rotation (`= t a  = a b  = b t`) once, outside any loop; `a` and `b` read after them.
// A guard of agora #634's fix: it ran clean before (every cursor was made before the `=` that handed its value over) and it runs clean with the assignments made moves.
// map: §2.2 | A2 | runs-clean | - | agora #634's guard: the rotation once, outside a loop
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ String t ( string_from `the third string, long enough for the heap, yes` )
    = t a
    = a b
    = b t
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
