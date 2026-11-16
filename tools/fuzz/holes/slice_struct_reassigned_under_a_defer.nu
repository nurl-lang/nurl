// slice_struct_reassigned_under_a_defer:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #841.
// map: §7.6 | A2 | runs-clean | - | agora #841: `: ~ Q q @ Q { [i | 1 n] n }  ; { … }  = q @ Q { [i | 10 n] n }`: the old slice of a struct a defer holds leaks
$ `stdlib/core/string.nu`

: Q { [i xs i n }

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

@ run i n → i {
    : ~ Q q @ Q { [i | 1 n] n }
    ; { ( nurl_println_int ( sum . q xs ) ) }
    = q @ Q { [i | 10 n] n }
    ^ . q n
}

@ main → i { ( nurl_println_int ( run 2 ) ) ^ 0 }
