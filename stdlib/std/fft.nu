// stdlib/std/fft.nu — the discrete Fourier transform, for ANY length.
//
// A radix-2 FFT is easy and covers powers of two. Real signal processing does
// not cooperate: a whisper spectrogram is 400 samples per frame, 400 = 2^4·5^2,
// and padding to 512 would compute a DIFFERENT transform, not a rounder one.
// So arbitrary N is handled properly, by Bluestein's algorithm (the chirp-z
// transform), which turns a DFT of any length into a CONVOLUTION — and a
// convolution can be done with power-of-two FFTs:
//
//     X[k] = conj(c[k]) · Σ_n ( x[n]·conj(c[n]) ) · c[k−n]     c[j] = e^(iπj²/N)
//
// which is a[n] = x[n]·conj(c[n]) convolved with c, evaluated by
// ifft( fft(a) · fft(b) ) over a padded power-of-two length ≥ 2N−1.
//
// Complex data is two parallel `( Vec f )` — real and imaginary. That is not a
// concession: it is what every kernel wants (contiguous, no strides, no struct
// of two doubles per element), and it keeps the transform allocation-free once
// a plan exists.
//
// A PLAN is where the work goes. The twiddle factors and — for a Bluestein
// length — the transformed chirp are computed ONCE. An STFT runs the same
// length thousands of times; making it pay for the setup each frame would be
// the whole cost of the transform.
//
//   ( fft_plan n )                     → *FftPlan     (any n ≥ 1)
//   ( fft_exec p re im )               → v            in-place forward
//   ( fft_exec_inv p re im )           → v            in-place inverse (1/N scaled)
//   ( fft_free p )                     → v
//
//   ( fft_forward re im )              → v            plan on the fly, one shot
//   ( fft_inverse re im )              → v
//   ( fft_rfft x out_re out_im )       → v            real input → n/2+1 bins
//
// The angle for a chirp is computed from (j·j mod 2N), never from j·j: at
// n = 100 000 the square overflows the exactly-representable range of a double
// and the phase quietly loses its low bits. The modulus keeps every angle exact
// no matter how long the transform is.

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

: f FFT_PI 3.14159265358979323846

: FftPlan {
    i n  // the transform length asked for
    b pow2  // n is a power of two → straight radix-2, no Bluestein
    i m  // Bluestein: the padded power-of-two length (≥ 2n−1)
    ( Vec f ) cre  // Bluestein: chirp c[j] = e^(iπj²/n), n entries
    ( Vec f ) cim
    ( Vec f ) bre  // Bluestein: fft(b), m entries — the whole point of a plan
    ( Vec f ) bim
    ( Vec f ) tre  // scratch, m entries (a, then the product)
    ( Vec f ) tim
}

@ fft_is_pow2 i n → b {
    ? < n 1 { ^ F } {}
    ^ == 0 & n - n 1
}

// The smallest power of two ≥ n.
@ fft_next_pow2 i n → i {
    : ~ i m 1
    ~ < m n { = m * m 2 }
    ^ m
}

// ── the radix-2 core (in place, length must be a power of two) ───────

@ __fft_bitrev ( Vec f ) re ( Vec f ) im i n → v {
    : ~ i j 0
    : ~ i i2 1
    ~ < i2 n {
        : ~ i bit >> n 1
        ~ & > bit 0 != 0 & j bit {
            = j ^^ j bit
            = bit >> bit 1
        }
        = j | j bit
        ? < i2 j {
            : f tr ( __fget re i2 )
            : f ti ( __fget im i2 )
            ( vec_set [f] re i2 ( __fget re j ) )
            ( vec_set [f] im i2 ( __fget im j ) )
            ( vec_set [f] re j tr )
            ( vec_set [f] im j ti )
        } {}
        = i2 + i2 1
    }
}

@ __fget ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Cooley-Tukey, decimation in time. `sign` is −1 for the forward transform
// and +1 for the inverse (the inverse's 1/n scaling is applied by the caller).
@ __fft_radix2 ( Vec f ) re ( Vec f ) im i n f sign → v {
    ? < n 2 { ^ v } {}
    ( __fft_bitrev re im n )
    : ~ i len 2
    ~ <= len n {
        : f ang / * * sign 2.0 FFT_PI # f len
        : f wr ( cos ang )
        : f wi ( sin ang )
        : ~ i i2 0
        ~ < i2 n {
            : ~ f ur 1.0
            : ~ f ui 0.0
            : ~ i j 0
            : i half / len 2
            ~ < j half {
                : i a + i2 j
                : i b + a half
                : f xr ( __fget re a )
                : f xi ( __fget im a )
                : f yr ( __fget re b )
                : f yi ( __fget im b )
                // (ur + i·ui) · (yr + i·yi)
                : f tr - * ur yr * ui yi
                : f ti + * ur yi * ui yr
                ( vec_set [f] re a + xr tr )
                ( vec_set [f] im a + xi ti )
                ( vec_set [f] re b - xr tr )
                ( vec_set [f] im b - xi ti )
                // u ← u · w
                : f nur - * ur wr * ui wi
                : f nui + * ur wi * ui wr
                = ur nur
                = ui nui
                = j + j 1
            }
            = i2 + i2 len
        }
        = len * len 2
    }
}

