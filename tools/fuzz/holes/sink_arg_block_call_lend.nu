// sink_arg_block_call_lend: agora #189 — `( keep { : W w ( mkw ) ( gets w ) } )`, `keep` taking a `sink`: the block's lend of its own local went to the callee as its own (sink_arg_block_call_lend).
// Closed: An argument that is a block whose tail is a call (g_blk_tail_eff) takes that call's lentness (arg_eff_tt): a `sink` gets a copy of what the call lends, and a value that cannot be copied is refused (agora #189).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h860 | agora #189: `( keep { : W w ( mkw ) ( gets w ) } )`, `keep` taking a `sink`: the block's lend of its own local went to the callee as its own
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ keep sink String x → i { ^ ( string_len x ) }

@ main → i {
    : i n ( keep {
        : W w ( mkw )
        ( gets w )
    } )
    ( nurl_println_int n )
    ^ 0
}
