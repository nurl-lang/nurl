// returned_block_tail_view_of_a_block_local: `^ { : String t ( mk c )  : s d ( string_data t )  d }`: a view of the block's local, released on the way out (agora #663).
// Closed: a value block that is the whole value of a `^` records its `endblock` row after the `ret` row (g_ret_blk_exit), and the return names its tail binding: the walk judges `^ { … d }` as `^ d` (agora #663).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #663: a returned block tail viewing a block local (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ mkv i c → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk c ) ) ^ v }

@ idg [T] T x → T { ^ x }

@ f i c → s { ^ { : String t ( mk c ) : s d ( string_data t ) d } }

@ main → i {
    : s v ( f 1 )
    ( nurl_println v )
    ^ 0
}
