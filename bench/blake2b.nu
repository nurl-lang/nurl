// benchmark-contract: blake2b;rfc7693;outlen=64;unkeyed;message=16384;hashes=2048;chain=digest[0..8]->message[0..8];checksum=digest-le64
//
// blake2b — RFC 7693 BLAKE2b-512, unkeyed, through the standard library's
// `blake2b512_pure` (stdlib/std/hash_blake2b.nu). A 16 KiB message is
// hashed 2048 times (32 MiB); before each hash the previous digest's first eight
// bytes overwrite the message's first eight, so every hash depends on the
// last and none can be hoisted. The C and Rust peers carry the same
// algorithm written out by hand — their standard libraries have no BLAKE2.
//
// Contract: the process prints exactly one line — the final digest's
// first eight bytes as a little-endian integer, masked to 63 bits — and
// nothing else. `bench/bench.sh` gates on the NURL, C and Rust
// implementations printing the same line before it reports a timing.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_blake2b.nu`

// v[k], or 0 past the end (every index here is in range).
@ byte_at ( Vec u ) v i k → u64 {
    ?? ( vec_get [u] v k ) { T x → ^ # u64 x F _ → ^ # u64 0 }
}

@ main → i {
    // The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i hashes * 2048 # i BENCH_SCALE
    : i len 16384
    : ( Vec u ) msg ( vec_with_cap [u] len )
    : ~ i i 0
    ~ < i len {
        ( vec_push [u] msg # u & + * i 131 7 255 )
        = i + i 1
    }
    : ~ ( Vec u ) digest ( vec_zeroed [u] 64 )

    : ~ i k 0
    ~ < k hashes {
        = i 0
        ~ < i 8 {
            ( vec_set [u] msg i # u ( byte_at digest i ) )
            = i + i 1
        }
        = digest ( blake2b512_pure msg )
        = k + k 1
    }

    : ~ u64 v 0
    = i 7
    ~ >= i 0 {
        = v | << v 8 ( byte_at digest i )
        = i - i 1
    }
    ( nurl_println_int # i & v 0x7fffffffffffffff )
    ^ 0
}
