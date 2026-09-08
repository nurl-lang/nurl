// arima — seasonal ARIMA forecasting for NURL: exact, fast, streaming.
//
// A SARIMA(p, d, q)(P, D, Q)_s model in the form R's `arima()` and
// statsmodels' `ARIMA` estimate: the series is differenced d times and D
// times at the seasonal lag, the remainder is a stationary ARMA whose
// seasonal factors multiply the plain ones, and an optional mean sits
// under it all (only when nothing is differenced — a mean under a
// differenced series is a drift, which is a regressor, not a mean).
//
//   φ(B) Φ(B^s) (1 − B)^d (1 − B^s)^D (y_t − μ) = θ(B) Θ(B^s) ε_t
//
// Estimation is CSS-ML: conditional sum of squares first (cheap, and a
// good place to start), then exact maximum likelihood by the Kalman
// filter over the state-space form (Harvey), the initial state covariance
// being the model's own stationary covariance — solved exactly, by the
// doubling recursion — so the likelihood is the true Gaussian likelihood
// of the differenced series, not an approximation that depends on how
// the series began. σ² is concentrated out. The optimizer is BFGS with a
// backtracking line search over parameters transformed (Jones 1980, the
// PACF map R uses) so every AR polynomial it tries is stationary and
// every MA polynomial invertible.
//
// Forecasting and streaming run on the FULL state-space model — the ARMA
// state with the differencing folded in, the way R's makeARIMA builds it
// — filtered over the raw series with a diffuse start for the
// differencing states. So a forecast's mean and its standard error come
// from the model's own state at the end of the data, and one new
// observation is one Kalman step: `arima_update` absorbs it in O(r²),
// reports the innovation it made and how surprising it was, and the next
// forecast starts from there. That is the streaming shape the anomaly
// service wants: a model trained once, kept current point by point, and
// refitted on a schedule.
//
// Surface (see README.md for the story):
//   ( arima_spec p d q ) / ( arima_spec_seasonal p d q P D Q s ) → ArimaSpec
//   ( arima_fit y spec )              → *ArimaModel    CSS-ML, the default
//   ( arima_fit_method y spec m )     → *ArimaModel    m = ARIMA_CSS | ARIMA_ML
//   ( arima_auto y s )                → *ArimaModel    stepwise order search by AICc
//   ( arima_forecast m h )            → ArimaForecast  h means and standard errors
//   ( arima_update m y )              → ArimaStep      one observation in: innovation, variance, z
//   ( arima_coef m )                  → Json           coefficients, σ², log-likelihood, AIC…
//   ( arima_to_json m ) / ( arima_from_json s ) persistence, bit-exact
//   ( arima_free m )
//
// Pure NURL, no dependencies beyond the stdlib; `src/arima_gpu.nu` adds
// batched fitting on a GPU through the `gpu` package for the case of many
// series or many candidate orders at once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/ext/json.nu`

: i ARIMA_CSS 0
: i ARIMA_ML 1

// The diffuse prior on a differencing state: R's kappa.
: f ARIMA_KAPPA 1000000.0

// Where the optimizer stops.
: i ARIMA_MAX_ITER 200
: f ARIMA_TOL 0.00000001

: f ARIMA_LOG_2PI 1.8378770664093453

// The numerical gradient's evaluations run on threads once one
// evaluation is worth a thread: this many multiply-adds per likelihood.
: i ARIMA_PAR_WORK 200000

// Threads per batch: the processors this process can use, at most 16.
@ __ar_threads → i {
    : i n ( sys_cpu_count )
    ^ ? > n 16 16 n
}

// ── Specification ─────────────────────────────────────────────────────

: ArimaSpec {
    i p
    i d
    i q
    i P
    i D
    i Q
    i s  // seasonal period; 0 or 1 = none
    b mean  // fit a mean (only honoured when d + D = 0)
}

@ arima_spec i p i d i q → ArimaSpec {
    ^ @ ArimaSpec { p d q 0 0 0 0 == + d 0 0 }
}

@ arima_spec_seasonal i p i d i q i P i D i Q i s → ArimaSpec {
    ^ @ ArimaSpec { p d q P D Q ? > s 1 s 0 == + d D 0 }
}

@ arima_spec_with_mean ArimaSpec sp b mean → ArimaSpec {
    ^ @ ArimaSpec { . sp p . sp d . sp q . sp P . sp D . sp Q . sp s & mean == + . sp d . sp D 0 }
}

// Number of free coefficients (without σ²).
@ __ar_ncoef ArimaSpec sp → i {
    ^ + + + + . sp p . sp q . sp P . sp Q ? . sp mean 1 0
}

// ── Small vector helpers ──────────────────────────────────────────────

@ __ar_vec_copy ( Vec f ) src → ( Vec f ) {
    : i n ( vec_len [f] src )
    : ( Vec f ) out ( vec_zeroed [f] n )
    : *f s ( vec_data [f] src )
    : *f o ( vec_data [f] out )
    : ~ i k 0
    ~ < k n { = . o k . s k = k + k 1 }
    ^ out
}

@ __ar_copy_into ( Vec f ) dst ( Vec f ) src → v {
    : i n ( vec_len [f] dst )
    : *f d ( vec_data [f] dst )
    : *f s ( vec_data [f] src )
    : ~ i k 0
    ~ < k n { = . d k . s k = k + k 1 }
}

@ __ar_fill ( Vec f ) v f x → v {
    : i n ( vec_len [f] v )
    : *f p ( vec_data [f] v )
    : ~ i k 0
    ~ < k n { = . p k x = k + k 1 }
}

@ __ar_max_abs ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    : *f p ( vec_data [f] v )
    : ~ f m 0.0
    : ~ i k 0
    ~ < k n {
        : f a ( float_abs . p k )
        ? > a m { = m a } {}
        = k + k 1
    }
    ^ m
}

// Polynomial product: (1 + Σ a_i B^i)(1 + Σ b_j B^j) → the coefficients
// beyond the leading 1, length len(a) + len(b).
@ __ar_poly_mul ( Vec f ) a ( Vec f ) b → ( Vec f ) {
    : i na ( vec_len [f] a )
    : i nb ( vec_len [f] b )
    : ( Vec f ) out ( vec_zeroed [f] + na nb )
    : *f o ( vec_data [f] out )
    : *f pa ( vec_data [f] a )
    : *f pb ( vec_data [f] b )
    : ~ i i 0
    ~ < i na { = . o i + . o i . pa i = i + i 1 }
    : ~ i j 0
    ~ < j nb {
        = . o j + . o j . pb j
        = i 0
        ~ < i na {
            : i k + + i j 1
            = . o k + . o k * . pa i . pb j
            = i + i 1
        }
        = j + j 1
    }
    ^ out
}

// A seasonal polynomial 1 + Σ c_j B^{s j} spread to lag form.
@ __ar_seasonal_spread ( Vec f ) c i s → ( Vec f ) {
    : i n ( vec_len [f] c )
    : ( Vec f ) out ( vec_zeroed [f] * n s )
    : *f o ( vec_data [f] out )
    : *f pc ( vec_data [f] c )
    : ~ i j 0
    ~ < j n {
        = . o - * + j 1 s 1 . pc j
        = j + j 1
    }
    ^ out
}

// The AR side as "1 − Σ φ B^k" coefficients: φ(B)Φ(B^s) expanded, the
// signs such that the result is the φ_k of the expanded polynomial.
@ _ar_expand_ar ( Vec f ) phi ( Vec f ) sphi i s → ( Vec f ) {
    // Work with the "1 + a B" convention: a = −φ.
    : ( Vec f ) a ( __ar_vec_copy phi )
    : ( Vec f ) b ( __ar_seasonal_spread sphi s )
    : i na ( vec_len [f] a )
    : *f pa ( vec_data [f] a )
    : ~ i k 0
    ~ < k na { = . pa k - 0.0 . pa k = k + k 1 }
    : i nb ( vec_len [f] b )
    : *f pb ( vec_data [f] b )
    = k 0
    ~ < k nb { = . pb k - 0.0 . pb k = k + k 1 }
    : ( Vec f ) prod ( __ar_poly_mul a b )
    : i np ( vec_len [f] prod )
    : *f pp ( vec_data [f] prod )
    = k 0
    ~ < k np { = . pp k - 0.0 . pp k = k + k 1 }
    ( vec_free [f] a )
    ( vec_free [f] b )
    ^ prod
}

// The MA side: θ(B)Θ(B^s) expanded, "1 + Σ θ B^k" convention as given.
@ _ar_expand_ma ( Vec f ) theta ( Vec f ) stheta i s → ( Vec f ) {
    : ( Vec f ) b ( __ar_seasonal_spread stheta s )
    : ( Vec f ) prod ( __ar_poly_mul theta b )
    ( vec_free [f] b )
    ^ prod
}

// The differencing polynomial (1 − B)^d (1 − B^s)^D as "1 − Σ δ_k B^k":
// returns δ (length d + s·D), so that y_t = w_t + Σ δ_k y_{t−k}.
@ _ar_delta i d i D i s → ( Vec f ) {
    : ~ ( Vec f ) poly ( vec_new [f] )  // "1 + Σ c B^k" convention
    : ~ i k 0
    ~ < k d {
        : ( Vec f ) one ( vec_zeroed [f] 1 )
        ( vec_set [f] one 0 -1.0 )
        : ( Vec f ) nxt ( __ar_poly_mul poly one )
        ( vec_free [f] poly )
        ( vec_free [f] one )
        = poly nxt
        = k + k 1
    }
    = k 0
    ~ < k D {
        : ( Vec f ) one ( vec_zeroed [f] s )
        ( vec_set [f] one - s 1 -1.0 )
        : ( Vec f ) nxt ( __ar_poly_mul poly one )
        ( vec_free [f] poly )
        ( vec_free [f] one )
        = poly nxt
        = k + k 1
    }
    : i n ( vec_len [f] poly )
    : *f pp ( vec_data [f] poly )
    = k 0
    ~ < k n { = . pp k - 0.0 . pp k = k + k 1 }
    ^ poly
}

// Δ^d Δ_s^D y: the first d + s·D values are consumed.
@ arima_difference ( Vec f ) y i d i D i s → ( Vec f ) {
    : ~ ( Vec f ) cur ( __ar_vec_copy y )
    : ~ i k 0
    ~ < k d {
        : i n ( vec_len [f] cur )
        : ( Vec f ) nxt ( vec_zeroed [f] ? > n 1 - n 1 0 )
        : *f c ( vec_data [f] cur )
        : *f o ( vec_data [f] nxt )
        : ~ i t 1
        ~ < t n { = . o - t 1 - . c t . c - t 1 = t + t 1 }
        ( vec_free [f] cur )
        = cur nxt
        = k + k 1
    }
    = k 0
    ~ < k D {
        : i n ( vec_len [f] cur )
        : ( Vec f ) nxt ( vec_zeroed [f] ? > n s - n s 0 )
        : *f c ( vec_data [f] cur )
        : *f o ( vec_data [f] nxt )
        : ~ i t s
        ~ < t n { = . o - t s - . c t . c - t s = t + t 1 }
        ( vec_free [f] cur )
        = cur nxt
        = k + k 1
    }
    ^ cur
}

// ── The parameter transform (Jones 1980; R's partrans) ────────────────
//
// tanh maps ℝ onto (−1, 1) — partial autocorrelations — and the
// Durbin–Levinson recursion turns those into AR coefficients, so every
// image is a stationary polynomial. The inverse recovers the raw values
// from a stationary polynomial; a non-stationary one has no preimage.

@ _ar_partrans ( Vec f ) raw i off i n → ( Vec f ) {
    : ( Vec f ) out ( vec_zeroed [f] n )
    ? == n 0 { ^ out } {}
    : ( Vec f ) work ( vec_zeroed [f] n )
    : *f o ( vec_data [f] out )
    : *f w ( vec_data [f] work )
    : *f r ( vec_data [f] raw )
    : ~ i j 0
    ~ < j n {
        : f x . r + off j
        // tanh, without a libm call the GPU could not match.
        : f e ( float_exp * 2.0 x )
        : f t ? ( float_is_inf e ) 1.0 / - e 1.0 + e 1.0
        = . o j t
        = . w j t
        = j + j 1
    }
    = j 1
    ~ < j n {
        : f a . o j
        : ~ i k 0
        ~ < k j { = . w k - . w k * a . o - - j k 1 = k + k 1 }
        = k 0
        ~ < k j { = . o k . w k = k + k 1 }
        = j + j 1
    }
    ( vec_free [f] work )
    ^ out
}

// Inverse: AR coefficients → raw. Returns F when the polynomial is not
// stationary (a partial autocorrelation reaches 1 in magnitude).
@ _ar_invpartrans ( Vec f ) phi ( Vec f ) raw i off → b {
    : i n ( vec_len [f] phi )
    ? == n 0 { ^ T } {}
    : ( Vec f ) nw ( __ar_vec_copy phi )
    : ( Vec f ) work ( __ar_vec_copy phi )
    : *f nu ( vec_data [f] nw )
    : *f w ( vec_data [f] work )
    : *f r ( vec_data [f] raw )
    : ~ b ok T
    : ~ i j - n 1
    ~ & ok > j 0 {
        : f a . nu j
        ? >= ( float_abs a ) 1.0 { = ok F } {
            : ~ i k 0
            ~ < k j { = . w k / + . nu k * a . nu - - j k 1 - 1.0 * a a = k + k 1 }
            = k 0
            ~ < k j { = . nu k . w k = k + k 1 }
        }
        = j - j 1
    }
    ? ok {
        = j 0
        ~ & ok < j n {
            : f x . nu j
            ? >= ( float_abs x ) 1.0 { = ok F } {
                = . r + off j * 0.5 ( float_log / + 1.0 x - 1.0 x )
            }
            = j + j 1
        }
    } {}
    ( vec_free [f] nw )
    ( vec_free [f] work )
    ^ ok
}

// ── Coefficient bundle ────────────────────────────────────────────────

: ArimaCoef {
    ( Vec f ) phi
    ( Vec f ) theta
    ( Vec f ) sphi
    ( Vec f ) stheta
    f mu
}

@ _ar_coef_new ArimaSpec sp → ArimaCoef {
    ^ @ ArimaCoef { ( vec_zeroed [f] . sp p ) ( vec_zeroed [f] . sp q ) ( vec_zeroed [f] . sp P ) ( vec_zeroed [f] . sp Q ) 0.0 }
}

@ _ar_coef_free ArimaCoef c → v {
    ( vec_free [f] . c phi )
    ( vec_free [f] . c theta )
    ( vec_free [f] . c sphi )
    ( vec_free [f] . c stheta )
}

@ __ar_coef_clone ArimaCoef c → ArimaCoef {
    ^ @ ArimaCoef { ( __ar_vec_copy . c phi ) ( __ar_vec_copy . c theta ) ( __ar_vec_copy . c sphi ) ( __ar_vec_copy . c stheta ) . c mu }
}

// Raw (transformed) vector → coefficients. Layout: φ, θ, Φ, Θ, μ.
@ _ar_coef_of_raw ArimaSpec sp ( Vec f ) raw → ArimaCoef {
    : ~ i off 0
    : ( Vec f ) phi ( _ar_partrans raw off . sp p )
    = off + off . sp p
    : ( Vec f ) th ( _ar_partrans raw off . sp q )
    : *f pt ( vec_data [f] th )
    : ~ i k 0
    ~ < k . sp q { = . pt k - 0.0 . pt k = k + k 1 }
    = off + off . sp q
    : ( Vec f ) sphi ( _ar_partrans raw off . sp P )
    = off + off . sp P
    : ( Vec f ) sth ( _ar_partrans raw off . sp Q )
    : *f ps ( vec_data [f] sth )
    = k 0
    ~ < k . sp Q { = . ps k - 0.0 . ps k = k + k 1 }
    = off + off . sp Q
    : f mu ? . sp mean ( _ar_at raw off ) 0.0
    ^ @ ArimaCoef { phi th sphi sth mu }
}

@ _ar_at ( Vec f ) v i idx → f {
    ?? ( vec_get [f] v idx ) { T x → { ^ x } F _ → { ^ 0.0 } }
}

// Coefficients → raw vector; F when a polynomial is outside its region
// (then `raw` is left as it was for that polynomial).
@ __ar_raw_of_coef ArimaSpec sp ArimaCoef c ( Vec f ) raw → b {
    : ~ b ok T
    : ~ i off 0
    ? ( _ar_invpartrans . c phi raw off ) {} { = ok F }
    = off + off . sp p
    : ( Vec f ) nth ( __ar_vec_copy . c theta )
    : *f pt ( vec_data [f] nth )
    : ~ i k 0
    ~ < k . sp q { = . pt k - 0.0 . pt k = k + k 1 }
    ? ( _ar_invpartrans nth raw off ) {} { = ok F }
    ( vec_free [f] nth )
    = off + off . sp q
    ? ( _ar_invpartrans . c sphi raw off ) {} { = ok F }
    = off + off . sp P
    : ( Vec f ) nst ( __ar_vec_copy . c stheta )
    : *f ps ( vec_data [f] nst )
    = k 0
    ~ < k . sp Q { = . ps k - 0.0 . ps k = k + k 1 }
    ? ( _ar_invpartrans nst raw off ) {} { = ok F }
    ( vec_free [f] nst )
    = off + off . sp Q
    ? . sp mean { ( vec_set [f] raw off . c mu ) } {}
    ^ ok
}

