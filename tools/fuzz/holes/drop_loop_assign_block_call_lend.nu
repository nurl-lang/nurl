// drop_loop_assign_block_call_lend: agora #190 — the same with a `% Drop` value: it cannot be copied (drop_loop_assign_block_call_lend).
// Closed: A value block whose tail call (g_blk_tail_eff) may lend what was bound below the assigned binding — the block's own locals, which live to the end of the enclosing scope — is copied in place after the store, and the binding owns it (mem_blk_tail_copy_slot; agora #190). One that cannot be copied is refused.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h857 | agora #190: the same with a `% Drop` value: it cannot be copied
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getd H h → D { ^ . h d }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ main → i {
    : ~ D out @ D { ( string_from `start` ) }
    : ~ i k 0
    ~ < k 3 {
        = out {
            : H h ( mkh )
            ( getd h )
        }
        = k + k 1
    }
    ( nurl_println_int ( string_len . out s ) )
    ^ 0
}
