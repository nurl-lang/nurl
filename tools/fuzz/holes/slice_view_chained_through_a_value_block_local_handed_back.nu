// slice_view_chained_through_a_value_block_local_handed_back: `: ( Slice String ) e { : ~ ( Vec String ) t … : ( Slice String ) w ( slice_from_vec t )  w }  ^ e`.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846). A view's source expression naming a binding of the block names one the walk still tracks (agora #847).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #847: a slice view chained through a value block's binding, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f → ( Slice String ) {
    : ( Slice String ) e { : ~ ( Vec String ) t ( vec_new [String] ) ( vec_push [String] t ( string_from `an element long enough to live on the heap for sure` ) ) : ( Slice String ) w ( slice_from_vec [String] t ) w }
    ^ e
}

@ main → i { : ( Slice String ) r ( f ) ( nurl_println ( string_data ( slice_at [String] r 0 ) ) ) ^ 0 }
