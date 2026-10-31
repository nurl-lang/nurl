// cursor_field_handed_on: h191's other exits. A field of a struct cursor (`: E b a`) handed to a `sink` parameter left the owner's slot full, so the owner freed what the callee had already released; a returned literal taking a field of a cursor over a PARAMETER (`: E b p`) or over a borrowed `vec_get` element took it without a copy, and the caller's struct and the result shared one buffer.
// Closed: the sink argument empties the field in each owner the cursor is over (a parameter owner is consumed with it), and a literal copies a field the struct and its owners did not give up while the struct still holds that very handle (gen_call, gen_agg_lit).
// main (before this PR): heap-use-after-free in all three.
// map: §7.6 | A2 | runs-clean | h192 | field of struct cursor sunk/returned while owner keeps it: double owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { i n ( Vec u ) out }

@ mk → E { ^ @ E { 1 ( vec_new [u] ) } }

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ from_param E p → ?( Vec u ) {
    : E b p
    ^ @ ?( Vec u ) { T . b out }
}

@ from_element ( Vec E ) vs → ?( Vec u ) {
    ?? ( vec_get [E] vs 0 ) {
        T e → {
            : E b e
            : ( Vec u ) o . b out
            ^ @ ?( Vec u ) { T o }
        }
        F → { ^ @ ?( Vec u ) { F } }
    }
}

@ main → i {
    : E a ( mk )
    : E b a
    ( nurl_println_int ( eat . b out ) )
    : E p ( mk )
    ( vec_push [u] . p out 9 )
    ?? ( from_param p ) { T v → { ( nurl_println_int ( vec_len [u] v ) ) } F → {} }
    ( nurl_println_int ( vec_len [u] . p out ) )
    : ( Vec E ) vs ( vec_new [E] )
    ( vec_push [E] vs ( mk ) )
    ?? ( from_element vs ) { T v → { ( nurl_println_int ( vec_len [u] v ) ) } F → {} }
    ?? ( vec_get [E] vs 0 ) { T e → { ( nurl_println_int ( vec_len [u] . e out ) ) } F → {} }
    ^ 0
}
