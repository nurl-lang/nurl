// renamed_drop_param_kept_on_one_path_dropped_on_the_other_runs_clean: `: R q p` (R with its own `% Drop`), pushed into a Vec on one path: on the other nothing dropped q — its flag was p's, "not consumed"
// Closed: as renamed_drop_param_pushed_into_a_vec_is_consumed_runs_clean (agora #759).
// main 3c4322c: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #759: `: R q p` kept on one path: never dropped on the other
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

: W { String w }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ eat String x → v { ( nurl_println ( nurl_str_cat `ate ` ( string_data x ) ) ) }

@ f ( Vec R ) log R p b keep → String { : R q p ? keep { ( vec_push [R] log q ) ^ ( string_from `kept` ) } {} ^ ( string_from `none` ) }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : String a ( f log ( mk `first value long enough for the heap buffer` ) F )
    ( nurl_println ( string_data a ) )
    : String b ( f log ( mk `second value long enough for the heap buffer` ) T )
    ( nurl_println ( string_data b ) )
    ^ 0
}
