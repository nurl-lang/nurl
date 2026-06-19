// lcg — 100 million iterations of a 64-bit linear congruential
// generator (MMIX constants). Each step depends on the previous so
// LLVM cannot fold it; output is the final state.

@ main → i {
    : ~ i x 1
    : ~ i k 0
    ~ < k 100000000 {
        = x + * x 6364136223846793005 1442695040888963407
        = k + k 1
    }
    ( nurl_print_int x )
    ^ 0
}
