// bare_view_of_a_loop_element_over_an_option_of_a_struct_handed_back_by_a_callee_below: agora #471 — `@ first_of ?Bag ob → s`, defined below its caller, hands back `( string_data x )` from `~ x . b items` over the option's payload; the option ends at its block's end, then the view is read
// Closed: a caller waits for a callee not walked yet that may hand back a view of a loop element over a parameter of any type but a number, a view, a String or an option of one (__rv_plain_param; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element over an option-of-struct parameter, handed back by a callee below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bag { ( Vec String ) items i n }

@ main → i {
    : String base ( string_from `the outer string, which outlives everything here` )
    : ~ s v ( string_data base )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string inside an option, freed at the end of its block` ) )
        : ?Bag ob @ ?Bag { T @ Bag { t 1 } }
        = v ( first_of ob )
    }
    ( nurl_println v )
    ^ 0
}

@ first_of ? Bag ob → s {
    ?? ob { T b → { ~ x . b items { ^ ( string_data x ) } } F → {} }
    ^ `none`
}