// ── State space ───────────────────────────────────────────────────────
//
// State a (rd = r + nd): the ARMA part (r = max(p', q'+1), Harvey's form:
// a[0] is the ARMA value, the rest carry what the past still owes the
// future), then the last nd values of the undifferenced series. σ² = 1
// units throughout; the model's σ² scales variances on the way out.

: ArimaSS {
    i r
    i nd
    i rd
    ( Vec f ) phi  // r, the expanded AR coefficients padded with zeros
    ( Vec f ) theta  // r, θ_0 = 1 then the expanded MA padded
    ( Vec f ) delta  // nd
    ( Vec f ) a  // rd
    ( Vec f ) pm  // rd × rd, row-major
    ( Vec f ) scratch  // rd × rd
    ( Vec f ) scratch2  // rd × rd
    ( Vec f ) pz  // rd
    ( Vec f ) prev  // rd × rd, the covariance a step ago (the steady-state test)
    ( Vec f ) kg  // rd, the gain once the covariance has converged
    ( Vec f ) fz  // 2: [the innovation variance at convergence, 1.0 once converged]
}

// Has the covariance recursion converged (see _ar_step)?
@ _ar_ss_steady ArimaSS ss → b {
    : *f fz ( vec_data [f] . ss fz )
    ^ != . fz 1 0.0
}

@ _ar_ss_free ArimaSS ss → v {
    ( vec_free [f] . ss phi )
    ( vec_free [f] . ss theta )
    ( vec_free [f] . ss delta )
    ( vec_free [f] . ss a )
    ( vec_free [f] . ss pm )
    ( vec_free [f] . ss scratch )
    ( vec_free [f] . ss scratch2 )
    ( vec_free [f] . ss pz )
    ( vec_free [f] . ss prev )
    ( vec_free [f] . ss kg )
    ( vec_free [f] . ss fz )
}

// Build the form from expanded polynomials (ar: "1 − Σ φ B^k" φ's; ma:
// "1 + Σ θ B^k" θ's) and the differencing δ.
@ _ar_ss_new ( Vec f ) ar ( Vec f ) ma ( Vec f ) delta → ArimaSS {
    : i pf ( vec_len [f] ar )
    : i qf ( vec_len [f] ma )
    : ~ i r pf
    ? > + qf 1 r { = r + qf 1 } {}
    ? < r 1 { = r 1 } {}
    : i nd ( vec_len [f] delta )
    : i rd + r nd
    : ( Vec f ) phi ( vec_zeroed [f] r )
    : ( Vec f ) th ( vec_zeroed [f] r )
    : *f pphi ( vec_data [f] phi )
    : *f pth ( vec_data [f] th )
    : *f par ( vec_data [f] ar )
    : *f pma ( vec_data [f] ma )
    : ~ i k 0
    ~ < k pf { = . pphi k . par k = k + k 1 }
    = . pth 0 1.0
    = k 0
    ~ < k qf { = . pth + k 1 . pma k = k + k 1 }
    ^ @ ArimaSS { r nd rd phi th ( __ar_vec_copy delta ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] 2 ) }
}

// out = T · X for a square X (rd × rd), T the transition matrix by its
// structure: rows < r are the companion (φ_{i+1} x_0 + x_{i+1}), row r is
// Z (the observation row), rows beyond shift the differencing states.
@ __ar_tmul ArimaSS ss ( Vec f ) x ( Vec f ) out → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : *f X ( vec_data [f] x )
    : *f O ( vec_data [f] out )
    : *f phi ( vec_data [f] . ss phi )
    : *f dl ( vec_data [f] . ss delta )
    : ~ i i 0
    ~ < i r {
        : ~ i j 0
        ~ < j rd {
            : ~ f v * . phi i . X j
            ? < + i 1 r { = v + v . X + * + i 1 rd j } {}
            = . O + * i rd j v
            = j + j 1
        }
        = i + i 1
    }
    ? > nd 0 {
        : ~ i j 0
        ~ < j rd {
            : ~ f v . X j
            : ~ i k 0
            ~ < k nd { = v + v * . dl k . X + * + r k rd j = k + k 1 }
            = . O + * r rd j v
            = j + j 1
        }
        = i + r 1
        ~ < i rd {
            = j 0
            ~ < j rd { = . O + * i rd j . X + * - i 1 rd j = j + j 1 }
            = i + i 1
        }
    } {}
}

// out = M · Tᵀ: the same structure applied on the right.
@ __ar_tmul_right ArimaSS ss ( Vec f ) m ( Vec f ) out → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : *f M ( vec_data [f] m )
    : *f O ( vec_data [f] out )
    : *f phi ( vec_data [f] . ss phi )
    : *f dl ( vec_data [f] . ss delta )
    : ~ i i 0
    ~ < i rd {
        : i row * i rd
        : ~ i j 0
        ~ < j r {
            : ~ f v * . phi j . M row
            ? < + j 1 r { = v + v . M + row + j 1 } {}
            = . O + row j v
            = j + j 1
        }
        ? > nd 0 {
            : ~ f v . M row
            : ~ i k 0
            ~ < k nd { = v + v * . dl k . M + row + r k = k + k 1 }
            = . O + row r v
            = j + r 1
            ~ < j rd { = . O + row j . M + row - j 1 = j + j 1 }
        } {}
        = i + i 1
    }
}

// a ← T a.
@ __ar_tvec ArimaSS ss → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : *f A ( vec_data [f] . ss a )
    : *f O ( vec_data [f] . ss pz )
    : *f phi ( vec_data [f] . ss phi )
    : *f dl ( vec_data [f] . ss delta )
    : ~ i i 0
    ~ < i r {
        : ~ f v * . phi i . A 0
        ? < + i 1 r { = v + v . A + i 1 } {}
        = . O i v
        = i + i 1
    }
    ? > nd 0 {
        : ~ f v . A 0
        : ~ i k 0
        ~ < k nd { = v + v * . dl k . A + r k = k + k 1 }
        = . O r v
        = i + r 1
        ~ < i rd { = . O i . A - i 1 = i + i 1 }
    } {}
    = i 0
    ~ < i rd { = . A i . O i = i + i 1 }
}

// P ← T P Tᵀ + V, V = θ θᵀ on the ARMA block.
@ __ar_predict_cov ArimaSS ss → v {
    ( __ar_tmul ss . ss pm . ss scratch )
    ( __ar_tmul_right ss . ss scratch . ss pm )
    : i r . ss r
    : i rd . ss rd
    : *f P ( vec_data [f] . ss pm )
    : *f th ( vec_data [f] . ss theta )
    : ~ i i 0
    ~ < i r {
        : ~ i j 0
        ~ < j r {
            = . P + * i rd j + . P + * i rd j * . th i . th j
            = j + j 1
        }
        = i + i 1
    }
}

// Z a and Z P Zᵀ, P Z into pz.
@ __ar_observe ArimaSS ss → f {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : *f P ( vec_data [f] . ss pm )
    : *f pz ( vec_data [f] . ss pz )
    : *f dl ( vec_data [f] . ss delta )
    : ~ i i 0
    ~ < i rd {
        : ~ f v . P * i rd
        : ~ i k 0
        ~ < k nd { = v + v * . dl k . P + * i rd + r k = k + k 1 }
        = . pz i v
        = i + i 1
    }
    : ~ f fv . pz 0
    : ~ i k 0
    ~ < k nd { = fv + fv * . dl k . pz + r k = k + k 1 }
    ^ fv
}

@ __ar_predicted ArimaSS ss → f {
    : *f A ( vec_data [f] . ss a )
    : *f dl ( vec_data [f] . ss delta )
    : ~ f y . A 0
    : ~ i k 0
    ~ < k . ss nd { = y + y * . dl k . A + . ss r k = k + k 1 }
    ^ y
}

: ArimaStep {
    f innovation  // y − its one-step forecast
    f variance  // the forecast's variance, σ² units applied by the caller
    f predicted  // the one-step forecast that was made
}

// One filter step: observe y, update, predict the next. Returns the
// innovation and its variance in σ² = 1 units; F ≤ 0 makes the step
// report a negative variance (the caller treats that as failure).
// One filter step of the full model. The covariance recursion converges
// (the model is time-invariant); once the step moved it by no more than
// 10⁻¹⁴ (1 + F) in any element the gain is fixed — the steady state —
// and a step is O(r_d): the innovation, the state moved by the gain, the
// transition. Before that, the O(r_d²) covariance form. The two agree
// to the last bit with what the covariance form would go on producing,
// short of the increments it stopped adding.
@ _ar_step ArimaSS ss f y → ArimaStep {
    : i rd . ss rd
    : *f A ( vec_data [f] . ss a )
    : *f fz ( vec_data [f] . ss fz )
    ? != . fz 1 0.0 {
        : f fss . fz 0
        : f pred ( __ar_predicted ss )
        : f v - y pred
        : *f G ( vec_data [f] . ss kg )
        : ~ i i 0
        ~ < i rd { = . A i + . A i * . G i v = i + i 1 }
        ( __ar_tvec ss )
        ^ @ ArimaStep { v fss pred }
    } {}
    : f fv ( __ar_observe ss )
    : f pred ( __ar_predicted ss )
    : f v - y pred
    ? > fv 0.0 {} { ^ @ ArimaStep { v -1.0 pred } }
    : *f P ( vec_data [f] . ss pm )
    : *f pz ( vec_data [f] . ss pz )
    : f g / v fv
    : ~ i i 0
    ~ < i rd { = . A i + . A i * . pz i g = i + i 1 }
    = i 0
    ~ < i rd {
        : f pi / . pz i fv
        : ~ i j 0
        ~ < j rd { = . P + * i rd j - . P + * i rd j * pi . pz j = j + j 1 }
        = i + i 1
    }
    ( __ar_tvec ss )
    ( __ar_predict_cov ss )
    // the steady-state test against the covariance a step ago
    : *f Q ( vec_data [f] . ss prev )
    : ~ f dmax 0.0
    = i 0
    ~ < i * rd rd {
        : f dd ( float_abs - . P i . Q i )
        ? > dd dmax { = dmax dd } {}
        = . Q i . P i
        = i + i 1
    }
    ? <= dmax * 0.00000000000001 + 1.0 ( float_abs . P 0 ) {
        : f fss ( __ar_observe ss )
        ? > fss 0.0 {
            : *f G ( vec_data [f] . ss kg )
            = i 0
            ~ < i rd { = . G i / . pz i fss = i + i 1 }
            = . fz 0 fss
            = . fz 1 1.0
        } {}
    } {}
    ^ @ ArimaStep { v fv pred }
}

// Solve M x = b for a small dense system by Gaussian elimination with
// partial pivoting; M and b are overwritten, x lands in b. F when singular.
@ _ar_solve ( Vec f ) M ( Vec f ) b i n → b {
    : *f pm ( vec_data [f] M )
    : *f pb ( vec_data [f] b )
    : ~ i c 0
    ~ < c n {
        : ~ i piv c
        : ~ f best ( float_abs . pm + * c n c )
        : ~ i rr + c 1
        ~ < rr n {
            : f a ( float_abs . pm + * rr n c )
            ? > a best { = best a = piv rr } {}
            = rr + rr 1
        }
        ? <= best 0.0 { ^ F } {}
        ? != piv c {
            : ~ i j 0
            ~ < j n {
                : f t . pm + * c n j
                = . pm + * c n j . pm + * piv n j
                = . pm + * piv n j t
                = j + j 1
            }
            : f tb . pb c
            = . pb c . pb piv
            = . pb piv tb
        } {}
        : f pv . pm + * c n c
        = rr + c 1
        ~ < rr n {
            : f fac / . pm + * rr n c pv
            ? != fac 0.0 {
                : ~ i j c
                ~ < j n { = . pm + * rr n j - . pm + * rr n j * fac . pm + * c n j = j + j 1 }
                = . pb rr - . pb rr * fac . pb c
            } {}
            = rr + rr 1
        }
        = c + c 1
    }
    : ~ i i - n 1
    ~ >= i 0 {
        : ~ f v . pb i
        : ~ i j + i 1
        ~ < j n { = v - v * . pm + * i n j . pb j = j + j 1 }
        = . pb i / v . pm + * i n i
        = i - i 1
    }
    ^ T
}

// The autocovariances γ(0..m−1) of the ARMA(p', q') with expanded
// polynomials (σ² = 1): the Yule–Walker system for γ(0..p'), then the
// recursion. Also the ψ weights ψ(0..m−1). F when the system is singular.
@ _ar_autocov ( Vec f ) ar ( Vec f ) ma i m ( Vec f ) gamma ( Vec f ) psi → b {
    : i pf ( vec_len [f] ar )
    : i qf ( vec_len [f] ma )
    : *f par ( vec_data [f] ar )
    : *f pma ( vec_data [f] ma )
    : *f pg ( vec_data [f] gamma )
    : *f pp ( vec_data [f] psi )
    // ψ
    = . pp 0 1.0
    : ~ i k 1
    ~ < k m {
        : ~ f v ? <= k qf . pma - k 1 0.0
        : ~ i j 1
        ~ & <= j pf <= j k { = v + v * . par - j 1 . pp - k j = j + j 1 }
        = . pp k v
        = k + k 1
    }
    // γ(0..p')
    : i n1 + pf 1
    : ( Vec f ) M ( vec_zeroed [f] * n1 n1 )
    : ( Vec f ) rhs ( vec_zeroed [f] n1 )
    : *f pM ( vec_data [f] M )
    : *f pr ( vec_data [f] rhs )
    = k 0
    ~ < k n1 {
        = . pM + * k n1 k + . pM + * k n1 k 1.0
        : ~ i j 1
        ~ <= j pf {
            : i idx ? >= - k j 0 - k j - j k
            = . pM + * k n1 idx - . pM + * k n1 idx . par - j 1
            = j + j 1
        }
        : ~ f v 0.0
        = j k
        ~ <= j qf {
            : f thj ? == j 0 1.0 . pma - j 1
            = v + v * thj . pp - j k
            = j + j 1
        }
        = . pr k v
        = k + k 1
    }
    : b ok ( _ar_solve M rhs n1 )
    ? ok {
        = k 0
        ~ & < k n1 < k m { = . pg k . pr k = k + k 1 }
        = k n1
        ~ < k m {
            : ~ f v 0.0
            : ~ i j 1
            ~ <= j pf { = v + v * . par - j 1 . pg - k j = j + j 1 }
            = j k
            ~ <= j qf { = v + v * . pma - j 1 . pp - j k = j + j 1 }
            = . pg k v
            = k + k 1
        }
    } {}
    ( vec_free [f] M )
    ( vec_free [f] rhs )
    ^ ok
}

