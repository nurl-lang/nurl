// returned_lend_of_a_block_argument: `^ ( id { : String t ( mk c ) t } )` over `@ id String x → String { ^ x }` (agora #833).
// Closed: a value block argument whose tail is a binding of its own stands for that binding in the call's roster codegen's lend questions read (`__last_call_args__`), so the lend is copied on the way out as `^ ( f t )`'s is (agora #833).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #833: a returned lend of a block argument's binding (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i c → String { ^ ( string_from `a heap string long enough for the heap buffer` ) }

@ idg [T] T x → T { ^ x }

@ id String x → String { ^ x }

@ eat sink String x → i { ^ ( string_len x ) }

@ h i c → String { ^ ( id { : String t ( mk c ) t } ) }

@ main → i { : String b ( h 1 ) ( nurl_println ( string_data b ) ) ^ 0 }
