// packages/audio/src/mel.nu — STFT and the mel filter bank.
//
// Every constant here was read out of transformers' audio_utils.py and
// feature_extraction_whisper.py, not remembered. The details that look like
// details are the ones that decide whether a speech model hears anything:
//
//   * the Hann window is PERIODIC — hanning(N+1) with the last sample dropped,
//     i.e. 0.5·(1 − cos(2πn/N)). The symmetric window (…/(N−1)) is a different
//     window, and every frame would be subtly wrong.
//   * the signal is REFLECT-padded by n_fft/2 on both sides before framing
//     ("center"), so frame k is centred on sample k·hop, not started there.
//   * the mel scale is SLANEY, not HTK: linear below 1 kHz (3f/200), log above.
//     HTK's 2595·log10(1+f/700) is the other convention, and it gives different
//     filters.
//   * the filters are area-normalised, Slaney-style: 2/(f[k+2] − f[k]).
//   * whisper drops the LAST STFT frame, then floors the log at (max − 8) and
//     maps it to (x + 4)/4.
//
//   ( mel_filters n_fft n_mels rate f_min f_max ) → ( Vec f )   (n_bins × n_mels)
//   ( stft_power x plan window hop )              → ( Vec f )   frames × n_bins
//   ( log_mel_whisper x n_fft hop n_mels rate )   → ( Vec f )   frames × n_mels
//
// Data is row-major and flat: a spectrogram is one `( Vec f )`, not a vec of
// vecs. It goes to a GPU next, and that is the layout a GPU wants.

$ `stdlib/core/vec.nu`
$ `stdlib/std/fft.nu`
$ `stdlib/std/float.nu`

: f MEL_PI 3.14159265358979323846

@ __mgeti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

@ __mget ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Slaney mel: linear at 3f/200 below 1 kHz, logarithmic above.
@ hz_to_mel_slaney f hz → f {
    : f lin / * 3.0 hz 200.0
    ? < hz 1000.0 { ^ lin } {}
    : f logstep / 27.0 ( log 6.4 )
    ^ + 15.0 * ( log / hz 1000.0 ) logstep
}

@ mel_to_hz_slaney f mel → f {
    : f lin / * 200.0 mel 3.0
    ? < mel 15.0 { ^ lin } {}
    : f logstep / ( log 6.4 ) 27.0
    ^ * 1000.0 ( exp * logstep - mel 15.0 )
}

// The triangular filter bank, row-major (n_bins rows × n_mels columns) — the
// same orientation transformers uses, so a mel value is a dot product down a
// column.
@ mel_filters i n_fft i n_mels i rate f f_min f f_max → ( Vec f ) {
    : i n_bins + / n_fft 2 1
    // fft bin centres: linspace(0, rate/2, n_bins)
    : ( Vec f ) fft_hz ( vec_with_cap [f] n_bins )
    : ~ i k 0
    ~ < k n_bins {
        : f nyq # f / rate 2
        ( vec_push [f] fft_hz / * nyq # f k # f - n_bins 1 )
        = k + k 1
    }
    // filter edges: n_mels + 2 points, equally spaced ON THE MEL SCALE
    : f m_min ( hz_to_mel_slaney f_min )
    : f m_max ( hz_to_mel_slaney f_max )
    : ( Vec f ) edges ( vec_with_cap [f] + n_mels 2 )
    = k 0
    ~ < k + n_mels 2 {
        : f m + m_min / * - m_max m_min # f k # f + n_mels 1
        ( vec_push [f] edges ( mel_to_hz_slaney m ) )
        = k + k 1
    }
    : ( Vec f ) w ( vec_with_cap [f] * n_bins n_mels )
    = k 0
    ~ < k * n_bins n_mels { ( vec_push [f] w 0.0 ) = k + k 1 }
    : ~ i m 0
    ~ < m n_mels {
        : f lo ( __mget edges m )
        : f ce ( __mget edges + m 1 )
        : f hi ( __mget edges + m 2 )
        // Slaney normalisation: each filter carries the same energy, whatever
        // its width — 2/(hi − lo).
        : f enorm / 2.0 - hi lo
        : ~ i b 0
        ~ < b n_bins {
            : f fz ( __mget fft_hz b )
            : f down / - fz lo - ce lo
            : f up / - hi fz - hi ce
            : f tri ? < down up down up
            : f val ? > tri 0.0 * tri enorm 0.0
            ( vec_set [f] w + * b n_mels m val )
            = b + b 1
        }
        = m + m 1
    }
    ( vec_free [f] fft_hz )
    ( vec_free [f] edges )
    ^ w
}

// Periodic Hann: 0.5·(1 − cos(2πn/N)). NOT the symmetric one.
@ hann_periodic i n → ( Vec f ) {
    : ( Vec f ) w ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] w * 0.5 - 1.0 ( cos / * * 2.0 MEL_PI # f k # f n ) )
        = k + k 1
    }
    ^ w
}

// Reflect-pad by `pad` samples on both sides: x[pad], x[pad-1], …, x[1] in
// front (the sample itself is not repeated) and the mirror image at the end.
// This is what "center=True" means, and it is why frame k is CENTRED on sample
// k·hop rather than starting there.
@ reflect_pad ( Vec f ) x i pad → ( Vec f ) {
    : i n ( vec_len [f] x )
    : ( Vec f ) out ( vec_with_cap [f] + n * 2 pad )
    : ~ i k 0
    ~ < k pad {
        ( vec_push [f] out ( __mget x - pad k ) )
        = k + k 1
    }
    = k 0
    ~ < k n {
        ( vec_push [f] out ( __mget x k ) )
        = k + k 1
    }
    = k 0
    ~ < k pad {
        ( vec_push [f] out ( __mget x - - n 2 k ) )
        = k + k 1
    }
    ^ out
}

