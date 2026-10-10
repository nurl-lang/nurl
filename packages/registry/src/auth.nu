// registry/auth.nu — bearer tokens: mint, hash, verify.
//
// The scheme matches the Worker this registry replaces: a token is 32
// CSPRNG bytes rendered as 64 hex chars, shown once at mint time; only
// `sha256(pepper || token)` (hex) is stored. The pepper is deployment
// config (REG_TOKEN_PEPPER), so a copied database alone cannot be
// brute-forced into live tokens.
//
// The hash input is built as BYTES (bytes_from_str + extend), never
// through a `# s` cast — nurl_str_get-style C-string reads are
// NUL-bounded and would silently truncate binary material (the B3
// crypto-block lesson).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/random.nu`
$ `stdlib/core/slice.nu`

// hex sha256(pepper || token)
@ reg_token_hash s pepper s token → String {
    : ( Vec u ) buf ( bytes_from_str pepper )
    ( bytes_extend_str buf token )
    : ( Vec u ) digest ( sha256_pure buf )
    : String hex ( bytes_to_hex digest )
    ^ hex
}

// A fresh 64-hex-char token (32 CSPRNG bytes).
@ reg_token_new → String {
    ^ ( rand_hex_str 64 )
}

// Extract the token from an `Authorization: Bearer <tok>` header value;
// "" when the scheme isn't Bearer or the token is empty. Scheme match is
// case-insensitive, surrounding whitespace tolerated.
@ reg_bearer_of s auth → String {
    : ( Slice u ) auth_v ( slice_of_str auth )
    : i n ( nurl_str_len auth )
    : ~ i k 0
    ~ & < k n | == ( slice_byte auth_v k ) 32 == ( slice_byte auth_v k ) 9 { = k + k 1 }
    // "bearer" case-insensitive
    : s want `bearer`
    : ( Slice u ) want_v ( slice_of_str want )
    : ~ i w 0
    : ~ b okscheme T
    ~ & < w 6 okscheme {
        ? >= + k w n { = okscheme F } {
            : ~ i c ( slice_byte auth_v + k w )
            ? & >= c 65 <= c 90 { = c + c 32 } {}
            ? != c ( slice_byte want_v w ) { = okscheme F } {}
        }
        = w + w 1
    }
    ? ! okscheme { ^ ( string_new ) } {}
    = k + k 6
    ? | >= k n & != ( slice_byte auth_v k ) 32 != ( slice_byte auth_v k ) 9 { ^ ( string_new ) } {}
    ~ & < k n | == ( slice_byte auth_v k ) 32 == ( slice_byte auth_v k ) 9 { = k + k 1 }
    : ~ i e n
    ~ & > e k | == ( slice_byte auth_v - e 1 ) 32 == ( slice_byte auth_v - e 1 ) 9 { = e - e 1 }
    ? >= k e { ^ ( string_new ) } {}
    : String out ( string_with_cap + - e k 1 )
    : ~ i j k
    ~ < j e {
        ( string_push_char out ( slice_byte auth_v j ) )
        = j + j 1
    }
    ^ out
}
