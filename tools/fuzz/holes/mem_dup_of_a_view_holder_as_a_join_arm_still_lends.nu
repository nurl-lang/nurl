// mem_dup_of_a_view_holder_as_a_join_arm_still_lends: `^ ? c ( mem_dup a ) ( mem_dup a )` over a struct with an `s` view field — the copies view what `a` views; the caller replaces the viewed String and reads the result.
// Control for agora #767: a copy of a value that holds a view is still a lend of what it views.
// map: §2.13 | A2 | rejected | - | agora #767: a join of copies of a view holder still lends its view's source
$ `stdlib/core/string.nu`

: W { s v i n }

@ mkw String src → W { ^ @ W { ( string_data src ) 1 } }

@ f W a b c → W { ^ ? c ( mem_dup a ) ( mem_dup a ) }

@ main → i {
    : ~ String src ( string_from `a source string long enough for the heap` )
    : W x ( mkw src )
    : W e ( f x T )
    = src ( string_from `replaced` )
    ^ - . e n 1
}
