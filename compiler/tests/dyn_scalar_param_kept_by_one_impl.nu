// dyn_scalar_param_kept_by_one_impl.nu — the impls behind a `dyn` call
// may take a scalar argument differently (agora #134). `Log` stores its
// integer, float and flag, `Counter` hands the integer on to a counter
// that records it (pncounter_inc keeps its replica id), and `Sum` only
// reads them. A scalar owns nothing, so there is nothing to leak whichever
// impl runs, as a `sink` of one is a copy (sink_scalar_is_a_copy.nu):
// the call compiles, and `k`, `w` and `on` are still the caller's after
// it. A String the impls take differently is still refused
// (diag_dyn_impls_disagree.nu).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`

% Tally [T] {
    @ add T self i k f w b on → i
}

: Log { ( Vec i ) ks ( Vec f ) ws ( Vec b ) ons }

: Counter { PNCounter c }

: Sum { i n }

% Tally Log {
    @ add Log l i k f w b on → i {
        ( vec_push [i] . l ks k )
        ( vec_push [f] . l ws w )
        ( vec_push [b] . l ons on )
        ^ ( vec_len [i] . l ks )
    }
}

% Tally Counter {
    @ add Counter c i k f w b on → i {
        ( pncounter_inc . c c k 3 )
        ^ ( pncounter_value . c c )
    }
}

% Tally Sum {
    @ add Sum s i k f w b on → i { ^ ? on + . s n k . s n }
}

@ main → i {
    : %Tally lg ( dyn Tally @ Log { ( vec_new [i] ) ( vec_new [f] ) ( vec_new [b] ) } )
    : %Tally ct ( dyn Tally @ Counter { ( pncounter_new ) } )
    : %Tally sm ( dyn Tally @ Sum { 40 } )
    : i k 2
    : f w 0.5
    : b on T
    ( nurl_println ( nurl_str_cat `log: ` ( nurl_str_int ( add lg k w on ) ) ) )
    ( nurl_println ( nurl_str_cat `counter: ` ( nurl_str_int ( add ct k w on ) ) ) )
    ( nurl_println ( nurl_str_cat `sum: ` ( nurl_str_int ( add sm k w on ) ) ) )
    ( nurl_println ? on ( nurl_str_cat `still the caller's: ` ( nurl_str_int + k # i * w 2.0 ) ) `lost` )
    ^ 0
}
