// let_block_join_locals_returned: agora #222 — `: String t { : String a … : String b … ? c a b }` then `^ t`: a typed binding of a value block whose tail is a join over the block's own locals (let_block_join_locals_returned).
// Closed: a typed `:` binding of a value block is elaborated (the binding first, the block's tail assigned to it before the block's names end); the join lends the block's locals, which end first, so the value is copied in where it does (rule (A), mem_join_copy_slot).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #222: a typed binding of a block whose tail is a join over its own locals, handed back
$ `stdlib/core/string.nu`

@ pick b c → String {
    : String t {
        : String a ( string_from `a string long enough for a heap buffer` )
        : String b ( string_from `another string long enough for a heap buffer` )
        ? c a b
    }
    ^ t
}

@ main → i {
    : String x ( pick T )
    : String y ( pick F )
    ( nurl_println_int + ( string_len x ) ( string_len y ) )
    ^ 0
}
