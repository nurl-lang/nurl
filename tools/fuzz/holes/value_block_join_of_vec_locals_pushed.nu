// value_block_join_of_vec_locals_pushed: the Vec of Vecs form of #827: `: ( Vec String ) e { … ? c s t }` pushed into a `( Vec ( Vec String ) )` (agora #827).
// Closed: the join, its value block's tail, publishes the block-locals its arms lent, and the block's `}` moves the selected one into the join's value on its arm's path; the other is dropped at the scope's end as before (__vb_tail_takes, agora #807).
// main (before this PR): accepted; LeakSanitizer reported leaks each round.
// map: §7.6 | A2 | runs-clean | - | agora #827: a value block's join of Vec locals pushed into a Vec (leak on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ . x n }

@ main → i {
    : ~ ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ i k 0
    ~ < k 3 { : ( Vec String ) e { : ~ ( Vec String ) s ( vec_new [String] ) ( vec_push [String] s ( string_from `a heap string long enough for the heap buffer` ) ) : ~ ( Vec String ) t ( vec_new [String] ) ? == 0 % k 2 s t } ( vec_push [( Vec String )] vv e ) = k + k 1 }
    ( nurl_println_int ( vec_len [( Vec String )] vv ) )
    ^ 0
}
