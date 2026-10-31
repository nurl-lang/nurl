// loop_assign_nested_block_call_lend: agora #190 — the same through a nested block (loop_assign_nested_block_call_lend).
// Closed: A value block whose tail call (g_blk_tail_eff) may lend what was bound below the assigned binding — the block's own locals, which live to the end of the enclosing scope — is copied in place after the store, and the binding owns it (mem_blk_tail_copy_slot; agora #190). One that cannot be copied is refused.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h856 | agora #190: the same through a nested block
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 3 {
        = out {
            : W w ( mkw )
            {
                : i z 1
                ( gets w )
            }
        }
        = k + k 1
    }
    ( nurl_println_int ( string_len out ) )
    ^ 0
}
