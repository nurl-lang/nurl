// stdlib/std/simd.nu — vectorised byte scanning and bulk byte ops
//
// The language's SIMD surface is the `v128` type and the `nurl_v128_*`
// primitives the compiler defines (see the § "The v128 SIMD primitive
// layer" block in compiler/nurlc.nu). Those are the instructions; this
// module is the small set of ALGORITHMS over raw byte pointers that
// every other part of the stdlib wants, written in pure NURL on top of
// them.
//
//   ( simd_index_byte p n c )   → i    first index of byte c, or -1
//   ( simd_index_crlf p n )     → i    first index of "\r\n", or -1
//   ( simd_index_head_end p n ) → i    first index of "\r\n\r\n", or -1
//   ( simd_index_ows_end p n )  → i    first index of a byte that is
//                                      neither SP nor HTAB
//   ( simd_bytes_eq a b n )     → b    equality over n bytes
//   ( simd_bytes_eq_ci a b n )  → b    ASCII case-insensitive equality
//   ( simd_xor_into dst a n )   → v    dst[0..n) ^= a[0..n)
//
// All of them take RAW POINTERS and a length: they are the layer under
// String / Vec, not a layer over them, so a caller that already has a
// `*u` (an HTTP read buffer, a cipher block) pays no wrapping.
//
// The shape is the same in every one: step sixteen bytes at a time,
// turn the comparison into a 16-bit mask, and if the mask is non-zero
// let `nurl_ctz` name the byte. One branch per sixteen bytes instead of
// one per byte — and no bounds check per byte either, which on the
// scalar path cost as much as the compare did. Every routine finishes
// with a scalar tail for the last `n & 15` bytes, so no caller has to
// know the vector width or pad its buffers; and none of them ever reads
// past `p + n`, which is what makes them safe on a buffer that ends at
// a page boundary.
//
// 128 bits and not 256: SSE2 is part of the x86-64 ABI and NEON part of
// AArch64, so this code needs no CPUID probe, no target-feature
// attribute and no scalar fallback path to be correct everywhere. A
// wider kernel would need all three.

