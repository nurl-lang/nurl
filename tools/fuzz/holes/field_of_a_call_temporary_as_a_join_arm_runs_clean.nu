// field_of_a_call_temporary_as_a_join_arm_runs_clean: `^ ? c . ( mks … ) name ( string_from … )`: a field taken out of a call's temporary as a ? arm
// Closed: a `?` arm that is (or ends in) such a field read answers by the read's own bit, as a return of it does (agora #771).
// main ae5e524: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #771: `^ ? c . ( mks … ) name ( string_from … )`: a field taken out of a call's temporary as a ? arm
$ `stdlib/core/string.nu`

: S { String name String tag i n }

@ mks s t → S { ^ @ S { ( string_from t ) ( string_from `a tag string long enough for the heap buf` ) 1 } }

@ f S o b c → String { ^ ? c . ( mks `a fresh struct name long enough heap` ) name ( string_from `a fresh one long enough for the heap buffer` ) }

@ main → i {
    : S o ( mks `the owner string, long enough for the heap` )
    : String r ( f o T )
    : String r2 ( f o F )
    ^ - ( string_len r ) ( string_len r )
}
