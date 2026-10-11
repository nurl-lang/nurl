// A call's result holds views of what the callee stores or hands back
// inside it: a ( Vec s ) built around an argument, a closure that captured
// it. Returned, such a result may not hold a view of a string this function
// releases on its way out.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wrapv s a → ( Vec s ) { : ( Vec s ) v ( vec_new [s] ) ( vec_push [s] v a ) ^ v }

@ mkc s a → ( @ i ) { ^ \ → i { ^ ( strlen a ) } }

@ back_vec → ( Vec s ) { : s x ( nurl_str_cat `ab` `cd` ) ^ ( wrapv x ) }

@ back_bound → ( Vec s ) { : s x ( nurl_str_cat `ab` `cd` ) : ( Vec s ) w ( wrapv x ) ^ w }

@ back_clo → ( @ i ) { : s x ( nurl_str_cat `ab` `cd` ) ^ ( mkc x ) }

@ main → i {
    : ( Vec s ) a ( back_vec )
    : ( Vec s ) b ( back_bound )
    : ( @ i ) f ( back_clo )
    ^ + ( f ) + ( vec_len [s] a ) ( vec_len [s] b )
}
