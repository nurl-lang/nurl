// value_block_nested_match_join_of_locals_sunk: a `??` inside a `??` arm, inside it a `?`, of block locals, sunk (agora #836).
// Closed: a join that is a bare arm of a value block's tail join publishes what its arms lent, and the outer join folds it in under a phi of its own arm's edge, so every path hands over a value of its own (__vb_sel_lift, agora #836).
// main (before this PR): accepted; LeakSanitizer reported leaks.
// map: §7.6 | A2 | runs-clean | - | agora #836: nested matches of block locals sunk (leak on main)
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ 0 }

@ main → i {
    : ~ i k 0
    ~ < k 4 { : String e { : String s ( string_from `a heap string long enough for the heap buffer` ) : String t ( string_from `a heap string long enough for the heap buffer` ) : String u ( string_from `a heap string long enough for the heap buffer` ) ?? @ ?i { T k } { T z → ?? @ ?i { T z } { T q → ? == 0 % q 2 s t F → u } F → u } } ( nurl_println_int ( eat e ) ) = k + k 1 }
    ^ 0
}
