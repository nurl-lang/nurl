// field_of_a_mem_dup_temporary_as_a_block_arm_runs_clean: `? c { . ( mem_dup o ) name } …`: a block arm ending in a field of a mem_dup copy
// Closed: a block arm whose tail is such a field read answers by the read's bit (agora #771).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #771: `? c { . ( mem_dup o ) name } …`: a block arm ending in a field of a mem_dup copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name String tag i n }
: O { S inner i k }

@ mks s t → S { ^ @ S { ( string_from t ) ( string_from `a tag string long enough for the heap buf` ) 1 } }

@ eat sink String s → i { ^ ( string_len s ) }

@ f S o b c → String { ^ ? c { . ( mem_dup o ) name } ( string_from `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : S o ( mks `the owner string, long enough for the heap` )
    : String r ( f o T ) : String r2 ( f o F )
    ^ - ( string_len r ) ( string_len r )
}