// First index in p[0..n) holding byte `c` (low 8 bits), or -1.
@ simd_index_byte * u p i n i c → i {
    : v128 needle ( nurl_v128_bcast8 c )
    : ~ i k 0
    ~ <= + k 16 n {
        : i m ( nurl_v128_eqmask8 ( nurl_v128_ld # s + # i p k ) needle )
        ? != m 0 { ^ + k # i ( nurl_ctz # u64 m ) } {}
        = k + k 16
    }
    : i cb & c 255
    ~ < k n {
        ? == & 255 # i . p k cb { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// First index in p[0..n) at which "\r\n" starts, or -1.
//
// Two masks and a shift, not two scans: bit j of `mcr` says byte j is
// CR, bit j of `mlf >> 1` says byte j+1 is LF, so their AND has a bit
// exactly where a CRLF begins. The 16-byte window is stepped by 15 so a
// CR in the last lane can still see its LF in the next window without
// re-reading it — the classic overlap, and the reason this cannot be
// written as a disjoint tiling.
@ simd_index_crlf * u p i n → i {
    ? < n 2 { ^ -1 } {}
    : v128 vcr ( nurl_v128_bcast8 13 )
    : v128 vlf ( nurl_v128_bcast8 10 )
    : ~ i k 0
    ~ <= + k 16 n {
        : v128 blk ( nurl_v128_ld # s + # i p k )
        : i mcr ( nurl_v128_eqmask8 blk vcr )
        : i mlf ( nurl_v128_eqmask8 blk vlf )
        : i hit & mcr >> mlf 1
        ? != hit 0 { ^ + k # i ( nurl_ctz # u64 hit ) } {}
        // The LF for a CR in lane 15 lives in the next window; step 15.
        = k + k 15
    }
    ~ < k - n 1 {
        ? & == & 255 # i . p k 13 == & 255 # i . p + k 1 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// First index in p[0..n) at which "\r\n\r\n" starts, or -1.
//
// Same trick, four deep: a head terminator is CR at j, LF at j+1, CR at
// j+2, LF at j+3, which is one AND of four shifted masks. The window
// steps by 13 so a terminator straddling the end of a block is still
// found whole.
@ simd_index_head_end * u p i n → i {
    ? < n 4 { ^ -1 } {}
    : v128 vcr ( nurl_v128_bcast8 13 )
    : v128 vlf ( nurl_v128_bcast8 10 )
    : ~ i k 0
    ~ <= + k 16 n {
        : v128 blk ( nurl_v128_ld # s + # i p k )
        : i mcr ( nurl_v128_eqmask8 blk vcr )
        : i mlf ( nurl_v128_eqmask8 blk vlf )
        : i hit & & & mcr >> mlf 1 >> mcr 2 >> mlf 3
        ? != hit 0 { ^ + k # i ( nurl_ctz # u64 hit ) } {}
        = k + k 13
    }
    ~ <= + k 4 n {
        ? & & & == & 255 # i . p k 13 == & 255 # i . p + k 1 10
        == & 255 # i . p + k 2 13 == & 255 # i . p + k 3 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// First index in p[0..n) whose byte is neither SP (32) nor HTAB (9),
// or `n` if every byte is one of the two. This is HTTP's "skip optional
// whitespace"; the mask is the complement of (is-SP or is-HTAB).
@ simd_index_ows_end * u p i n → i {
    : v128 vsp ( nurl_v128_bcast8 32 )
    : v128 vht ( nurl_v128_bcast8 9 )
    : ~ i k 0
    ~ <= + k 16 n {
        : v128 blk ( nurl_v128_ld # s + # i p k )
        : i ows | ( nurl_v128_eqmask8 blk vsp ) ( nurl_v128_eqmask8 blk vht )
        : i other & 65535 ^^ ows 65535
        ? != other 0 { ^ + k # i ( nurl_ctz # u64 other ) } {}
        = k + k 16
    }
    ~ < k n {
        : i bb & 255 # i . p k
        ? & != bb 32 != bb 9 { ^ k } {}
        = k + k 1
    }
    ^ n
}

// a[0..n) == b[0..n), byte for byte.
@ simd_bytes_eq * u a * u b i n → b {
    : ~ i k 0
    ~ <= + k 16 n {
        : i m ( nurl_v128_eqmask8 ( nurl_v128_ld # s + # i a k ) ( nurl_v128_ld # s + # i b k ) )
        ? != m 65535 { ^ F } {}
        = k + k 16
    }
    ~ < k n {
        ? != & 255 # i . a k & 255 # i . b k { ^ F } {}
        = k + k 1
    }
    ^ T
}

// a[0..n) == b[0..n) after ASCII case folding — the comparison every
// HTTP header lookup performs.
//
// `nurl_v128_lower8` folds only 'A'..'Z'. The tempting `x | 32` would
// also fold '^' onto '~' and '@' onto '`', and all four are legal HTTP
// token characters, so it would report two DIFFERENT header names as
// the same one.
@ simd_bytes_eq_ci * u a * u b i n → b {
    : ~ i k 0
    ~ <= + k 16 n {
        : v128 la ( nurl_v128_lower8 ( nurl_v128_ld # s + # i a k ) )
        : v128 lb ( nurl_v128_lower8 ( nurl_v128_ld # s + # i b k ) )
        ? != ( nurl_v128_eqmask8 la lb ) 65535 { ^ F } {}
        = k + k 16
    }
    ~ < k n {
        : i ca ( simd_ascii_lower & 255 # i . a k )
        : i cb ( simd_ascii_lower & 255 # i . b k )
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Scalar counterpart of nurl_v128_lower8, for the tails above and for
// any caller that has one byte rather than sixteen.
@ simd_ascii_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// dst[0..n) ^= a[0..n). The keystream-application step of every stream
// cipher, and the fastest form the language can express: sixteen bytes
// per load/xor/store rather than one.
@ simd_xor_into * u dst * u a i n → v {
    : ~ i k 0
    ~ <= + k 16 n {
        : v128 d ( nurl_v128_ld # s + # i dst k )
        : v128 s ( nurl_v128_ld # s + # i a k )
        ( nurl_v128_st # s + # i dst k ( nurl_v128_xor d s ) )
        = k + k 16
    }
    ~ < k n {
        = . dst k # u ^^ & 255 # i . dst k & 255 # i . a k
        = k + k 1
    }
}
