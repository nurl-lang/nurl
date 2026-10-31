// match_arm_block_call_lend_returned: agora #191 — the same through a returned `??` (match_arm_block_call_lend_returned).
// Closed: An arm whose value is a call's lend out of a binding the arm owns itself copies it on those paths (mem_arm_take_call), so the arm hands over a value of its own and its locals are dropped at its exit even when the join's value is consumed (agora #191).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h850 | agora #191: the same through a returned `??`
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick ? i o → String {
    ^ ?? o {
        T x → {
            : W w ( mkw )
            ( gets w )
        }
        F → ( string_from `fresh` )
    }
}

@ main → i {
    : String a ( pick @ ?i { T 1 } )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
