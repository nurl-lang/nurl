// value_block_three_way_join_of_locals_sunk: `: String e { : String s … t … u …  ? a s ? b t u }  ( eat e )` in a loop: the locals leaked each round (agora #836).
// Closed: a join that is a bare arm of a value block's tail join publishes what its arms lent, and the outer join folds it in under a phi of its own arm's edge, so every path hands over a value of its own (__vb_sel_lift, agora #836).
// main (before this PR): accepted; LeakSanitizer reported leaks.
// map: §7.6 | A2 | runs-clean | - | agora #836: a three-way tail join of block locals sunk (leak on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ . x n }

@ main → i {
    : ~ i k 0
    ~ < k 3 { : String e { : String s ( string_from `a heap string long enough for the heap buffer` ) : String t ( string_from `a heap string long enough for the heap buffer` ) : String u ( string_from `a heap string long enough for the heap buffer` ) ? == 0 % k 3 s ? == 1 % k 3 t u } ( nurl_println_int ( eat e ) ) = k + k 1 }
    ^ 0
}
