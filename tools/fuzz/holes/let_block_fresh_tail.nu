// let_block_fresh_tail: agora #242 — `: String t { : i k 1 ( string_from … ) }`: the binding was taken for a borrow of the block's value, and the fresh String leaked (let_block_fresh_tail).
// Closed: a `:` binding of a block ending in a call that lends none of the block's locals takes that call's ownership answer, as the call bound directly does (__blk_bind_tt; agora #242).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #242: a value block ending in a fresh call, bound by `:`: taken for a borrow, the String leaked
$ `stdlib/core/string.nu`

@ main → i {
    : String t { : i k 1 ( string_from `a string long enough for a heap buffer` ) }
    : String u { ( string_from `another string long enough for a heap buffer` ) }
    ( nurl_println_int + ( string_len t ) ( string_len u ) )
    ^ 0
}