// ── plan ────────────────────────────────────────────────────────────

// The chirp angle for index j: π·j²/n, with j² taken modulo 2n first. j·j
// overflows a double's exact range around j = 94 906 265, and a phase that has
// lost its low bits is a transform that is quietly wrong at long lengths.
@ __fft_chirp_angle i j i n → f {
    : i jm % j * 2 n
    : i j2 % * jm jm * 2 n
    ^ / * FFT_PI # f j2 # f n
}

@ fft_plan i n → *FftPlan {
    : *FftPlan p # *FftPlan ( nurl_alloc Z FftPlan )
    = . p n n
    = . p pow2 ( fft_is_pow2 n )
    = . p m 0
    = . p cre ( vec_new [f] )
    = . p cim ( vec_new [f] )
    = . p bre ( vec_new [f] )
    = . p bim ( vec_new [f] )
    = . p tre ( vec_new [f] )
    = . p tim ( vec_new [f] )
    ? . p pow2 { ^ p } {}

    // Bluestein. m ≥ 2n−1, a power of two.
    : i m ( fft_next_pow2 - * 2 n 1 )
    = . p m m

    // c[j] = e^(iπj²/n)
    : ~ i j 0
    ~ < j n {
        : f a ( __fft_chirp_angle j n )
        ( vec_push [f] . p cre ( cos a ) )
        ( vec_push [f] . p cim ( sin a ) )
        = j + j 1
    }

    // b[j] = c[j] for j < n, b[m−j] = c[j] for 0 < j < n, zero elsewhere;
    // then fft(b), once, for every transform this plan will ever run.
    = j 0
    ~ < j m {
        ( vec_push [f] . p bre 0.0 )
        ( vec_push [f] . p bim 0.0 )
        ( vec_push [f] . p tre 0.0 )
        ( vec_push [f] . p tim 0.0 )
        = j + j 1
    }
    = j 0
    ~ < j n {
        : f cr ( __fget . p cre j )
        : f ci ( __fget . p cim j )
        ( vec_set [f] . p bre j cr )
        ( vec_set [f] . p bim j ci )
        ? > j 0 {
            ( vec_set [f] . p bre - m j cr )
            ( vec_set [f] . p bim - m j ci )
        } {}
        = j + j 1
    }
    ( __fft_radix2 . p bre . p bim m -1.0 )
    ^ p
}

