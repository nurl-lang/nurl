// vec_field_of_a_struct_param_through_a_cond: agora #178 — a Vec field of a parameter handed back through a `?`, the argument reassigned (vec_field_of_a_struct_param_through_a_cond).
// Closed: a `?` / `??` arm that hands out a field of a parameter — or of a payload binding or cursor over one — lends that parameter back in part (mem_note_field_part; agora #178).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h712 | agora #178: a Vec field of a parameter handed back through a `?`, the argument reassigned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: B { ( Vec String ) xs i n }

@ mkb → B {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mk ) )
    ^ @ B { v 1 }
}

@ part B b b c → ( Vec String ) { ^ ? c . b xs ( vec_new [String] ) }

@ main → i {
    : ~ B b ( mkb )
    : ( Vec String ) t ( part b T )
    = b ( mkb )
    ( nurl_println_int ( vec_len [String] t ) )
    ^ 0
}
