// blake3.nu — regression for stdlib/std/hash_blake3.nu (BLAKE3, 32-byte).
//
// Expected digests verified against the official BLAKE3 reference
// (PyPI `blake3`, which wraps the upstream Rust crate). The byte-pattern
// inputs (data[i] = i % 251) at lengths 64 / 1024 / 1025 / 2048 cover
// every structural path: a single full block, exactly one chunk, the
// two-chunk tree boundary, and a balanced two-chunk tree.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash.nu`

@ show_str s tag s input → v {
    : ( Vec u ) d ( bytes_from_str input )
    : String hx ( blake3_hex d )
    ( nurl_print tag ) ( nurl_print `=` )
    ( nurl_print ( string_data hx ) ) ( nurl_print `\n` )
    ( string_free hx )
    ( vec_free [u] d )
}

@ pattern i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u % i 251 ) = i + i 1 }
    ^ v
}

@ show_pattern i n → v {
    : ( Vec u ) d ( pattern n )
    : String hx ( blake3_hex d )
    ( nurl_print `bytes` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `=` )
    ( nurl_print ( string_data hx ) ) ( nurl_print `\n` )
    ( string_free hx )
    ( vec_free [u] d )
}

@ main → i {
    ( show_str `empty` `` )
    ( show_str `abc` `abc` )
    ( show_str `hello` `hello world` )
    ( show_str `fox` `The quick brown fox jumps over the lazy dog` )
    ( show_pattern 64 )
    ( show_pattern 1024 )
    ( show_pattern 1025 )
    ( show_pattern 2048 )
    ^ 0
}
