// lent_element_through_a_chain_of_twenty_generic_forwarders_kept_past_a_clear: generic g1 … g20, each handing back the next (`^ ( g2 [T] xs )`), g20 `^ ( vec_at [T] xs 0 )`; the caller views ( g1 [String] xs )'s String past ( vec_clear xs )
// refused - a guard for resolve_retfwd_lends, which settles its fixed point without a round cap
// map: §2.10 | A2 | rejected | - | retfwd fixpoint
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ g1 [T] ( Vec T ) xs → T { ^ ( g2 [T] xs ) }

@ g2 [T] ( Vec T ) xs → T { ^ ( g3 [T] xs ) }

@ g3 [T] ( Vec T ) xs → T { ^ ( g4 [T] xs ) }

@ g4 [T] ( Vec T ) xs → T { ^ ( g5 [T] xs ) }

@ g5 [T] ( Vec T ) xs → T { ^ ( g6 [T] xs ) }

@ g6 [T] ( Vec T ) xs → T { ^ ( g7 [T] xs ) }

@ g7 [T] ( Vec T ) xs → T { ^ ( g8 [T] xs ) }

@ g8 [T] ( Vec T ) xs → T { ^ ( g9 [T] xs ) }

@ g9 [T] ( Vec T ) xs → T { ^ ( g10 [T] xs ) }

@ g10 [T] ( Vec T ) xs → T { ^ ( g11 [T] xs ) }

@ g11 [T] ( Vec T ) xs → T { ^ ( g12 [T] xs ) }

@ g12 [T] ( Vec T ) xs → T { ^ ( g13 [T] xs ) }

@ g13 [T] ( Vec T ) xs → T { ^ ( g14 [T] xs ) }

@ g14 [T] ( Vec T ) xs → T { ^ ( g15 [T] xs ) }

@ g15 [T] ( Vec T ) xs → T { ^ ( g16 [T] xs ) }

@ g16 [T] ( Vec T ) xs → T { ^ ( g17 [T] xs ) }

@ g17 [T] ( Vec T ) xs → T { ^ ( g18 [T] xs ) }

@ g18 [T] ( Vec T ) xs → T { ^ ( g19 [T] xs ) }

@ g19 [T] ( Vec T ) xs → T { ^ ( g20 [T] xs ) }

@ g20 [T] ( Vec T ) xs → T { ^ ( vec_at [T] xs 0 ) }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough to own a heap buffer for sure` ) )
    : s v ( string_data ( g1 [String] xs ) )
    ( vec_clear [String] xs )
    ( nurl_println v )
    ^ 0
}