// The stationary covariance of the ARMA block, from the autocovariances:
// with a_t[i] = Σ_m (φ_{i+1+m} y_{t−1−m} + θ_{i+m} ε_{t−m}),
//   P = Φ Γ Φᵀ + Φ C Θᵀ + Θ Cᵀ Φᵀ + Θ Θᵀ,
// Φ[i][m] = φ_{i+1+m}, Θ[i][m] = θ_{i+m}, Γ[m][l] = γ(|m−l|),
// C[m][l] = ψ_{l−1−m} (l > m). Three r³ products, no iteration — the
// doubling recursion needed dozens of them for a seasonal polynomial's
// roots close to the circle. Writes the ARMA block of pm; the
// differencing block gets the diffuse prior.
@ _ar_init_cov ArimaSS ss → b {
    : i r . ss r
    : i rd . ss rd
    : *f P ( vec_data [f] . ss pm )
    ( __ar_fill . ss pm 0.0 )
    : *f phi ( vec_data [f] . ss phi )
    : *f th ( vec_data [f] . ss theta )
    // the expanded polynomials back from the padded state form
    : ~ i pf r
    ~ & > pf 0 == . phi - pf 1 0.0 { = pf - pf 1 }
    : ~ i qf - r 1
    ~ & > qf 0 == . th qf 0.0 { = qf - qf 1 }
    : ( Vec f ) ar ( vec_zeroed [f] pf )
    : ( Vec f ) ma ( vec_zeroed [f] qf )
    : ~ i k 0
    ~ < k pf { ( vec_set [f] ar k . phi k ) = k + k 1 }
    = k 0
    ~ < k qf { ( vec_set [f] ma k . th + k 1 ) = k + k 1 }
    : ( Vec f ) gamma ( vec_zeroed [f] r )
    : ( Vec f ) psi ( vec_zeroed [f] r )
    : b ok ( _ar_autocov ar ma r gamma psi )
    ( vec_free [f] ar )
    ( vec_free [f] ma )
    ? ok {
        : *f pg ( vec_data [f] gamma )
        : *f pp ( vec_data [f] psi )
        : ( Vec f ) A ( vec_zeroed [f] * r r )
        : ( Vec f ) B ( vec_zeroed [f] * r r )
        : *f pa ( vec_data [f] A )
        : *f pb ( vec_data [f] B )
        // A = Φ Γ, B = Φ C  (Φ[i][m] = φ_{i+1+m} = phi[i+m], zero past r)
        : ~ i i 0
        ~ < i r {
            : ~ i l 0
            ~ < l r {
                : ~ f va 0.0
                : ~ f vb 0.0
                : ~ i m 0
                ~ < m - r i {
                    : f f1 . phi + i m
                    : i dlt ? >= - m l 0 - m l - l m
                    = va + va * f1 . pg dlt
                    ? > l m { = vb + vb * f1 . pp - - l 1 m } {}
                    = m + m 1
                }
                = . pa + * i r l va
                = . pb + * i r l vb
                = l + l 1
            }
            = i + i 1
        }
        // P = A Φᵀ + B Θᵀ + (B Θᵀ)ᵀ + Θ Θᵀ  (Θ[j][l] = θ_{j+l} = th[j+l])
        = i 0
        ~ < i r {
            : ~ i j 0
            ~ < j r {
                : ~ f v 0.0
                : ~ i l 0
                ~ < l - r j {
                    : f fj . phi + j l
                    : f tj . th + j l
                    = v + v * . pa + * i r l fj
                    = v + v * . pb + * i r l tj
                    ? < l - r i { = v + v * . th + i l tj } {}
                    = l + l 1
                }
                = . P + * i rd j v
                = j + j 1
            }
            = i + i 1
        }
        // the (B Θᵀ)ᵀ term: add B Θᵀ transposed
        = i 0
        ~ < i r {
            : ~ i j 0
            ~ < j r {
                : ~ f v 0.0
                : ~ i l 0
                ~ < l - r i { = v + v * . pb + * j r l . th + i l = l + l 1 }
                = . P + * i rd j + . P + * i rd j v
                = j + j 1
            }
            = i + i 1
        }
        ( vec_free [f] A )
        ( vec_free [f] B )
    } {}
    ( vec_free [f] gamma )
    ( vec_free [f] psi )
    : ~ i i r
    ~ < i rd { = . P + * i rd i ARIMA_KAPPA = i + i 1 }
    ^ ok
}

// The same by doubling (P_{k+1} = P_k + A_k P_k A_kᵀ, A_{k+1} = A_k²):
// kept as the independent check of the closed form.
@ _ar_init_cov_doubling ArimaSS ss → b {
    : i r . ss r
    : i rd . ss rd
    : *f P ( vec_data [f] . ss pm )
    ( __ar_fill . ss pm 0.0 )
    // Dense r × r work: A, X, and two temporaries.
    : ( Vec f ) A ( vec_zeroed [f] * r r )
    : ( Vec f ) X ( vec_zeroed [f] * r r )
    : ( Vec f ) T1 ( vec_zeroed [f] * r r )
    : ( Vec f ) T2 ( vec_zeroed [f] * r r )
    : *f pa ( vec_data [f] A )
    : *f px ( vec_data [f] X )
    : *f t1 ( vec_data [f] T1 )
    : *f t2 ( vec_data [f] T2 )
    : *f phi ( vec_data [f] . ss phi )
    : *f th ( vec_data [f] . ss theta )
    : ~ i i 0
    ~ < i r {
        = . pa * i r . phi i
        ? < + i 1 r { = . pa + * i r + i 1 1.0 } {}
        : ~ i j 0
        ~ < j r { = . px + * i r j * . th i . th j = j + j 1 }
        = i + i 1
    }
    : ~ i iter 0
    : ~ b going T
    : ~ b ok T
    ~ & going < iter 64 {
        // T1 = A X ; X += T1 Aᵀ ; T2 = A A ; A = T2
        = i 0
        ~ < i r {
            : ~ i j 0
            ~ < j r {
                : ~ f v 0.0
                : ~ i k 0
                ~ < k r { = v + v * . pa + * i r k . px + * k r j = k + k 1 }
                = . t1 + * i r j v
                = j + j 1
            }
            = i + i 1
        }
        = i 0
        ~ < i r {
            : ~ i j 0
            ~ < j r {
                : ~ f v 0.0
                : ~ i k 0
                ~ < k r { = v + v * . t1 + * i r k . pa + * j r k = k + k 1 }
                = . px + * i r j + . px + * i r j v
                = j + j 1
            }
            = i + i 1
        }
        : ~ f amax 0.0
        = i 0
        ~ < i r {
            : ~ i j 0
            ~ < j r {
                : ~ f v 0.0
                : ~ i k 0
                ~ < k r { = v + v * . pa + * i r k . pa + * k r j = k + k 1 }
                = . t2 + * i r j v
                : f av ( float_abs v )
                ? > av amax { = amax av } {}
                = j + j 1
            }
            = i + i 1
        }
        = i 0
        ~ < i * r r { = . pa i . t2 i = i + i 1 }
        ? ( float_is_nan amax ) { = ok F = going F } {}
        ? < amax 0.0000000000000001 { = going F } {}
        = iter + iter 1
    }
    = i 0
    ~ < i r {
        : ~ i j 0
        ~ < j r { = . P + * i rd j . px + * i r j = j + j 1 }
        = i + i 1
    }
    = i r
    ~ < i rd { = . P + * i rd i ARIMA_KAPPA = i + i 1 }
    ( vec_free [f] A )
    ( vec_free [f] X )
    ( vec_free [f] T1 )
    ( vec_free [f] T2 )
    ^ ok
}

// ── Likelihoods ───────────────────────────────────────────────────────

: ArimaLik {
    b ok
    f loglik
    f sigma2
    i n_used
}

// The ARMA block alone, padded to the state's width: φ_1..φ_r and
// θ_0 = 1, θ_1..θ_{r−1} — what the exact likelihood works from.
: ArimaArma {
    i r
    ( Vec f ) phi
    ( Vec f ) theta
}

@ _ar_arma_new ( Vec f ) ar ( Vec f ) ma → ArimaArma {
    : i pf ( vec_len [f] ar )
    : i qf ( vec_len [f] ma )
    : ~ i r pf
    ? > + qf 1 r { = r + qf 1 } {}
    ? < r 1 { = r 1 } {}
    : ( Vec f ) phi ( vec_zeroed [f] r )
    : ( Vec f ) th ( vec_zeroed [f] r )
    : *f pphi ( vec_data [f] phi )
    : *f pth ( vec_data [f] th )
    : *f par ( vec_data [f] ar )
    : *f pma ( vec_data [f] ma )
    : ~ i k 0
    ~ < k pf { = . pphi k . par k = k + k 1 }
    = . pth 0 1.0
    = k 0
    ~ < k qf { = . pth + k 1 . pma k = k + k 1 }
    ^ @ ArimaArma { r phi th }
}

@ _ar_arma_free ArimaArma a → v {
    ( vec_free [f] . a phi )
    ( vec_free [f] . a theta )
}

// The first column of the stationary covariance, P e₀, in O(r²): the
// four terms of _ar_init_cov applied to the unit vector instead of
// multiplied out — Φ(Γ Φᵀe₀) + Φ(C Θᵀe₀) + Θ(Bᵀe₀) + Θ(Θᵀe₀) with B = ΦC.
// It is all the Chandrasekhar recursion needs of P.
@ _ar_init_col i r ( Vec f ) phiv ( Vec f ) thv ( Vec f ) out → b {
    : *f phi ( vec_data [f] phiv )
    : *f th ( vec_data [f] thv )
    : *f po ( vec_data [f] out )
    // the expanded polynomials back from the padded state form
    : ~ i pf r
    ~ & > pf 0 == . phi - pf 1 0.0 { = pf - pf 1 }
    : ~ i qf - r 1
    ~ & > qf 0 == . th qf 0.0 { = qf - qf 1 }
    : ( Vec f ) ar ( vec_zeroed [f] pf )
    : ( Vec f ) ma ( vec_zeroed [f] qf )
    : ~ i k 0
    ~ < k pf { ( vec_set [f] ar k . phi k ) = k + k 1 }
    = k 0
    ~ < k qf { ( vec_set [f] ma k . th + k 1 ) = k + k 1 }
    : ( Vec f ) gamma ( vec_zeroed [f] r )
    : ( Vec f ) psi ( vec_zeroed [f] r )
    : b ok ( _ar_autocov ar ma r gamma psi )
    ( vec_free [f] ar )
    ( vec_free [f] ma )
    ? ok {
        : *f pg ( vec_data [f] gamma )
        : *f pp ( vec_data [f] psi )
        // x = Γ Φᵀe₀, y = C Θᵀe₀, b = Bᵀe₀ — Φ[i][m] = φ_{i+m}, Θ[i][l] = θ_{i+l},
        // Γ[m][l] = γ(|m−l|), C[m][l] = ψ_{l−1−m} (l > m)
        : ( Vec f ) xv ( vec_zeroed [f] r )
        : ( Vec f ) yv ( vec_zeroed [f] r )
        : ( Vec f ) bv ( vec_zeroed [f] r )
        : *f x ( vec_data [f] xv )
        : *f y ( vec_data [f] yv )
        : *f b ( vec_data [f] bv )
        : ~ i m 0
        ~ < m r {
            : ~ f sx 0.0
            : ~ f sy 0.0
            : ~ f sb 0.0
            : ~ i l 0
            ~ < l r {
                : i dlt ? >= - m l 0 - m l - l m
                = sx + sx * . pg dlt . phi l
                ? > l m { = sy + sy * . pp - - l 1 m . th l } {}
                ? < l m { = sb + sb * . phi l . pp - - m 1 l } {}
                = l + l 1
            }
            = . x m sx
            = . y m sy
            = . b m sb
            = m + m 1
        }
        : ~ i i 0
        ~ < i r {
            : ~ f v 0.0
            : ~ i l 0
            ~ < l - r i {
                = v + v * . phi + i l + . x l . y l
                = v + v * . th + i l + . b l . th l
                = l + l 1
            }
            = . po i v
            = i + i 1
        }
        ( vec_free [f] xv )
        ( vec_free [f] yv )
        ( vec_free [f] bv )
    } {}
    ( vec_free [f] gamma )
    ( vec_free [f] psi )
    ^ ok
}

