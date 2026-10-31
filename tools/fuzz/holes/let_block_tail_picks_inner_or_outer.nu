// let_block_tail_picks_inner_or_outer: agora #222 — a block's tail call lends either the block's own local or an outer binding (`( pick w outer c )`): copied where it lends the local, a borrow of `outer` where it lends that (let_block_tail_picks_inner_or_outer).
// Closed: kept as a guard — rule (A) leaves only the block's locals out of the call's lend sources (`callee!w`, bck_take_plend), so the binding still borrows `outer`.
// main: accepted and ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #222: a block's tail call lending its own local or an outer binding (precision pin)
$ `stdlib/core/string.nu`

: W { String s }

@ pick W a W b b c → String { ? c { ^ . a s } { ^ . b s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : W outer ( mkw )
    : String r {
        : W w ( mkw )
        ( pick w outer F )
    }
    ( nurl_println_int ( string_len r ) )
    : String q {
        : W w2 ( mkw )
        ( pick w2 outer T )
    }
    ( nurl_println_int ( string_len q ) )
    ^ 0
}
