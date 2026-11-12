// vec_parameter_kept_on_one_path_element_handed_back_through_a_binding: `: String e ( vec_at [String] p 0 )  ^ e`, p a `( Vec String )` pushed into a Vec on another path
// Closed: a `:` binding's lend out of a parameter the function takes over on another path is judged at `^` as the returned call is (agora #743): parked, refused at module end (__pfo_bind_lends, agora #765).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #765: a vec_at element of a kept parameter handed back through a binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name i n }

@ f ( Vec ( Vec String ) ) log ( Vec String ) p b keep → String { ? keep { ( vec_push [( Vec String )] log p ) ^ ( string_from `kept` ) } {} : String e ( vec_at [String] p 0 ) ^ e }

@ main → i {
    : ~ ( Vec ( Vec String ) ) log ( vec_new [( Vec String )] )
    : ~ ( Vec String ) v1 ( vec_new [String] ) ( vec_push [String] v1 ( string_from `element string long enough for heap a` ) )
    : String a ( f log v1 F ) ( nurl_println ( string_data a ) )
    ^ 0
}
