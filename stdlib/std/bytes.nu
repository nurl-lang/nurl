// stdlib/std/bytes.nu — byte buffers built on Vec[u]
//
// `( Vec u )` is the canonical NURL byte buffer. All Vec[A] operations
// already work with `[u]`-instantiation (push/pop/get/set/len/cap/data
// /clear/extend/each/fold/free); this module adds byte-specific
// helpers that don't exist on the generic Vec.
//
//   ( bytes_from_str raw )     → ( Vec u )         copy NUL-terminated
//                                                  string (excluding the
//                                                  NUL); for an owned
//                                                  String pass
//                                                  `( string_data str )`.
//   ( bytes_to_str v )         → String            copy bytes into a
//                                                  String (the SB appends
//                                                  the NUL terminator).
//   ( bytes_to_hex v )         → String            lowercase 2 chars/byte
//   ( bytes_from_hex raw )     → ! ( Vec u ) ParseErr
//   ( bytes_eq a b )           → b                 byte-by-byte equality
//   ( bytes_find_byte v t )    → ? i               first index of byte t
//   ( bytes_extend_str v raw ) → v                 append from NUL string
//
//   ( bytes_read_u16_be v off ) → ? u16             load 2 bytes, big-endian
//   ( bytes_read_u16_le v off ) → ? u16             load 2 bytes, little-endian
//   ( bytes_read_u32_be v off ) → ? u32
//   ( bytes_read_u32_le v off ) → ? u32
//   ( bytes_read_u64_be v off ) → ? u64
//   ( bytes_read_u64_le v off ) → ? u64
//   ( bytes_push_u16_be v n )   → v                 append 2 bytes
//   ( bytes_push_u16_le v n )   → v
//   ( bytes_push_u32_be v n )   → v
//   ( bytes_push_u32_le v n )   → v
//   ( bytes_push_u64_be v n )   → v
//   ( bytes_push_u64_le v n )   → v
//
// Memory model: byte buffers are owned heap allocations; free with
// `( vec_free [u] v )`. Borrowed pointers (e.g. `bytes_data`) must not
// outlive the Vec.
//
// Example — read a file, hex-encode, write the digest back out:
//   : ! ( Vec u ) IoErr r ( read_file_bytes `input.bin` )
//   ?? r {
//     T v → {
//       : String hex ( bytes_to_hex v )
//       ( println ( string_data hex ) )
//       ( string_free hex )
//       ( vec_free [u] v )
//     }
//     F e → ( eprintln ( io_err_msg # IoErr e ) )
//   }

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

// ── Construction from raw / String ─────────────────────────────────

// One `strlen` + one `nurl_memcpy`. The previous body pushed byte by
// byte through `nurl_str_get`, which re-runs `strlen` on EVERY call —
// and because the `vec_push` in the same loop stores, LLVM could not
// CSE that strlen away, so the whole converter was O(n²): 117 µs for a
// 4 KB input, versus 168 ns for the memcpy below (699×). Same shape as
// `bytes_extend_str`.
@ bytes_from_str s raw → ( Vec u ) {
    : i n ( nurl_str_len raw )
    : ( Vec u ) v ( vec_with_cap [u] n )
    ? > n 0 {
        : *u src # *u raw
        : *u dst ( vec_data [u] v )
        ( nurl_memcpy dst src n )
        : b _ok ( vec_set_len [u] v n )
    } {}
    ^ v
}

// Append the bytes of `raw` (NUL-terminated, excluding NUL) onto `v`.
// Bulk `nurl_memcpy` instead of byte-by-byte `vec_push`. A per-byte
// push for the 330 KB JSON response body in nurlapi's /build_wasm was
// costing ~2.5 s wall-time for a 250 ms compile job; the memcpy
// variant drops that to single-digit ms. Mirrors the fast path
// __string_append_raw already uses in stdlib/core/string.nu.
@ bytes_extend_str ( Vec u ) v s raw → v {
    : i n ( nurl_str_len raw )
    ? > n 0 {
        ( vec_reserve [u] v n )
        : *u src # *u raw
        : *u dst ( vec_data [u] v )
        : i len ( vec_len [u] v )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        ( vec_set_len [u] v + len n )
    } {}
}

// Append exactly `n` raw bytes from pointer `raw` onto `v` — the
// length-explicit, BINARY-SAFE sibling of `bytes_extend_str` (which
// stops at the first NUL via strlen). Use this to copy out a runtime-
// owned byte buffer whose length is known independently of any NUL
// terminator (e.g. a streamed HTTP body chunk that may contain NULs).
// `raw` is BORROWED. No-op when `n <= 0`.
@ bytes_extend_raw ( Vec u ) v s raw i n → v {
    ? > n 0 {
        ( vec_reserve [u] v n )
        : *u src # *u raw
        : *u dst ( vec_data [u] v )
        : i len ( vec_len [u] v )
        : *u dst_at # *u + # i dst len
        ( nurl_memcpy dst_at src n )
        ( vec_set_len [u] v + len n )
    } {}
}

