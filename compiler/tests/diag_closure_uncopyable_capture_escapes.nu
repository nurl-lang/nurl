// diag_closure_uncopyable_capture_escapes.nu — a closure holds a copy of
// the handle of what it captured by value; stored into an owner it copies
// in what it can (adopt) — but a value with no Clone (a Vec of `% Drop`
// values, an option of one, a trait object, a closure) stays the frame's.
// Such a closure may not outlive the frame: returned inside a struct, or
// stored into storage the caller holds (agora #161, h680–h688).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string that owns a heap buffer` ) n } }

: H { ( @ i ) cb i pad }

@ make → H {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd 1 ) )
    : ( @ i ) f \ → i { ^ ( vec_len [D] v ) }
    ^ @ H { f 0 }
}

@ keep ( Vec ( @ i ) ) out → v {
    : ( Vec D ) w ( vec_new [D] )
    ( vec_push [D] w ( mkd 2 ) )
    : ( @ i ) g \ → i { ^ ( vec_len [D] w ) }
    ( vec_push [( @ i )] out g )
}

@ main → i {
    : H h ( make )
    : ( Vec ( @ i ) ) o ( vec_new [( @ i )] )
    ( keep o )
    : ( @ i ) c . h cb
    ^ ( c )
}
