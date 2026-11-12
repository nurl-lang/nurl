// drop_vec_parameter_sunk_on_one_path_loop_element_handed_back_on_the_other: as vec_parameter_sunk_on_one_path_loop_element_handed_back_on_the_other, a `( Vec Bomb )`, Bomb with its own `% Drop`
// Closed: as that probe (agora #677 item A).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #677: as that probe, a `% Drop` element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println `drop` ) } }

@ eatvec sink ( Vec Bomb ) w → v {}

@ f ( Vec Bomb ) v i c → Bomb { ? == c 1 { ( eatvec v ) ^ @ Bomb { ( string_from `x` ) 1 } } {} ~ x v { ^ x } ^ @ Bomb { ( string_from `none` ) 0 } }

@ main → i { : ~ ( Vec Bomb ) v ( vec_new [Bomb] ) ( vec_push [Bomb] v @ Bomb { ( string_from `element bomb long enough for heap a` ) 2 } ) : Bomb a ( f v 0 ) ( nurl_println ( string_data . a tag ) ) ^ 0 }
