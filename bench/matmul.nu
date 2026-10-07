// matmul — multiply two 256x256 integer matrices, print the trace of
// the product. Deterministic fill: A[i][j] = (i*N+j) % 7,
// B[i][j] = (i+j) % 5. Stresses nested loops + flat-array indexing.
unsafe @ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i N 256
    : *i a # *i ( malloc * * N N 8 )
    : *i b # *i ( malloc * * N N 8 )
    : *i c # *i ( malloc * * N N 8 )
    // BENCH_SCALE products, the inputs shifted by the repetition so no two
    // are the same computation; the traces add up.
    : ~ i tr 0
    : ~ i rep 0
    ~ < rep # i BENCH_SCALE {
        : ~ i i 0
        ~ < i N {
            : ~ i j 0
            ~ < j N {
                : i idx + * i N j
                = . a idx % + idx rep 7
                = . b idx % + + i j rep 5
                = . c idx 0
                = j + j 1
            }
            = i + i 1
        }
        : ~ i ri 0
        ~ < ri N {
            : ~ i cj 0
            ~ < cj N {
                : ~ i s 0
                : ~ i k 0
                ~ < k N {
                    : i av . a + * ri N k
                    : i bv . b + * k N cj
                    = s + s * av bv
                    = k + k 1
                }
                = . c + * ri N cj s
                = cj + cj 1
            }
            = ri + ri 1
        }
        : ~ i d 0
        ~ < d N {
            = tr + tr . c + * d N d
            = d + d 1
        }
        = rep + rep 1
    }
    ( nurl_println_int tr )
    ( free a )
    ( free b )
    ( free c )
    ^ 0
}
