// argument_literal_over_a_binding_handed_back_leaks_the_binding: agora #545 — `( keep @ H { b 1 } )`, a literal written as an argument over a binding, to a callee that hands its parameter back: the binding moved into the literal, the result was taken for lent, and the moved-in value was released by nobody.
// Closed: the result owns what moved into the argument literal on the run that hands it back; where the result is discarded it is released with it.
// main (before this PR): LeakSanitizer, each moved-in value.
// map: §7.6 | A2 | runs-clean | - | agora #545: a binding moved into an argument literal that the callee handed back was never released (leak)
$ `stdlib/core/string.nu`

: In { String s }
: H { [i items i n }
: HI { In items i n }

@ keep H h → H { ^ h }
@ keep_i HI h → HI { ^ h }

@ main → i {
    : [i b [i | 1 2 3]
    : H gb ( keep @ H { b 1 } )
    ~ x . gb items { ( nurl_println ( nurl_str_int x ) ) }
    : [i b2 [i | 1 2 3]
    ( keep @ H { b2 1 } )
    : In c @ In { ( string_from `a string long enough to be on the heap, in` ) }
    : HI gc ( keep_i @ HI { c 1 } )
    ( nurl_println ( string_data . . gc items s ) )
    : In c2 @ In { ( string_from `a string long enough to be on the heap, in2` ) }
    ( keep_i @ HI { c2 1 } )
    ^ 0
}
