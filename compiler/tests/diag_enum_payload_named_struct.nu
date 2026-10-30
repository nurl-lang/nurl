// diag_enum_payload_named_struct.nu — an enum variant declared to carry an
// `A` given a `B` (agora #129): the arm used to read B's int as A's String.
$ `stdlib/core/string.nu`

: A { String s }

: B { i n i m }

: | E { V A N }

@ main → i {
    : B b @ B { 12345 6 }
    : E e @ E { V b }
    ?? e { V a → ( nurl_println_int ( string_len . a s ) ) N → {} }
    ^ 0
}
