// element_view_chained_through_a_value_block_local_handed_back: `: s e { : ( Vec String ) t … : s w ( string_data ( vec_at t 0 ) )  w }  ^ e` — a view of an element of the block's Vec.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846). A view's source expression naming a binding of the block names one the walk still tracks (agora #847).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #847: an element view chained through a value block's binding, handed back
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk i k → s { : s e { : ( Vec String ) t ( vec_new [String] ) ( vec_push [String] t ( string_from `an element long enough to live on the heap for sure` ) ) : s w ( string_data ( vec_at [String] t 0 ) ) w } ^ e }

@ main → i { ( nurl_println ( mk 7 ) ) ^ 0 }
