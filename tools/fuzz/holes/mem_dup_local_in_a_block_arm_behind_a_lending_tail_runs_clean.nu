// mem_dup_local_in_a_block_arm_behind_a_lending_tail_runs_clean: `? c { : S t ( mem_dup x ) ( pick o t ) } …`: the arm's own copy beside a tail call lending another argument
// Closed: an arm whose tail call is handed one of its own locals asks the callee, after the copy it makes where that local is lent, whether it lends anything the arm owns (mem_arm_outer_lend, after mem_arm_take_call); where it does not, the locals go at the arm's exit (agora #662, #771).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #662: `? c { : S t ( mem_dup x ) ( pick o t ) } …`: the arm's own copy beside a tail call lending another argument
$ `stdlib/core/string.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick S a S b → S { ^ a }

@ eat sink S s → i { ^ . s n }

@ f S o S x b c → S { ^ ? c { : S t ( mem_dup x ) ( pick o t ) } ( mks `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : S o ( mks `the owner string, long enough for the heap` )
    : S x ( mks `another string, long enough for the heap ok` )
    : S r ( f o x T )
    : S r2 ( f o x F )
    ^ - + . r n . r2 n + . o n 1
}
