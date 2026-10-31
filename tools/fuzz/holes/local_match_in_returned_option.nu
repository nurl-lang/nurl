// local_match_in_returned_option: agora #184 — an option literal returned with a `??` over a local option as its payload (local_match_in_returned_option).
// Closed: a returned option or result literal whose payload is a `?` / `??` that lent this function's own value copies it, as `^ ?` does; only a lend of the caller's value is answered per call (__phi_lends_params_only; agora #184).
// main: ran clean (kept so it stays clean).
// map: §7.6 | A2 | runs-clean | h772 | agora #184: an option literal returned with a `??` over a local option as its payload
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part i n → ?String {
    : ?String o @ ?String { T ( mk ) }
    ^ @ ?String { T ?? o { T s → s F → ( mk ) } }
}

@ main → i {
    : ?String t ( part 1 )
    ( nurl_println_int ?? t { T s → ( string_len s ) F → 0 } )
    ^ 0
}
