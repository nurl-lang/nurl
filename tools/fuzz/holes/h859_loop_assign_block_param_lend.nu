// H859: agora #190 — the block's call lending a parameter: still a lend, no copy (loop_assign_block_param_lend).
// Closed: A value block whose tail call (g_blk_tail_eff) may lend what was bound below the assigned binding — the block's own locals, which live to the end of the enclosing scope — is copied in place after the store, and the binding owns it (mem_blk_tail_copy_slot; agora #190). One that cannot be copied is refused.
// main: accepted and ran clean (kept as a guard: no copy).
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ run W p → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 3 {
        = out {
            : i z 1
            ( gets p )
        }
        = k + k 1
    }
    ^ ( string_len out )
}

@ main → i {
    : W p ( mkw )
    ( nurl_println_int ( run p ) )
    ^ 0
}
