// let_block_outer_lend_guard: agora #193 — the block's call lending a binding made before the block (`( gets p )`): still a lend, no copy (let_block_outer_lend_guard).
// Closed: A `:` binding of a value block whose tail call lends a binding made while the block ran — its own locals, which live only to the end of the enclosing scope — copies the value in place, and the binding owns it (gen_let_or_struct: mem_blk_tail_deeper_args from the first register the right-hand side took, then mem_blk_tail_copy_slot; agora #193). The walk takes the value for what those locals held (h216); this makes it so. One that cannot be copied is refused.
// main: accepted and ran clean (kept as a guard: no copy).
// map: §7.6 | A2 | runs-clean | h879 | agora #193: the block's call lending a binding made before the block: still a lend, no copy
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : ~ String out ( string_from `start` )
    : W p ( mkw )
    : ~ i k 0
    ~ < k 3 {
        : String r {
            : i z k
            ( gets p )
        }
        = out r
        = k + k 1
    }
    ( nurl_println_int ( string_len out ) )
    ^ 0
}