// Append the decimal-text bytes of `n` onto `v` (no leading zeros, '-' for
// negatives). Convenience over `bytes_extend_str ( nurl_str_int n )` —
// hides the malloc'd intermediate from caller-side accounting.
@ bytes_push_int ( Vec u ) v i n → v {
    ( bytes_extend_str v ( nurl_str_int n ) )
}

// Bulk-append every byte of `src` to `v` via `nurl_memcpy`. Same shape
// as `vec_extend [u]` but skips the per-element copy loop — for HTTP
// response serialisation (a 330 KB body byte-vector being copied into
// the wire buffer) the loop variant was the dominant cost in the
// nurlapi playground; this drops it to a single memcpy. Source vector
// is BORROWED.
@ bytes_extend_bytes ( Vec u ) dst ( Vec u ) src → v {
    : i n ( vec_len [u] src )
    ? > n 0 {
        ( vec_reserve [u] dst n )
        : *u sp ( vec_data [u] src )
        : *u dp ( vec_data [u] dst )
        : i dlen ( vec_len [u] dst )
        : *u dst_at # *u + # i dp dlen
        ( nurl_memcpy dst_at sp n )
        ( vec_set_len [u] dst + dlen n )
    } {}
}

// Append the default float formatting (`%g`) of `x` onto `v`.
@ bytes_push_float ( Vec u ) v f x → v {
    ( bytes_extend_str v ( nurl_str_float x ) )
}

// Copy the bytes of `v` into a fresh owned String. The SB appends a
// trailing NUL automatically. NUL bytes inside `v` are stored verbatim
// — `string_data` returns the buffer up to the first NUL, so if you
// want the full contents iterate the bytes manually.
//
// `string_push_bytes` is one memcpy; the previous per-byte
// `vec_get` + `string_push_char` walk cost 16.8 µs on a 4 KB buffer
// against 164 ns here (103×), because every pushed byte re-sealed the
// NUL terminator and re-ran the capacity check.
@ bytes_to_str ( Vec u ) v → String {
    : i n ( vec_len [u] v )
    : String out ( string_with_cap n )
    ? > n 0 {
        ( string_push_bytes out ( vec_data [u] v ) n )
    } {}
    ^ out
}

// ── Hex round-trip ─────────────────────────────────────────────────

@ __byte_hex_hi i b → i {
    : i n & 15 / b 16
    ? < n 10 { ^ + 48 n } {}
    ^ + 87 n
}

@ __byte_hex_lo i b → i {
    : i n & b 15
    ? < n 10 { ^ + 48 n } {}
    ^ + 87 n
}

// Hoists the data pointer once instead of an `?u`-returning `vec_get`
// (bounds check + Option construction) per byte; the loop index is
// already bounded by the length read above.
@ bytes_to_hex ( Vec u ) v → String {
    : i n ( vec_len [u] v )
    : String out ( string_with_cap * n 2 )
    ? > n 0 {
        : *u p ( vec_data [u] v )
        // Output length is exactly 2n, so reserve once and write through
        // the cursor rather than paying string_push_char per nibble.
        : *u w ( string_reserve_at out * n 2 )
        : ~ i k 0
        ~ < k n {
            : i ib & # i . p k 255
            = . w * k 2 # u ( __byte_hex_hi ib )
            = . w + * k 2 1 # u ( __byte_hex_lo ib )
            = k + k 1
        }
        ( string_commit out * n 2 )
    } {}
    ^ out
}

@ __hex_byte_value i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}
    ^ -1
}

