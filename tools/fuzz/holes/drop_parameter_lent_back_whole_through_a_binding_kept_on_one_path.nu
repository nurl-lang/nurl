// drop_parameter_lent_back_whole_through_a_binding_kept_on_one_path: control: `: R r ( g0 p )  ^ r`, R with its own `% Drop` (no copy), p kept on another path: lent back whole, r holds p's value by identity and hands it over
// Closed: a whole lend of a value that cannot be copied is left alone (`@bn`, agora #765).
// main 9052104: runs clean.
// AGORA-869: refused now, as `^ ( g0 p )` is: f hands back what the call lends out of p, which it takes over on the other path. Run clean only because main hands a literal; a binding's value is freed under the result (drop_parameter_lent_back_whole_through_a_binding_kept_on_one_path_given_a_binding).
// map: §7.6 | A2 | rejected | - | agora #765: control, a `% Drop` value lent back whole through a binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println `drop R` ) } }

@ f0 String p → String { ^ p }

@ g0 R p → R { ^ p }

@ f ( Vec R ) log R p b keep → R { ? keep { ( vec_push [R] log p ) ^ @ R { ( string_from `kept` ) 1 } } {} : R r ( g0 p ) ^ r }

@ main → i { : ~ ( Vec R ) log ( vec_new [R] ) : R a ( f log @ R { ( string_from `first value long enough for the heap` ) 1 } F ) ^ 0 }
