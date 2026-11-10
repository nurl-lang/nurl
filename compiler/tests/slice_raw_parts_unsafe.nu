// slice_raw_parts_unsafe.nu — a slice built from a pointer and a length in
// an `unsafe` function owns the buffer behind the pointer from then on
// (agora #545): returned, bound or passed straight to a call, it is
// released once, by whoever holds the slice — no hand-written free. (Safe
// code may not build one: diag_slice_raw_parts.)
unsafe @ build i n → [i {
    : *i buf # *i ( malloc * n 8 )
    : ~ i k 0
    ~ < k n { = . buf k * k k = k + k 1 }
    ^ @ [i { buf n }
}
unsafe @ bound i n → i {
    : *i buf # *i ( malloc * n 8 )
    = . buf 0 41
    : [i a @ [i { buf n }
    : ~ i t 0 ~ x a { = t + t x } ^ t
}
@ sum i z [i a → i { : ~ i t z ~ x a { = t + t x } ^ t }
unsafe @ asarg → i {
    : *i buf # *i ( malloc 8 )
    = . buf 0 5
    ^ ( sum 0 @ [i { buf 1 } )
}
@ main → i {
    : [i a ( build 4 )
    ( nurl_println ( nurl_str_int ( sum 0 a ) ) )
    ( nurl_println ( nurl_str_int ( sum 0 ( build 3 ) ) ) )
    ( nurl_println ( nurl_str_int ( bound 1 ) ) )
    ( nurl_println ( nurl_str_int ( asarg ) ) )
    ^ 0 }
