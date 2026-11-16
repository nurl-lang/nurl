// closure_pushes_its_captured_drop_parameter_on_one_path:
// AGORA-869: runs clean - a closure that keeps its captured by-value parameter makes the function take the parameter over, as the same push in its body does (main 3358873a: heap-use-after-free).
// map: §7.6 | A2 | runs-clean | - | agora #868: a closure run on one path pushes its captured by-value `% Drop` parameter into a Vec parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ f ( Vec R ) log R p b keep → i { : ( @ v ) run \ → v { ( vec_push [R] log p ) } ? keep { ( run ) } {} ^ 1 }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mk `a value long enough for the heap buffer, surely, yes` )
    : i b ( f log x T )
    ( nurl_println ( string_data . ( vec_at [R] log 0 ) s ) )
    ^ 0
}
