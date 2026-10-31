// diag_simd_bad_level.nu — a `simd` level that does not exist (grammar
// v2.12). `v4` is the one level: `simd v4 @ f` adds an x86-64-v4 clone
// to the baseline and x86-64-v3 ones. Any other word after `simd` is
// named back, with the valid level and what the bare prefix keeps, so
// the reader does not have to look up which levels there are.

simd v5 @ f i x → i { ^ + x 1 }

@ main → i { ^ ( f 1 ) }
