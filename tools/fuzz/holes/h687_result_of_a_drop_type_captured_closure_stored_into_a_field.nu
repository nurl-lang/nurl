// H687: as h683, the capture a !D i.
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

@ make inout H r → v {
    : !D i o @ !D i { T ( mkd 1 ) }
    : ( @ i ) f \ → i { ^ ?? o { T d → . d n F _ → 0 } }
    = . r cb f
}

@ main → i { : ~ H h @ H { \ → i { ^ 0 } 0 } ( make h ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
