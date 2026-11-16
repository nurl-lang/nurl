// option_payload_slice:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #841.
// map: §7.6 | A2 | runs-clean | - | agora #841: `: ?[i o @ ?[i { T [i | 1 2] }`: an option payload that owns a slice is never released
$ `stdlib/core/string.nu`

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

@ main → i {
    : ?[i o @ ?[i { T [i | 1 2] }
    ?? o { T q → ( nurl_println_int ( sum q ) ) F → ( nurl_println_int 0 ) }
    ^ 0
}
