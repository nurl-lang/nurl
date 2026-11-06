// handle_or_closure_read_off_a_field_taken_from_a_call_result: agora #474 — what else a read two levels off a call's result hands on: a String to a `sink` parameter, a `( Vec String )` field bound and read, a closure field bound and called, a scalar in a loop's condition and in a `?` condition, a String handed to string_clone. Each left the struct its inner read took out of the temporary undropped.
// Closed: the outer read releases the taken struct (its rest, or all of it) and hands an owning field on as a value of its own (gen_member, __mb_tmp_flag).
// main (before this PR): LeakSanitizer, the taken struct's String, Vec or closure env per round.
// map: §7.1 | A2 | runs-clean | - | agora #474: a handle, closure or scalar read off a field taken from a call's struct result; the taken struct was never dropped (leak)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pair { String a i b }
: Box1 { Pair v }
: Box2 { Box1 w }
: VB { ( Vec String ) xs }
: OB { VB i }
: C { ( @ i i ) f }
: OC { C c }

@ boxit Pair p → Box1 { ^ @ Box1 { p } }

@ mkpair i k → Pair { ^ @ Pair { ( string_from `a string long enough to be on the heap, and then some more bytes` ) k } }

@ box2 i k → Box2 { ^ @ Box2 { ( boxit ( mkpair k ) ) } }

@ mko i k → OB {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for the heap, more` ) )
    ^ @ OB { @ VB { xs } }
}

@ mkoc i k → OC {
    : String s ( string_from `a captured string long enough for the heap buffer` )
    ^ @ OC { @ C { \ i x → i { ^ + x ( string_len s ) } } }
}

@ eat sink String s → i { ^ ( string_len s ) }

@ once i k → i {
    : i e ( eat . . ( boxit ( mkpair k ) ) v a )
    : ( Vec String ) ys . . ( mko k ) i xs
    : i vl + ( vec_len [String] . . ( mko k ) i xs ) ( vec_len [String] ys )
    : ( @ i i ) g . . ( mkoc k ) c f
    : ~ i n 0
    : ~ i j 0
    ~ < j . . ( boxit ( mkpair k ) ) v b { = n + n 1 = j + j 1 }
    : ~ i q 0
    ? > . . ( boxit ( mkpair k ) ) v b 3 { = q ( string_len . . ( boxit ( mkpair k ) ) v a ) } { = q . . . ( box2 k ) w v b }
    : i cl ( string_len ( string_clone . . . ( box2 k ) w v a ) )
    ^ + + + + + + e vl ( g k ) n q cl 0
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 10 { = t + t ( once k ) = k + k 1 }
    ( nurl_println_int t )
    ^ 0
}
