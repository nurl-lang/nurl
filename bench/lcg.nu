// benchmark-contract: lcg64-mmix-xs33;seed=1;iterations=20000000;mul=6364136223846793005;add=1442695040888963407;xorshift=33
//
// lcg — 20M iterations of the MMIX linear congruential generator with a
// PCG-style xorshift mix folded into the state each step. A bare LCG is
// an affine recurrence, and LLVM's unroller composes k affine steps
// into one (x·aᵏ + cₖ), so a bare-LCG row measures the compiler's
// composition factor rather than the chain. The xor of a shifted copy
// breaks affinity: no number of steps composes, every step's multiply,
// add, shift and xor stay on the critical path.
//
// Contract: the process prints exactly one line — the final state as a
// signed 64-bit integer, matching the peers that have no unsigned type.

@ main → i {
    : u64 iterations 20000000
    : ~ u64 x 1
    : ~ u64 k 0
    ~ < k iterations {
        = x + * x 6364136223846793005 1442695040888963407
        = x ^^ x >> x 33
        = k + k 1
    }
    ( nurl_println_int # i x )
    ^ 0
}
