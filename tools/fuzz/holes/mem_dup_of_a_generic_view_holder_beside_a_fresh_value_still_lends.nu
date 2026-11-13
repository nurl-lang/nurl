// mem_dup_of_a_generic_view_holder_beside_a_fresh_value_still_lends: `^ ? c ( mem_dup a ) ( mkl )` over `( Gw s )`, a generic struct instantiated with a view; the caller replaces the viewed String and reads the result.
// Control for agora #767 (claude-formal's precision note): a generic instance holding a view is a view holder, so a copy of it still reaches the source.
// map: §2.13 | A2 | rejected | - | agora #767: a join of a copy of a generic view holder and a fresh value still lends
$ `stdlib/core/string.nu`

: Gw [T] { T x i n }

@ mkg String src → ( Gw s ) { ^ @ ( Gw s ) { ( string_data src ) 1 } }

@ mkl → ( Gw s ) { ^ @ ( Gw s ) { `a static literal` 2 } }

@ f ( Gw s ) a b c → ( Gw s ) { ^ ? c ( mem_dup a ) ( mkl ) }

@ main → i {
    : ~ String src ( string_from `a source string long enough for the heap` )
    : ( Gw s ) x ( mkg src )
    : ( Gw s ) e ( f x T )
    = src ( string_from `replaced` )
    ( nurl_println . e x )
    ^ - . e n 1
}
