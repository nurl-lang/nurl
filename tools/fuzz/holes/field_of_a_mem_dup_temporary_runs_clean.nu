// field_of_a_mem_dup_temporary_runs_clean: `^ . ( mem_dup o ) name`: a field read out of a mem_dup copy
// Closed: a field read of a `( mem_dup x )` copy takes the field over and drops the rest of the copy, as a read off a call that handed its result over does (agora #771).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #771: `^ . ( mem_dup o ) name`: a field read out of a mem_dup copy
$ `stdlib/core/string.nu`

: S { String name String tag i n }

@ mks s t → S { ^ @ S { ( string_from t ) ( string_from `a tag string long enough for the heap buf` ) 1 } }

@ f S o b c → String { ^ . ( mem_dup o ) name }

@ main → i {
    : S o ( mks `the owner string, long enough for the heap` )
    : String r ( f o T )
    : String r2 ( f o F )
    ^ - ( string_len r ) ( string_len r )
}
