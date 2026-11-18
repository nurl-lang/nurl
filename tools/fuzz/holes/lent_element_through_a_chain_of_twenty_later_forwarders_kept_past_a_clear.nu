// lent_element_through_a_chain_of_twenty_later_forwarders_kept_past_a_clear: f1 … f20, each defined above the one it hands back (`^ ( f2 xs )`), f20 `^ ( vec_at [String] xs 0 )`; the caller views ( f1 xs )'s String past ( vec_clear xs )
// refused - a guard for resolve_retfwd_lends, which settles its fixed point without a round cap
// map: §2.10 | A2 | rejected | - | retfwd fixpoint
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ f1 ( Vec String ) xs → String { ^ ( f2 xs ) }

@ f2 ( Vec String ) xs → String { ^ ( f3 xs ) }

@ f3 ( Vec String ) xs → String { ^ ( f4 xs ) }

@ f4 ( Vec String ) xs → String { ^ ( f5 xs ) }

@ f5 ( Vec String ) xs → String { ^ ( f6 xs ) }

@ f6 ( Vec String ) xs → String { ^ ( f7 xs ) }

@ f7 ( Vec String ) xs → String { ^ ( f8 xs ) }

@ f8 ( Vec String ) xs → String { ^ ( f9 xs ) }

@ f9 ( Vec String ) xs → String { ^ ( f10 xs ) }

@ f10 ( Vec String ) xs → String { ^ ( f11 xs ) }

@ f11 ( Vec String ) xs → String { ^ ( f12 xs ) }

@ f12 ( Vec String ) xs → String { ^ ( f13 xs ) }

@ f13 ( Vec String ) xs → String { ^ ( f14 xs ) }

@ f14 ( Vec String ) xs → String { ^ ( f15 xs ) }

@ f15 ( Vec String ) xs → String { ^ ( f16 xs ) }

@ f16 ( Vec String ) xs → String { ^ ( f17 xs ) }

@ f17 ( Vec String ) xs → String { ^ ( f18 xs ) }

@ f18 ( Vec String ) xs → String { ^ ( f19 xs ) }

@ f19 ( Vec String ) xs → String { ^ ( f20 xs ) }

@ f20 ( Vec String ) xs → String { ^ ( vec_at [String] xs 0 ) }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough to own a heap buffer for sure` ) )
    : s v ( string_data ( f1 xs ) )
    ( vec_clear [String] xs )
    ( nurl_println v )
    ^ 0
}
