// packages/f5tts/src/sample.nu — the ODE that turns noise into a mel.
//
// F5-TTS is a conditional flow-matching model: the network does not predict
// the mel, it predicts a VELOCITY, and the mel is what you get by starting at
// Gaussian noise and integrating that velocity from t=0 to t=1. Plain Euler,
// a fixed number of steps, no adaptive anything.
//
// Two details decide whether it sounds like the reference voice:
//
//   * CLASSIFIER-FREE GUIDANCE. Every step runs the network twice — once
//     with the reference audio and the text, once with neither — and pushes
//     the answer away from the unconditional one: v = v + (v − v_null)·cfg.
//     Both forwards go in ONE batch here, so the GEMMs are twice as tall
//     rather than run twice.
//   * SWAY SAMPLING. The timesteps are not evenly spaced. They are bent
//     towards zero by t + c·(cos(πt/2) − 1 + t) with c = −1, which spends
//     most of the steps where the trajectory actually curves. It is the
//     difference between 32 steps sounding like 32 steps and sounding like
//     a hundred.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `deps/gpukit/src/dev.nu`
$ `model.nu`
$ `kernels.nu`

: f F5S_PI 3.14159265358979323846

@ __f5s_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// The step schedule: linspace(0, 1, steps+1), swayed.
@ f5_timesteps i steps f sway → ( Vec f ) {
    : ( Vec f ) t ( vec_with_cap [f] + steps 1 )
    : ~ i k 0
    ~ <= k steps {
        : f u / # f k # f steps
        : f s + u * sway - + ( cos * / F5S_PI 2.0 u ) u 1.0
        ( vec_push [f] t s )
        = k + k 1
    }
    ^ t
}

// Gaussian noise for the whole mel, one draw per element.
@ f5_noise i n i mel i seed → ( Vec f ) {
    : Rng g ( rng_seed seed )
    : i total * n mel
    : ( Vec f ) y ( vec_with_cap [f] total )
    : ~ i k 0
    ~ < k total { ( vec_push [f] y ( rng_normal g ) ) = k + k 1 }
    ( rng_free g )
    ^ y
}

// ── the integration ─────────────────────────────────────────────────
//
// `cond_mel` is the reference recording's mel, frames × mel_channels; the
// generated frames follow it in the same buffer and the model is free to
// overwrite them. `out` receives duration × mel_channels.
@ f5_sample * F5Model m ( Vec i ) ids i duration ( Vec f ) cond_mel
i steps f cfg f sway ( Vec f ) noise ( Vec f ) out → b {
    : i mel ( f5_mel m )
    : i n duration
    ? ( f5_alloc m n 2 ) {} { ^ F }
    : ~ b ok ( f5_rope m )
    // the text, conditional and unconditional, computed once for every step
    = ok & ok ( f5_text_encode m ids F 0 )
    = ok & ok ( f5_text_encode m ids T n )
    ? ok {} { ^ F }

    // the conditioning audio: the reference mel for as long as it lasts, zero
    // after it, and zero throughout for the unconditional row
    : ( Vec f ) c2 ( vec_with_cap [f] * 2 * n mel )
    : i have ( vec_len [f] cond_mel )
    : ~ i k 0
    ~ < k * n mel { ( vec_push [f] c2 ? < k have ( __f5s_get cond_mel k ) 0.0 ) = k + k 1 }
    = k 0
    ~ < k * n mel { ( vec_push [f] c2 0.0 ) = k + k 1 }
    = ok & ok ( gk_dbuf_upload ( f5_kit m ) ( f5_buf_cond m ) c2 )
    ( vec_free [f] c2 )
    = ok & ok ( f5_set_x m noise )
    ? ok {} { ^ F }

    : ( Vec f ) ts ( f5_timesteps steps sway )
    : ~ i st 0
    ~ < st steps {
        : f t0 ( __f5s_get ts st )
        : f dt - ( __f5s_get ts + st 1 ) t0
        = ok & ok ( f5_set_time m t0 )
        = ok & ok ( f5_forward m )
        // v = cond + (cond − uncond)·cfg, written over the first row block
        = ok & ok ( f5k_cfg ( f5_kit m ) . ( f5_buf_pred m ) dptr
        . ( f5_buf_vel m ) dptr n mel cfg )
        = ok & ok ( f5k_axpy ( f5_kit m ) . ( f5_buf_x m ) dptr
        . ( f5_buf_vel m ) dptr dt * n mel )
        ? ok {} { ( vec_free [f] ts ) ^ F }
        = st + st 1
    }
    ( vec_free [f] ts )
    ^ ( f5_download m ( f5_buf_x m ) out * n mel )
}