// The exact Gaussian likelihood of the stationary series `w` (mean μ)
// under the ARMA block, by the Chandrasekhar recursions (Morf, Sidhu &
// Kailath 1974; Herbst 2015 for this form). The filter's covariance
// recursion, started at the stationary P, moves by a rank-one increment
// P_{t+1} − P_t = W_t M_t W_tᵀ, and that increment has its own recursion —
// F_{t+1} = F_t + (Z W_t)² M_t, K_{t+1} = (K_t F_t + T W_t M_t Z W_t)/F_{t+1},
// W_{t+1} = (T − K_{t+1} Z) W_t, M_{t+1} = M_t + (M_t Z W_t)²/F_t — so a
// step costs O(r) where the covariance form costs O(r²): the same
// innovations and variances, arrived at without P. `col` is P e₀ (the
// start needs nothing else: F₁ = P₀₀, K₁ = T P e₀ / F₁, W₁ = K₁,
// M₁ = −F₁). Once the increment is below 10⁻¹⁴ (1 + F) in every element
// the gain is fixed — the steady state — and only the state moves.
@ _ar_filter_arma ( Vec f ) phiv ( Vec f ) thv ( Vec f ) col ( Vec f ) w f mu → ArimaLik {
    : i r ( vec_len [f] phiv )
    : i n ( vec_len [f] w )
    : *f phi ( vec_data [f] phiv )
    : *f p0 ( vec_data [f] col )
    : *f pw ( vec_data [f] w )
    : f f0 . p0 0
    ? > f0 0.0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : ( Vec f ) av ( vec_zeroed [f] r )
    : ( Vec f ) kv ( vec_zeroed [f] r )
    : ( Vec f ) wv ( vec_zeroed [f] r )
    : ( Vec f ) ov ( vec_zeroed [f] r )
    : *f A ( vec_data [f] av )
    : *f K ( vec_data [f] kv )
    : *f W ( vec_data [f] wv )
    : *f O ( vec_data [f] ov )
    : ~ i i 0
    ~ < i r {
        : ~ f v * . phi i . p0 0
        ? < + i 1 r { = v + v . p0 + i 1 } {}
        = . K i / v f0
        = . W i . K i
        = i + i 1
    }
    : ~ f fv f0
    : ~ f mm - 0.0 f0
    : ~ f logf ( float_log f0 )
    : ~ b frozen F
    : ~ b ok T
    : ~ f ssq 0.0
    : ~ f sumlog 0.0
    : ~ i t 0
    ~ & ok < t n {
        : f v - - . pw t mu . A 0
        = ssq + ssq / * v v fv
        = sumlog + sumlog logf
        // a ← T a + K v
        = i 0
        ~ < i r {
            : ~ f x * . phi i . A 0
            ? < + i 1 r { = x + x . A + i 1 } {}
            = . O i + x * . K i v
            = i + i 1
        }
        = i 0
        ~ < i r { = . A i . O i = i + i 1 }
        ? frozen {} {
            : f w0 . W 0
            : f fn + fv * * w0 w0 mm
            : ~ f wmax 0.0
            = i 0
            ~ < i r {
                : ~ f x * . phi i w0
                ? < + i 1 r { = x + x . W + i 1 } {}
                = . O i x
                : f aw ( float_abs . W i )
                ? > aw wmax { = wmax aw } {}
                = i + i 1
            }
            ? <= * ( float_abs mm ) * wmax wmax * 0.00000000000001 + 1.0 fv { = frozen T } {
                ? > fn 0.0 {
                    = i 0
                    ~ < i r {
                        = . K i / + * . K i fv * * . O i mm w0 fn
                        = . W i - . O i * . K i w0
                        = i + i 1
                    }
                    = mm + mm / * * mm w0 * mm w0 fv
                    = fv fn
                    = logf ( float_log fv )
                } { = ok F }
            }
        }
        = t + t 1
    }
    ( vec_free [f] av )
    ( vec_free [f] kv )
    ( vec_free [f] wv )
    ( vec_free [f] ov )
    ? ok {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    ^ ( _ar_lik_ml_from ssq sumlog n )
}

@ __ar_loglik_ml ArimaSpec sp ArimaCoef c ( Vec f ) w → ArimaLik {
    : ( Vec f ) ar ( _ar_expand_ar . c phi . c sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . c theta . c stheta . sp s )
    : ArimaArma am ( _ar_arma_new ar ma )
    ( vec_free [f] ar )
    ( vec_free [f] ma )
    : ( Vec f ) col ( vec_zeroed [f] . am r )
    : ~ ArimaLik out @ ArimaLik { F 0.0 0.0 0 }
    ? ( _ar_init_col . am r . am phi . am theta col ) {
        = out ( _ar_filter_arma . am phi . am theta col w . c mu )
    } {}
    ( vec_free [f] col )
    ( _ar_arma_free am )
    ^ out
}

// The exact log-likelihood from the filter's two sums — one formula for
// every route that produces them.
@ _ar_lik_ml_from f ssq f sumlog i n → ArimaLik {
    ? > n 0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : f s2 / ssq # f n
    ? > s2 0.0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : f ll * -0.5 + + * # f n + ARIMA_LOG_2PI ( float_log s2 ) sumlog # f n
    ? ( float_is_nan ll ) { ^ @ ArimaLik { F 0.0 0.0 0 } } {}
    ^ @ ArimaLik { T ll s2 n }
}

// The conditional-sum-of-squares "log-likelihood" from its sum.
@ _ar_lik_css_from f ssq i nu → ArimaLik {
    ? > nu 0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : f s2 / ssq # f nu
    ? > s2 0.0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : f ll * -0.5 * # f nu + + ARIMA_LOG_2PI ( float_log s2 ) 1.0
    ? ( float_is_nan ll ) { ^ @ ArimaLik { F 0.0 0.0 0 } } {}
    ^ @ ArimaLik { T ll s2 nu }
}

// Conditional sum of squares: residuals from the recursion with the
// first values as given and earlier shocks zero; the "log-likelihood"
// is the Gaussian one at those residuals. The recursion starts at
// max(p', ncond): a model's own order on a plain fit (R's arima), and
// the largest order in play when the stepwise search screens candidates
// by CSS — conditioning each on its own order scores the candidates on
// different observations, and the ones that drop more of the start win
// on the drop, not the fit (measured on a true AR(1): AR(4) by 5 AICc,
// against the exact likelihood's AR(1) by 4).
@ __ar_loglik_css ArimaSpec sp ArimaCoef c ( Vec f ) w i ncond → ArimaLik {
    : ( Vec f ) ar ( _ar_expand_ar . c phi . c sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . c theta . c stheta . sp s )
    : i pf ( vec_len [f] ar )
    : i qf ( vec_len [f] ma )
    : i n ( vec_len [f] w )
    : i nc ? > ncond pf ncond pf
    : ~ ArimaLik out @ ArimaLik { F 0.0 0.0 0 }
    ? > n nc {
        : ( Vec f ) e ( vec_zeroed [f] n )
        : *f pe ( vec_data [f] e )
        : *f pw ( vec_data [f] w )
        : *f par ( vec_data [f] ar )
        : *f pma ( vec_data [f] ma )
        // A seasonal polynomial is sparse — (p+1)(P+1)−1 terms across
        // s·P+p lags — and a zero coefficient's term is exactly zero, so
        // the lags that carry one are visited and the sums are the
        // dense recursion's bit for bit.
        : ( Vec i ) ari ( vec_new [i] )
        : ( Vec i ) mai ( vec_new [i] )
        : ~ i i 0
        ~ < i pf { ? == . par i 0.0 {} { ( vec_push [i] ari i ) } = i + i 1 }
        = i 0
        ~ < i qf { ? == . pma i 0.0 {} { ( vec_push [i] mai i ) } = i + i 1 }
        : i nar ( vec_len [i] ari )
        : i nma ( vec_len [i] mai )
        : *i pari ( vec_data [i] ari )
        : *i pmai ( vec_data [i] mai )
        : ~ f ssq 0.0
        : ~ i t nc
        ~ < t n {
            : ~ f v - . pw t . c mu
            = i 0
            ~ < i nar {
                : i lag . pari i
                = v - v * . par lag - . pw - t + lag 1 . c mu
                = i + i 1
            }
            : ~ i j 0
            ~ < j nma {
                : i lag . pmai j
                : i at - t + lag 1
                ? >= at nc { = v - v * . pma lag . pe at } {}
                = j + j 1
            }
            = . pe t v
            = ssq + ssq * v v
            = t + t 1
        }
        = out ( _ar_lik_css_from ssq - n nc )
        ( vec_free [f] e )
        ( vec_free [i] ari )
        ( vec_free [i] mai )
    } {}
    ( vec_free [f] ar )
    ( vec_free [f] ma )
    ^ out
}

// ── The optimizer: BFGS over the transformed parameters ───────────────

// What the objective needs to see: the spec, the differenced series, the
// method (and CSS's conditioning count), and a count of evaluations.
: ArimaObj {
    ArimaSpec sp
    ( Vec f ) w
    i method
    i ncond
    i evals
}

// Negative log-likelihood at raw parameters; a huge value where the
// likelihood does not exist. Pure: safe on any thread.
@ __ar_eval ArimaSpec sp ( Vec f ) w i method i ncond ( Vec f ) raw → f {
    : ArimaCoef c ( _ar_coef_of_raw sp raw )
    : ArimaLik lk ? == method ARIMA_CSS ( __ar_loglik_css sp c w ncond ) ( __ar_loglik_ml sp c w )
    ( _ar_coef_free c )
    ? . lk ok { ^ - 0.0 . lk loglik } {}
    ^ 1000000000000.0
}

@ __ar_objective * ArimaObj o ( Vec f ) raw → f {
    = . o evals + . o evals 1
    ^ ( __ar_eval . o sp . o w . o method . o ncond raw )
}

// One evaluation as a job: its parameters (raw, or — kind 1 — natural
// coefficients for the Hessian), its slot in the answers.
: ArimaJob {
    ArimaSpec sp
    ( Vec f ) w
    i method
    i ncond
    ( Vec f ) raw
    ( Vec f ) out
    i idx
    i kind  // 0 raw objective, 1 natural objective, 2/3 prepare (raw/natural, ML), 4/5 prepare (raw/natural, CSS)
    i extra  // a prepare job's *ArimaPrep
}

// A worker: every job whose index ≡ lane (mod stride).
: ArimaLane {
    ( Vec i ) jobs
    i lane
    i stride
}

@ __ar_job_run * ArimaJob j → v {
    ? >= . j kind 2 {
        : b natural | == . j kind 3 == . j kind 5
        : b cov < . j kind 4
        = . j extra # i ( _ar_prep_at . j sp . j raw natural cov )
        ^
    } {}
    ? == . j kind 1 {
        ( vec_set [f] . j out . j idx ( __ar_eval_natural . j sp . j w . j method . j ncond . j raw ) )
    } {
        ( vec_set [f] . j out . j idx ( __ar_eval . j sp . j w . j method . j ncond . j raw ) )
    }
}

@ __ar_lane_run * ArimaLane ln → v {
    : i n ( vec_len [i] . ln jobs )
    : ~ i k . ln lane
    ~ < k n {
        : *ArimaJob j # *ArimaJob ( _ar_geti . ln jobs k )
        ( __ar_job_run j )
        = k + k . ln stride
    }
}

// Run every job: on a pool of __ar_threads workers striding the list
// when `par`, else in place. Frees the jobs.
@ _ar_jobs_run ( Vec i ) jobs b par → v {
    : i n ( vec_len [i] jobs )
    : ~ i nt ? par ( __ar_threads ) 1
    ? > nt n { = nt n } {}
    ? > nt 1 {
        : ( Vec Thread ) ts ( vec_new [Thread] )
        : ( Vec i ) lanes ( vec_new [i] )
        : ~ i l 0
        ~ < l nt {
            : *ArimaLane ln # *ArimaLane ( nurl_malloc Z ArimaLane )
            = . ln jobs jobs
            = . ln lane l
            = . ln stride nt
            ( vec_push [i] lanes # i ln )
            // The runtime frees the closure's env once the body returns
            // (thread_spawn_owned); a spawn that fails runs the lane here
            // and frees the env by hand — it was handed over either way.
            : ( @ v ) body \ → v { ( __ar_lane_run ln ) }
            ?? ( thread_spawn_owned body ) {
                T t → { ( vec_push [Thread] ts t ) }
                F _ → { ( __ar_lane_run ln ) ( nurl_free # s # *u body 1 ) }
            }
            = l + l 1
        }
        = l 0
        ~ < l ( vec_len [Thread] ts ) { ?? ( vec_get [Thread] ts l ) { T t → { : i _j ( thread_join t ) } F _ → {} } = l + l 1 }
        = l 0
        ~ < l ( vec_len [i] lanes ) { ( nurl_free # s ( _ar_geti lanes l ) ) = l + l 1 }
        ( vec_free [Thread] ts )
        ( vec_free [i] lanes )
    } {
        : ~ i k 0
        ~ < k n { ( __ar_job_run # *ArimaJob ( _ar_geti jobs k ) ) = k + k 1 }
    }
}

// Free the jobs of a batch (their results have been read).
@ _ar_jobs_free ( Vec i ) jobs → v {
    : i n ( vec_len [i] jobs )
    : ~ i k 0
    ~ < k n { ( nurl_free # s ( _ar_geti jobs k ) ) = k + k 1 }
    ( vec_free [i] jobs )
}

// A state-space form at a parameter point, prepared for a device: the
// expanded polynomials, the padded state vectors and, for ML, the first
// column of the stationary covariance. What the kernel cannot compute
// itself.
: ArimaPrep {
    b ok
    i r
    ( Vec f ) phi
    ( Vec f ) theta
    ( Vec f ) p0  // ML: P e₀, r values
    ( Vec f ) ar
    ( Vec f ) ma
    f mu
}

@ _ar_prep_free * ArimaPrep p → v {
    ( vec_free [f] . p phi ) ( vec_free [f] . p theta ) ( vec_free [f] . p p0 )
    ( vec_free [f] . p ar ) ( vec_free [f] . p ma )
    ( nurl_free # s p )
}

// Prepare at `raw` (transformed parameters when natural = F, natural
// coefficients when T); with_cov adds the stationary covariance.
@ _ar_prep_at ArimaSpec sp ( Vec f ) raw b natural b with_cov → *ArimaPrep {
    : ArimaCoef cf ? natural ( _ar_coef_of_natural sp raw ) ( _ar_coef_of_raw sp raw )
    : *ArimaPrep p # *ArimaPrep ( nurl_malloc Z ArimaPrep )
    = . p ar ( _ar_expand_ar . cf phi . cf sphi . sp s )
    = . p ma ( _ar_expand_ma . cf theta . cf stheta . sp s )
    = . p mu . cf mu
    = . p ok T
    = . p r 0
    = . p phi ( vec_new [f] )
    = . p theta ( vec_new [f] )
    = . p p0 ( vec_new [f] )
    ? with_cov {
        : ArimaArma am ( _ar_arma_new . p ar . p ma )
        ( vec_free [f] . p phi ) ( vec_free [f] . p theta ) ( vec_free [f] . p p0 )
        = . p r . am r
        = . p phi . am phi
        = . p theta . am theta
        = . p p0 ( vec_zeroed [f] . am r )
        = . p ok ( _ar_init_col . am r . am phi . am theta . p p0 )
    } {}
    ( _ar_coef_free cf )
    ^ p
}

@ _ar_job_new ArimaSpec sp ( Vec f ) w i method i ncond ( Vec f ) raw ( Vec f ) out i idx i kind → i {
    : *ArimaJob j # *ArimaJob ( nurl_malloc Z ArimaJob )
    = . j sp sp
    = . j w w
    = . j method method
    = . j ncond ncond
    = . j raw raw
    = . j out out
    = . j idx idx
    = . j kind kind
    = . j extra 0
    ^ # i j
}

@ __ar_work * ArimaObj o → i {
    : ArimaSpec sp . o sp
    : i n ( vec_len [f] . o w )
    : i pf + . sp p * . sp s . sp P
    : i qf + . sp q * . sp s . sp Q
    ? == . o method ARIMA_CSS { ^ * n + + pf qf 1 } {}
    : ~ i r pf
    ? > + qf 1 r { = r + qf 1 } {}
    // the Chandrasekhar step is O(r), the start O(r²) plus a (p'+1)-wide solve
    ^ + * n * 4 r + * r r * * pf pf pf
}

// Evaluate the objective at every row of `raws` into `out`: on threads,
// __ar_threads at a time, when an evaluation is worth one; otherwise
// in place. Either way the answers are the same numbers.
@ __ar_eval_batch * ArimaObj o ( Vec ( Vec f ) ) raws ( Vec f ) out → v {
    : i m ( vec_len [( Vec f )] raws )
    = . o evals + . o evals m
    : b par & > ( __ar_work o ) ARIMA_PAR_WORK > m 1
    : ( Vec i ) jobs ( vec_new [i] )
    : ~ i i 0
    ~ < i m {
        ?? ( vec_get [( Vec f )] raws i ) {
            T rw → { ( vec_push [i] jobs ( _ar_job_new . o sp . o w . o method . o ncond rw out i 0 ) ) }
            F _ → {}
        }
        = i + i 1
    }
    ( _ar_jobs_run jobs par )
    ( _ar_jobs_free jobs )
}

// ── The optimizer as a state machine ──────────────────────────────────
//
// BFGS asks for function values in rounds — the start point and its
// gradient stencil, then a line-search trial, then the gradient at the
// accepted point — and never needs them one at a time. So the optimizer
// is a machine that SAYS what it wants next (`__ar_bfgs_requests`) and
// TAKES the answers (`__ar_bfgs_absorb`); whoever drives it evaluates
// the requests however it likes: in place, on threads, or — for many
// models at once — as one batch on a GPU. The order of evaluations and
// every arithmetic step are the same on every route, so the answer is.

: i ARIMA_PH_START 0
: i ARIMA_PH_GRAD 1
: i ARIMA_PH_TRIAL 2

: ArimaBfgs {
    i k
    ( Vec f ) raw
    ( Vec f ) g
    ( Vec f ) d
    ( Vec f ) s
    ( Vec f ) yv
    ( Vec f ) hy
    ( Vec f ) trial
    ( Vec f ) H
    ( Vec f ) hs  // the finite-difference steps of the pending stencil
    f f0
    f fn
    f alpha
    f gd
    i tries
    i iter
    i phase
    b converged
    b done
}

@ __ar_bfgs_new ( Vec f ) raw0 → *ArimaBfgs {
    : i k ( vec_len [f] raw0 )
    : *ArimaBfgs st # *ArimaBfgs ( nurl_malloc Z ArimaBfgs )
    = . st k k
    = . st raw ( __ar_vec_copy raw0 )
    = . st g ( vec_zeroed [f] k )
    = . st d ( vec_zeroed [f] k )
    = . st s ( vec_zeroed [f] k )
    = . st yv ( vec_zeroed [f] k )
    = . st hy ( vec_zeroed [f] k )
    = . st trial ( vec_zeroed [f] k )
    = . st H ( vec_zeroed [f] * k k )
    = . st hs ( vec_zeroed [f] k )
    : *f pH ( vec_data [f] . st H )
    : ~ i i 0
    ~ < i k { = . pH + * i k i 1.0 = i + i 1 }
    = . st f0 0.0
    = . st fn 0.0
    = . st alpha 1.0
    = . st gd 0.0
    = . st tries 0
    = . st iter 0
    = . st phase ARIMA_PH_START
    = . st converged F
    = . st done ? == k 0 T F
    ^ st
}

@ __ar_bfgs_free * ArimaBfgs st → v {
    ( vec_free [f] . st raw ) ( vec_free [f] . st g ) ( vec_free [f] . st d ) ( vec_free [f] . st s )
    ( vec_free [f] . st yv ) ( vec_free [f] . st hy ) ( vec_free [f] . st trial ) ( vec_free [f] . st H )
    ( vec_free [f] . st hs )
    ( nurl_free # s st )
}

// The 2k stencil points around raw, with the step of each coordinate
// recorded in hs.
@ __ar_bfgs_stencil * ArimaBfgs st ( Vec ( Vec f ) ) out → v {
    : i k . st k
    : *f pr ( vec_data [f] . st raw )
    : *f ph ( vec_data [f] . st hs )
    : ~ i i 0
    ~ < i k {
        : f x . pr i
        : ~ f h 0.00001
        : f ax ( float_abs x )
        ? > ax 1.0 { = h * h ax } {}
        = . ph i h
        : ( Vec f ) up ( __ar_vec_copy . st raw )
        ( vec_set [f] up i + x h )
        ( vec_push [( Vec f )] out up )
        : ( Vec f ) dn ( __ar_vec_copy . st raw )
        ( vec_set [f] dn i - x h )
        ( vec_push [( Vec f )] out dn )
        = i + i 1
    }
}

// What the machine wants evaluated next (owned by the caller).
@ __ar_bfgs_requests * ArimaBfgs st → ( Vec ( Vec f ) ) {
    : ( Vec ( Vec f ) ) out ( vec_new [( Vec f )] )
    ? . st done { ^ out } {}
    ? == . st phase ARIMA_PH_START {
        ( vec_push [( Vec f )] out ( __ar_vec_copy . st raw ) )
        ( __ar_bfgs_stencil st out )
    } {}
    ? == . st phase ARIMA_PH_GRAD { ( __ar_bfgs_stencil st out ) } {}
    ? == . st phase ARIMA_PH_TRIAL { ( vec_push [( Vec f )] out ( __ar_vec_copy . st trial ) ) } {}
    ^ out
}

// The gradient from stencil values starting at `off` in vals, into `into`.
@ __ar_bfgs_take_grad * ArimaBfgs st ( Vec f ) vals i off ( Vec f ) into → v {
    : i k . st k
    : *f pv ( vec_data [f] vals )
    : *f ph ( vec_data [f] . st hs )
    : *f pg ( vec_data [f] into )
    : ~ i i 0
    ~ < i k {
        = . pg i / - . pv + off * 2 i . pv + + off * 2 i 1 * 2.0 . ph i
        = i + i 1
    }
}

// From a gradient at raw: the direction d = −H g, and the first trial —
// no coordinate moving by more than one, the transform saturating beyond
// a few units.
@ __ar_bfgs_direction * ArimaBfgs st → v {
    : i k . st k
    : *f pg ( vec_data [f] . st g )
    : *f pd ( vec_data [f] . st d )
    : *f pH ( vec_data [f] . st H )
    : *f pr ( vec_data [f] . st raw )
    : *f pt ( vec_data [f] . st trial )
    : ~ f gd 0.0
    : ~ i i 0
    ~ < i k {
        : ~ f v 0.0
        : ~ i j 0
        ~ < j k { = v + v * . pH + * i k j . pg j = j + j 1 }
        = . pd i - 0.0 v
        = gd + gd * . pg i . pd i
        = i + i 1
    }
    ? >= gd 0.0 {
        = i 0
        ~ < i k {
            : ~ i j 0
            ~ < j k { = . pH + * i k j ? == i j 1.0 0.0 = j + j 1 }
            = . pd i - 0.0 . pg i
            = i + i 1
        }
        = gd 0.0
        = i 0
        ~ < i k { = gd - gd * . pg i . pg i = i + i 1 }
    } {}
    = . st gd gd
    : ~ f dmax 0.0
    = i 0
    ~ < i k { : f a ( float_abs . pd i ) ? > a dmax { = dmax a } {} = i + i 1 }
    = . st alpha ? > dmax 1.0 / 1.0 dmax 1.0
    = . st tries 0
    = i 0
    ~ < i k { = . pt i + . pr i * . st alpha . pd i = i + i 1 }
    = . st phase ARIMA_PH_TRIAL
}

// Take the values of the last request. Returns T when the machine is done.
@ __ar_bfgs_absorb * ArimaBfgs st ( Vec f ) vals → b {
    ? . st done { ^ T } {}
    : i k . st k
    : *f pv ( vec_data [f] vals )
    ? == . st phase ARIMA_PH_START {
        = . st f0 . pv 0
        ( __ar_bfgs_take_grad st vals 1 . st g )
        ( __ar_bfgs_direction st )
        ^ F
    } {}
    ? == . st phase ARIMA_PH_TRIAL {
        = . st fn . pv 0
        ? <= . st fn + . st f0 * * 0.0001 . st alpha . st gd {
            // accepted: move, then ask for the gradient there
            : *f pr ( vec_data [f] . st raw )
            : *f pt ( vec_data [f] . st trial )
            : *f ps ( vec_data [f] . st s )
            : ~ i i 0
            ~ < i k { = . ps i - . pt i . pr i = . pr i . pt i = i + i 1 }
            = . st phase ARIMA_PH_GRAD
            ^ F
        } {
            = . st tries + . st tries 1
            ? >= . st tries 40 {
                // No descent along d: the gradient is as good as it gets here.
                = . st converged T
                = . st done T
                ^ T
            } {}
            = . st alpha * . st alpha 0.5
            : *f pr ( vec_data [f] . st raw )
            : *f pt ( vec_data [f] . st trial )
            : *f pd ( vec_data [f] . st d )
            : ~ i i 0
            ~ < i k { = . pt i + . pr i * . st alpha . pd i = i + i 1 }
            ^ F
        }
    } {}
    // ARIMA_PH_GRAD: the gradient at the accepted point — the update.
    : ( Vec f ) gn ( vec_zeroed [f] k )
    ( __ar_bfgs_take_grad st vals 0 gn )
    : *f pg ( vec_data [f] . st g )
    : *f pgn ( vec_data [f] gn )
    : *f ps ( vec_data [f] . st s )
    : *f py ( vec_data [f] . st yv )
    : *f phy ( vec_data [f] . st hy )
    : *f pH ( vec_data [f] . st H )
    : ~ f smax 0.0
    : ~ f sy 0.0
    : ~ f gmax 0.0
    : ~ i i 0
    ~ < i k {
        : f a ( float_abs . ps i )
        ? > a smax { = smax a } {}
        = . py i - . pgn i . pg i
        = sy + sy * . ps i . py i
        : f ga ( float_abs . pgn i )
        ? > ga gmax { = gmax ga } {}
        = i + i 1
    }
    ? > sy 0.0000000001 {
        // The first update scales H to the curvature seen (Nocedal &
        // Wright 6.20), so the identity's unit scale never lingers.
        ? == . st iter 0 {
            : ~ f yy 0.0
            = i 0
            ~ < i k { = yy + yy * . py i . py i = i + i 1 }
            ? > yy 0.0 {
                : f sc / sy yy
                = i 0
                ~ < i k {
                    : ~ i j 0
                    ~ < j k { = . pH + * i k j ? == i j sc 0.0 = j + j 1 }
                    = i + i 1
                }
            } {}
        } {}
        // H ← (I − ρ s yᵀ) H (I − ρ y sᵀ) + ρ s sᵀ
        : f rho / 1.0 sy
        = i 0
        ~ < i k {
            : ~ f v 0.0
            : ~ i j 0
            ~ < j k { = v + v * . pH + * i k j . py j = j + j 1 }
            = . phy i v
            = i + i 1
        }
        : ~ f yhy 0.0
        = i 0
        ~ < i k { = yhy + yhy * . py i . phy i = i + i 1 }
        = i 0
        ~ < i k {
            : ~ i j 0
            ~ < j k {
                : f hij . pH + * i k j
                : f ss_term * * rho + 1.0 * rho yhy * . ps i . ps j
                : f cross * rho + * . phy i . ps j * . ps i . phy j
                = . pH + * i k j - + hij ss_term cross
                = j + j 1
            }
            = i + i 1
        }
    } {}
    : f df - . st f0 . st fn
    = . st f0 . st fn
    = i 0
    ~ < i k { = . pg i . pgn i = i + i 1 }
    ( vec_free [f] gn )
    = . st iter + . st iter 1
    : ~ b stop F
    ? | < df * ARIMA_TOL + 1.0 ( float_abs . st f0 ) < smax 0.000000001 {
        ? | < gmax 0.001 < smax 0.000000001 { = stop T } {}
    } {}
    ? < gmax 0.00001 { = stop T } {}
    ? stop { = . st converged T = . st done T ^ T } {}
    ? >= . st iter ARIMA_MAX_ITER { = . st done T ^ T } {}
    ( __ar_bfgs_direction st )
    ^ F
}

: ArimaOpt {
    b converged
    f value
    i iterations
}

// Minimise the objective from `raw` (updated in place): the machine
// driven with the batch evaluator.
@ __ar_bfgs * ArimaObj o ( Vec f ) raw → ArimaOpt {
    : i k ( vec_len [f] raw )
    ? == k 0 { ^ @ ArimaOpt { T ( __ar_objective o raw ) 0 } } {}
    : *ArimaBfgs st ( __ar_bfgs_new raw )
    : ~ b done F
    ~ ! done {
        : ( Vec ( Vec f ) ) reqs ( __ar_bfgs_requests st )
        : ( Vec f ) vals ( vec_zeroed [f] ( vec_len [( Vec f )] reqs ) )
        ( __ar_eval_batch o reqs vals )
        = done ( __ar_bfgs_absorb st vals )
        ( vec_free [f] vals )
        ( vec_free_with [( Vec f )] reqs \ ( Vec f ) v → v { ( vec_free [f] v ) } )
    }
    ( __ar_copy_into raw . st raw )
    : ArimaOpt out @ ArimaOpt { . st converged . st f0 . st iter }
    ( __ar_bfgs_free st )
    ^ out
}

// ── The model ─────────────────────────────────────────────────────────

: ArimaModel {
    ArimaSpec spec
    ArimaCoef coef
    f sigma2
    f loglik
    f aic
    f aicc
    f bic
    i n  // observations the model has absorbed (fit + updates)
    i n_fit  // observations the coefficients were fitted on
    i n_used  // differenced observations in the likelihood
    i method
    b converged
    i iterations
    i evals
    ArimaSS ss  // the full model's state after the last observation
    ( Vec f ) se  // standard errors, coefficient order (may be NaN)
    f last_innovation
    f last_variance
    f last_predicted
    ( Vec i ) xper  // Fourier periods in rows (empty: no regressors) — see arima_fit_harmonic
    i xk  // harmonics per period
    ( Vec f ) xcoef  // 1 + 2·xk·|xper|: the intercept, then per period and harmonic the sine and cosine weights
    i xt  // rows since the fit's origin: the index the next observation has in the regressors
}

@ arima_free * ArimaModel m → v {
    ( _ar_coef_free . m coef )
    ( _ar_ss_free . m ss )
    ( vec_free [f] . m se )
    ( vec_free [i] . m xper )
    ( vec_free [f] . m xcoef )
    ( nurl_free # s m )
}

// The deterministic seasonal at row `t`: the intercept and the Fourier
// terms of every period (0.0 when the model has none).
@ __ar_fourier * ArimaModel m i t → f {
    ? > . m xk 0 {} { ^ 0.0 }
    : *f c ( vec_data [f] . m xcoef )
    : *i per ( vec_data [i] . m xper )
    : i np ( vec_len [i] . m xper )
    : ~ f mu . c 0
    : ~ i q 1
    : ~ i p 0
    ~ < p np {
        : f base / * TAU # f t # f . per p
        : ~ i k 1
        ~ <= k . m xk {
            : f a * base # f k
            = mu + mu * . c q ( float_sin a )
            = mu + mu * . c + q 1 ( float_cos a )
            = q + q 2
            = k + k 1
        }
        = p + p 1
    }
    ^ mu
}

@ arima_spec_of * ArimaModel m → ArimaSpec { ^ . m spec }

@ arima_sigma2 * ArimaModel m → f { ^ . m sigma2 }

@ arima_loglik * ArimaModel m → f { ^ . m loglik }

@ arima_aic * ArimaModel m → f { ^ . m aic }

@ arima_aicc * ArimaModel m → f { ^ . m aicc }

@ arima_n * ArimaModel m → i { ^ . m n }

@ arima_converged * ArimaModel m → b { ^ . m converged }

@ arima_phi * ArimaModel m → ( Vec f ) { : ArimaCoef c . m coef ^ . c phi }

@ arima_theta * ArimaModel m → ( Vec f ) { : ArimaCoef c . m coef ^ . c theta }

@ arima_sphi * ArimaModel m → ( Vec f ) { : ArimaCoef c . m coef ^ . c sphi }

@ arima_stheta * ArimaModel m → ( Vec f ) { : ArimaCoef c . m coef ^ . c stheta }

@ arima_mu * ArimaModel m → f { : ArimaCoef c . m coef ^ . c mu }

// The full state-space form for the coefficients, with the differencing
// folded in, at its diffuse start.
@ __ar_full_ss ArimaSpec sp ArimaCoef c → ArimaSS {
    : ( Vec f ) ar ( _ar_expand_ar . c phi . c sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . c theta . c stheta . sp s )
    : ( Vec f ) delta ( _ar_delta . sp d . sp D . sp s )
    : ArimaSS ss ( _ar_ss_new ar ma delta )
    ( vec_free [f] ar )
    ( vec_free [f] ma )
    ( vec_free [f] delta )
    : b _ok ( _ar_init_cov ss )
    ^ ss
}

// Run the full model over the raw series to reach its end state. The
// mean is removed on the way in (the state holds y − μ).
@ __ar_run_full * ArimaModel m ( Vec f ) y → v {
    : i n ( vec_len [f] y )
    : *f py ( vec_data [f] y )
    : ArimaCoef mc . m coef
    : ArimaSS ss . m ss
    : ~ i t 0
    ~ < t n {
        : ArimaStep st ( _ar_step ss - . py t . mc mu )
        = . m last_innovation . st innovation
        = . m last_variance * . st variance . m sigma2
        = . m last_predicted + . st predicted . mc mu
        = t + t 1
    }
}

// Numerical Hessian of −loglik over the natural coefficients at the
// optimum → standard errors. NaN where the curvature is not positive.
@ __ar_stderr * ArimaModel m ( Vec f ) w → ( Vec f ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    ? == k 0 { ^ ( vec_zeroed [f] 0 ) } {}
    : ( Vec ( Vec f ) ) pts ( __ar_hessian_points m )
    : i np ( vec_len [( Vec f )] pts )
    : ( Vec f ) vals ( vec_zeroed [f] np )
    : ( Vec i ) jobs ( vec_new [i] )
    : ~ i q 0
    ~ < q np {
        ?? ( vec_get [( Vec f )] pts q ) { T pt → { ( vec_push [i] jobs ( _ar_job_new sp w . m method 0 pt vals q 1 ) ) } F _ → {} }
        = q + q 1
    }
    : *ArimaObj wo # *ArimaObj ( nurl_malloc Z ArimaObj )
    = . wo sp sp
    = . wo w w
    = . wo method . m method
    = . wo ncond 0
    = . wo evals 0
    : b par > * ( __ar_work wo ) np ARIMA_PAR_WORK
    ( nurl_free # s wo )
    ( _ar_jobs_run jobs par )
    ( _ar_jobs_free jobs )
    ( vec_free_with [( Vec f )] pts \ ( Vec f ) v → v { ( vec_free [f] v ) } )
    : ( Vec f ) se ( __ar_hessian_fold m vals )
    ( vec_free [f] vals )
    ^ se
}

// The finite-difference step of coordinate x.
@ __ar_hstep f x → f {
    : f ax ( float_abs x )
    ^ ? > ax 1.0 * 0.0001 ax 0.0001
}

// The stencil of the Hessian of −loglik over the natural coefficients at
// the model's optimum: four points per (i ≤ j) pair, natural coordinates.
@ __ar_hessian_points * ArimaModel m → ( Vec ( Vec f ) ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    : ( Vec f ) x ( _ar_natural_of_coef sp . m coef )
    : *f px ( vec_data [f] x )
    : ( Vec ( Vec f ) ) pts ( vec_new [( Vec f )] )
    : ~ i i 0
    ~ < i k {
        : ~ i j i
        ~ < j k {
            : f hi ( __ar_hstep . px i )
            : f hj ( __ar_hstep . px j )
            : ~ i sgn 0
            ~ < sgn 4 {
                : ( Vec f ) pt ( __ar_vec_copy x )
                : *f pp ( vec_data [f] pt )
                : f si ? < sgn 2 hi - 0.0 hi
                : f sj ? | == sgn 0 == sgn 2 hj - 0.0 hj
                = . pp i + . pp i si
                = . pp j + . pp j sj
                ( vec_push [( Vec f )] pts pt )
                = sgn + sgn 1
            }
            = j + j 1
        }
        = i + i 1
    }
    ( vec_free [f] x )
    ^ pts
}

// The stencil's values → standard errors (NaN where the curvature is
// not positive, or the Hessian is singular).
@ __ar_hessian_fold * ArimaModel m ( Vec f ) vals → ( Vec f ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    : ( Vec f ) se ( vec_zeroed [f] k )
    ? == k 0 { ^ se } {}
    : *f pse ( vec_data [f] se )
    : ( Vec f ) x ( _ar_natural_of_coef sp . m coef )
    : *f px ( vec_data [f] x )
    : ( Vec f ) Hm ( vec_zeroed [f] * k k )
    : *f pH ( vec_data [f] Hm )
    : *f pv ( vec_data [f] vals )
    : ~ i q 0
    : ~ i i 0
    ~ < i k {
        : ~ i j i
        ~ < j k {
            : f hi ( __ar_hstep . px i )
            : f hj ( __ar_hstep . px j )
            : f fpp . pv * 4 q
            : f fpm . pv + * 4 q 1
            : f fmp . pv + * 4 q 2
            : f fmm . pv + * 4 q 3
            : f v / - - + fpp fmm fpm fmp * * 4.0 hi hj
            = . pH + * i k j v
            = . pH + * j k i v
            = q + q 1
            = j + j 1
        }
        = i + i 1
    }
    // Invert by Gauss–Jordan; a failure leaves NaN everywhere.
    : ( Vec f ) inv ( vec_zeroed [f] * k k )
    : *f pi ( vec_data [f] inv )
    = i 0
    ~ < i k { = . pi + * i k i 1.0 = i + i 1 }
    : ~ b ok T
    : ~ i c 0
    ~ & ok < c k {
        : ~ i piv c
        : ~ f best ( float_abs . pH + * c k c )
        : ~ i rr + c 1
        ~ < rr k {
            : f a ( float_abs . pH + * rr k c )
            ? > a best { = best a = piv rr } {}
            = rr + rr 1
        }
        ? <= best 0.0000000000001 { = ok F } {
            ? != piv c {
                : ~ i j 0
                ~ < j k {
                    : f t1 . pH + * c k j
                    = . pH + * c k j . pH + * piv k j
                    = . pH + * piv k j t1
                    : f t2 . pi + * c k j
                    = . pi + * c k j . pi + * piv k j
                    = . pi + * piv k j t2
                    = j + j 1
                }
            } {}
            : f pv . pH + * c k c
            : ~ i j 0
            ~ < j k { = . pH + * c k j / . pH + * c k j pv = . pi + * c k j / . pi + * c k j pv = j + j 1 }
            = rr 0
            ~ < rr k {
                ? != rr c {
                    : f fac . pH + * rr k c
                    ? != fac 0.0 {
                        = j 0
                        ~ < j k {
                            = . pH + * rr k j - . pH + * rr k j * fac . pH + * c k j
                            = . pi + * rr k j - . pi + * rr k j * fac . pi + * c k j
                            = j + j 1
                        }
                    } {}
                } {}
                = rr + rr 1
            }
        }
        = c + c 1
    }
    = i 0
    ~ < i k {
        : f vii . pi + * i k i
        = . pse i ? & ok > vii 0.0 ( float_sqrt vii ) / 0.0 0.0
        = i + i 1
    }
    ( vec_free [f] x )
    ( vec_free [f] Hm )
    ( vec_free [f] inv )
    ^ se
}

@ __ar_eval_natural ArimaSpec sp ( Vec f ) w i method i ncond ( Vec f ) x → f {
    : ArimaCoef c ( _ar_coef_of_natural sp x )
    : ArimaLik lk ? == method ARIMA_CSS ( __ar_loglik_css sp c w ncond ) ( __ar_loglik_ml sp c w )
    ( _ar_coef_free c )
    ? . lk ok { ^ - 0.0 . lk loglik } {}
    ^ 1000000000000.0
}

// Natural coefficients (φ, θ, Φ, Θ, μ in one vector) → the bundle.
@ _ar_coef_of_natural ArimaSpec sp ( Vec f ) x → ArimaCoef {
    : ArimaCoef c ( _ar_coef_new sp )
    : *f px ( vec_data [f] x )
    : ~ i off 0
    : ~ i i 0
    ~ < i . sp p { ( vec_set [f] . c phi i . px + off i ) = i + i 1 }
    = off + off . sp p
    = i 0
    ~ < i . sp q { ( vec_set [f] . c theta i . px + off i ) = i + i 1 }
    = off + off . sp q
    = i 0
    ~ < i . sp P { ( vec_set [f] . c sphi i . px + off i ) = i + i 1 }
    = off + off . sp P
    = i 0
    ~ < i . sp Q { ( vec_set [f] . c stheta i . px + off i ) = i + i 1 }
    = off + off . sp Q
    ^ @ ArimaCoef { . c phi . c theta . c sphi . c stheta ? . sp mean . px off 0.0 }
}

// The bundle → the natural vector.
@ _ar_natural_of_coef ArimaSpec sp ArimaCoef mc → ( Vec f ) {
    : i k ( __ar_ncoef sp )
    : ( Vec f ) x ( vec_zeroed [f] k )
    : *f px ( vec_data [f] x )
    : ~ i off 0
    : ~ i i 0
    ~ < i . sp p { = . px + off i ( _ar_at . mc phi i ) = i + i 1 }
    = off + off . sp p
    = i 0
    ~ < i . sp q { = . px + off i ( _ar_at . mc theta i ) = i + i 1 }
    = off + off . sp q
    = i 0
    ~ < i . sp P { = . px + off i ( _ar_at . mc sphi i ) = i + i 1 }
    = off + off . sp P
    = i 0
    ~ < i . sp Q { = . px + off i ( _ar_at . mc stheta i ) = i + i 1 }
    = off + off . sp Q
    ? . sp mean { = . px off . mc mu } {}
    ^ x
}

@ arima_fit_method ( Vec f ) y ArimaSpec sp0 i method → *ArimaModel {
    ^ ( __ar_fit_cond y sp0 method 0 T )
}

// The fit with CSS's conditioning count given (0 = the model's own
// order; the search passes the largest order it screens); without
// `with_se` the model has neither standard errors nor a filtered state —
// a screened candidate, judged by its AICc and discarded.
@ __ar_fit_cond ( Vec f ) y ArimaSpec sp0 i method i ncond b with_se → *ArimaModel {
    : ArimaSpec sp ( arima_spec_with_mean sp0 . sp0 mean )
    : ( Vec f ) w ( arima_difference y . sp d . sp D . sp s )
    : ( Vec f ) raw ( __ar_raw_start w sp )
    : *ArimaObj o # *ArimaObj ( nurl_malloc Z ArimaObj )
    = . o sp sp
    = . o w w
    = . o method ARIMA_CSS
    = . o ncond ncond
    = . o evals 0
    : ~ ArimaOpt opt ( __ar_bfgs o raw )
    : ~ i iters . opt iterations
    ? == method ARIMA_ML {
        = . o method ARIMA_ML
        : ArimaOpt opt2 ( __ar_bfgs o raw )
        = opt opt2
        = iters + iters . opt2 iterations
    } {}
    : *ArimaModel m ( __ar_model_from_raw y w sp method ncond raw . opt converged iters . o evals with_se with_se )
    ( vec_free [f] raw )
    ( vec_free [f] w )
    ( nurl_free # s o )
    ^ m
}

// The model at an optimum: coefficients, statistics, standard errors,
// and the full state filtered over the raw series.
@ __ar_model_from_raw ( Vec f ) y ( Vec f ) w ArimaSpec sp i method i ncond ( Vec f ) raw b converged i iters i evals b with_se b with_state → *ArimaModel {
    : i k ( __ar_ncoef sp )
    : ArimaCoef c ( _ar_coef_of_raw sp raw )
    : ArimaLik lk ? == method ARIMA_CSS ( __ar_loglik_css sp c w ncond ) ( __ar_loglik_ml sp c w )
    : *ArimaModel m # *ArimaModel ( nurl_malloc Z ArimaModel )
    = . m spec sp
    = . m coef c
    = . m sigma2 . lk sigma2
    = . m loglik . lk loglik
    : f kk # f + k 1
    : f nn # f . lk n_used
    = . m aic + * -2.0 . lk loglik * 2.0 kk
    = . m aicc ? > - nn + kk 1.0 0.0 + . m aic / * * 2.0 kk + kk 1.0 - nn + kk 1.0 . m aic
    = . m bic + * -2.0 . lk loglik * kk ( float_log ? > nn 0.0 nn 1.0 )
    = . m n ( vec_len [f] y )
    = . m n_fit ( vec_len [f] y )
    = . m n_used . lk n_used
    = . m method method
    = . m converged & converged . lk ok
    = . m iterations iters
    = . m evals evals
    = . m ss ( __ar_full_ss sp c )
    = . m se ? with_se ( __ar_stderr m w ) ( vec_zeroed [f] k )
    = . m last_innovation 0.0
    = . m last_variance 0.0
    = . m last_predicted 0.0
    = . m xper ( vec_new [i] )
    = . m xk 0
    = . m xcoef ( vec_new [f] )
    = . m xt 0
    // The full model's pass over the raw series is O(n · r_d²) — for a
    // weekly season the cost of the fit itself over again — and a
    // candidate the search will discard has no use for a state.
    ? with_state { ( __ar_run_full m y ) } {}
    ^ m
}

// The starting parameters for a fit: zeros, the mean at the sample mean.
@ __ar_raw_start ( Vec f ) w ArimaSpec sp → ( Vec f ) {
    : i k ( __ar_ncoef sp )
    : ( Vec f ) raw ( vec_zeroed [f] k )
    ? . sp mean {
        : i n ( vec_len [f] w )
        : *f pw ( vec_data [f] w )
        : ~ f sum 0.0
        : ~ i t 0
        ~ < t n { = sum + sum . pw t = t + t 1 }
        ( vec_set [f] raw - k 1 ? > n 0 / sum # f n 0.0 )
    } {}
    ^ raw
}

// ── Many models at once ───────────────────────────────────────────────
//
// K series under one specification, fitted together: every model's
// optimizer asks for its round of evaluations, the rounds are joined
// into one batch, the batch is evaluated by whatever evaluator the
// caller hands in — the threaded CPU one below, or the GPU one in
// src/arima_gpu.nu — and the answers go back. A model that finishes its
// CSS stage moves on to ML while the others continue. The evaluations
// happen in the same order with the same arithmetic as in arima_fit, so
// the K models equal K separate fits.

// One evaluation of a batch: which context (series + method), at which
// parameters.
: ArimaEvalItem {
    i ctx
    ( Vec f ) raw
    i kind  // 0 = transformed parameters, 1 = natural coefficients
}

// A context: the differenced series, the specification, the method
// (and CSS's conditioning count, 0 = the model's own order).
: ArimaCtx {
    ArimaSpec sp
    ( Vec f ) w
    i method
    i ncond
}

// The threaded CPU evaluator: every item on a thread of its own,
// __ar_threads at a time, when one is worth it.
@ arima_eval_cpu ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) out → v {
    : i m ( vec_len [ArimaEvalItem] items )
    : ~ i big 0
    : ~ i i 0
    ~ < i m {
        ?? ( vec_get [ArimaEvalItem] items i ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → {
                        : *ArimaObj o # *ArimaObj ( nurl_malloc Z ArimaObj )
                        = . o sp . cx sp
                        = . o w . cx w
                        = . o method . cx method
                        = . o ncond . cx ncond
                        = . o evals 0
                        : i wk ( __ar_work o )
                        ? > wk big { = big wk } {}
                        ( nurl_free # s o )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    // Many small evaluations are worth threads together even when one
    // alone is not: the whole batch's work is what a thread amortises.
    : b par & > * big m ARIMA_PAR_WORK > m 1
    : ( Vec i ) jobs ( vec_new [i] )
    = i 0
    ~ < i m {
        ?? ( vec_get [ArimaEvalItem] items i ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → { ( vec_push [i] jobs ( _ar_job_new . cx sp . cx w . cx method . cx ncond . it raw out i . it kind ) ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    ( _ar_jobs_run jobs par )
    ( _ar_jobs_free jobs )
}

: ArimaFitState {
    * ArimaBfgs st
    i stage  // 0 = CSS running, 1 = ML running, 2 = finished
    i iters
    i evals
    b converged
    i req_at  // where this model's requests start in the current batch
    i req_n
}

// Fit `series` (each a raw series) under `sp` by `method`, the
// evaluations batched through `evaluator`.
@ arima_fit_many_with ( Vec ( Vec f ) ) series ArimaSpec sp0 i method ( @ v ( Vec ArimaEvalItem ) ( Vec ArimaCtx ) ( Vec f ) ) evaluator → ( Vec * ArimaModel ) {
    : ArimaSpec sp ( arima_spec_with_mean sp0 . sp0 mean )
    : i K ( vec_len [( Vec f )] series )
    // Per-model state lives on the heap, addressed through these.
    : ( Vec i ) ctxp ( vec_new [i] )
    : ( Vec i ) fsp ( vec_new [i] )
    : ~ i i 0
    ~ < i K {
        ?? ( vec_get [( Vec f )] series i ) {
            T y → {
                : ( Vec f ) w ( arima_difference y . sp d . sp D . sp s )
                : *ArimaCtx cx # *ArimaCtx ( nurl_malloc Z ArimaCtx )
                = . cx sp sp
                = . cx w w
                = . cx method ARIMA_CSS
                = . cx ncond 0
                ( vec_push [i] ctxp # i cx )
                : ( Vec f ) raw ( __ar_raw_start w sp )
                : *ArimaFitState f # *ArimaFitState ( nurl_malloc Z ArimaFitState )
                = . f st ( __ar_bfgs_new raw )
                ( vec_free [f] raw )
                = . f stage 0
                = . f iters 0
                = . f evals 0
                = . f converged F
                = . f req_at 0
                = . f req_n 0
                ( vec_push [i] fsp # i f )
            }
            F _ → {}
        }
        = i + i 1
    }
    : ~ b active T
    ~ active {
        = active F
        : ( Vec ArimaEvalItem ) items ( vec_new [ArimaEvalItem] )
        = i 0
        ~ < i K {
            : *ArimaFitState f # *ArimaFitState ( _ar_geti fsp i )
            = . f req_at ( vec_len [ArimaEvalItem] items )
            = . f req_n 0
            ? < . f stage 2 {
                : ( Vec ( Vec f ) ) reqs ( __ar_bfgs_requests . f st )
                : i nr ( vec_len [( Vec f )] reqs )
                : ~ i q 0
                ~ < q nr {
                    ?? ( vec_get [( Vec f )] reqs q ) { T rw → { ( vec_push [ArimaEvalItem] items @ ArimaEvalItem { i rw 0 } ) } F _ → {} }
                    = q + q 1
                }
                = . f req_n nr
                = . f evals + . f evals nr
                ( vec_free [( Vec f )] reqs )
                ? > nr 0 { = active T } {}
            } {}
            = i + i 1
        }
        ? active {
            : ( Vec f ) vals ( vec_zeroed [f] ( vec_len [ArimaEvalItem] items ) )
            // the contexts as the evaluator sees them, by value
            : ( Vec ArimaCtx ) ctxs ( vec_new [ArimaCtx] )
            = i 0
            ~ < i K {
                : *ArimaCtx cx # *ArimaCtx ( _ar_geti ctxp i )
                ( vec_push [ArimaCtx] ctxs @ ArimaCtx { . cx sp . cx w . cx method . cx ncond } )
                = i + i 1
            }
            ( evaluator items ctxs vals )
            ( vec_free [ArimaCtx] ctxs )
            : *f pv ( vec_data [f] vals )
            = i 0
            ~ < i K {
                : *ArimaFitState f # *ArimaFitState ( _ar_geti fsp i )
                ? & < . f stage 2 > . f req_n 0 {
                    : ( Vec f ) mine ( vec_zeroed [f] . f req_n )
                    : *f pm ( vec_data [f] mine )
                    : ~ i q 0
                    ~ < q . f req_n { = . pm q . pv + . f req_at q = q + q 1 }
                    : *ArimaBfgs st . f st
                    ? ( __ar_bfgs_absorb st mine ) {
                        = . f iters + . f iters . st iter
                        = . f converged . st converged
                        ? & == . f stage 0 == method ARIMA_ML {
                            // CSS done: ML from there
                            : *ArimaBfgs st2 ( __ar_bfgs_new . st raw )
                            ( __ar_bfgs_free st )
                            = . f st st2
                            = . f stage 1
                            : *ArimaCtx cx # *ArimaCtx ( _ar_geti ctxp i )
                            = . cx method ARIMA_ML
                        } { = . f stage 2 }
                    } {}
                    ( vec_free [f] mine )
                } {}
                = i + i 1
            }
            ( vec_free [f] vals )
        } {}
        ( vec_free_with [ArimaEvalItem] items \ ArimaEvalItem it → v { ( vec_free [f] . it raw ) } )
    }
    : ( Vec * ArimaModel ) out ( vec_new [* ArimaModel] )
    = i 0
    ~ < i K {
        : *ArimaFitState f # *ArimaFitState ( _ar_geti fsp i )
        : *ArimaCtx cx # *ArimaCtx ( _ar_geti ctxp i )
        ?? ( vec_get [( Vec f )] series i ) {
            T y → {
                : *ArimaBfgs st . f st
                ( vec_push [* ArimaModel] out ( __ar_model_from_raw y . cx w sp method 0 . st raw . f converged . f iters . f evals F T ) )
                ( __ar_bfgs_free st )
            }
            F _ → {}
        }
        ( nurl_free # s f )
        = i + i 1
    }
    // The standard errors: every model's Hessian stencil in one round.
    : ( Vec ArimaEvalItem ) hitems ( vec_new [ArimaEvalItem] )
    : ( Vec i ) hat ( vec_new [i] )
    : ( Vec i ) hn ( vec_new [i] )
    : ( Vec ArimaCtx ) hctx ( vec_new [ArimaCtx] )
    = i 0
    ~ < i K {
        : *ArimaCtx cx # *ArimaCtx ( _ar_geti ctxp i )
        = . cx method method
        ( vec_push [ArimaCtx] hctx @ ArimaCtx { . cx sp . cx w . cx method . cx ncond } )
        ( vec_push [i] hat ( vec_len [ArimaEvalItem] hitems ) )
        ?? ( vec_get [* ArimaModel] out i ) {
            T mm → {
                : ( Vec ( Vec f ) ) pts ( __ar_hessian_points mm )
                : i np ( vec_len [( Vec f )] pts )
                : ~ i q 0
                ~ < q np {
                    ?? ( vec_get [( Vec f )] pts q ) { T pt → { ( vec_push [ArimaEvalItem] hitems @ ArimaEvalItem { i pt 1 } ) } F _ → {} }
                    = q + q 1
                }
                ( vec_free [( Vec f )] pts )
                ( vec_push [i] hn np )
            }
            F _ → { ( vec_push [i] hn 0 ) }
        }
        = i + i 1
    }
    : ( Vec f ) hvals ( vec_zeroed [f] ( vec_len [ArimaEvalItem] hitems ) )
    ? > ( vec_len [ArimaEvalItem] hitems ) 0 { ( evaluator hitems hctx hvals ) } {}
    : *f phv ( vec_data [f] hvals )
    = i 0
    ~ < i K {
        ?? ( vec_get [* ArimaModel] out i ) {
            T mm → {
                : i np ( _ar_geti hn i )
                : i at ( _ar_geti hat i )
                : ( Vec f ) mine ( vec_zeroed [f] np )
                : *f pm ( vec_data [f] mine )
                : ~ i q 0
                ~ < q np { = . pm q . phv + at q = q + q 1 }
                ( vec_free [f] . mm se )
                = . mm se ( __ar_hessian_fold mm mine )
                ( vec_free [f] mine )
            }
            F _ → {}
        }
        : *ArimaCtx cx # *ArimaCtx ( _ar_geti ctxp i )
        ( vec_free [f] . cx w )
        ( nurl_free # s cx )
        = i + i 1
    }
    ( vec_free_with [ArimaEvalItem] hitems \ ArimaEvalItem it → v { ( vec_free [f] . it raw ) } )
    ( vec_free [f] hvals ) ( vec_free [i] hat ) ( vec_free [i] hn ) ( vec_free [ArimaCtx] hctx )
    ( vec_free [i] ctxp )
    ( vec_free [i] fsp )
    ^ out
}

@ _ar_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } }
}

// K series fitted together on the CPU's threads.
@ arima_fit_many ( Vec ( Vec f ) ) series ArimaSpec sp i method → ( Vec * ArimaModel ) {
    ^ ( arima_fit_many_with series sp method \ ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) out → v { ( arima_eval_cpu items ctxs out ) } )
}

@ arima_models_free ( Vec * ArimaModel ) ms → v {
    ( vec_free_with [* ArimaModel] ms \ * ArimaModel m → v { ( arima_free m ) } )
}

@ arima_fit ( Vec f ) y ArimaSpec sp → *ArimaModel {
    ^ ( arima_fit_method y sp ARIMA_ML )
}

// ── Forecasting and streaming ─────────────────────────────────────────

: ArimaForecast {
    ( Vec f ) mean
    ( Vec f ) se
}

@ arima_forecast_free ArimaForecast fc → v {
    ( vec_free [f] . fc mean )
    ( vec_free [f] . fc se )
}

// h steps ahead from the model's current state: means and standard
// errors (σ² applied). The state is left where it was.
@ arima_forecast * ArimaModel m i h → ArimaForecast {
    : ( Vec f ) mean ( vec_zeroed [f] h )
    : ( Vec f ) se ( vec_zeroed [f] h )
    : ArimaSS ss . m ss
    : ArimaCoef mc . m coef
    : ( Vec f ) a0 ( __ar_vec_copy . ss a )
    : ( Vec f ) p0 ( __ar_vec_copy . ss pm )
    : *f pm ( vec_data [f] mean )
    : *f pse ( vec_data [f] se )
    : ~ i j 0
    ~ < j h {
        : f fv ( __ar_observe ss )
        = . pm j + ( __ar_predicted ss ) . mc mu
        ? > . m xk 0 { = . pm j + . pm j ( __ar_fourier m + . m xt j ) } {}
        : f vr * fv . m sigma2
        = . pse j ? > vr 0.0 ( float_sqrt vr ) 0.0
        ( __ar_tvec ss )
        ( __ar_predict_cov ss )
        = j + j 1
    }
    // restore
    : *f A ( vec_data [f] . ss a )
    : *f P ( vec_data [f] . ss pm )
    : *f A0 ( vec_data [f] a0 )
    : *f P0 ( vec_data [f] p0 )
    : ~ i i 0
    ~ < i . ss rd { = . A i . A0 i = i + i 1 }
    = i 0
    ~ < i * . ss rd . ss rd { = . P i . P0 i = i + i 1 }
    ( vec_free [f] a0 )
    ( vec_free [f] p0 )
    ^ @ ArimaForecast { mean se }
}

: ArimaUpdate {
    f predicted  // what the model expected
    f innovation  // y − predicted
    f variance  // the forecast variance (σ² applied)
    f z  // innovation / √variance: how surprising y was
}

// One new observation: a Kalman step on the full model. The coefficients
// do not change; refit when the schedule says so.
//
// A NaN `y` is a missing observation: the step is the filter's time
// update alone — the state moves on, its uncertainty grows, nothing is
// learned — so a gap in a stream costs a tick of the clock and not a
// restart. The answer then carries what the model predicted and the
// variance it would have judged an observation by; innovation and z are
// NaN, because there was nothing to be surprised by.
@ arima_update * ArimaModel m f y → ArimaUpdate {
    : ArimaCoef mc . m coef
    : ArimaSS ss . m ss
    = . m n + . m n 1
    // with regressors the filter sees the reading less the seasonal
    // of this row, and the forecast is the filter's plus it
    : ~ f mu 0.0
    ? > . m xk 0 { = mu ( __ar_fourier m . m xt ) = . m xt + . m xt 1 } {}
    ? ( float_is_nan y ) {
        : f fv ( __ar_observe ss )
        : f pred + + ( __ar_predicted ss ) . mc mu mu
        : f vr * fv . m sigma2
        ( __ar_tvec ss )
        ( __ar_predict_cov ss )
        = . m last_innovation y
        = . m last_variance vr
        = . m last_predicted pred
        ^ @ ArimaUpdate { pred y vr y }
    } {}
    : ~ f yy y
    ? > . m xk 0 { = yy - y mu } {}
    : ArimaStep st ( _ar_step ss - yy . mc mu )
    : f vr * . st variance . m sigma2
    : f pred + + . st predicted . mc mu mu
    = . m last_innovation . st innovation
    = . m last_variance vr
    = . m last_predicted pred
    : f z ? > vr 0.0 / . st innovation ( float_sqrt vr ) 0.0
    ^ @ ArimaUpdate { pred . st innovation vr z }
}

// Forget the observations: the state goes back to where a freshly fitted
// model's stands before its first point (the stationary covariance for
// the ARMA part, diffuse for the differencing), `n` to 0. The
// coefficients stay. Feed the series again with arima_update and the
// state after n points is the state a fit over them would have left —
// which is how a caller replays a stored history through a model whose
// state has moved past it.
@ arima_restart * ArimaModel m → v {
    ( arima_restart_at m 0 )
}

// The same, with the regressors' clock set: `t0` is the row the next
// observation has, counted from the fit's origin (negative for rows
// before it) — a replay that begins elsewhere than the fit did keeps the
// seasonal's phase. A model without regressors ignores it.
@ arima_restart_at * ArimaModel m i t0 → v {
    ( _ar_ss_free . m ss )
    = . m ss ( __ar_full_ss . m spec . m coef )
    = . m n 0
    = . m last_innovation 0.0
    = . m last_variance 0.0
    = . m last_predicted 0.0
    = . m xt t0
}

// A deep copy: coefficients, fit statistics, standard errors and the
// state, so the copy can be stepped without moving the original.
@ arima_clone * ArimaModel m → *ArimaModel {
    : *ArimaModel c # *ArimaModel ( nurl_malloc Z ArimaModel )
    = . c spec . m spec
    = . c coef ( __ar_coef_clone . m coef )
    = . c sigma2 . m sigma2
    = . c loglik . m loglik
    = . c aic . m aic
    = . c aicc . m aicc
    = . c bic . m bic
    = . c n . m n
    = . c n_fit . m n_fit
    = . c n_used . m n_used
    = . c method . m method
    = . c converged . m converged
    = . c iterations . m iterations
    = . c evals . m evals
    : ArimaSS src . m ss
    = . c ss @ ArimaSS { . src r . src nd . src rd ( __ar_vec_copy . src phi ) ( __ar_vec_copy . src theta ) ( __ar_vec_copy . src delta ) ( __ar_vec_copy . src a ) ( __ar_vec_copy . src pm ) ( __ar_vec_copy . src scratch ) ( __ar_vec_copy . src scratch2 ) ( __ar_vec_copy . src pz ) ( __ar_vec_copy . src prev ) ( __ar_vec_copy . src kg ) ( __ar_vec_copy . src fz ) }
    = . c se ( __ar_vec_copy . m se )
    = . c last_innovation . m last_innovation
    = . c last_variance . m last_variance
    = . c last_predicted . m last_predicted
    = . c xper ( __ar_veci_copy . m xper )
    = . c xk . m xk
    = . c xcoef ( __ar_vec_copy . m xcoef )
    = . c xt . m xt
    ^ c
}

@ __ar_veci_copy ( Vec i ) src → ( Vec i ) {
    : i n ( vec_len [i] src )
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] out ( _ar_geti src k ) ) = k + k 1 }
    ^ out
}

// ── Regressors: Fourier terms for long or several seasons ─────────────
//
// A seasonal polynomial at lag s puts s rows into the state: at a
// minute's step the day is 1 440 of them, and a week at an hour's 168,
// which a state-space filter carries as an r_d² covariance — 2880² is
// not a model, it is a memory. The other standard form of a seasonal
// (Hyndman's `fourier()` with ARIMA errors) is deterministic: K
// harmonics per period, sine and cosine, fitted by least squares, and
// an ARMA on what is left. It takes any period length, several at once
// (the day and the week), and costs O(K) a row. It assumes the seasonal
// shape is fixed — a SARIMA lets it drift — so for a short season the
// polynomial is the better model and the Fourier terms an addition for
// a second, longer one.

// Fit `y` as Fourier terms of `periods` (rows) with `k` harmonics each,
// by least squares, then the ARIMA `sp` on the residuals by `method`,
// and attach the terms to the model: its updates and forecasts carry
// them, its state and statistics are the residual model's. `t = 0` is
// the first row of `y`.
@ arima_fit_harmonic ( Vec f ) y ( Vec i ) periods i k ArimaSpec sp i method → *ArimaModel {
    : ( Vec f ) coef ( __ar_fourier_ols y periods k )
    : ( Vec f ) res ( __ar_fourier_residuals y periods k coef )
    : *ArimaModel m ( arima_fit_method res sp method )
    ( __ar_attach_fourier m periods k coef ( vec_len [f] y ) )
    ( vec_free [f] res )
    ^ m
}

// The same with the residual model's order chosen by the stepwise
// search (`s` its season, 0 for none — the periods carry the long ones).
@ arima_auto_harmonic ( Vec f ) y ( Vec i ) periods i k i s → *ArimaModel {
    : ( Vec f ) coef ( __ar_fourier_ols y periods k )
    : ( Vec f ) res ( __ar_fourier_residuals y periods k coef )
    : *ArimaModel m ( arima_auto res s )
    ( __ar_attach_fourier m periods k coef ( vec_len [f] y ) )
    ( vec_free [f] res )
    ^ m
}

@ __ar_attach_fourier * ArimaModel m ( Vec i ) periods i k ( Vec f ) coef i n → v {
    ( vec_free [i] . m xper )
    ( vec_free [f] . m xcoef )
    = . m xper ( __ar_veci_copy periods )
    = . m xk ? > ( vec_len [i] periods ) 0 k 0
    = . m xcoef coef
    = . m xt n
}

// One row of the design: 1, then per period and harmonic sin, cos.
@ __ar_fourier_row ( Vec i ) periods i k i t ( Vec f ) row → v {
    : *f x ( vec_data [f] row )
    = . x 0 1.0
    : ~ i q 1
    : i np ( vec_len [i] periods )
    : ~ i p 0
    ~ < p np {
        : f base / * TAU # f t # f ( _ar_geti periods p )
        : ~ i j 1
        ~ <= j k {
            : f a * base # f j
            = . x q ( float_sin a )
            = . x + q 1 ( float_cos a )
            = q + q 2
            = j + j 1
        }
        = p + p 1
    }
}

// Least squares by the normal equations (a handful of columns; rows
// with a NaN reading are left out). Zeros when the system is singular
// — fewer rows than columns.
@ __ar_fourier_ols ( Vec f ) y ( Vec i ) periods i k → ( Vec f ) {
    : i n ( vec_len [f] y )
    : i nc + 1 * 2 * k ( vec_len [i] periods )
    : ( Vec f ) M ( vec_zeroed [f] * nc nc )
    : ( Vec f ) b ( vec_zeroed [f] nc )
    : ( Vec f ) row ( vec_zeroed [f] nc )
    : *f pm ( vec_data [f] M )
    : *f pb ( vec_data [f] b )
    : *f pr ( vec_data [f] row )
    : *f py ( vec_data [f] y )
    : ~ i t 0
    ~ < t n {
        : f v . py t
        ? ( float_is_nan v ) {} {
            ( __ar_fourier_row periods k t row )
            : ~ i i 0
            ~ < i nc {
                = . pb i + . pb i * . pr i v
                : ~ i j 0
                ~ < j nc { = . pm + * i nc j + . pm + * i nc j * . pr i . pr j = j + j 1 }
                = i + i 1
            }
        }
        = t + t 1
    }
    ? ( _ar_solve M b nc ) {} { ( __ar_fill b 0.0 ) }
    ( vec_free [f] M )
    ( vec_free [f] row )
    ^ b
}

@ __ar_fourier_residuals ( Vec f ) y ( Vec i ) periods i k ( Vec f ) coef → ( Vec f ) {
    : i n ( vec_len [f] y )
    : i nc ( vec_len [f] coef )
    : ( Vec f ) res ( vec_zeroed [f] n )
    : ( Vec f ) row ( vec_zeroed [f] nc )
    : *f pr ( vec_data [f] row )
    : *f pc ( vec_data [f] coef )
    : *f py ( vec_data [f] y )
    : *f po ( vec_data [f] res )
    : ~ i t 0
    ~ < t n {
        ( __ar_fourier_row periods k t row )
        : ~ f mu 0.0
        : ~ i i 0
        ~ < i nc { = mu + mu * . pr i . pc i = i + i 1 }
        = . po t - . py t mu
        = t + t 1
    }
    ( vec_free [f] row )
    ^ res
}

// ── Order selection ───────────────────────────────────────────────────
//
// The Hyndman–Khandakar stepwise search: how many differences by the KPSS
// test (level stationarity, 5 %), a seasonal difference when the
// autocorrelation at the seasonal lag says the season dominates, then
// from four starting orders the best by AICc, each neighbour tried in
// turn — one more or one fewer of p, q, P, Q, the mean toggled — until
// nothing nearby is better.

// The KPSS statistic for level stationarity of `x`, with the Bartlett
// long-run variance over l = 4 (n/100)^{1/4} lags (Kwiatkowski et al.).
@ arima_kpss ( Vec f ) x → f {
    : i n ( vec_len [f] x )
    ? < n 8 { ^ 0.0 } {}
    : *f px ( vec_data [f] x )
    : ~ f mean 0.0
    : ~ i t 0
    ~ < t n { = mean + mean . px t = t + t 1 }
    = mean / mean # f n
    : ( Vec f ) e ( vec_zeroed [f] n )
    : *f pe ( vec_data [f] e )
    : ~ f s 0.0
    : ~ f eta 0.0
    : ~ f s2 0.0
    = t 0
    ~ < t n {
        = . pe t - . px t mean
        = s + s . pe t
        = eta + eta * s s
        = s2 + s2 * . pe t . pe t
        = t + t 1
    }
    : i l # i ( float_floor * 4.0 ( float_pow / # f n 100.0 0.25 ) )
    : ~ f lrv s2
    : ~ i k 1
    ~ <= k l {
        : ~ f g 0.0
        = t k
        ~ < t n { = g + g * . pe t . pe - t k = t + t 1 }
        = lrv + lrv * * 2.0 - 1.0 / # f k # f + l 1 g
        = k + k 1
    }
    = lrv / lrv # f n
    ( vec_free [f] e )
    ? > lrv 0.0 {} { ^ 0.0 }
    ^ / eta * # f n * # f n lrv
}

// Differences needed for level stationarity: KPSS at 5 % (0.463), at
// most two.
@ arima_ndiffs ( Vec f ) y → i {
    : ~ i d 0
    : ~ ( Vec f ) cur ( __ar_vec_copy y )
    : ~ b going T
    ~ & going < d 2 {
        ? > ( arima_kpss cur ) 0.463 {
            : ( Vec f ) nxt ( arima_difference cur 1 0 0 )
            ( vec_free [f] cur )
            = cur nxt
            = d + d 1
        } { = going F }
    }
    ( vec_free [f] cur )
    ^ d
}

// The sample autocorrelation of x at lag k.
@ arima_acf ( Vec f ) x i k → f {
    : i n ( vec_len [f] x )
    ? | <= k 0 >= k n { ^ 0.0 } {}
    : *f px ( vec_data [f] x )
    : ~ f mean 0.0
    : ~ i t 0
    ~ < t n { = mean + mean . px t = t + t 1 }
    = mean / mean # f n
    : ~ f c0 0.0
    : ~ f ck 0.0
    = t 0
    ~ < t n {
        : f e - . px t mean
        = c0 + c0 * e e
        ? >= t k { = ck + ck * e - . px - t k mean } {}
        = t + t 1
    }
    ? > c0 0.0 {} { ^ 0.0 }
    ^ / ck c0
}

// A seasonal difference when the season carries the series: the
// autocorrelation at lag s of the (first-differenced, if d > 0) series
// above 0.5 — the rule of thumb behind the older auto.arima.
@ arima_nsdiffs ( Vec f ) y i s i d → i {
    ? | < s 2 < ( vec_len [f] y ) * 3 s { ^ 0 } {}
    : ( Vec f ) w ( arima_difference y d 0 0 )
    : f r ( arima_acf w s )
    ( vec_free [f] w )
    ^ ? > r 0.5 1 0
}

@ __ar_try ( Vec f ) y ArimaSpec sp i method i ncond → *ArimaModel {
    ^ ( __ar_fit_cond y sp method ncond F )
}

// Is the candidate worth a look: within the bounds, not already tried.
@ __ar_auto_step ( Vec f ) y ArimaSpec cand * ArimaModel best ( Vec i ) tried i max_pq i max_PQ i method i ncond → *ArimaModel {
    ? | | | | | < . cand p 0 < . cand q 0 > . cand p max_pq > . cand q max_pq < . cand P 0 < . cand Q 0 { ^ best } {}
    ? | > . cand P max_PQ > . cand Q max_PQ { ^ best } {}
    : i key + + + + * . cand p 1000000 * . cand q 10000 * . cand P 100 * . cand Q 10 ? . cand mean 1 0
    ? ( vec_contains [i] tried key \ i a i b → b { ^ == a b } ) { ^ best } {}
    ( vec_push [i] tried key )
    : *ArimaModel m ( __ar_try y cand method ncond )
    ? & . m converged < . m aicc . best aicc {
        ( arima_free best )
        ^ m
    } {}
    ( arima_free m )
    ^ best
}

// Stepwise search; `s` is the season (0 = none), d and D chosen by the
// tests above. Returns the best model found.
@ arima_auto ( Vec f ) y i s → *ArimaModel {
    : i d ( arima_ndiffs y )
    : i D ( arima_nsdiffs y s d )
    ^ ( arima_auto_d y s d D )
}

// Candidates are screened by conditional sum of squares — the way
// auto.arima approximates — whenever the series is longer than
// ARIMA_SCREEN_N points or the season longer than ARIMA_SCREEN_S (R's
// rule: `approximation = n > 150 | frequency > 12`), and the winner is
// then refitted by ML. Below that, every candidate gets the exact
// likelihood. The rule is about the search, not one fit: a daily season
// on hourly data makes a candidate's state 50 wide, and the stepwise
// search evaluates thousands of likelihoods — 42 s exactly against 0.3 s
// screened, for the same chosen order.
: i ARIMA_SCREEN_N 150
: i ARIMA_SCREEN_S 12

@ arima_auto_d ( Vec f ) y i s i d i D → *ArimaModel {
    : b seasonal > s 1
    : i max_pq 5
    : i max_PQ ? seasonal 2 0
    : b mean0 == + d D 0
    : i n ( vec_len [f] y )
    : i method ? | > n ARIMA_SCREEN_N > s ARIMA_SCREEN_S ARIMA_CSS ARIMA_ML
    // every screened candidate conditions on the largest order in play
    : i ncond + max_pq * s max_PQ
    : ( Vec i ) tried ( vec_new [i] )
    : ~ * ArimaModel best ( __ar_try y ( arima_spec_with_mean ( arima_spec_seasonal 2 d 2 ? seasonal 1 0 D ? seasonal 1 0 s ) mean0 ) method ncond )
    ( vec_push [i] tried + + + + * 2 1000000 * 2 10000 * ? seasonal 1 0 100 * ? seasonal 1 0 10 ? mean0 1 0 )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 0 d 0 0 D 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 1 d 0 ? seasonal 1 0 D 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 0 d 1 0 D ? seasonal 1 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    : ~ b improved T
    : ~ i rounds 0
    ~ & improved < rounds 30 {
        = improved F
        : ArimaSpec b . best spec
        : f before . best aicc
        = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal + . b p 1 d . b q . b P D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
        = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal - . b p 1 d . b q . b P D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
        = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d + . b q 1 . b P D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
        = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d - . b q 1 . b P D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
        ? seasonal {
            = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d . b q + . b P 1 D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
            = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d . b q - . b P 1 D . b Q s ) . b mean ) best tried max_pq max_PQ method ncond )
            = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d . b q . b P D + . b Q 1 s ) . b mean ) best tried max_pq max_PQ method ncond )
            = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d . b q . b P D - . b Q 1 s ) . b mean ) best tried max_pq max_PQ method ncond )
        } {}
        ? == + d D 0 {
            = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal . b p d . b q . b P D . b Q s ) ! . b mean ) best tried max_pq max_PQ method ncond )
        } {}
        ? < . best aicc before { = improved T } {}
        = rounds + rounds 1
    }
    ( vec_free [i] tried )
    // The chosen order fitted in full — exactly where the screening was
    // approximate, and with its standard errors and state either way.
    : *ArimaModel exact ( arima_fit_method y . best spec ARIMA_ML )
    ( arima_free best )
    ^ exact
}

// ── Reporting ─────────────────────────────────────────────────────────

@ _ar_jarr ( Vec f ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [f] v )
    : *f p ( vec_data [f] v )
    : ~ i k 0
    ~ < k n { ( json_arr_push a ( json_float . p k ) ) = k + k 1 }
    ^ a
}

@ __ar_jspec ArimaSpec sp → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `p` ( json_int . sp p ) )
    ( json_obj_set o `d` ( json_int . sp d ) )
    ( json_obj_set o `q` ( json_int . sp q ) )
    ( json_obj_set o `P` ( json_int . sp P ) )
    ( json_obj_set o `D` ( json_int . sp D ) )
    ( json_obj_set o `Q` ( json_int . sp Q ) )
    ( json_obj_set o `s` ( json_int . sp s ) )
    ( json_obj_set o `mean` ( json_bool . sp mean ) )
    ^ o
}

// Coefficients and fit statistics as JSON, for a report or a table.
@ arima_coef * ArimaModel m → Json {
    : Json o ( json_obj_new )
    : ArimaCoef mc . m coef
    ( json_obj_set o `order` ( __ar_jspec . m spec ) )
    ( json_obj_set o `phi` ( _ar_jarr . mc phi ) )
    ( json_obj_set o `theta` ( _ar_jarr . mc theta ) )
    ( json_obj_set o `seasonal_phi` ( _ar_jarr . mc sphi ) )
    ( json_obj_set o `seasonal_theta` ( _ar_jarr . mc stheta ) )
    ( json_obj_set o `mu` ( json_float . mc mu ) )
    ? > . m xk 0 {
        : Json fo ( json_obj_new )
        ( json_obj_set fo `periods` ( __ar_jints . m xper ) )
        ( json_obj_set fo `k` ( json_int . m xk ) )
        ( json_obj_set fo `coef` ( _ar_jarr . m xcoef ) )
        ( json_obj_set o `fourier` fo )
    } {}
    ( json_obj_set o `sigma2` ( json_float . m sigma2 ) )
    ( json_obj_set o `loglik` ( json_float . m loglik ) )
    ( json_obj_set o `aic` ( json_float . m aic ) )
    ( json_obj_set o `aicc` ( json_float . m aicc ) )
    ( json_obj_set o `bic` ( json_float . m bic ) )
    ( json_obj_set o `se` ( _ar_jarr . m se ) )
    ( json_obj_set o `n` ( json_int . m n ) )
    ( json_obj_set o `n_used` ( json_int . m n_used ) )
    ( json_obj_set o `method` ( json_str_lit ? == . m method ARIMA_CSS `css` `ml` ) )
    ( json_obj_set o `converged` ( json_bool . m converged ) )
    ( json_obj_set o `iterations` ( json_int . m iterations ) )
    ( json_obj_set o `evaluations` ( json_int . m evals ) )
    ^ o
}

// ── Persistence ───────────────────────────────────────────────────────
//
// Floats travel as their IEEE bits (hex) so a round trip is exact.

@ __ar_jints ( Vec i ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n { ( json_arr_push a ( json_int ( _ar_geti v k ) ) ) = k + k 1 }
    ^ a
}

@ __ar_jbits ( Vec f ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [f] v )
    : *f p ( vec_data [f] v )
    : ~ i k 0
    ~ < k n {
        ( json_arr_push a ( json_int ( f64_to_bits . p k ) ) )
        = k + k 1
    }
    ^ a
}

@ __ar_jbit f x → Json {
    ^ ( json_int ( f64_to_bits x ) )
}

@ __ar_unbits Json a → ( Vec f ) {
    : i n ( json_arr_len a )
    : ( Vec f ) out ( vec_zeroed [f] n )
    : *f p ( vec_data [f] out )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get a k ) {
            T v → { ? ( json_is_num v ) { = . p k ( bits_to_f64 ( json_as_int v ) ) } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

@ __ar_unbit Json o s key → f {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( bits_to_f64 ( json_as_int v ) ) } {} }
        F _ → {}
    }
    ^ 0.0
}

@ __ar_jint_of Json e → i {
    ?? ( json_num_as_i e ) { T x → { ^ x } F _ → { ^ 0 } }
}

@ __ar_jint Json o s key → i {
    ?? ( json_obj_get o key ) { T v → { ^ ( json_as_int v ) } F _ → {} }
    ^ 0
}

@ arima_to_json * ArimaModel m → String {
    : Json o ( json_obj_new )
    : ArimaCoef mc . m coef
    : ArimaSS ss . m ss
    ( json_obj_set o `format` ( json_str_lit `arima-1` ) )
    ( json_obj_set o `order` ( __ar_jspec . m spec ) )
    ( json_obj_set o `phi` ( __ar_jbits . mc phi ) )
    ( json_obj_set o `theta` ( __ar_jbits . mc theta ) )
    ( json_obj_set o `seasonal_phi` ( __ar_jbits . mc sphi ) )
    ( json_obj_set o `seasonal_theta` ( __ar_jbits . mc stheta ) )
    ( json_obj_set o `mu` ( __ar_jbit . mc mu ) )
    ( json_obj_set o `sigma2` ( __ar_jbit . m sigma2 ) )
    ( json_obj_set o `loglik` ( __ar_jbit . m loglik ) )
    ( json_obj_set o `aic` ( __ar_jbit . m aic ) )
    ( json_obj_set o `aicc` ( __ar_jbit . m aicc ) )
    ( json_obj_set o `bic` ( __ar_jbit . m bic ) )
    ( json_obj_set o `n` ( json_int . m n ) )
    ( json_obj_set o `n_fit` ( json_int . m n_fit ) )
    ( json_obj_set o `n_used` ( json_int . m n_used ) )
    ( json_obj_set o `method` ( json_int . m method ) )
    ( json_obj_set o `converged` ( json_bool . m converged ) )
    ( json_obj_set o `iterations` ( json_int . m iterations ) )
    ( json_obj_set o `evaluations` ( json_int . m evals ) )
    ( json_obj_set o `se` ( __ar_jbits . m se ) )
    ( json_obj_set o `state_a` ( __ar_jbits . ss a ) )
    ( json_obj_set o `state_p` ( __ar_jbits . ss pm ) )
    ? ( _ar_ss_steady ss ) {
        // the fixed gain, so a reloaded model steps on exactly as this one
        ( json_obj_set o `steady_gain` ( __ar_jbits . ss kg ) )
        ( json_obj_set o `steady_f` ( json_int ( f64_to_bits ( _ar_at . ss fz 0 ) ) ) )
    } {}
    ? > . m xk 0 {
        : Json fo ( json_obj_new )
        ( json_obj_set fo `periods` ( __ar_jints . m xper ) )
        ( json_obj_set fo `k` ( json_int . m xk ) )
        ( json_obj_set fo `coef` ( __ar_jbits . m xcoef ) )
        ( json_obj_set fo `t` ( json_int . m xt ) )
        ( json_obj_set o `fourier` fo )
    } {}
    ( json_obj_set o `last_innovation` ( __ar_jbit . m last_innovation ) )
    ( json_obj_set o `last_variance` ( __ar_jbit . m last_variance ) )
    ( json_obj_set o `last_predicted` ( __ar_jbit . m last_predicted ) )
    : String s ( json_stringify o )
    ( json_free o )
    ^ s
}

@ arima_from_json s src → ?*ArimaModel {
    ?? ( json_parse src ) {
        T o → {
            : ~ b ok ( json_is_obj o )
            ? ok {
                ?? ( json_obj_get o `format` ) {
                    T fv → { ? == ( nurl_str_eq ( json_str_data fv ) `arima-1` ) 1 {} { = ok F } }
                    F _ → { = ok F }
                }
            } {}
            ? ok {} { ( json_free o ) ^ @ ?*ArimaModel { F } }
            : Json so ?? ( json_obj_get o `order` ) { T x → x F _ → o }
            : ArimaSpec sp @ ArimaSpec { ( __ar_jint so `p` ) ( __ar_jint so `d` ) ( __ar_jint so `q` ) ( __ar_jint so `P` ) ( __ar_jint so `D` ) ( __ar_jint so `Q` ) ( __ar_jint so `s` ) ?? ( json_obj_get so `mean` ) { T mv → ( json_as_bool mv ) F _ → F } }
            : ( Vec f ) phi ?? ( json_obj_get o `phi` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) th ?? ( json_obj_get o `theta` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) sphi ?? ( json_obj_get o `seasonal_phi` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) sth ?? ( json_obj_get o `seasonal_theta` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ArimaCoef c @ ArimaCoef { phi th sphi sth ( __ar_unbit o `mu` ) }
            : *ArimaModel m # *ArimaModel ( nurl_malloc Z ArimaModel )
            = . m spec sp
            = . m coef c
            = . m sigma2 ( __ar_unbit o `sigma2` )
            = . m loglik ( __ar_unbit o `loglik` )
            = . m aic ( __ar_unbit o `aic` )
            = . m aicc ( __ar_unbit o `aicc` )
            = . m bic ( __ar_unbit o `bic` )
            = . m n ( __ar_jint o `n` )
            = . m n_fit ( __ar_jint o `n_fit` )
            = . m n_used ( __ar_jint o `n_used` )
            = . m method ( __ar_jint o `method` )
            = . m converged ?? ( json_obj_get o `converged` ) { T cv → ( json_as_bool cv ) F _ → F }
            = . m iterations ( __ar_jint o `iterations` )
            = . m evals ( __ar_jint o `evaluations` )
            : ArimaSS fss ( __ar_full_ss sp c )
            ?? ( json_obj_get o `state_a` ) {
                T a → {
                    : ( Vec f ) av ( __ar_unbits a )
                    ? == ( vec_len [f] av ) . fss rd { ( __ar_copy_into . fss a av ) } {}
                    ( vec_free [f] av )
                }
                F _ → {}
            }
            ?? ( json_obj_get o `state_p` ) {
                T a → {
                    : ( Vec f ) pv ( __ar_unbits a )
                    ? == ( vec_len [f] pv ) * . fss rd . fss rd { ( __ar_copy_into . fss pm pv ) ( __ar_copy_into . fss prev pv ) } {}
                    ( vec_free [f] pv )
                }
                F _ → {}
            }
            ?? ( json_obj_get o `steady_gain` ) {
                T a → {
                    : ( Vec f ) gv ( __ar_unbits a )
                    ? == ( vec_len [f] gv ) . fss rd {
                        ( __ar_copy_into . fss kg gv )
                        : *f fz ( vec_data [f] . fss fz )
                        = . fz 0 ( __ar_unbit o `steady_f` )
                        = . fz 1 1.0
                    } {}
                    ( vec_free [f] gv )
                }
                F _ → {}
            }
            = . m ss fss
            = . m se ?? ( json_obj_get o `se` ) { T a → ( __ar_unbits a ) F _ → ( vec_zeroed [f] ( __ar_ncoef sp ) ) }
            = . m last_innovation ( __ar_unbit o `last_innovation` )
            = . m last_variance ( __ar_unbit o `last_variance` )
            = . m last_predicted ( __ar_unbit o `last_predicted` )
            = . m xper ( vec_new [i] )
            = . m xk 0
            = . m xcoef ( vec_new [f] )
            = . m xt 0
            ?? ( json_obj_get o `fourier` ) {
                T fo → {
                    ?? ( json_obj_get fo `periods` ) {
                        T pa → {
                            : i np ( json_arr_len pa )
                            : ~ i q 0
                            ~ < q np { ?? ( json_arr_get pa q ) { T e → { ( vec_push [i] . m xper ( __ar_jint_of e ) ) } F _ → {} } = q + q 1 }
                        }
                        F _ → {}
                    }
                    = . m xk ( __ar_jint fo `k` )
                    ?? ( json_obj_get fo `coef` ) { T a → { ( vec_free [f] . m xcoef ) = . m xcoef ( __ar_unbits a ) } F _ → {} }
                    = . m xt ( __ar_jint fo `t` )
                    ? == ( vec_len [f] . m xcoef ) + 1 * 2 * . m xk ( vec_len [i] . m xper ) {} { = . m xk 0 }
                }
                F _ → {}
            }
            ( json_free o )
            ^ @ ?*ArimaModel { T m }
        }
        F _ → { ^ @ ?*ArimaModel { F } }
    }
}
