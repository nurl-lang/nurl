// A returned literal with a field of its own is the caller's whole, so a
// field lent beside it has to be copied — and a `% Drop` value cannot be:
// refused, where the lent field stands. (Lent with the rest, the literal's
// own slice was released by nobody — agora #635.)
$ `stdlib/core/string.nu`

: R { String name }
% Drop R { @ drop R r → v { ( nurl_println `drop R` ) } }

: P { R r [i xs }

@ mix P h → P { ^ @ P { . h r [i | 9 9] } }

@ main → i {
    : P h @ P { @ R { ( string_from `a long enough string to be on the heap, one` ) } [i | 1 2] }
    : P g ( mix h )
    ( nurl_println ( string_data . . g r name ) )
    ^ 0
}
