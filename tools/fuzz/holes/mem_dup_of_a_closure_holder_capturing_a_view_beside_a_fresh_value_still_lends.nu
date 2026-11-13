// mem_dup_of_a_closure_holder_capturing_a_view_beside_a_fresh_value_still_lends: `^ ? c ( mem_dup a ) ( mkl )` over a struct whose closure field captured a view of a String; the caller replaces the String and runs the copy's closure.
// Control for agora #767 (claude-formal's precision note): a closure that captured a view holds one, so a copy of its holder still reaches the source (__ty_holds_view_p).
// map: §2.13 | A2 | rejected | - | agora #767: a join of a copy of a closure holder over a view and a fresh value still lends
$ `stdlib/core/string.nu`

: Cl { ( @ i ) f i n }

@ mkc String src → Cl { : s v ( string_data src ) ^ @ Cl { \ → i { ^ ( strlen v ) } 1 } }

@ mkl → Cl { ^ @ Cl { \ → i { ^ 3 } 2 } }

@ f Cl a b c → Cl { ^ ? c ( mem_dup a ) ( mkl ) }

@ main → i {
    : ~ String src ( string_from `a source string long enough for the heap` )
    : Cl x ( mkc src )
    : Cl e ( f x T )
    = src ( string_from `replaced` )
    : ( @ i ) g . e f
    ^ - ( g ) 40
}
