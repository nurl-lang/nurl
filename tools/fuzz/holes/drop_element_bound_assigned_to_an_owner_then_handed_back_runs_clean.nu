// drop_element_bound_assigned_to_an_owner_then_handed_back_runs_clean: as drop_loop_element_assigned_to_an_owner_then_handed_back_runs_clean, the element bound with vec_at first
// Closed: as that probe (agora #669 item 2).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #669: as that probe, a vec_at binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s t i k → Bomb { ^ @ Bomb { ( string_from t ) k } }

@ see s w Bomb b → v { ( nurl_println ( nurl_str_cat3 w ` sees ` ( string_data . b tag ) ) ) }

@ f ( Vec Bomb ) v → Bomb { : ~ Bomb best ( bomb `init bomb long enough for the heap` 0 ) : Bomb x ( vec_at [Bomb] v 0 ) = best x ^ best }

@ main → i { : ~ ( Vec Bomb ) v ( vec_new [Bomb] ) ( vec_push [Bomb] v ( bomb `element bomb long enough for heap` 0 ) ) : Bomb b ( f v ) ( see `main` b ) ^ 0 }
