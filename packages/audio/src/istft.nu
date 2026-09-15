// packages/audio/src/istft.nu — the inverse short-time Fourier transform.
//
// A neural vocoder of the vocos family does not predict a waveform. It
// predicts, per frame and per frequency bin, a magnitude and a phase — and
// the waveform is what comes back out of those. That step is this file.
//
// Overlap-add is the easy half. The half that decides whether the result is
// the signal or a comb filter is the WINDOW ENVELOPE: each output sample is
// covered by several overlapping windows, by a different total weight
// depending on where it falls relative to the hop, and dividing by the
// overlap-added w² is what undoes that. Skip it and a steady tone comes back
// amplitude-modulated at the frame rate — audible as roughness, not as an
// obvious bug.
//
//   ( istft_center re im n_fft hop frames )  → ( Vec f )
//
// `re` and `im` are frames × (n_fft/2+1), row-major — the layout `stft_power`
// writes, and the layout a vocoder's head produces. "center" means the
// analysis was centred (torch's center=True), so n_fft/2 samples are trimmed
// from each end and the result is (frames−1)·hop samples long.

$ `stdlib/core/vec.nu`
$ `stdlib/std/fft.nu`
$ `mel.nu`

@ __ist_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ istft_center ( Vec f ) re ( Vec f ) im i n_fft i hop i frames → ( Vec f ) {
    : i n_bins + / n_fft 2 1
    : ( Vec f ) win ( hann_periodic n_fft )
    : i full + * - frames 1 hop n_fft
    : ( Vec f ) acc ( vec_with_cap [f] full )
    : ( Vec f ) env ( vec_with_cap [f] full )
    : ~ i k 0
    ~ < k full { ( vec_push [f] acc 0.0 ) ( vec_push [f] env 0.0 ) = k + k 1 }
    : *FftPlan p ( fft_plan n_fft )
    : ( Vec f ) fr ( vec_with_cap [f] n_bins )
    : ( Vec f ) fi ( vec_with_cap [f] n_bins )
    : ( Vec f ) x ( vec_new [f] )
    : ~ i t 0
    ~ < t frames {
        ( vec_clear [f] fr )
        ( vec_clear [f] fi )
        : i base * t n_bins
        = k 0
        ~ < k n_bins {
            ( vec_push [f] fr ( __ist_get re + base k ) )
            ( vec_push [f] fi ( __ist_get im + base k ) )
            = k + k 1
        }
        ( fft_irfft_plan p fr fi x )
        : i off * t hop
        = k 0
        ~ < k n_fft {
            : f w ( __ist_get win k )
            ( vec_set [f] acc + off k + ( __ist_get acc + off k ) * w ( __ist_get x k ) )
            ( vec_set [f] env + off k + ( __ist_get env + off k ) * w w )
            = k + k 1
        }
        = t + t 1
    }
    ( fft_free p )
    ( vec_free [f] win )
    ( vec_free [f] fr )
    ( vec_free [f] fi )
    ( vec_free [f] x )
    // centred analysis: the first and last half-window were padding
    : i pad / n_fft 2
    : i outn * - frames 1 hop
    : ( Vec f ) out ( vec_with_cap [f] outn )
    = k 0
    ~ < k outn {
        : f e ( __ist_get env + pad k )
        : f a ( __ist_get acc + pad k )
        ( vec_push [f] out ? > e 1.0e-11 / a e 0.0 )
        = k + k 1
    }
    ( vec_free [f] acc )
    ( vec_free [f] env )
    ^ out
}
