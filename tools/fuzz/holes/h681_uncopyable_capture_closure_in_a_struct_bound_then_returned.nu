// H681: as h680, with the struct bound first and returned by name: the
// capture, modelled as stored into the struct (bck_borrow_transfer), was
// no dependency of it any more.
// Closed: the capture is tagged `\~!(…)` (gen_closure_expr), its handle
// copy marked one no owner can copy in (`nch_`): adopting the closure keeps
// it, so the escape is the view of a released binding it is (agora #161).
// v0.80.0: HOLE (heap-use-after-free).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: H { ( @ i ) cb i pad }

@ make → H {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd 1 ) )
    : ( @ i ) f \ → i { ^ ( vec_len [D] v ) }
    : H h @ H { f 0 }
    ^ h
}

@ main → i { : H h ( make ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
