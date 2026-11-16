// raw_view_chained_through_a_value_block_local_handed_back: `: s e { : s t ( nurl_str_cat … ) : s w t  w }  ^ e` — the bare `: s t …  : s w t  ^ w` is refused.
// Closed: a value block's bindings are the enclosing scope's to the walk as they are to codegen — its `vblock` row ends their names at the `}`, not their lives, which end where the enclosing scope does (agora #846). A view's source expression naming a binding of the block names one the walk still tracks (agora #847).
// main 525613d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #847: a raw view chained through a value block's binding, handed back
$ `stdlib/core/string.nu`

@ f → s {
    : s e { : s t ( nurl_str_cat `a heap string long enough to be on the heap ` `for sure, and then some` ) : s w t w }
    ^ e
}

@ main → i { : s r ( f ) ( nurl_println r ) ^ 0 }