// |STFT|², row-major frames × (n_fft/2+1). `x` is already padded; the caller
// owns the plan (an STFT runs the same length thousands of times).
@ stft_power * FftPlan p ( Vec f ) x ( Vec f ) window i n_fft i hop → ( Vec f ) {
    : i n ( vec_len [f] x )
    : i n_bins + / n_fft 2 1
    : i frames ? >= n n_fft + 1 / - n n_fft hop 0
    : ( Vec f ) out ( vec_with_cap [f] * frames n_bins )
    // the windowed frame, and the rfft's n/2+1 bins — reused every frame
    : ( Vec f ) wf ( vec_with_cap [f] n_fft )
    : ( Vec f ) sre ( vec_new [f] )
    : ( Vec f ) sim ( vec_new [f] )
    : ~ i k 0
    ~ < k n_fft {
        ( vec_push [f] wf 0.0 )
        = k + k 1
    }
    : ~ i fr 0
    ~ < fr frames {
        : i base * fr hop
        = k 0
        ~ < k n_fft {
            ( vec_set [f] wf k * ( __mget x + base k ) ( __mget window k ) )
            = k + k 1
        }
        // real input → half-length transform; the imaginary zeros above were
        // half the arithmetic
        ( fft_rfft_plan p wf sre sim )
        = k 0
        ~ < k n_bins {
            : f a ( __mget sre k )
            : f b ( __mget sim k )
            ( vec_push [f] out + * a a * b b )
            = k + k 1
        }
        = fr + fr 1
    }
    ( vec_free [f] wf )
    ( vec_free [f] sre )
    ( vec_free [f] sim )
    ^ out
}

// The whisper log-mel spectrogram: exactly what WhisperFeatureExtractor
// produces, in the same layout (frames × n_mels, row-major).
@ log_mel_whisper ( Vec f ) x i n_fft i hop i n_mels i rate → ( Vec f ) {
    : i n_bins + / n_fft 2 1
    : ( Vec f ) win ( hann_periodic n_fft )
    : ( Vec f ) padded ( reflect_pad x / n_fft 2 )
    : *FftPlan p ( fft_plan n_fft )
    : ( Vec f ) pw ( stft_power p padded win n_fft hop )
    ( fft_free p )
    ( vec_free [f] win )
    ( vec_free [f] padded )
    : i frames / ( vec_len [f] pw ) n_bins
    // whisper drops the last frame — with 30 s of audio that is what turns
    // 3001 frames into the 3000 the encoder expects
    : i keep ? > frames 0 - frames 1 0
    : ( Vec f ) fb ( mel_filters n_fft n_mels rate 0.0 8000.0 )
    // A mel filter is a TRIANGLE: band m is nonzero over a handful of adjacent
    // bins and zero over the other ~195. The apply loop walks each band's own
    // bin range, found once here — walking all n_bins for every band multiplies
    // the whole spectrogram by a matrix that is 98 % zeros, and that dense loop
    // cost as much as a third of the mel stage. The sum over an identical bin
    // range in the same order is the same floats in the same order: bit-exact.
    : ( Vec i ) blo ( vec_new [i] )
    : ( Vec i ) bhi ( vec_new [i] )
    : ~ i mm 0
    ~ < mm n_mels {
        : ~ i lo n_bins
        : ~ i hi 0
        : ~ i bb 0
        ~ < bb n_bins {
            ? > ( __mget fb + * bb n_mels mm ) 0.0 {
                ? < bb lo { = lo bb } {}
                = hi + bb 1
            } {}
            = bb + bb 1
        }
        ? > lo hi { = lo hi } {}
        ( vec_push [i] blo lo )
        ( vec_push [i] bhi hi )
        = mm + mm 1
    }
    : ( Vec f ) out ( vec_with_cap [f] * keep n_mels )
    : ~ f mx -1.0e30
    : ~ i fr 0
    ~ < fr keep {
        : ~ i m 0
        ~ < m n_mels {
            : ~ f s 0.0
            : ~ i b ( __mgeti blo m )
            : i bend ( __mgeti bhi m )
            ~ < b bend {
                = s + s * ( __mget pw + * fr n_bins b ) ( __mget fb + * b n_mels m )
                = b + b 1
            }
            : f cl ? < s 1.0e-10 1.0e-10 s
            : f lg ( log10 cl )
            ? > lg mx { = mx lg } {}
            ( vec_push [f] out lg )
            = m + m 1
        }
        = fr + fr 1
    }
    // floor at (max − 8), then map to (x + 4)/4 — whisper's own scaling, and
    // the reason the encoder sees numbers near [-1, 1] rather than decibels
    : f floor8 - mx 8.0
    : ~ i k 0
    ~ < k ( vec_len [f] out ) {
        : f v ( __mget out k )
        : f c ? < v floor8 floor8 v
        ( vec_set [f] out k / + c 4.0 4.0 )
        = k + k 1
    }
    ( vec_free [f] pw )
    ( vec_free [f] fb )
    ( vec_free [i] blo )
    ( vec_free [i] bhi )
    ^ out
}

// Pad with zeros (or trim) to exactly `n` samples — whisper always feeds its
// encoder 30 s, whatever the clip is.
@ pad_or_trim ( Vec f ) x i n → ( Vec f ) {
    : i have ( vec_len [f] x )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] out ? < k have ( __mget x k ) 0.0 )
        = k + k 1
    }
    ^ out
}
