// string_owners_swapped_through_a_loop_local_runs_clean: two String owners swapped in a loop through a binding made in its body (`: String u a  = a b  = b u`), read after it.
// A guard of agora #634's fix: `u` is bound in each round and gone at its end, so no round sees a cursor of the round before; it ran clean before and runs clean with the `:` and the `=` made moves.
// map: §2.2 | A2 | runs-clean | - | agora #634's guard: a swap in a loop through a binding of the loop body
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String a ( string_from `the first string, long enough for the heap, yes` )
    : ~ String b ( string_from `the second string, long enough for the heap, yes` )
    : ~ i k 0
    ~ < k 3 {
        : String u a
        = a b
        = b u
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
