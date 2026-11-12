// renamed_drop_param_of_a_temporary_stored_in_an_inout_vec_runs_clean: `@ put Bomb p inout ( Vec Bomb ) out → v { : Bomb e p ( vec_push [Bomb] out e ) }` called with a temporary: the temporary was released after the call while out held it
// Closed: a binding of a parameter's own value is that parameter in the summaries (`__pmove`, agora #759), so put takes the temporary over (agora #669 item 3).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #669: a renamed `% Drop` parameter of a temporary stored in an inout Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s t i k → Bomb { ^ @ Bomb { ( string_from t ) k } }

@ see s w Bomb b → v { ( nurl_println ( nurl_str_cat3 w ` sees ` ( string_data . b tag ) ) ) }

@ put Bomb p inout ( Vec Bomb ) out → v { : Bomb e p ( vec_push [Bomb] out e ) }

@ main → i { : ~ ( Vec Bomb ) out ( vec_new [Bomb] ) ( put ( bomb `temporary bomb long enough for heap` 0 ) out ) ( see `main` ( vec_at [Bomb] out 0 ) ) ^ 0 }
