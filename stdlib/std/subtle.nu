// stdlib/std/subtle.nu — constant-time comparisons for secret material.
//
// Comparing a secret (API token, MAC, password hash, session id) with
// `seq` / `nurl_str_eq` leaks how many leading bytes matched through
// the loop's duration — a timing oracle that recovers the secret
// byte-by-byte over enough requests. These helpers accumulate byte
// differences with no early exit, so duration depends only on the
// LENGTH of the inputs, never their contents. Leaking length is
// standard and accepted (cf. Python's hmac.compare_digest, Go's
// crypto/subtle, Rust's subtle crate).
//
// First extracted from the bearer-token timing fix in
// stdlib/ext/mcp_registry.nu (PR #97), promoted here so every
// secret-compare site shares one audited implementation.
//
//   ( constant_time_eq s a s b )                   → b
//       True iff a and b have equal length AND equal bytes. The
//       length check returns early — that is fine, length is public.
//
//   ( constant_time_eq_n s a s b i n )             → b
//       Compare exactly n bytes of both (caller guarantees both
//       pointers have ≥ n readable bytes). For sub-slice compares
//       where the surrounding lengths are already known equal.
//
//   ( constant_time_eq_vec ( Vec u ) a ( Vec u ) b ) → b
//       Vec[u] form for binary material (MACs, derived keys, raw
//       signatures) — binary-safe, no NUL truncation.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ constant_time_eq_n s a s b i n → b {
    : ~ i diff 0
    : ~ i k 0
    ~ < k n {
        = diff | diff - ( nurl_str_get a k ) ( nurl_str_get b k )
        = k + k 1
    }
    ^ == diff 0
}

@ constant_time_eq s a s b → b {
    : i n ( nurl_str_len a )
    ? != n ( nurl_str_len b ) { ^ F } {}
    ^ ( constant_time_eq_n a b n )
}

@ constant_time_eq_vec ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    ^ ( constant_time_eq_n # s ( vec_data [u] a ) # s ( vec_data [u] b ) n )
}
