// drop_loop_element_handed_to_a_sink: as drop_loop_element_handed_to_a_sink_in_a_callee, the loop in main over its own Vec
// Closed: as that probe (agora #669 item 4).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #669: a `% Drop` loop element handed to a `sink`, the loop in main
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s t i k → Bomb { ^ @ Bomb { ( string_from t ) k } }

@ see s w Bomb b → v { ( nurl_println ( nurl_str_cat3 w ` sees ` ( string_data . b tag ) ) ) }

@ eat sink Bomb b → v { ( see `eat` b ) }

@ main → i { : ~ ( Vec Bomb ) v ( vec_new [Bomb] ) ( vec_push [Bomb] v ( bomb `element bomb long enough for heap` 0 ) ) ~ x v { ( eat x ) } ( see `main` ( vec_at [Bomb] v 0 ) ) ^ 0 }
