// H685: as h684 over a ( Vec String ), which has a Clone: adopting the
// outer closure copies in nothing a captured closure views (gen_env_vtable
// clones a captured closure in as it is).
// Closed: a captured closure is tagged `\~*(…)` (gen_closure_expr): the
// handle copies it holds are marked ones no owner can copy in (`nch_`), so
// adopting the closure that captured it keeps them, and the escape is the
// view of a released binding it is (agora #161).
// v0.80.0: HOLE (heap-use-after-free).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

: H { ( @ i ) cb i pad }

@ make → H {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to own a heap buffer here` ) )
    : ( @ i ) f \ → i { ^ ( vec_len [String] v ) }
    ^ @ H { \ → i { ^ ( f ) } 0 }
}

@ main → i { : H h ( make ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
