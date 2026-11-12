// mem_dup_of_a_view_holder_beside_a_fresh_value_still_lends: `^ ? c ( mem_dup a ) ( mkl )` over a struct with an `s` view field — the copy views what `a` views; the caller replaces the viewed String and reads the result.
// Control for agora #767: a copy of a value that holds a view still reaches what it views, beside a fresh arm (a view of a static literal).
// map: §2.13 | A2 | rejected | - | agora #767: a join of a copy of a view holder and a fresh value still lends its view's source
$ `stdlib/core/string.nu`

: W { s v i n }

@ mkw String src → W { ^ @ W { ( string_data src ) 1 } }

@ mkl → W { ^ @ W { `a static literal` 2 } }

@ f W a b c → W { ^ ? c ( mem_dup a ) ( mkl ) }

@ main → i {
    : ~ String src ( string_from `a source string long enough for the heap` )
    : W x ( mkw src )
    : W e ( f x T )
    = src ( string_from `replaced` )
    ( nurl_println . e v )
    ^ - . e n 1
}
