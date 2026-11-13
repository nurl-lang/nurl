// value_block_join_of_locals_pushed: `: String e { : String s …  : String t …  ? c s t }  ( vec_push [String] v e )`: both sources were cleared and a clone pushed, so neither local was dropped (agora #827).
// Closed: the join, its value block's tail, publishes the block-locals its arms lent, and the block's `}` moves the selected one into the join's value on its arm's path; the other is dropped at the scope's end as before (__vb_tail_takes, agora #807).
// main (before this PR): accepted; LeakSanitizer reported leaks each round.
// map: §7.6 | A2 | runs-clean | - | agora #827: a value block's join of locals pushed into a Vec (leak on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i { : ~ i k 0 ~ < k 3 { : String e { : String s ( string_from `s long enough for a heap buffer` ) : String t ( string_from `t long enough for a heap buffer` ) ? == 0 % k 2 s t } : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v e ) ( nurl_println_int ( eatv v ) ) = k + k 1 } ^ 0 }
