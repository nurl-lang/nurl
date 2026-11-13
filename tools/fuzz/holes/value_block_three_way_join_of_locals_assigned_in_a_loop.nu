// value_block_three_way_join_of_locals_assigned_in_a_loop: `= r { : String s … t … u …  ? a s ? b t u }` in a loop: the selected local was released under r (agora #836).
// Closed: a join that is a bare arm of a value block's tail join publishes what its arms lent, and the outer join folds it in under a phi of its own arm's edge, so every path hands over a value of its own (__vb_sel_lift, agora #836).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #836: a three-way tail join of block locals assigned in a loop (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ 0 }

@ main → i {
    : ~ String r ( string_from `a heap string long enough for the heap buffer` )
    : ~ i k 0
    ~ < k 3 { = r { : String s ( string_from `a heap string long enough for the heap buffer` ) : String t ( string_from `a heap string long enough for the heap buffer` ) : String u ( string_from `a heap string long enough for the heap buffer` ) ? == 0 % k 3 s ? == 1 % k 3 t u } = k + k 1 }
    ( nurl_println ( string_data r ) )
    ^ 0
}
