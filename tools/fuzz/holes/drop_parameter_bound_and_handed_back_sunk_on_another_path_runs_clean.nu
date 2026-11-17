// drop_parameter_bound_and_handed_back_sunk_on_another_path_runs_clean: p handed to a `sink` on one path, `: R r p ^ r` on the other
// Closed (agora #876): a binding holding a parameter's own value (`: R r p`, __pmove) handed back is answered as `^ p` is - its flag, p's moved to it, says per run whether the caller gets it back owned.
// main fcf68942: LeakSanitizer reported the value never released (`run F`).
// map: §7.6 | A2 | runs-clean | - | AGORA-876: p handed to a `sink` on one path, `: R r p ^ r` on the other
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mkr s t → R { ^ @ R { ( string_from t ) 1 } }

@ g0 R p → R { ^ p }

@ eat sink R r → v { ( nurl_println ( string_data . r s ) ) }

@ f ( Vec R ) log R p b keep → R { ? keep { ( eat p ) ^ ( mkr `kept` ) } {} : R r p ^ r }

@ run b keep → v {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mkr `first value long enough for the heap, surely so` )
    : R a ( f log x keep )
    ( nurl_println ( string_data . a s ) )
    ( nurl_println_int ( vec_len [R] log ) )
}

@ main → i { ( run T ) ( run F ) ^ 0 }
