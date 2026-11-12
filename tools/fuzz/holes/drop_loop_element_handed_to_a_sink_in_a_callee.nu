// drop_loop_element_handed_to_a_sink_in_a_callee: `~ x v { ( eat x ) }` in a function over a borrowed `( Vec Bomb )`, eat a `sink`: the loop's element went to eat while the Vec still dropped it
// Closed: refused: a `% Drop` loop element that cannot be copied may not be handed to a `sink` — the message names vec_pop / vec_remove / a draining callee, or a borrowing one (agora #669 item 4).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #669: a `% Drop` loop element handed to a `sink` in a callee
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s t i k → Bomb { ^ @ Bomb { ( string_from t ) k } }

@ see s w Bomb b → v { ( nurl_println ( nurl_str_cat3 w ` sees ` ( string_data . b tag ) ) ) }

@ eat sink Bomb b → v { ( see `eat` b ) }

@ f ( Vec Bomb ) v → v { ~ x v { ( eat x ) } }

@ main → i { : ~ ( Vec Bomb ) v ( vec_new [Bomb] ) ( vec_push [Bomb] v ( bomb `element bomb long enough for heap` 0 ) ) ( f v ) ( see `main` ( vec_at [Bomb] v 0 ) ) ^ 0 }
