// benchmark-contract: poly1305;rfc8439;message=16384;macs=4096;key=chained;checksum=tag-le64
//
// poly1305 — the RFC 8439 one-time authenticator through the standard
// library's `poly1305_mac` (stdlib/std/chacha20poly1305.nu, the
// poly1305-donna-64 formulation: three limbs at radix 2^44, nine
// 64x64->128 products a block). A 16 KiB message is MACed 4096 times
// (64 MiB); every tag is XORed back into both halves of the key, so each
// MAC depends on the one before and none can be hoisted. The C and Rust
// peers carry the same formulation written out by hand — their standard
// libraries have no Poly1305.
//
// Contract: the process prints exactly one line — the final tag's first
// eight bytes as a little-endian integer, masked to 63 bits — and nothing
// else. `bench/bench.sh` gates on the NURL, C and Rust implementations
// printing the same line before it reports a timing.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

// v[k], or 0 past the end (every index here is in range).
@ byte_at ( Vec u ) v i k → u64 {
    ?? ( vec_get [u] v k ) { T x → ^ # u64 x F _ → ^ # u64 0 }
}

@ main → i {
    // The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i macs * 4096 # i BENCH_SCALE
    : i len 16384
    : ( Vec u ) key ( vec_with_cap [u] 32 )
    : ~ i i 0
    ~ < i 32 {
        ( vec_push [u] key # u & + * i 7 3 255 )
        = i + i 1
    }
    : ( Vec u ) msg ( vec_with_cap [u] len )
    = i 0
    ~ < i len {
        ( vec_push [u] msg # u & + * i 31 17 255 )
        = i + i 1
    }
    : ~ ( Vec u ) tag ( vec_zeroed [u] 16 )

    : ~ i k 0
    ~ < k macs {
        = tag ( poly1305_mac key msg )
        = i 0
        ~ < i 16 {
            : u64 t ( byte_at tag i )
            ( vec_set [u] key i # u ^^ ( byte_at key i ) t )
            ( vec_set [u] key + i 16 # u ^^ ( byte_at key + i 16 ) t )
            = i + i 1
        }
        = k + k 1
    }

    : ~ u64 v 0
    = i 7
    ~ >= i 0 {
        = v | << v 8 ( byte_at tag i )
        = i - i 1
    }
    ( nurl_println_int # i & v 0x7fffffffffffffff )
    ^ 0
}
