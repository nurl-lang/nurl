// vec_parameter_kept_on_one_path_loop_element_handed_back: `~ x p { ^ x }`, p a `( Vec String )` the function pushes into a Vec on another path: the element went to the caller while the function released p
// Closed: a `~` loop element lends what its container is, judged as a returned binding is (__pfo_bind_lends, agora #765 / #677 item A).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #765: a loop element of a kept parameter handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println `drop R` ) } }

@ f0 String p → String { ^ p }

@ g0 R p → R { ^ p }

@ f ( Vec ( Vec String ) ) log ( Vec String ) p b keep → String { ? keep { ( vec_push [( Vec String )] log p ) ^ ( string_from `kept` ) } {} ~ x p { ^ x } ^ ( string_from `none` ) }

@ main → i { : ~ ( Vec ( Vec String ) ) log ( vec_new [( Vec String )] ) : ~ ( Vec String ) v1 ( vec_new [String] ) ( vec_push [String] v1 ( string_from `element string long enough for heap a` ) ) : String a ( f log v1 F ) ( nurl_println ( string_data a ) ) ^ 0 }
