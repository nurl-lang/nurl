// value_block_join_of_drop_struct_locals_sunk: the `% Drop` twin of #821: each destructor runs once, three rounds print six drop lines (agora #821).
// Closed: the join, its value block's tail, publishes the block-locals its arms lent, and the block's `}` moves the selected one into the join's value on its arm's path; the other is dropped at the scope's end as before (__vb_tail_takes, agora #807).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #821: a value block's join of % Drop struct locals handed to a sink (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

: D { String a i n }

% Drop D { @ drop D d → v { ( nurl_println_int . d n ) } }

@ eatd sink D x → i { ^ . x n }

@ main → i {
    : ~ i k 0
    ~ < k 3 { : D e { : D s @ D { ( string_from `a heap string long enough for the heap buffer` ) 1 } : D t @ D { ( string_from `a heap string long enough for the heap buffer` ) 2 } ? == 0 % k 2 s t } ( nurl_println_int ( eatd e ) ) = k + k 1 }
    ^ 0
}