@ fft_free * FftPlan p → v {
    ( vec_free [f] . p cre )
    ( vec_free [f] . p cim )
    ( vec_free [f] . p bre )
    ( vec_free [f] . p bim )
    ( vec_free [f] . p tre )
    ( vec_free [f] . p tim )
    ( nurl_free # s p )
}

// ── execute ─────────────────────────────────────────────────────────

// Bluestein, FORWARD only. The inverse is built from it below by conjugation,
// rather than by threading a sign through the chirp and the kernel: conjugating
// a signal in time reverses AND conjugates its spectrum, so "just flip the
// imaginary parts of fft(b)" is wrong in a way that still round-trips — the
// forward transform comes out wrong while ifft(fft(x)) == x keeps passing.
// (It did exactly that here, which is why the test compares against numpy and
// not only against itself.)
@ __fft_bluestein * FftPlan p ( Vec f ) re ( Vec f ) im → v {
    : i n . p n
    : i m . p m
    : ~ i j 0
    ~ < j m {
        ( vec_set [f] . p tre j 0.0 )
        ( vec_set [f] . p tim j 0.0 )
        = j + j 1
    }
    // a[j] = x[j] · conj(c[j])
    = j 0
    ~ < j n {
        : f xr ( __fget re j )
        : f xi ( __fget im j )
        : f cr ( __fget . p cre j )
        : f ci ( __fget . p cim j )
        ( vec_set [f] . p tre j + * xr cr * xi ci )
        ( vec_set [f] . p tim j - * xi cr * xr ci )
        = j + j 1
    }
    ( __fft_radix2 . p tre . p tim m -1.0 )

    // multiply by fft(b), which the plan already holds
    = j 0
    ~ < j m {
        : f ar ( __fget . p tre j )
        : f ai ( __fget . p tim j )
        : f br ( __fget . p bre j )
        : f bi ( __fget . p bim j )
        ( vec_set [f] . p tre j - * ar br * ai bi )
        ( vec_set [f] . p tim j + * ar bi * ai br )
        = j + j 1
    }
    // inverse transform of the product (the 1/m is folded into the output step)
    ( __fft_radix2 . p tre . p tim m 1.0 )

    // X[k] = conv[k]/m · conj(c[k])
    : f inv / 1.0 # f m
    : ~ i k 0
    ~ < k n {
        : f vr * inv ( __fget . p tre k )
        : f vi * inv ( __fget . p tim k )
        : f cr ( __fget . p cre k )
        : f ci ( __fget . p cim k )
        ( vec_set [f] re k + * vr cr * vi ci )
        ( vec_set [f] im k - * vi cr * vr ci )
        = k + k 1
    }
}

// Forward DFT, in place. `re` and `im` must both hold exactly n values.
@ fft_exec * FftPlan p ( Vec f ) re ( Vec f ) im → v {
    ? . p pow2 { ( __fft_radix2 re im . p n -1.0 ) } { ( __fft_bluestein p re im ) }
}

// Inverse DFT, in place, scaled by 1/n — so ifft(fft(x)) == x.
//
//     ifft(x) = conj( fft( conj(x) ) ) / n
//
// One identity instead of a second transform with the signs flipped: there is
// no separate inverse to keep in step with the forward, and no chance of the
// two drifting apart.
@ fft_exec_inv * FftPlan p ( Vec f ) re ( Vec f ) im → v {
    : i n . p n
    : ~ i k 0
    ~ < k n {
        ( vec_set [f] im k - 0.0 ( __fget im k ) )
        = k + k 1
    }
    ( fft_exec p re im )
    : f inv / 1.0 # f n
    = k 0
    ~ < k n {
        ( vec_set [f] re k * inv ( __fget re k ) )
        ( vec_set [f] im k * inv - 0.0 ( __fget im k ) )
        = k + k 1
    }
}

// ── one-shot convenience ────────────────────────────────────────────
// Plans on the fly. Fine for a one-off; for an STFT, build the plan once.

@ fft_forward ( Vec f ) re ( Vec f ) im → v {
    : *FftPlan p ( fft_plan ( vec_len [f] re ) )
    ( fft_exec p re im )
    ( fft_free p )
}

@ fft_inverse ( Vec f ) re ( Vec f ) im → v {
    : *FftPlan p ( fft_plan ( vec_len [f] re ) )
    ( fft_exec_inv p re im )
    ( fft_free p )
}

// Real input → the n/2+1 bins that are not redundant. `out_re` / `out_im` are
// cleared and filled. (A real signal's spectrum is conjugate-symmetric, so the
// upper half carries no information — a spectrogram never wants it.)
@ fft_rfft ( Vec f ) x ( Vec f ) out_re ( Vec f ) out_im → v {
    : i n ( vec_len [f] x )
    : ( Vec f ) re ( vec_with_cap [f] n )
    : ( Vec f ) im ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] re ( __fget x k ) )
        ( vec_push [f] im 0.0 )
        = k + k 1
    }
    ( fft_forward re im )
    ( vec_clear [f] out_re )
    ( vec_clear [f] out_im )
    : i nb + / n 2 1
    = k 0
    ~ < k nb {
        ( vec_push [f] out_re ( __fget re k ) )
        ( vec_push [f] out_im ( __fget im k ) )
        = k + k 1
    }
    ( vec_free [f] re )
    ( vec_free [f] im )
}

// The same, with a plan the caller keeps — an STFT runs this once per frame.
@ fft_rfft_plan * FftPlan p ( Vec f ) x ( Vec f ) out_re ( Vec f ) out_im → v {
    : i n . p n
    : ( Vec f ) re ( vec_with_cap [f] n )
    : ( Vec f ) im ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] re ( __fget x k ) )
        ( vec_push [f] im 0.0 )
        = k + k 1
    }
    ( fft_exec p re im )
    ( vec_clear [f] out_re )
    ( vec_clear [f] out_im )
    : i nb + / n 2 1
    = k 0
    ~ < k nb {
        ( vec_push [f] out_re ( __fget re k ) )
        ( vec_push [f] out_im ( __fget im k ) )
        = k + k 1
    }
    ( vec_free [f] re )
    ( vec_free [f] im )
}
