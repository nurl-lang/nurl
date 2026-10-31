// enum_payload_named_struct: agora #129 — an enum variant declared to carry an `A` given a `B`: the arm reads B's int as A's String (enum_payload_named_struct).
// Closed: A struct literal field and an enum variant payload refuse a value whose type differs from the declared one across an option, result, slice or closure shape (__agg_shape_clash — the binding check's rule), and an enum payload refuses a different named type (__arg_named_struct_mismatch); agora #129.
// main: accepted; the program died with SIGSEGV.
// map: §2.12 | A2 | rejected | h915 | agora #129: an enum variant declared to carry an `A` given a `B`: the arm reads B's int as A's String
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
