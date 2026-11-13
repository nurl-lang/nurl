// returned_lend_of_a_block_argument_generic: `^ ( idg [String] { : String t ( mk c ) t } )`: the call handed back t, which this frame released on the way out (agora #833).
// Closed: a value block argument whose tail is a binding of its own stands for that binding in the call's roster codegen's lend questions read (`__last_call_args__`), so the lend is copied on the way out as `^ ( f t )`'s is (agora #833).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #833: a returned generic lend of a block argument's binding (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ mkv i c → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk c ) ) ^ v }

@ idg [T] T x → T { ^ x }

@ h i c → String { ^ ( idg [String] { : String t ( mk c ) t } ) }

@ main → i {
    : String b ( h 1 )
    ( nurl_println ( string_data b ) )
    ^ 0
}
