// try_block_fail_drops_locals: agora #202 — the same over a block `\ { ? c o p }` (try_block_fail_drops_locals).
// Closed: A try's fail path leaves the function as `^` does (gen_ret_term): the tried binding is skipped as `^ o` skips it, and a failure that owns nothing raises no question for any other operand (agora #202).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h931 | agora #202: the same over a block `\ { ? c o p }`
$ `stdlib/core/string.nu`

@ f ? i o ? i p b c → ?i {
    : String s ( string_from `a string long enough for a heap buffer` )
    : i v \ { ? c o p }
    ( nurl_println_int ( string_len s ) )
    ^ @ ?i { T + v 1 }
}

@ main → i {
    ?? ( f @ ?i { F 0 } @ ?i { T 1 } T ) { T x → ( nurl_println_int x ) F → ( nurl_println `none` ) }
    ^ 0
}
