// value_block_three_way_join_of_drop_structs_sunk: the `% Drop` twin of the three-way join: each destructor runs once a round (agora #836).
// Closed: a join that is a bare arm of a value block's tail join publishes what its arms lent, and the outer join folds it in under a phi of its own arm's edge, so every path hands over a value of its own (__vb_sel_lift, agora #836).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #836: a three-way tail join of % Drop block locals sunk (UAF on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ 0 }

@ main → i {
    : ~ i k 0
    ~ < k 3 { : D e { : D s @ D { ( string_from `a heap string long enough for the heap buffer` ) 1 } : D t @ D { ( string_from `a heap string long enough for the heap buffer` ) 2 } : D u @ D { ( string_from `a heap string long enough for the heap buffer` ) 3 } ? == 0 % k 3 s ? == 1 % k 3 t u } ( nurl_println_int ( eatd e ) ) = k + k 1 }
    ^ 0
}
