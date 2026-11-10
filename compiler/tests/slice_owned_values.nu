// slice_owned_values.nu — a `[T` slice is an owned value like a String or a
// Vec (agora #545, #540, #510): its binding releases its buffer once, a
// second owner gets a buffer of its own (a parameter, a field of a live
// binding, a mutable copy) or takes the first one's (an immutable binding
// of a local, a struct or enum built over it, a return), and a struct, an
// enum, an option or a result that holds one releases it with itself.
// Every shape here read freed memory, freed a buffer twice or leaked one
// before; the sanitizer run (run_san_tests.sh) is what holds them.
// #545: an owned binding handed to an enum payload moves into it
: | BoxBox { BoxFull [i BoxEmpty }
@ box_mk → [i { ^ [i | 1 2] }
@ box_boxit → BoxBox { : [i q ( box_mk ) ^ @ BoxBox { BoxFull q } }
@ run_box → i {
    : BoxBox b ( box_boxit )
    ?? b { BoxFull sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } BoxEmpty → {} }
    ^ 0
}

// #545: …and to a struct field
: HoldHolder { [i items i n }
@ hold_mk → [i { ^ [i | 1 2] }
@ hold_hold → HoldHolder { : [i q ( hold_mk ) ^ @ HoldHolder { q 1 } }
@ run_hold → i {
    : HoldHolder h ( hold_hold )
    ~ x . h items { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #545: …and to another binding, which is then returned
@ via_mk → [i { ^ [i | 1 2] }
@ via_via → [i { : [i q ( via_mk ) : [i r q ^ r }
@ run_via → i {
    : [i a ( via_via )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #545: a parameter assigned to an owned binding is copied (the caller keeps its buffer)
@ asgp_f [i p → i {
    : ~ [i d [i | 1 2 3]
    = d p
    ^ . d length
}
@ run_asgp → i {
    : [i a [i | 5 6]
    ( nurl_println ( nurl_str_int ( asgp_f a ) ) )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #545: an inout slice given a parameter (a copy) or a literal; the old buffer is released once
@ inout_setq inout [i p [i q → v { = p q }
@ inout_setl inout [i p → v { = p [i | 3 4] }
@ run_inout → i {
    : ~ [i d [i | 1 2]
    : [i q [i | 9 9 9]
    ( inout_setq d q )
    ~ x d { ( nurl_println ( nurl_str_int x ) ) }
    : ~ [i e [i | 1 2]
    ( inout_setl e )
    ~ x e { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #545: two owners swapped through a third, once and in a loop
@ run_swap → i {
    : ~ [i a [i | 1 2]
    : ~ [i b [i | 3 4 5]
    : ~ [i t [i | 0]
    = t a
    = a b
    = b t
    : ~ i k 0
    ~ < k 2 {
        : [i u a
        = a b
        = b u
        = k + k 1
    }
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ~ x b { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #540: the function's own slice on one path, its parameter (a copy) on another
@ mixed_pick b c [i p → [i {
    ? c { ^ p } {}
    : [i s [i | 1 2]
    ^ s
}
@ mixed_pick_lit b c [i p → [i {
    ? c { ^ p } {}
    ^ [i | 3 4]
}
@ run_mixed → i {
    : [i a [i | 5 6]
    : [i r ( mixed_pick T a )
    : [i q ( mixed_pick F a )
    : [i t ( mixed_pick_lit T a )
    : [i u ( mixed_pick_lit F a )
    ~ x r { ( nurl_println ( nurl_str_int x ) ) }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ~ x t { ( nurl_println ( nurl_str_int x ) ) }
    ~ x u { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}

// #510: a callee declared below its caller, and a generic one
@ run_below → i {
    { : [i sl ( below_mk ) ~ x sl { ( nurl_println ( nurl_str_int x ) ) } }
    : [i g ( below_mkg [i] 1 2 )
    ~ x g { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
@ below_mk → [i { : [i s [i | 1 2 3] ^ s }
@ below_mkg [T] T a T b → [T { : [T s [T | a b] ^ s }

// a call's result passed straight to a call
@ argc_mk → [i { ^ [i | 1 2 3] }
@ argc_sum [i p → i { : ~ i t 0 ~ x p { = t + t x } ^ t }
@ run_argc → i { ( nurl_println ( nurl_str_int ( argc_sum ( argc_mk ) ) ) ) ^ 0 }

// a literal passed straight to a call
@ argl_sum i z [i p → i { : ~ i t z ~ x p { = t + t x } ^ t }
@ run_argl → i { ( nurl_println ( nurl_str_int ( argl_sum 0 [i | 1 2 3] ) ) ) ^ 0 }

// a local returned
@ retl_mk → [i { : [i a [i | 1 2 3] ^ a }
@ run_retl → i { : [i b ( retl_mk ) ~ x b { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a parameter returned
@ retp_id [i p → [i { ^ p }
@ run_retp → i { : [i a [i | 1 2 3] : [i b ( retp_id a ) ~ x b { ( nurl_println ( nurl_str_int x ) ) } ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a ?-join of two literals
@ joinl_pick b c → i { : [i a ? c [i | 1] [i | 2 3] : ~ i t 0 ~ x a { = t + t x } ^ t }
@ run_joinl → i { ( nurl_println ( nurl_str_int + ( joinl_pick T ) ( joinl_pick F ) ) ) ^ 0 }

// a ?-join of a parameter and a literal
@ joinp_pick b c [i p → i { : [i a ? c p [i | 2 3] : ~ i t 0 ~ x a { = t + t x } ^ t }
@ run_joinp → i { : [i q [i | 7 8] ( nurl_println ( nurl_str_int + ( joinp_pick T q ) ( joinp_pick F q ) ) ) ^ 0 }

// a binding per iteration
@ loop_mk i n → [i { ^ [i | n + n 1] }
@ run_loop → i { : ~ i k 0 : ~ i t 0 ~ < k 5 { : [i a ( loop_mk k ) ~ x a { = t + t x } = k + k 1 } ( nurl_println ( nurl_str_int t ) ) ^ 0 }

// a slice of slices
@ run_nest → i { : [[i a [[i | [i | 1] [i | 2 3]] ~ r a { ~ x r { ( nurl_println ( nurl_str_int x ) ) } } ^ 0 }

// an option of a slice, matched as a temporary
@ opt_f b c → ?[i { ? c { ^ @ ?[i { T [i | 1 2] } } {} ^ @ ?[i { F } }
@ run_opt → i { ?? ( opt_f T ) { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F → {} } ?? ( opt_f F ) { T sl → {} F → { ( nurl_println `none` ) } } ^ 0 }

// …built from a binding
@ optb_f b c → ?[i { ? c { : [i q [i | 1 2] ^ @ ?[i { T q } } {} ^ @ ?[i { F } }
@ run_optb → i { : ?[i o ( optb_f T ) ?? o { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F → {} } ^ 0 }

// a field given a literal, then a binding
: FstoreH { [i items i n }
@ run_fstore → i { : ~ FstoreH h @ FstoreH { [i | 1 2] 2 } = . h items [i | 5 6 7] : [i q [i | 8 9] = . h items q ~ x . h items { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a closure reading a captured slice
@ run_clo → i { : [i a [i | 10 20 30] : ( @ i i ) f \ i k → i { : ~ i t 0 ~ x a { = t + t x } ^ + t k }
    ( nurl_println ( nurl_str_int ( f 1 ) ) ) ( nurl_println ( nurl_str_int ( f 2 ) ) ) ^ 0 }

// a sink parameter given a binding and a literal
@ sink_take i z sink [i p → i { : ~ i t z ~ x p { = t + t x } ^ t }
@ run_sink → i { : [i a [i | 1 2 3] ( nurl_println ( nurl_str_int ( sink_take 0 a ) ) ) ( nurl_println ( nurl_str_int ( sink_take 0 [i | 4 5] ) ) ) ^ 0 }

// an early return past one binding and before another
@ early_f b c → i { : [i a [i | 1 2 3] ? c { ^ 1 } {} : [i b2 [i | 4] : ~ i t 0 ~ x a { = t + t x } ~ x b2 { = t + t x } ^ t }
@ run_early → i { ( nurl_println ( nurl_str_int + ( early_f T ) ( early_f F ) ) ) ^ 0 }

// a binding reassigned a literal, a call and a binding
@ reasg_mk → [i { ^ [i | 7 8 9] }
@ run_reasg → i { : ~ [i a [i | 1 2 3] = a [i | 4 5] = a ( reasg_mk ) : ~ [i b [i | 6] = a b ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a ??-join of literals
: | MatchK { MatchA MatchB }
@ match_g MatchK k → i { : [i a ?? k { MatchA → [i | 1 2] MatchB → [i | 3 4 5] } : ~ i t 0 ~ x a { = t + t x } ^ t }
@ run_match → i { ( nurl_println ( nurl_str_int + ( match_g MatchA ) ( match_g MatchB ) ) ) ^ 0 }

// a generic function's literal
@ gen_two [T] T x T y → [T { ^ [T | x y] }
@ run_gen → i { : [i a ( gen_two [i] 1 2 ) ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a struct built over a parameter: the function keeps it, so the caller's slice moves in
: WrappH { [i items i n }
@ wrapp_wrap [i p → WrappH { ^ @ WrappH { p 1 } }
@ run_wrapp → i { : [i a [i | 1 2] : WrappH h ( wrapp_wrap a ) ~ x . h items { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a parameter's field returned (a copy)
: RetfH { [i items i n }
@ retf_get RetfH h → [i { ^ . h items }
@ run_retf → i { : RetfH h @ RetfH { [i | 1 2] 2 } : [i a ( retf_get h ) ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a slice of raw strings
@ run_raws → i { : [s a [s | `one` `two`] ~ x a { ( nurl_println x ) } ^ 0 }

// the same name in two blocks
@ run_shadow → i { : ~ i t 0 { : [i a [i | 1 2] ~ x a { = t + t x } } { : [i a [i | 3 4] ~ x a { = t + t x } } ( nurl_println ( nurl_str_int t ) ) ^ 0 }

// a call's result discarded
@ unused_mk → [i { ^ [i | 1 2 3] }
@ run_unused → i { ( unused_mk ) ( nurl_println `ok` ) ^ 0 }

// two temporaries in one expression
@ tmp2_mk → [i { ^ [i | 1 2 3] }
@ tmp2_n [i p → i { : ~ i t 0 ~ x p { = t + t 1 } ^ t }
@ run_tmp2 → i { ( nurl_println ( nurl_str_int + ( tmp2_n ( tmp2_mk ) ) ( tmp2_n ( tmp2_mk ) ) ) ) ^ 0 }

// a local or a parameter returned
@ lorp_pick b c [i p → [i { ? c { ^ p } {} : [i a [i | 9 9] ^ a }
@ run_lorp → i { : [i q [i | 1 2] : [i r1 ( lorp_pick T q ) : [i r2 ( lorp_pick F q ) ~ x r1 { ( nurl_println ( nurl_str_int x ) ) } ~ x r2 { ( nurl_println ( nurl_str_int x ) ) } ~ x q { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a struct with a slice field moves between bindings
: SretH { [i items i n }
@ sret_mkh → SretH { ^ @ SretH { [i | 1 2] 2 } }
@ run_sret → i { : SretH h ( sret_mkh ) : SretH g h ~ x . g items { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a mutable binding of another binding is a copy
@ run_mcopy → i { : [i a [i | 1 2] : ~ [i c a = c [i | 5] ~ x c { ( nurl_println ( nurl_str_int x ) ) } ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a binding reassigned per iteration
@ wreasg_mk i n → [i { ^ [i | n + n 1] }
@ run_wreasg → i { : ~ [i a [i | 0] : ~ i k 0 ~ < k 4 { = a ( wreasg_mk k ) = k + k 1 } ~ x a { ( nurl_println ( nurl_str_int x ) ) } ^ 0 }

// a binding in each arm
@ run_cond → i { : b c T : ~ i t 0 ? c { : [i a [i | 1 2] ~ x a { = t + t x } } { : [i z [i | 3] ~ x z { = t + t x } } ( nurl_println ( nurl_str_int t ) ) ^ 0 }

// an option binding matched twice
@ opt2_f → ?[i { ^ @ ?[i { T [i | 1 2] } }
@ run_opt2 → i { : ?[i o ( opt2_f ) ?? o { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F → {} } ?? o { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F → {} } ^ 0 }

// an option of a slice as a struct field
: OptfH { ? [i items i n }
@ optf_mk → OptfH { ^ @ OptfH { @ ?[i { T [i | 1 2] } 2 } }
@ run_optf → i { : OptfH h ( optf_mk ) ?? . h items { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F → {} } ^ 0 }

// a result of a slice
@ res_f b c → ![i i { ? c { ^ @ ![i i { T [i | 1 2] } } {} ^ @ ![i i { F 7 } }
@ run_res → i { : ![i i o ( res_f T ) ?? o { T sl → { ~ x sl { ( nurl_println ( nurl_str_int x ) ) } } F e → {} } : ![i i p ( res_f F ) ^ 0 }

// an option's payload joined with a literal
@ unwrap_f → ?[i { ^ @ ?[i { T [i | 1 2] } }
@ unwrap_g → ?i { : [i a ?? ( unwrap_f ) { T sl → sl F → [i | 0] } : ~ i t 0 ~ x a { = t + t x } ^ @ ?i { T t } }
@ run_unwrap → i { ?? ( unwrap_g ) { T n → { ( nurl_println ( nurl_str_int n ) ) } F → {} } ^ 0 }

// an option of a slice as an argument: a binding, then a literal
@ optp_cnt ? [i o → i { ?? o { T sl → { : ~ i t 0 ~ x sl { = t + t x } ^ t } F → { ^ 0 } } }
@ run_optp → i { : ?[i o @ ?[i { T [i | 1 2] } ( nurl_println ( nurl_str_int ( optp_cnt o ) ) ) ( nurl_println ( nurl_str_int ( optp_cnt o ) ) ) ( nurl_println ( nurl_str_int ( optp_cnt @ ?[i { T [i | 4 5] } ) ) ) ^ 0 }

// a struct literal with a slice field as an argument
: LitaH { [i items i n }
: LitaK { ? [i items i n }
@ lita_sum LitaH h → i { : ~ i t 0 ~ x . h items { = t + t x } ^ t }
@ lita_sumk LitaK k → i { ?? . k items { T sl → { : ~ i t 0 ~ x sl { = t + t x } ^ t } F → { ^ 0 } } }
@ lita_mk → [i { ^ [i | 7 8] }
@ run_lita → i { : [i q [i | 5 6]
    ( nurl_println ( nurl_str_int ( lita_sum @ LitaH { [i | 1 2] 2 } ) ) )
    ( nurl_println ( nurl_str_int ( lita_sum @ LitaH { ( lita_mk ) 2 } ) ) )
    ( nurl_println ( nurl_str_int ( lita_sum @ LitaH { q 2 } ) ) )
    ( nurl_println ( nurl_str_int ( lita_sumk @ LitaK { @ ?[i { T [i | 1 2] } 2 } ) ) )
    ( nurl_println ( nurl_str_int ( lita_sumk @ LitaK { @ ?[i { T q } 2 } ) ) )
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0 }

// a field of a temporary, of a binding, and through a call
: FotH { [i items i n }
@ fot_mk → FotH { ^ @ FotH { [i | 1 2 3] 3 } }
@ fot_sum i z [i a → i { : ~ i t z ~ x a { = t + t x } ^ t }
@ fot_first FotH h → [i { ^ . h items }
@ run_fot → i {
    ( nurl_println ( nurl_str_int ( fot_sum 0 . ( fot_mk ) items ) ) )
    : FotH h ( fot_mk )
    ( nurl_println ( nurl_str_int ( fot_sum 0 . h items ) ) )
    : [i c . h items
    ( nurl_println ( nurl_str_int ( fot_sum 0 c ) ) )
    ( nurl_println ( nurl_str_int ( fot_sum 0 ( fot_first h ) ) ) )
    ( nurl_println ( nurl_str_int ( fot_sum 0 ( fot_first ( fot_mk ) ) ) ) )
    ^ 0 }

// continue, break and an early return past owned bindings
@ brk_mk i n → [i { ^ [i | n + n 1] }
@ brk_sum i z [i a → i { : ~ i t z ~ x a { = t + t x } ^ t }
@ brk_work i n → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k n {
        : [i a ( brk_mk k )
        ? == k 2 { = k + k 1 continue } {}
        ? == k 5 { break } {}
        = t + t ( brk_sum 0 a )
        : ~ [i m ( brk_mk k )
        = m ( brk_mk + k 1 )
        = m [i | 9]
        = t + t ( brk_sum 0 m )
        = k + k 1
    }
    ^ t }
@ brk_early i n → i { : [i a ( brk_mk n ) ? > n 3 { ^ 1 } {} : [i bb ( brk_mk n ) ^ ( brk_sum 0 bb ) }
@ run_brk → i { ( nurl_println ( nurl_str_int ( brk_work 8 ) ) ) ( nurl_println ( nurl_str_int + ( brk_early 1 ) ( brk_early 9 ) ) ) ^ 0 }

@ main → i {
    ( nurl_println `box` ) ( run_box )
    ( nurl_println `hold` ) ( run_hold )
    ( nurl_println `via` ) ( run_via )
    ( nurl_println `asgp` ) ( run_asgp )
    ( nurl_println `inout` ) ( run_inout )
    ( nurl_println `swap` ) ( run_swap )
    ( nurl_println `mixed` ) ( run_mixed )
    ( nurl_println `below` ) ( run_below )
    ( nurl_println `argc` ) ( run_argc )
    ( nurl_println `argl` ) ( run_argl )
    ( nurl_println `retl` ) ( run_retl )
    ( nurl_println `retp` ) ( run_retp )
    ( nurl_println `joinl` ) ( run_joinl )
    ( nurl_println `joinp` ) ( run_joinp )
    ( nurl_println `loop` ) ( run_loop )
    ( nurl_println `nest` ) ( run_nest )
    ( nurl_println `opt` ) ( run_opt )
    ( nurl_println `optb` ) ( run_optb )
    ( nurl_println `fstore` ) ( run_fstore )
    ( nurl_println `clo` ) ( run_clo )
    ( nurl_println `sink` ) ( run_sink )
    ( nurl_println `early` ) ( run_early )
    ( nurl_println `reasg` ) ( run_reasg )
    ( nurl_println `match` ) ( run_match )
    ( nurl_println `gen` ) ( run_gen )
    ( nurl_println `wrapp` ) ( run_wrapp )
    ( nurl_println `retf` ) ( run_retf )
    ( nurl_println `raws` ) ( run_raws )
    ( nurl_println `shadow` ) ( run_shadow )
    ( nurl_println `unused` ) ( run_unused )
    ( nurl_println `tmp2` ) ( run_tmp2 )
    ( nurl_println `lorp` ) ( run_lorp )
    ( nurl_println `sret` ) ( run_sret )
    ( nurl_println `mcopy` ) ( run_mcopy )
    ( nurl_println `wreasg` ) ( run_wreasg )
    ( nurl_println `cond` ) ( run_cond )
    ( nurl_println `opt2` ) ( run_opt2 )
    ( nurl_println `optf` ) ( run_optf )
    ( nurl_println `res` ) ( run_res )
    ( nurl_println `unwrap` ) ( run_unwrap )
    ( nurl_println `optp` ) ( run_optp )
    ( nurl_println `lita` ) ( run_lita )
    ( nurl_println `fot` ) ( run_fot )
    ( nurl_println `brk` ) ( run_brk )
    ^ 0
}
