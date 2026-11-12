// vec_parameter_sunk_on_one_path_loop_element_handed_back_on_the_other: `? == c 1 { ( eatvec v ) … } {}  ~ x v { ^ x }`, eatvec a `sink` of the `( Vec String )` parameter: the function is an inferred sink and drops v on every way out, the caller held the element
// Closed: a `~` loop element lends its container, judged at `^` as a returned call's lend is (__pfo_bind_lends, agora #677 item A / #765).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #677: a loop element handed back while another path sinks its container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eatvec sink ( Vec String ) w → v {}

@ f ( Vec String ) v i c → String { ? == c 1 { ( eatvec v ) ^ ( string_from `x` ) } {} ~ x v { ^ x } ^ ( string_from `none` ) }

@ main → i { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `element string long enough for heap a` ) ) : String a ( f v 0 ) ( nurl_println ( string_data a ) ) ^ 0 }
