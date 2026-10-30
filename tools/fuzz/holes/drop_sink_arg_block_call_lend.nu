// drop_sink_arg_block_call_lend: agora #189 — the same with a `% Drop` value: it cannot be copied (drop_sink_arg_block_call_lend).
// Closed: An argument that is a block whose tail is a call (g_blk_tail_eff) takes that call's lentness (arg_eff_tt): a `sink` gets a copy of what the call lends, and a value that cannot be copied is refused (agora #189).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h861 | agora #189: the same with a `% Drop` value: it cannot be copied
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getd H h → D { ^ . h d }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ keep sink D x → i { ^ ( string_len . x s ) }

@ main → i {
    : i n ( keep {
        : H h ( mkh )
        ( getd h )
    } )
    ( nurl_println_int n )
    ^ 0
}
