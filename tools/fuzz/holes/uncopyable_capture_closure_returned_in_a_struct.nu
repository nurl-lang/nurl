// uncopyable_capture_closure_returned_in_a_struct: a closure over a ( Vec D ) — D with a Drop of its own, so the Vec
// has no Clone — returned inside a struct literal. Storing a closure into
// an owner adopts it: what it views it copies in, but a Vec it cannot copy
// stays a copy of the frame's handle, released at the return; the caller
// ran the closure on freed memory. (`^ f` itself was rejected: h310.)
// Closed: the capture is tagged `\~!(…)` (gen_closure_expr), its handle
// copy marked one no owner can copy in (`nch_`): adopting the closure keeps
// it, so the escape is the view of a released binding it is (agora #161).
// v0.80.0: HOLE (heap-use-after-free).
// map: §2.11 | A2 | rejected | h680 | agora #161: a closure over a ( Vec D ) (D with a Drop, no Clone) returned inside a struct literal: adopting it could not copy the Vec in, its copy was the frame's released handle (UAF)
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
    ^ @ H { f 0 }
}

@ main → i { : H h ( make ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
