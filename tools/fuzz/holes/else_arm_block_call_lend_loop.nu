// else_arm_block_call_lend_loop: agora #191 — the same in the else arm (else_arm_block_call_lend_loop).
// Closed: An arm whose value is a call's lend out of a binding the arm owns itself copies it on those paths (mem_arm_take_call), so the arm hands over a value of its own and its locals are dropped at its exit even when the join's value is consumed (agora #191).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h847 | agora #191: the same in the else arm
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ main → i {
    : ~ i k 0
    : ~ i t 0
    ~ < k 3 {
        : b c == % k 2 0
        : String r ? c ( string_from `fresh` ) {
            : W w ( mkw )
            ( gets w )
        }
        = t + t ( string_len r )
        = k + k 1
    }
    ( nurl_println_int t )
    ^ 0
}
