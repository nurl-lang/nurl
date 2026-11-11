// raw_string_or_slice_struct_released_at_a_return_above_the_defer_that_keeps_it: `: s raw ( nurl_str_cat … )`, an early `^`, then a defer that reads `raw`; the same with a struct holding a slice.
// Closed: a raw string and a struct's owned fields that a `;` defer keeps back have the "left to the cleanup" flag a value with a destructor has (#630): set where an exit or a scope's end skips them because the defer keeps them, and fn_cleanup releases them under it. The early return, compiled before the defer kept anything back, releases them itself, and fn_cleanup released them again (agora #653).
// main 0b31ade: accepted; AddressSanitizer: attempting double-free (the raw string), double-free / bad-free (the struct's slice).
// map: §7.1 | A2 | runs-clean | - | agora #653: a raw string or a struct with a slice field released at a `^` between its binding and the `;` defer that keeps it — and again by the cleanup
$ `stdlib/core/string.nu`

: Q {
    [i xs
    i n
}

@ sum [i xs → i {
    : ~ i t 0
    ~ w xs { = t + t w }
    ^ t
}

@ raw i n → i {
    : i z + n 1
    ; { ( nurl_println `raw: first defer` ) }
    : s r ( nurl_str_cat `a raw string ` `made on the heap, long enough` )
    ? > n 1 { ^ z } {}
    ; { ( nurl_println r ) }
    ^ + n z
}

@ field i n → i {
    ; { ( nurl_println `field: first defer` ) }
    : Q q @ Q { [i | 1 2 3 n] n }
    ? == n 1 { ^ 1 } {}
    ; { ( nurl_println_int ( sum . q xs ) ) }
    ^ n
}

@ main → i {
    ( nurl_println_int ( raw 1 ) )
    ( nurl_println_int ( raw 2 ) )
    ( nurl_println_int ( field 1 ) )
    ( nurl_println_int ( field 0 ) )
    ^ 0
}
