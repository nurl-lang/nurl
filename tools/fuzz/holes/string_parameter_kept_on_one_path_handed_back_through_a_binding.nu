// string_parameter_kept_on_one_path_handed_back_through_a_binding: `: String r ( f0 p )  ^ r`, f0 `^ p` declared above, p pushed into a Vec on another path: on that run the function took p over and released it on the way out while the caller held r
// Closed: a `:` binding's lend out of a parameter the function takes over on another path is judged at `^` as the returned call is (agora #743): parked, refused at module end (__pfo_bind_lends, agora #765).
// main 9052104: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | rejected | - | agora #765: a lend of a kept parameter handed back through a binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name i n }

@ f0 String p → String { ^ p }

@ f ( Vec String ) log String p b keep → String { ? keep { ( vec_push [String] log p ) ^ ( string_from `kept` ) } {} : String r ( f0 p ) ^ r }

@ main → i {
    : ~ ( Vec String ) log ( vec_new [String] )
    : String a ( f log ( string_from `first value long enough for the heap buffer` ) F )
    ( nurl_println ( string_data a ) )
    : String x ( string_from `second value long enough for the heap buffer` )
    : String b ( f log x T )
    ( nurl_println ( string_data b ) )
    ^ 0
}
