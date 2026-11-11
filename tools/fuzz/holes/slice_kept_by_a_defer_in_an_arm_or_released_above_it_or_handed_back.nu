// slice_kept_by_a_defer_in_an_arm_or_released_above_it_or_handed_back: a slice bound in an arm with a defer in that arm (taken and not taken); a slice with a `^` between its binding and the defer; a slice handed back on one path, another on the other, under a defer.
// Closed: owned slices are listed by their storage (__slice_key), so fn_cleanup releases one a `;` defer kept back without its name or its scope being there still, under its "left to the cleanup" flag; and a slice handed back is the caller's on that path only (its storage's transferred flag), where it was skipped by the last name the `^` had read, on every path. An arm's kept slice was found by nobody once the arm had ended, and a slice any `^` had read was released on no path (agora #653).
// main 0b31ade: accepted; LeakSanitizer: the slice's buffer (32 bytes) in `arm` and `above`.
// map: §7.1 | A2 | runs-clean | - | agora #653: a slice a `;` defer keeps back in an arm, or that a `^` above the defer read, is released by nobody
@ sum [i xs → i {
    : ~ i t 0
    ~ w xs { = t + t w }
    ^ t
}

@ arm i n → i {
    ? > n 1 { : [i xs [i | 1 2 3 n] ; { ( nurl_println_int ( sum xs ) ) } } {}
    ^ n
}

@ above i n → i {
    : i z + n 1
    ; { ( nurl_println `above: first defer` ) }
    : [i xs [i | 1 2 3 n]
    ? > n 1 { ^ ( sum xs ) } {}
    ; { ( nurl_println_int ( sum xs ) ) }
    ^ + n z
}

@ back i n → [i {
    : [i xs [i | 1 2 3 n]
    ; { ( nurl_println_int ( sum xs ) ) }
    : [i ys [i | 9 9 n]
    ? > n 5 { ^ ys } {}
    ^ xs
}

@ main → i {
    ( nurl_println_int ( arm 2 ) )
    ( nurl_println_int ( arm 1 ) )
    ( nurl_println_int ( above 1 ) )
    ( nurl_println_int ( above 2 ) )
    : [i a ( back 1 )
    : [i b ( back 7 )
    ( nurl_println_int + ( sum a ) ( sum b ) )
    ^ 0
}
