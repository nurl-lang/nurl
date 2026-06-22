// u64_literal_parsing.nu — integer literals above i64 max must store their
// exact two's-complement bits, not be clamped.
//
// The decimal lexer used C `atoll`, which saturates at LLONG_MAX — so EVERY
// literal in [2^63, 2^64) (the upper half of the u64 range) silently became
// i64 max. `: u64 x 18446744073709551615` was 9223372036854775807 instead of
// all-ones. Fixed: nurl_lex_parse_int_wrap accumulates with wrapping i64
// arithmetic (matching the hex/binary lexer paths), so the full u64 range and
// i64 MIN round-trip exactly.
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

@ main → i {
    : u64 m 18446744073709551615  // all-ones
    ( pr `u64max_mod10` # i % m 10 )  // 5
    ( pr `u64max_div2` # i / m 2 )  // 9223372036854775807 (udiv)
    ( pr `u64max_as_i` m )  // -1 (signed view of all-ones)

    : u64 p 10000000000000000000  // 1e19 > i64max
    ( pr `e19_mod10` # i % p 10 )  // 0

    : u64 q 9223372036854775808  // 2^63
    ( pr `pow63_mod10` # i % q 10 )  // 8

    // boundaries round-trip
    ( pr `i64_min` -9223372036854775808 )
    ( pr `i64_max` 9223372036854775807 )
    ^ 0
}
