// renamed_drop_param_pushed_into_a_vec_is_consumed_runs_clean: a `% Drop` parameter bound by a new name (`: R q p`) and pushed into a Vec parameter: what q was handed to was recorded under q, which names no parameter, so the function was taken not to consume p and the caller freed what the Vec held
// Closed: a binding that takes over a parameter's own value carries that parameter (`__pmove`), and the summary recorders count what it is kept, stored, sunk or handed back as the parameter (__pmove_param, agora #759).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #759: `: R q p  ( vec_push log q )` (R with its own `% Drop`): the caller freed what the Vec held
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ f ( Vec R ) log R p → i { : R q p ( vec_push [R] log q ) ^ 1 }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : i a ( f log ( mk `first value long enough for the heap buffer` ) )
    : R x ( mk `second value long enough for the heap buffer` )
    : i b ( f log x )
    ( nurl_println ( string_data . ( vec_at [R] log 0 ) s ) )
    ( nurl_println ( string_data . ( vec_at [R] log 1 ) s ) )
    ^ 0
}
