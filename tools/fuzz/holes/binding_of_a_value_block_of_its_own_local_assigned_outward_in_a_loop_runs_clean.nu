// binding_of_a_value_block_of_its_own_local_assigned_outward_in_a_loop_runs_clean: agora #615 guard — in a loop body, `: String e { : String s … s }` then `= out e` with `out` outside the loop: e owns the value, so it moves to out each round and the old one is released.
// Guard: main refused this (`out` borrows from `e`, which ended): e was a borrow with no owner. It is a cursor over s now, of a scope that ends before out's, so the assignment moves s's value.
// main 0b31adec: rejected ('out' borrows from 'e', which ended).
// map: §7.6 | A2 | runs-clean | - | agora #615 guard: a binding of a value block of the block's own local, assigned outward in a loop
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String out ( string_from `the first value of the outer binding, long` )
    : ~ i k 0
    ~ < k 2 {
        : String e { : String s ( string_from `inner string long enough for a heap buffer` ) s }
        = out e
        = k + k 1
    }
    ( nurl_println_int ( string_len out ) )
    ^ 0
}
