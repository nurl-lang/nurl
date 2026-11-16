// slice_returned_by_a_closure_call:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #841.
// map: §7.6 | A2 | runs-clean | - | agora #841: `: ( @ [i i ) mk \ i a → [i { … ^ xs }  : [i ys ( mk n )`: a slice returned through a closure call is never released
$ `stdlib/core/string.nu`

@ sum [i xs → i { : ~ i t 0 ~ x xs { = t + t x } ^ t }

@ main → i {
    : ( @ [i i ) mk \ i a → [i { : [i xs [i | a a a a a a a a] ^ xs }
    : [i ys ( mk 3 )
    ( nurl_println_int ( sum ys ) )
    ^ 0
}
