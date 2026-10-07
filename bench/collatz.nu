// collatz — longest Collatz chain length for starts in [1, 100000).
// Output: 350. A hot while loop with a branch and integer arithmetic.
@ steps i n → i {
    : ~ i c 0
    : ~ i x n
    ~ > x 1 {
        ? == % x 2 0 { = x / x 2 } { = x + * 3 x 1 }
        = c + c 1
    }
    ^ c
}

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : ~ i best 0
    : ~ i k 1
    ~ < k * 100000 # i BENCH_SCALE {
        : i s ( steps k )
        ? > s best { = best s } {}
        = k + k 1
    }
    ( nurl_println_int best )
    ^ 0
}
