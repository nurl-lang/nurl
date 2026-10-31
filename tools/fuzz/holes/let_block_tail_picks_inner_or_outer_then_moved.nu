// let_block_tail_picks_inner_or_outer_then_moved: agora #222 — the same, then `outer` handed to a `sink` before the binding is read (let_block_tail_picks_inner_or_outer_then_moved).
// Closed: the binding still borrows `outer` on the paths the call lends it (rule (A) copies only what the block's locals lend), so reading it after `outer` moved is refused.
// main: rejected.
// map: §7.6 | A2 | rejected | - | agora #222: a block's tail call lending its own local or an outer binding, the outer one then moved
$ `stdlib/core/string.nu`

: W { String s }

@ pick W a W b b c → String { ? c { ^ . a s } { ^ . b s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ eat sink W w → i { ^ ( string_len . w s ) }

@ main → i {
    : W outer ( mkw )
    : String r {
        : W w ( mkw )
        ( pick w outer F )
    }
    ( eat outer )
    ( nurl_println_int ( string_len r ) )
    ^ 0
}
