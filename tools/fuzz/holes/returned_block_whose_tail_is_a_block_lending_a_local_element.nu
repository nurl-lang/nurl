// returned_block_whose_tail_is_a_block_lending_a_local_element: `^ { { : ( Vec String ) u ( mkv c )  : String t ( vec_at [String] u 0 )  t } }`: the element was handed back, then released with u (agora #663).
// Closed: a block's tail that is itself a block hands up that block's first token (`{ { v } }` ends in `v`), so `^` hands the binding back by `^ v`'s rules: a parameter or a lend is copied (gen_block_expr, `__tail_first_deep__`; agora #663).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #663: a returned block whose inner block lends a local element (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ mkv i c → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk c ) ) ^ v }

@ idg [T] T x → T { ^ x }

@ f i c → String { ^ { { : ( Vec String ) u ( mkv c ) : String t ( vec_at [String] u 0 ) t } } }

@ main → i {
    : String b ( f 1 )
    ( nurl_println ( string_data b ) )
    ^ 0
}
