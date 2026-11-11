// loop_element_wrapped_handed_back_beside_a_fresh_wrap_runs_clean: agora #635 — `~ x v { … ^ @ ?D { T x } … }` beside `^ @ ?D { F }`, and `^ @ W { x 1 }` beside a fresh `W`: the literal lends the element with the Vec parameter it is part of.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #635: `~ x v { … ^ @ ?D { T x } … }` beside `^ @ ?D { F }`, and `^ @ W { x 1 }` beside a fresh `W`: the literal lends the element with the Vec parameter it is part of
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: W { Bomb b i n }

@ f ( Vec Bomb ) v → ?Bomb {
    ~ x v { ? == . x boom 0 { ^ @ ?Bomb { T x } } {} }
    ^ @ ?Bomb { F }
}

@ g ( Vec Bomb ) v → W {
    ~ x v { ? == . x boom 0 { ^ @ W { x 1 } } {} }
    ^ @ W { ( bomb `fresh` 0 ) 2 }
}

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `e0` 0 ) )
    ( vec_push [Bomb] v ( bomb `e1` 0 ) )
    : ?Bomb r ( f v )
    ?? r { T b → { ( see `main` b ) } F → {} }
    : W w ( g v )
    ( see `main` . w b )
    : ~ ( Vec Bomb ) e ( vec_new [Bomb] )
    : W w2 ( g e )
    ( see `main` . w2 b )
    ( nurl_println_int ( vec_len [Bomb] v ) )
    ^ 0
}
