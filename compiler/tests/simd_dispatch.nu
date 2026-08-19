// The `simd` prefix (grammar v2.5): nurlc emits a marked function
// twice — once for the baseline ISA, once with an x86-64-v3 feature set
// — and a dispatcher under the real name picks one on a cached CPUID
// answer. This test pins the OBSERVABLE contract: whichever clone runs,
// it computes the same thing, and `pub simd` / `simd pub` both parse.
//
// That the two clones are separate functions with different target
// features is checked at the IR level by simd_dispatch_ir.sh; a
// behavioural test cannot see which one ran, and should not — the
// language's promise is precisely that it does not matter.

$ `stdlib/core/io.nu`

// A vectorisable reduction. Marked, so the wide clone gets AVX2 and
// the baseline one does not; both must total the same.
simd @ __sum * u p i n → i {
    : ~ i acc 0
    : ~ i i 0
    ~ < i n { = acc + acc ( nurl_peek # s p i ) = i + i 1 }
    ^ acc
}

// Order of the two prefixes is free, and both must still be public.
pub simd @ scale_into * u dst * u src i n i k → v {
    : ~ i i 0
    ~ < i n { ( nurl_poke # s dst i * k ( nurl_peek # s src i ) ) = i + i 1 }
}

simd pub @ dot * u a * u b i n → i {
    : ~ i acc 0
    : ~ i i 0
    ~ < i n { = acc + acc * ( nurl_peek # s a i ) ( nurl_peek # s b i ) = i + i 1 }
    ^ acc
}

// A marked function may call an unmarked one. The callee is what gets
// inlined INTO the wide clone and vectorised there, which is the whole
// reason the prefix belongs on few, coarse functions.
@ __triple i x → i { ^ * x 3 }

simd @ sum_tripled * u p i n → i {
    : ~ i acc 0
    : ~ i i 0
    ~ < i n { = acc + acc ( __triple ( nurl_peek # s p i ) ) = i + i 1 }
    ^ acc
}

// Recursion through a marked function re-enters via the dispatcher.
// Correctness is the claim here: it must still terminate and total up.
simd @ tri i n → i {
    ? <= n 0 { ^ 0 } {}
    ^ + n ( tri - n 1 )
}

@ __show s label i v → v {
    ( nurl_print label )
    ( nurl_print ( nurl_str_int v ) )
    ( nurl_print `\n` )
}

@ main → v {
    : i n 100
    : s a ( nurl_zalloc * n 8 )
    : s b ( nurl_zalloc * n 8 )
    : s c ( nurl_zalloc * n 8 )
    : ~ i i 0
    ~ < i n {
        ( nurl_poke a i + i 1 )
        ( nurl_poke b i - n i )
        = i + i 1
    }

    // 1+2+…+100
    ( __show `sum       ` ( __sum # *u a n ) )
    // 3·(1+2+…+100)
    ( __show `sum_tripled ` ( sum_tripled # *u a n ) )
    // Σ (i+1)(n−i)
    ( __show `dot       ` ( dot # *u a # *u b n ) )
    // Same series, reached by recursion through the dispatcher.
    ( __show `tri       ` ( tri 100 ) )

    ( scale_into # *u c # *u a n 7 )
    ( __show `scaled    ` ( __sum # *u c n ) )

    // An empty range must not read anything, on either clone.
    ( __show `empty     ` ( __sum # *u a 0 ) )

    ( nurl_free a )
    ( nurl_free b )
    ( nurl_free c )
}
