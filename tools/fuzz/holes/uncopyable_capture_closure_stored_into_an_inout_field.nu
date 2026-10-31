// uncopyable_capture_closure_stored_into_an_inout_field: as h680, the closure stored into a field of the caller's struct
// through an `inout` parameter.
// Closed: the capture is tagged `\~!(…)` (gen_closure_expr), its handle
// copy marked one no owner can copy in (`nch_`): adopting the closure keeps
// it, so the escape is the view of a released binding it is (agora #161).
// v0.80.0: HOLE (heap-use-after-free).
// map: §2.11 | A2 | rejected | h683 | agora #161: as h680, the closure stored into a field of the caller's struct through inout
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: H { ( @ i ) cb i pad }

@ make inout H r → v {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd 1 ) )
    : ( @ i ) f \ → i { ^ ( vec_len [D] v ) }
    = . r cb f
}

@ main → i { : ~ H h @ H { \ → i { ^ 0 } 0 } ( make h ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