@ bytes_from_hex s raw → !( Vec u ) ParseErr {
    : i n ( nurl_str_len raw )
    ? == n 0 { ^ @ !( Vec u ) ParseErr { F @ ParseErr { Empty } } } {}
    ? != 0 & n 1 {
        ^ @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
    } {}
    : ( Vec u ) v ( vec_with_cap [u] / n 2 )
    // Read through a raw pointer with the length hoisted above: the
    // former `nurl_str_get` per nibble re-ran strlen on every call, and
    // the `vec_push` in the loop blocked LLVM from hoisting it — O(n²).
    : *u p # *u raw
    : ~ i k 0
    ~ < k n {
        : i hi ( __hex_byte_value & # i . p k 255 )
        : i lo ( __hex_byte_value & # i . p + k 1 255 )
        ? | < hi 0 < lo 0 {
            ( vec_free [u] v )
            ^ @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
        } {}
        ( vec_push [u] v # u + lo * hi 16 )
        = k + k 2
    }
    ^ @ !( Vec u ) ParseErr { T v }
}

// ── Equality ────────────────────────────────────────────────────────

@ bytes_eq ( Vec u ) a ( Vec u ) b → b {
    : i la ( vec_len [u] a )
    : i lb ( vec_len [u] b )
    ? != la lb { ^ F } {}
    ? == la 0 { ^ T } {}
    : *u pa ( vec_data [u] a )
    : *u pb ( vec_data [u] b )
    ^ == 0 # i ( memcmp # s pa # s pb la )
}

// ── Search ──────────────────────────────────────────────────────────

@ bytes_find_byte ( Vec u ) v u target → ?i {
    : i n ( vec_len [u] v )
    : *u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k n {
        : u x . p k
        ? == x target { ^ @ ?i { T k } } {}
        = k + k 1
    }
    ^ @ ?i { F 0 }
}

// First index where `needle` starts inside `v`. Empty needle → 0
// (mirrors `string_index_of`'s convention). Returns None if no match.
@ bytes_index_of ( Vec u ) v ( Vec u ) needle → ?i {
    : i n ( vec_len [u] v )
    : i m ( vec_len [u] needle )
    ? == m 0 { ^ @ ?i { T 0 } } {}
    ? > m n { ^ @ ?i { F 0 } } {}
    : *u p ( vec_data [u] v )
    : *u q ( vec_data [u] needle )
    : i last + - n m 1
    : ~ i k 0
    ~ < k last {
        : ~ i j 0
        : ~ b ok T
        ~ < j m {
            : u x . p + k j
            : u y . q j
            ? != x y { = ok F = j m } { = j + j 1 }
        }
        ? ok { ^ @ ?i { T k } } {}
        = k + k 1
    }
    ^ @ ?i { F 0 }
}

// ── Prefix / suffix ────────────────────────────────────────────────

@ bytes_starts_with ( Vec u ) v ( Vec u ) prefix → b {
    : i n ( vec_len [u] v )
    : i m ( vec_len [u] prefix )
    ? > m n { ^ F } {}
    : *u p ( vec_data [u] v )
    : *u q ( vec_data [u] prefix )
    : ~ i k 0
    ~ < k m {
        : u x . p k
        : u y . q k
        ? != x y { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ bytes_ends_with ( Vec u ) v ( Vec u ) suffix → b {
    : i n ( vec_len [u] v )
    : i m ( vec_len [u] suffix )
    ? > m n { ^ F } {}
    : *u p ( vec_data [u] v )
    : *u q ( vec_data [u] suffix )
    : i base - n m
    : ~ i k 0
    ~ < k m {
        : u x . p + base k
        : u y . q k
        ? != x y { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── Fixed-width integer read / write ───────────────────────────────
//
// Endianness-aware load and store helpers for u16 / u32 / u64. Reads
// return `?T` so callers can detect out-of-range offsets without a
// die. Writes append N bytes in the chosen order and return `v` so
// callers can chain.
//
// Conventions:
//   * Big-endian (`_be`): byte 0 is most-significant (network byte
//     order, used by gzip CRC, MessagePack, BSON, IP/TCP/UDP).
//   * Little-endian (`_le`): byte 0 is least-significant (gzip ISIZE,
//     PE/COFF headers, x86 wire formats, Bitcoin protocol).
//   * Offset bounds: a read of N bytes at offset `off` succeeds iff
//     `off >= 0 && off + N <= ( vec_len v )`. Otherwise None.
//
// Implementation note: bytes are loaded as `i` (i64) via the `# i ( . p k )`
// cast. The compiler's `gen_member` now propagates the source pointer's
// unsigned-ness through `__last_unsigned__`, so a load from `*u` emits
// `zext i8 → i64` (not `sext`). Without that propagation, a high-bit-set
// byte like 0x89 would sign-extend to 0xFFFFFFFFFFFFFF89 and corrupt
// every subsequent shift+add — fixed at the compiler level 2026-05-17.

@ bytes_read_u16_be ( Vec u ) v i off → ?u16 {
    : i n ( vec_len [u] v )
    : i end + off 2
    ? | < off 0 > end n { ^ @ ?u16 { F # u16 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i r + << b0 8 b1
    ^ @ ?u16 { T # u16 r }
}

@ bytes_read_u16_le ( Vec u ) v i off → ?u16 {
    : i n ( vec_len [u] v )
    : i end + off 2
    ? | < off 0 > end n { ^ @ ?u16 { F # u16 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i r + b0 << b1 8
    ^ @ ?u16 { T # u16 r }
}

@ bytes_read_u32_be ( Vec u ) v i off → ?u32 {
    : i n ( vec_len [u] v )
    : i end + off 4
    ? | < off 0 > end n { ^ @ ?u32 { F # u32 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i hi + << b0 24 << b1 16
    : i lo + << b2 8 b3
    : i r + hi lo
    ^ @ ?u32 { T # u32 r }
}

@ bytes_read_u32_le ( Vec u ) v i off → ?u32 {
    : i n ( vec_len [u] v )
    : i end + off 4
    ? | < off 0 > end n { ^ @ ?u32 { F # u32 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i hi + << b3 24 << b2 16
    : i lo + << b1 8 b0
    : i r + hi lo
    ^ @ ?u32 { T # u32 r }
}

@ bytes_read_u64_be ( Vec u ) v i off → ?u64 {
    : i n ( vec_len [u] v )
    : i end + off 8
    ? | < off 0 > end n { ^ @ ?u64 { F # u64 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i b4 # i . p + off 4
    : i b5 # i . p + off 5
    : i b6 # i . p + off 6
    : i b7 # i . p + off 7
    : i hi0 + << b0 56 << b1 48
    : i hi1 + << b2 40 << b3 32
    : i lo0 + << b4 24 << b5 16
    : i lo1 + << b6 8 b7
    : i hi + hi0 hi1
    : i lo + lo0 lo1
    : i r + hi lo
    ^ @ ?u64 { T # u64 r }
}

@ bytes_read_u64_le ( Vec u ) v i off → ?u64 {
    : i n ( vec_len [u] v )
    : i end + off 8
    ? | < off 0 > end n { ^ @ ?u64 { F # u64 0 } } {}
    : *u p ( vec_data [u] v )
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i b4 # i . p + off 4
    : i b5 # i . p + off 5
    : i b6 # i . p + off 6
    : i b7 # i . p + off 7
    : i hi0 + << b7 56 << b6 48
    : i hi1 + << b5 40 << b4 32
    : i lo0 + << b3 24 << b2 16
    : i lo1 + << b1 8 b0
    : i hi + hi0 hi1
    : i lo + lo0 lo1
    : i r + hi lo
    ^ @ ?u64 { T # u64 r }
}

@ bytes_push_u16_be ( Vec u ) v u16 n → v {
    : i x # i n
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & x 255 )
}

@ bytes_push_u16_le ( Vec u ) v u16 n → v {
    : i x # i n
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
}

@ bytes_push_u32_be ( Vec u ) v u32 n → v {
    : i x # i n
    ( vec_push [u] v # u & >> x 24 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & x 255 )
}

@ bytes_push_u32_le ( Vec u ) v u32 n → v {
    : i x # i n
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
}

@ bytes_push_u64_be ( Vec u ) v u64 n → v {
    : i x # i n
    ( vec_push [u] v # u & >> x 56 255 )
    ( vec_push [u] v # u & >> x 48 255 )
    ( vec_push [u] v # u & >> x 40 255 )
    ( vec_push [u] v # u & >> x 32 255 )
    ( vec_push [u] v # u & >> x 24 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & x 255 )
}

@ bytes_push_u64_le ( Vec u ) v u64 n → v {
    : i x # i n
    ( vec_push [u] v # u & x 255 )
    ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 )
    ( vec_push [u] v # u & >> x 24 255 )
    ( vec_push [u] v # u & >> x 32 255 )
    ( vec_push [u] v # u & >> x 40 255 )
    ( vec_push [u] v # u & >> x 48 255 )
    ( vec_push [u] v # u & >> x 56 255 )
}

// ── Slice (copy) ───────────────────────────────────────────────────

// Copy the half-open range [from, to) of `v` into a fresh owned Vec[u].
// Both bounds are clamped to [0, len]; if the resulting range is empty
// (or inverted) the returned Vec has len 0. Caller owns the result and
// must `( vec_free [u] out )`.
@ bytes_slice ( Vec u ) v i from i to → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ~ i lo from
    : ~ i hi to
    ? < lo 0 { = lo 0 } {}
    ? > lo n { = lo n } {}
    ? < hi lo { = hi lo } {}
    ? > hi n { = hi n } {}
    : i len - hi lo
    : ( Vec u ) out ( vec_with_cap [u] len )
    // memcpy, not a per-byte push loop: the TLS record layer slices every
    // received record twice (body out, remainder back into rxbuf), so a
    // byte-at-a-time copy here shows up directly in download throughput.
    ? > len 0 {
        : *u p ( vec_data [u] v )
        ( bytes_extend_raw out # s + # i p lo len )
    } {}
    ^ out
}
