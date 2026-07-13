// stdlib/std/fft.nu — the DFT, for any length.
//
// The checks are IDENTITIES, not baked numbers, and they are chosen to pin the
// transform down completely:
//
//   * δ[0]      → all ones                    pins the scaling
//   * δ[1]      → e^(−2πik/N)                 pins the SIGN and direction: a
//                                             conjugated (i.e. inverse-signed)
//                                             transform gives e^(+2πik/N) here
//   * cos(2πk₀n/N) → N/2 at bins k₀ and N−k₀  pins the whole thing at once
//   * Parseval                                pins the energy
//   * ifft(fft(x)) == x                       and this pins NOTHING on its own
//
// That last line is the point of the others. While writing this, Bluestein's
// forward transform was wrong by a factor of e^(iπj²/N) — and the round trip
// still passed, because the inverse was wrong in exactly the compensating way.
// A test that only checks a thing against itself proves that it is consistent,
// not that it is right.
//
// N = 400 is here explicitly: it is what a whisper spectrogram uses, it is not
// a power of two (400 = 2⁴·5²), and padding to 512 would compute a different
// transform rather than a rounder one — which is why Bluestein exists at all.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fft.nu`
$ `stdlib/std/float.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ ck b ok s name → v {
    ? ok {
        = g_pass + g_pass 1
        ( nurl_print `PASS ` )
    } {
        = g_fail + g_fail 1
        ( nurl_print `FAIL ` )
    }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ near f a f b → b { ^ < ( fabs - a b ) 1.0e-9 }

@ zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

@ get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// δ[at] → X[k] = e^(−2πi·at·k/N): magnitude 1 everywhere, and a phase that
// runs the RIGHT way round. This is the check that catches a conjugated
// transform, which a round-trip test cannot see.
@ delta_case i n i at → v {
    : ( Vec f ) re ( zeros n )
    : ( Vec f ) im ( zeros n )
    ( vec_set [f] re at 1.0 )
    ( fft_forward re im )
    : ~ b ok T
    : ~ i k 0
    ~ < k n {
        : f ang / * * -2.0 3.14159265358979323846 * # f at # f k # f n
        ? ( near ( get re k ) ( cos ang ) ) {} { = ok F }
        ? ( near ( get im k ) ( sin ang ) ) {} { = ok F }
        = k + k 1
    }
    : String nm ( string_from `delta at ` )
    ( string_push_int nm at )
    ( string_push_str nm ` of N=` )
    ( string_push_int nm n )
    ( string_push_str nm ` → e^(-2pi i k/N), phase runs the right way` )
    ( ck ok ( string_data nm ) )
    ( string_free nm )
    ( vec_free [f] re )
    ( vec_free [f] im )
}

// A real cosine at bin k0 must put N/2 at bins k0 and N−k0, and nothing
// anywhere else.
@ cosine_case i n i k0 → v {
    : ( Vec f ) re ( zeros n )
    : ( Vec f ) im ( zeros n )
    : ~ i j 0
    ~ < j n {
        : f ang / * * 2.0 3.14159265358979323846 * # f k0 # f j # f n
        ( vec_set [f] re j ( cos ang ) )
        = j + j 1
    }
    ( fft_forward re im )
    : ~ b ok T
    : f half / # f n 2.0
    : ~ i k 0
    ~ < k n {
        : f want ? | == k k0 == k - n k0 half 0.0
        ? < ( fabs - ( get re k ) want ) 1.0e-8 {} { = ok F }
        ? < ( fabs ( get im k ) ) 1.0e-8 {} { = ok F }
        = k + k 1
    }
    : String nm ( string_from `cos at bin ` )
    ( string_push_int nm k0 )
    ( string_push_str nm ` of N=` )
    ( string_push_int nm n )
    ( string_push_str nm ` → N/2 at k0 and N-k0, zero elsewhere` )
    ( ck ok ( string_data nm ) )
    ( string_free nm )
    ( vec_free [f] re )
    ( vec_free [f] im )
}

// Parseval: Σ|x|² = (1/N)·Σ|X|².
@ parseval_case i n → v {
    : ( Vec f ) re ( zeros n )
    : ( Vec f ) im ( zeros n )
    : ~ f e_time 0.0
    : ~ i j 0
    ~ < j n {
        : f a + ( sin * 0.7 # f j ) * 0.3 ( cos * 2.3 # f j )
        : f b * 0.5 ( sin * 1.9 + # f j 1.0 )
        ( vec_set [f] re j a )
        ( vec_set [f] im j b )
        = e_time + e_time + * a a * b b
        = j + j 1
    }
    ( fft_forward re im )
    : ~ f e_freq 0.0
    = j 0
    ~ < j n {
        : f a ( get re j )
        : f b ( get im j )
        = e_freq + e_freq + * a a * b b
        = j + j 1
    }
    = e_freq / e_freq # f n
    : String nm ( string_from `Parseval holds at N=` )
    ( string_push_int nm n )
    ( ck < ( fabs - e_time e_freq ) * 1.0e-9 + 1.0 e_time ( string_data nm ) )
    ( string_free nm )
    ( vec_free [f] re )
    ( vec_free [f] im )
}

// ifft(fft(x)) == x. Necessary, and — as the header says — nowhere near
// sufficient: it passed while the forward transform was wrong.
@ roundtrip_case i n → v {
    : ( Vec f ) re ( zeros n )
    : ( Vec f ) im ( zeros n )
    : ( Vec f ) r0 ( zeros n )
    : ( Vec f ) i0 ( zeros n )
    : ~ i j 0
    ~ < j n {
        : f a + ( sin * 0.7 # f j ) * 0.3 ( cos * 2.3 # f j )
        : f b * 0.5 ( sin * 1.9 + # f j 1.0 )
        ( vec_set [f] re j a )
        ( vec_set [f] im j b )
        ( vec_set [f] r0 j a )
        ( vec_set [f] i0 j b )
        = j + j 1
    }
    : *FftPlan p ( fft_plan n )
    ( fft_exec p re im )
    ( fft_exec_inv p re im )
    ( fft_free p )
    : ~ b ok T
    = j 0
    ~ < j n {
        ? < ( fabs - ( get re j ) ( get r0 j ) ) 1.0e-9 {} { = ok F }
        ? < ( fabs - ( get im j ) ( get i0 j ) ) 1.0e-9 {} { = ok F }
        = j + j 1
    }
    : String nm ( string_from `roundtrip ifft(fft(x)) == x at N=` )
    ( string_push_int nm n )
    ( ck ok ( string_data nm ) )
    ( string_free nm )
    ( vec_free [f] re ) ( vec_free [f] im )
    ( vec_free [f] r0 ) ( vec_free [f] i0 )
}

@ main → i {
    ( ck ( fft_is_pow2 1024 ) `1024 is a power of two` )
    ( ck ! ( fft_is_pow2 400 ) `400 is NOT a power of two (hence Bluestein)` )
    ( ck == 1024 ( fft_next_pow2 1000 ) `next_pow2 1000 = 1024` )
    ( ck == 1024 ( fft_next_pow2 1024 ) `next_pow2 1024 = 1024` )

    // radix-2 lengths
    ( delta_case 8 1 )
    ( delta_case 64 3 )
    ( cosine_case 16 3 )
    ( cosine_case 256 40 )
    ( parseval_case 128 )
    ( roundtrip_case 512 )

    // Bluestein lengths: whisper's 400, a prime, a small odd length
    ( delta_case 5 1 )
    ( delta_case 400 1 )
    ( cosine_case 400 40 )
    ( cosine_case 12 3 )
    ( parseval_case 400 )
    ( parseval_case 997 )
    ( roundtrip_case 400 )
    ( roundtrip_case 997 )

    // rfft: a real signal's spectrum, n/2+1 bins
    : ( Vec f ) x ( zeros 400 )
    : ~ i j 0
    ~ < j 400 {
        ( vec_set [f] x j ( cos / * * 2.0 3.14159265358979323846 * 40.0 # f j 400.0 ) )
        = j + j 1
    }
    : ( Vec f ) orr ( vec_new [f] )
    : ( Vec f ) oi ( vec_new [f] )
    ( fft_rfft x orr oi )
    ( ck == 201 ( vec_len [f] orr ) `rfft of 400 real samples → 201 bins` )
    ( ck < ( fabs - ( get orr 40 ) 200.0 ) 1.0e-8 `rfft peak is N/2 at the signal's bin` )
    ( vec_free [f] x ) ( vec_free [f] orr ) ( vec_free [f] oi )

    : String m ( string_from `fft: ` )
    ( string_push_int m g_pass )
    ( string_push_str m ` passed, ` )
    ( string_push_int m g_fail )
    ( string_push_str m ` failed` )
    ( nurl_print ( string_data m ) )
    ( nurl_print `\n` )
    ( string_free m )
    ^ ? > g_fail 0 1 0
}
