// closure_fresh_join_fall: agora #186 — a closure whose fall-off value is a `?` over two fresh Strings: the value it hands back was copied and the original leaked (closure_fresh_join_fall).
// Closed: A closure body's tail join says what it owns past the body's scope (gen_block_expr): a fresh value is handed over, not copied and leaked; a local moved out by `^` is the caller's (agora #186).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h811 | agora #186: a closure whose fall-off value is a `?` over two fresh Strings: the value it hands back was copied and the original leaked
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ String b ) f \ b c → String { ? c ( string_from `first fresh string long enough for a heap buffer` ) ( string_from `second fresh string long enough for a heap buffer` ) }
    : String a ( f T )
    : String b ( f F )
    ( nurl_println_int + ( string_len a ) ( string_len b ) )
    ^ 0
}
