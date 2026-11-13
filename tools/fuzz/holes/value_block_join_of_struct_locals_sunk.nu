// value_block_join_of_struct_locals_sunk: `: P e { : P s …  : P t …  ? c s t }  ( eatp e )` in a loop: the sink took the selected struct while the block still dropped it (agora #821).
// Closed: the join, its value block's tail, publishes the block-locals its arms lent, and the block's `}` moves the selected one into the join's value on its arm's path; the other is dropped at the scope's end as before (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #821: a value block's join of struct locals handed to a sink (UAF on main)
$ `stdlib/core/string.nu`

: P { String a i n }

@ eatp sink P x → i { ^ . x n }

@ main → i { : ~ i k 0 ~ < k 3 { : P e { : P s @ P { ( string_from `first local long enough for the heap buffer` ) 1 } : P t @ P { ( string_from `second local long enough for the heap buffer` ) 2 } ? == 0 % k 2 s t } ( nurl_println_int ( eatp e ) ) = k + k 1 } ^ 0 }
