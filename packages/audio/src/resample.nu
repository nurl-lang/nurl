// packages/audio/src/resample.nu — sample-rate conversion.
//
// Linear interpolation is the tempting one-liner, and it is wrong in a way that
// matters here: it is a lousy low-pass filter, so downsampling with it folds
// everything above the new Nyquist frequency back into the speech band as
// aliasing — exactly the frequencies a speech model is listening to.
//
// So: windowed-sinc (Kaiser-ish, a Hann-windowed sinc), the standard honest
// answer. The kernel is band-limited to the LOWER of the two Nyquist
// frequencies, which is what makes downsampling safe.
//
//   ( resample x from_rate to_rate )  → ( Vec f )

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`

: f RS_PI 3.14159265358979323846

// Zeros are half the taps of a windowed sinc — 16 gives a stopband deep enough
// that the aliasing is far below the noise floor of any real recording.
: i RS_ZEROS 16

@ __rget ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ __sinc f x → f {
    ? < ( fabs x ) 1.0e-12 { ^ 1.0 } {}
    : f px * RS_PI x
    ^ / ( sin px ) px
}

@ resample ( Vec f ) x i from_rate i to_rate → ( Vec f ) {
    : i n ( vec_len [f] x )
    ? | == from_rate to_rate == n 0 {
        : ( Vec f ) same ( vec_with_cap [f] n )
        : ~ i k 0
        ~ < k n {
            ( vec_push [f] same ( __rget x k ) )
            = k + k 1
        }
        ^ same
    } {}
    : f ratio / # f to_rate # f from_rate
    : f fn # f n
    : i out_n # i ( ceil * fn ratio )
    : ( Vec f ) out ( vec_with_cap [f] out_n )
    // The kernel is band-limited to whichever Nyquist is lower: when
    // downsampling, that is the OUTPUT's — which is the whole point.
    : f cutoff ? < ratio 1.0 ratio 1.0
    : f half / # f RS_ZEROS cutoff
    : ~ i o 0
    ~ < o out_n {
        // where this output sample sits in the input
        : f pos / # f o ratio
        : i first # i ( ceil - pos half )
        : i last # i ( floor + pos half )
        : ~ f acc 0.0
        : ~ f wsum 0.0
        : ~ i j first
        ~ <= j last {
            ? & >= j 0 < j n {
                : f d - pos # f j
                // sinc, low-passed to `cutoff`, times a Hann window over the
                // support — the window is what stops the truncation of an
                // infinite sinc from ringing
                : f w * 0.5 + 1.0 ( cos / * RS_PI d half )
                : f k * cutoff * ( __sinc * cutoff d ) w
                = acc + acc * k ( __rget x j )
                = wsum + wsum k
            } {}
            = j + j 1
        }
        ( vec_push [f] out ? > ( fabs wsum ) 1.0e-12 / acc wsum acc )
        = o + o 1
    }
    ^ out
}
