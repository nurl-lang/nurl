// stdlib/std/hash_xxh64.nu — XXH64, the 64-bit xxHash (Yann Collet).
//
// A NON-CRYPTOGRAPHIC hash: fast, well-distributed, and trivial to
// forge. Use it for checksums, hash tables and content addressing where
// the adversary is bit rot, not a person. For anything an attacker can
// influence use `std/hash.nu` (SHA-2 / HMAC) instead.
//
// XXH64 is what Zstandard stores in a frame's optional content
// checksum (`std/zstd.nu` — the low 32 bits of the digest over the
// whole decompressed content), which is why it lives in the stdlib.
//
//   ( xxh64      ( Vec u ) data )          → i        seed 0
//   ( xxh64_seed ( Vec u ) data i seed )   → i
//   ( xxh64_hex  ( Vec u ) data )          → String   16 lowercase hex
//
// The digest is 64 bits of payload carried in NURL's signed `i`. Print
// it with `xxh64_hex`, or compare it against another `i` — the bit
// pattern is what matters, not the sign. To take the low 32 bits (the
// zstd checksum), mask: `& d 0xFFFFFFFF`.
//
// Verified against the reference implementation's test vectors:
// XXH64("") = 0xEF46DB3751D8E999, XXH64("abc") = 0x44BC2CF5AD770999.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

: i XXH64_P1 0x9E3779B185EBCA87
: i XXH64_P2 0xC2B2AE3D27D4EB4F
: i XXH64_P3 0x165667B19E3779F9
: i XXH64_P4 0x85EBCA77C2B2AE63
: i XXH64_P5 0x27D4EB2F165667C5

// Little-endian 8-byte load from a byte pointer. Assembled from single
// byte loads: a NURL `*u` is a byte pointer and the language has no
// unaligned wide load, so this is the portable spelling.
@ __xxh_ld64 * u p i off → i {
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i b4 # i . p + off 4
    : i b5 # i . p + off 5
    : i b6 # i . p + off 6
    : i b7 # i . p + off 7
    : i lo | | | b0 << b1 8 << b2 16 << b3 24
    : i hi | | | b4 << b5 8 << b6 16 << b7 24
    ^ | lo << hi 32
}

@ __xxh_ld32 * u p i off → i {
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    ^ | | | b0 << b1 8 << b2 16 << b3 24
}

@ __xxh_round i acc i inp → i {
    : i a + acc * inp XXH64_P2
    ^ * ( nurl_rotl64 # u64 a # u64 31 ) XXH64_P1
}

@ __xxh_merge i acc i val → i {
    : i v ( __xxh_round 0 val )
    ^ + * ^^ acc v XXH64_P1 XXH64_P4
}

@ __xxh_avalanche i h0 → i {
    : ~ i h ^^ h0 >> # u64 h0 33
    = h * h XXH64_P2
    = h ^^ h >> # u64 h 29
    = h * h XXH64_P3
    = h ^^ h >> # u64 h 32
    ^ h
}

// The digest over `n` bytes at `p`. `xxh64_seed` is this over a Vec —
// the pointer form exists because callers like `std/zstd.nu` need the
// digest of a RANGE of a buffer they are still filling, and copying it
// out to hash it would be the whole point of a fast hash undone.
@ xxh64_ptr * u p i n i seed → i {
    : ~ i h 0
    : ~ i pos 0
    ? >= n 32 {
        : ~ i v1 + + seed XXH64_P1 XXH64_P2
        : ~ i v2 + seed XXH64_P2
        : ~ i v3 seed
        : ~ i v4 - seed XXH64_P1
        : i limit - n 32
        ~ <= pos limit {
            = v1 ( __xxh_round v1 ( __xxh_ld64 p pos ) )
            = v2 ( __xxh_round v2 ( __xxh_ld64 p + pos 8 ) )
            = v3 ( __xxh_round v3 ( __xxh_ld64 p + pos 16 ) )
            = v4 ( __xxh_round v4 ( __xxh_ld64 p + pos 24 ) )
            = pos + pos 32
        }
        = h + + + ( nurl_rotl64 # u64 v1 # u64 1 ) ( nurl_rotl64 # u64 v2 # u64 7 )
        ( nurl_rotl64 # u64 v3 # u64 12 ) ( nurl_rotl64 # u64 v4 # u64 18 )
        = h ( __xxh_merge h v1 )
        = h ( __xxh_merge h v2 )
        = h ( __xxh_merge h v3 )
        = h ( __xxh_merge h v4 )
    } {
        = h + seed XXH64_P5
    }
    = h + h n
    // Tail: 8-byte groups, then 4, then single bytes.
    ~ <= + pos 8 n {
        : i k ( __xxh_round 0 ( __xxh_ld64 p pos ) )
        = h ^^ h k
        = h + * ( nurl_rotl64 # u64 h # u64 27 ) XXH64_P1 XXH64_P4
        = pos + pos 8
    }
    ? <= + pos 4 n {
        = h ^^ h * ( __xxh_ld32 p pos ) XXH64_P1
        = h + * ( nurl_rotl64 # u64 h # u64 23 ) XXH64_P2 XXH64_P3
        = pos + pos 4
    } {}
    ~ < pos n {
        = h ^^ h * # i . p pos XXH64_P5
        = h * ( nurl_rotl64 # u64 h # u64 11 ) XXH64_P1
        = pos + pos 1
    }
    ^ ( __xxh_avalanche h )
}

@ xxh64_seed ( Vec u ) data i seed → i {
    ^ ( xxh64_ptr ( vec_data [u] data ) ( vec_len [u] data ) seed )
}

@ xxh64 ( Vec u ) data → i {
    ^ ( xxh64_seed data 0 )
}

@ xxh64_hex ( Vec u ) data → String {
    : i d ( xxh64_seed data 0 )
    : ( Vec u ) b ( vec_with_cap [u] 8 )
    : ~ i k 56
    ~ >= k 0 {
        ( vec_push [u] b # u & >> # u64 d k 255 )
        = k - k 8
    }
    : String s ( bytes_to_hex b )
    ( vec_free [u] b )
    ^ s
}
