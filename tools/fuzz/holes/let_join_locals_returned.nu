// let_join_locals_returned: agora #242 — `: String t ? c a b` over two local Strings, then `^ t`: the caller got `a`'s buffer, released by `a` on the way out (let_join_locals_returned).
// Closed: a `:` binding of a join takes the owner its arm selects on that path (docs/MEMORY.md §2.2), as `^ ? c a b` does: `a`'s flag goes to `t` (mem_arm_hown, g_join_rdepth 0; agora #242).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.2 | A2 | runs-clean | - | agora #242: a `?` over two local Strings bound by `:` and handed back by name: the selected owner was left releasing it
$ `stdlib/core/string.nu`

@ pick b c → String {
    : String a ( string_from `alpha string long enough for a heap buffer` )
    : String b ( string_from `beta string long enough for a heap buffer` )
    : String t ? c a b
    ^ t
}

@ main → i {
    : String r ( pick T )
    : String q ( pick F )
    ( nurl_println_int + ( string_len r ) ( string_len q ) )
    ^ 0
}
