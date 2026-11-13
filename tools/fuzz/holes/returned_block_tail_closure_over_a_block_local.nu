// returned_block_tail_closure_over_a_block_local: `^ { : String tag ( mk c )  : ( @ i i ) clo \ i x → i { … tag … }  clo }`: a closure over the block's local (agora #638 item 1) (agora #663).
// Closed: a value block that is the whole value of a `^` records its `endblock` row after the `ret` row (g_ret_blk_exit), and the return names its tail binding: the walk judges `^ { … d }` as `^ d` (agora #663).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #663: a returned block tail closure over a block local (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

: V { s d }

@ f i c → ( @ i i ) { ^ { : String tag ( mk c ) : ( @ i i ) clo \ i x → i { ^ + x ( string_len tag ) } clo } }

@ main → i {
    : ( @ i i ) g ( f 1 )
    ( nurl_println_int ( g 1 ) )
    ^ 0
}
