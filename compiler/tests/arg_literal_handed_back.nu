// A literal written as an argument, built over a binding, to a callee that
// hands its parameter back: `( keep @ H { a 1 } )`. The binding moved into
// the literal on the run that hands it back, so the result owns it; where
// the result is discarded it is released with it. The moved-in binding
// leaked — a slice, and a struct (agora #545).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: In { String s }
: HS { String items i n }
: H { [i items i n }
: HV { ( Vec i ) items i n }
: HI { In items i n }

@ keep_s HS h → HS { ^ h }
@ keep H h → H { ^ h }
@ keep_v HV h → HV { ^ h }
@ keep_i HI h → HI { ^ h }
@ keep_o ? [i h → ?[i { ^ h }
@ mk → [i { ^ [i | 4 5 6] }

@ main → i {
    : String a ( string_from `a string long enough to be on the heap for sure` )
    : HS g ( keep_s @ HS { a 1 } )
    ( nurl_println ( string_data . g items ) )
    ( keep_s @ HS { ( string_from `a fresh string long enough to be on the heap` ) 1 } )
    : [i b [i | 1 2 3]
    : H gb ( keep @ H { b 1 } )
    ~ x . gb items { ( nurl_println ( nurl_str_int x ) ) }
    : [i b2 [i | 1 2 3]
    ( keep @ H { b2 1 } )
    : ~ [i b3 [i | 1 2 3]
    : H gb3 ( keep @ H { b3 1 } )
    ( nurl_println ( nurl_str_int . . gb3 items length ) )
    : H gb4 ( keep @ H { ( mk ) 1 } )
    ( nurl_println ( nurl_str_int . . gb4 items length ) )
    : H gb5 ( keep @ H { [i | 9] 1 } )
    ( nurl_println ( nurl_str_int . . gb5 items length ) )
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 5 )
    : HV gw ( keep_v @ HV { w 1 } )
    ( nurl_println ( nurl_str_int ( vec_len [i] . gw items ) ) )
    : In c @ In { ( string_from `a string long enough to be on the heap, in` ) }
    : HI gc ( keep_i @ HI { c 1 } )
    ( nurl_println ( string_data . . gc items s ) )
    : In c2 @ In { ( string_from `a string long enough to be on the heap, in2` ) }
    ( keep_i @ HI { c2 1 } )
    : [i d [i | 1 2 3]
    : ?[i go ( keep_o @ ?[i { T d } )
    ?? go {
        T sl → { ( nurl_println ( nurl_str_int . sl length ) ) }
        F → {}
    }
    ^ 0
}
