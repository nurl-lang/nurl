// returned_block_tail_vec_of_views_of_a_param: `^ { : ~ ( Vec s ) w …  ( vec_push [s] w ( string_data p ) )  w }`, the caller then gives its argument a new value (agora #663).
// Closed: a value block that is the whole value of a `^` records its `endblock` row after the `ret` row (g_ret_blk_exit), and the return names its tail binding: the walk judges `^ { … d }` as `^ d` (agora #663).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #663: a returned block tail Vec holding a view of a parameter (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

: V { s d }

@ f String p → ( Vec s ) { ^ { : ~ ( Vec s ) w ( vec_new [s] ) ( vec_push [s] w ( string_data p ) ) w } }

@ main → i {
    : ~ String a ( mk 1 )
    : ( Vec s ) v ( f a )
    = a ( mk 2 )
    ( nurl_println ( vec_at [s] v 0 ) )
    ^ 0
}
