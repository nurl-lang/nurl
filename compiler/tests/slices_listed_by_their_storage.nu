// slices_listed_by_their_storage.nu — owned slices are listed by their
// storage, and a raw string, a struct's owned fields and a slice that a
// `;` defer keeps back are released by the function's cleanup only where
// they were left to it (agora #653):
//   raw, field   released at a `^` above the defer, not again by the cleanup;
//   arm          a slice and its defer in an arm, taken and not taken;
//   above        a slice a `^` above the defer read;
//   back         a slice handed back on one path, another on the other;
//   g            inner-scope slices named like an outer one;
//   body         owners bound in a defer body; two slice fields kept back.

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

@ g i n → i {
    : [i xs [i | 1 2 3 n]
    : ~ i t 0
    ? > n 0 { : [i xs [i | 7 8 9 n n] = t + t ( sum xs ) } {}
    : ~ i k 0
    ~ < k 3 {
        : [i xs [i | k k k]
        ? > k 1 { : [i xs [i | 100 k] = t + t ( sum xs ) } {}
        = t + t ( sum xs )
        = k + k 1
    }
    ^ + t ( sum xs )
}

// A defer body's own raw string and slice struct, and a struct with two
// slice fields a defer keeps back: each released once, after the chain.
: R {
    [i xs
    [i ys
}

@ body i n → i {
    ; { : s q ( nurl_str_cat `a raw string bound in a defer body, ` `long enough` ) ( nurl_println q ) }
    ; { : Q q @ Q { [i | 1 2 3 n] n } ( nurl_println_int ( sum . q xs ) ) }
    : R r @ R { [i | 1 2 n] [i | 3 n] }
    ; { ( nurl_println_int + ( sum . r xs ) ( sum . r ys ) ) }
    ^ n
}

@ main → i {
    ( nurl_println_int ( body 4 ) )
    ( nurl_println_int ( raw 1 ) )
    ( nurl_println_int ( raw 2 ) )
    ( nurl_println_int ( field 1 ) )
    ( nurl_println_int ( field 0 ) )

    ( nurl_println_int ( arm 2 ) )
    ( nurl_println_int ( arm 1 ) )
    ( nurl_println_int ( above 1 ) )
    ( nurl_println_int ( above 2 ) )
    : [i a ( back 1 )
    : [i b ( back 7 )
    ( nurl_println_int + ( sum a ) ( sum b ) )

    ( nurl_println_int ( g 2 ) )
    ( nurl_println_int ( g 0 ) )

    ^ 0
}
