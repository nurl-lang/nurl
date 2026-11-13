// returned_block_tail_struct_of_views_of_a_block_local: `^ { : String t ( mk c )  : V w @ V { ( string_data t ) }  w }`: a struct of views of the block's local (agora #663).
// Closed: a value block that is the whole value of a `^` records its `endblock` row after the `ret` row (g_ret_blk_exit), and the return names its tail binding: the walk judges `^ { … d }` as `^ d` (agora #663).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #663: a returned block tail holding a view of a block local (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

: V { s d }

@ f i c → V { ^ { : String t ( mk c ) : V w @ V { ( string_data t ) } w } }

@ main → i {
    : V v ( f 1 )
    ( nurl_println . v d )
    ^ 0
}
