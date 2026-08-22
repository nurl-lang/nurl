// diag_inline_with_simd.nu — `inline` and `simd` on one function
// (grammar v2.7).
//
// `simd` replaces the function with a CPU-dispatching stub and puts the
// real body under decorated names. That stub is exactly the opaque call
// `inline` asks to remove, so the two prefixes cancel rather than compose.

inline simd @ scale * i32 r * i32 a i n → v {
    : ~ i k 0
    ~ < k n { = . r k * . a k 2 = k + k 1 }
}

@ main → i { ^ 0 }
