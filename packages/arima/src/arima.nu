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
//   ( arima_fit y spec )              → ArimaModel     CSS-ML, the default
//   ( arima_fit_method y spec m )     → ArimaModel     m = ARIMA_CSS | ARIMA_ML
//   ( arima_auto y s )                → ArimaModel     stepwise order search by AICc
//   ( arima_forecast m h )            → ArimaForecast  h means and standard errors
//   ( arima_update m y )              → ArimaStep      one observation in: innovation, variance, z
//   ( arima_coef m )                  → Json           coefficients, σ², log-likelihood, AIC…
//   ( arima_to_json m ) / ( arima_from_json s ) persistence, bit-exact
//   ( arima_free m )                  early release (optional)
//
// Memory: an ArimaModel is a handle on the model's state (an Arc) —
// every copy is the same model, stepped by any of them — released with
// its last owner. An ArimaForecast is an owning struct. Nothing is freed
// by hand.
//
// Pure NURL, no dependencies beyond the stdlib; `src/arima_gpu.nu` adds
// batched fitting on a GPU through the `gpu` package for the case of many
// series or many candidate orders at once.

$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/par.nu`

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
    : ( Slice f ) s ( slice_from_vec [f] src )
    : ( Slice f ) o ( slice_from_vec [f] out )
    : ~ i k 0
    ~ < k n { ( slice_put [f] o k ( slice_at [f] s k ) ) = k + k 1 }
    ^ out
}

@ __ar_copy_into ( Vec f ) dst ( Vec f ) src → v {
    : i n ( vec_len [f] dst )
    : ( Slice f ) d ( slice_from_vec [f] dst )
    : ( Slice f ) s ( slice_from_vec [f] src )
    : ~ i k 0
    ~ < k n { ( slice_put [f] d k ( slice_at [f] s k ) ) = k + k 1 }
}

@ __ar_fill ( Vec f ) v f x → v {
    : i n ( vec_len [f] v )
    : ( Slice f ) p ( slice_from_vec [f] v )
    : ~ i k 0
    ~ < k n { ( slice_put [f] p k x ) = k + k 1 }
}

@ __ar_max_abs ( Vec f ) v → f {
    : i n ( vec_len [f] v )
    : ( Slice f ) p ( slice_from_vec [f] v )
    : ~ f m 0.0
    : ~ i k 0
    ~ < k n {
        : f a ( float_abs ( slice_at [f] p k ) )
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
    : ( Slice f ) o ( slice_from_vec [f] out )
    : ( Slice f ) pa ( slice_from_vec [f] a )
    : ( Slice f ) pb ( slice_from_vec [f] b )
    : ~ i i 0
    ~ < i na { ( slice_put [f] o i + ( slice_at [f] o i ) ( slice_at [f] pa i ) ) = i + i 1 }
    : ~ i j 0
    ~ < j nb {
        ( slice_put [f] o j + ( slice_at [f] o j ) ( slice_at [f] pb j ) )
        = i 0
        ~ < i na {
            : i k + + i j 1
            ( slice_put [f] o k + ( slice_at [f] o k ) * ( slice_at [f] pa i ) ( slice_at [f] pb j ) )
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
    : ( Slice f ) o ( slice_from_vec [f] out )
    : ( Slice f ) pc ( slice_from_vec [f] c )
    : ~ i j 0
    ~ < j n {
        ( slice_put [f] o - * + j 1 s 1 ( slice_at [f] pc j ) )
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
    : ( Slice f ) pa ( slice_from_vec [f] a )
    : ~ i k 0
    ~ < k na { ( slice_put [f] pa k - 0.0 ( slice_at [f] pa k ) ) = k + k 1 }
    : i nb ( vec_len [f] b )
    : ( Slice f ) pb ( slice_from_vec [f] b )
    = k 0
    ~ < k nb { ( slice_put [f] pb k - 0.0 ( slice_at [f] pb k ) ) = k + k 1 }
    : ( Vec f ) prod ( __ar_poly_mul a b )
    : i np ( vec_len [f] prod )
    : ( Slice f ) pp ( slice_from_vec [f] prod )
    = k 0
    ~ < k np { ( slice_put [f] pp k - 0.0 ( slice_at [f] pp k ) ) = k + k 1 }
    ^ prod
}

// The MA side: θ(B)Θ(B^s) expanded, "1 + Σ θ B^k" convention as given.
@ _ar_expand_ma ( Vec f ) theta ( Vec f ) stheta i s → ( Vec f ) {
    : ( Vec f ) b ( __ar_seasonal_spread stheta s )
    : ( Vec f ) prod ( __ar_poly_mul theta b )
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
        = poly nxt
        = k + k 1
    }
    = k 0
    ~ < k D {
        : ( Vec f ) one ( vec_zeroed [f] s )
        ( vec_set [f] one - s 1 -1.0 )
        : ( Vec f ) nxt ( __ar_poly_mul poly one )
        = poly nxt
        = k + k 1
    }
    : i n ( vec_len [f] poly )
    : ( Slice f ) pp ( slice_from_vec [f] poly )
    = k 0
    ~ < k n { ( slice_put [f] pp k - 0.0 ( slice_at [f] pp k ) ) = k + k 1 }
    ^ poly
}

// Δ^d Δ_s^D y: the first d + s·D values are consumed.
@ arima_difference ( Vec f ) y i d i D i s → ( Vec f ) {
    : ~ ( Vec f ) cur ( __ar_vec_copy y )
    : ~ i k 0
    ~ < k d {
        : i n ( vec_len [f] cur )
        : ( Vec f ) nxt ( vec_zeroed [f] ? > n 1 - n 1 0 )
        : ( Slice f ) c ( slice_from_vec [f] cur )
        : ( Slice f ) o ( slice_from_vec [f] nxt )
        : ~ i t 1
        ~ < t n { ( slice_put [f] o - t 1 - ( slice_at [f] c t ) ( slice_at [f] c - t 1 ) ) = t + t 1 }
        = cur nxt
        = k + k 1
    }
    = k 0
    ~ < k D {
        : i n ( vec_len [f] cur )
        : ( Vec f ) nxt ( vec_zeroed [f] ? > n s - n s 0 )
        : ( Slice f ) c ( slice_from_vec [f] cur )
        : ( Slice f ) o ( slice_from_vec [f] nxt )
        : ~ i t s
        ~ < t n { ( slice_put [f] o - t s - ( slice_at [f] c t ) ( slice_at [f] c - t s ) ) = t + t 1 }
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
    : ( Slice f ) o ( slice_from_vec [f] out )
    : ( Slice f ) w ( slice_from_vec [f] work )
    : ( Slice f ) r ( slice_from_vec [f] raw )
    : ~ i j 0
    ~ < j n {
        : f x ( slice_at [f] r + off j )
        // tanh, without a libm call the GPU could not match.
        : f e ( float_exp * 2.0 x )
        : f t ? ( float_is_inf e ) 1.0 / - e 1.0 + e 1.0
        ( slice_put [f] o j t )
        ( slice_put [f] w j t )
        = j + j 1
    }
    = j 1
    ~ < j n {
        : f a ( slice_at [f] o j )
        : ~ i k 0
        ~ < k j { ( slice_put [f] w k - ( slice_at [f] w k ) * a ( slice_at [f] o - - j k 1 ) ) = k + k 1 }
        = k 0
        ~ < k j { ( slice_put [f] o k ( slice_at [f] w k ) ) = k + k 1 }
        = j + j 1
    }
    ^ out
}

// Inverse: AR coefficients → raw. Returns F when the polynomial is not
// stationary (a partial autocorrelation reaches 1 in magnitude).
@ _ar_invpartrans ( Vec f ) phi ( Vec f ) raw i off → b {
    : i n ( vec_len [f] phi )
    ? == n 0 { ^ T } {}
    : ( Vec f ) nw ( __ar_vec_copy phi )
    : ( Vec f ) work ( __ar_vec_copy phi )
    : ( Slice f ) nu ( slice_from_vec [f] nw )
    : ( Slice f ) w ( slice_from_vec [f] work )
    : ( Slice f ) r ( slice_from_vec [f] raw )
    : ~ b ok T
    : ~ i j - n 1
    ~ & ok > j 0 {
        : f a ( slice_at [f] nu j )
        ? >= ( float_abs a ) 1.0 { = ok F } {
            : ~ i k 0
            ~ < k j { ( slice_put [f] w k / + ( slice_at [f] nu k ) * a ( slice_at [f] nu - - j k 1 ) - 1.0 * a a ) = k + k 1 }
            = k 0
            ~ < k j { ( slice_put [f] nu k ( slice_at [f] w k ) ) = k + k 1 }
        }
        = j - j 1
    }
    ? ok {
        = j 0
        ~ & ok < j n {
            : f x ( slice_at [f] nu j )
            ? >= ( float_abs x ) 1.0 { = ok F } {
                ( slice_put [f] r + off j * 0.5 ( float_log / + 1.0 x - 1.0 x ) )
            }
            = j + j 1
        }
    } {}
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

// Let go of `c` now (an owning struct: its vectors go with it).
@ _ar_coef_free sink ArimaCoef c → v {}

@ __ar_coef_clone ArimaCoef c → ArimaCoef {
    ^ @ ArimaCoef { ( __ar_vec_copy . c phi ) ( __ar_vec_copy . c theta ) ( __ar_vec_copy . c sphi ) ( __ar_vec_copy . c stheta ) . c mu }
}

// Raw (transformed) vector → coefficients. Layout: φ, θ, Φ, Θ, μ.
@ _ar_coef_of_raw ArimaSpec sp ( Vec f ) raw → ArimaCoef {
    : ~ i off 0
    : ( Vec f ) phi ( _ar_partrans raw off . sp p )
    = off + off . sp p
    : ( Vec f ) th ( _ar_partrans raw off . sp q )
    : ( Slice f ) pt ( slice_from_vec [f] th )
    : ~ i k 0
    ~ < k . sp q { ( slice_put [f] pt k - 0.0 ( slice_at [f] pt k ) ) = k + k 1 }
    = off + off . sp q
    : ( Vec f ) sphi ( _ar_partrans raw off . sp P )
    = off + off . sp P
    : ( Vec f ) sth ( _ar_partrans raw off . sp Q )
    : ( Slice f ) ps ( slice_from_vec [f] sth )
    = k 0
    ~ < k . sp Q { ( slice_put [f] ps k - 0.0 ( slice_at [f] ps k ) ) = k + k 1 }
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
    : ( Slice f ) pt ( slice_from_vec [f] nth )
    : ~ i k 0
    ~ < k . sp q { ( slice_put [f] pt k - 0.0 ( slice_at [f] pt k ) ) = k + k 1 }
    ? ( _ar_invpartrans nth raw off ) {} { = ok F }
    = off + off . sp q
    ? ( _ar_invpartrans . c sphi raw off ) {} { = ok F }
    = off + off . sp P
    : ( Vec f ) nst ( __ar_vec_copy . c stheta )
    : ( Slice f ) ps ( slice_from_vec [f] nst )
    = k 0
    ~ < k . sp Q { ( slice_put [f] ps k - 0.0 ( slice_at [f] ps k ) ) = k + k 1 }
    ? ( _ar_invpartrans nst raw off ) {} { = ok F }
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
    : ( Slice f ) fz ( slice_from_vec [f] . ss fz )
    ^ != ( slice_at [f] fz 1 ) 0.0
}

// Let go of `ss` now — what a state stored in a model's heap block is
// handed to before a new one is written over it.
@ _ar_ss_free sink ArimaSS ss → v {}

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
    : ( Slice f ) pphi ( slice_from_vec [f] phi )
    : ( Slice f ) pth ( slice_from_vec [f] th )
    : ( Slice f ) par ( slice_from_vec [f] ar )
    : ( Slice f ) pma ( slice_from_vec [f] ma )
    : ~ i k 0
    ~ < k pf { ( slice_put [f] pphi k ( slice_at [f] par k ) ) = k + k 1 }
    ( slice_put [f] pth 0 1.0 )
    = k 0
    ~ < k qf { ( slice_put [f] pth + k 1 ( slice_at [f] pma k ) ) = k + k 1 }
    ^ @ ArimaSS { r nd rd phi th ( __ar_vec_copy delta ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] * rd rd ) ( vec_zeroed [f] rd ) ( vec_zeroed [f] 2 ) }
}

// out = T · X for a square X (rd × rd), T the transition matrix by its
// structure: rows < r are the companion (φ_{i+1} x_0 + x_{i+1}), row r is
// Z (the observation row), rows beyond shift the differencing states.
@ __ar_tmul ArimaSS ss ( Vec f ) x ( Vec f ) out → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    // Rows as windows of rd: a loop over a row's columns is checked once.
    : ( Slice f ) X ( slice_from_vec [f] x )
    : ( Slice f ) O ( slice_from_vec [f] out )
    : ( Slice f ) phi ( slice_prefix [f] ( slice_from_vec [f] . ss phi ) r )
    : ( Slice f ) dl ( slice_prefix [f] ( slice_from_vec [f] . ss delta ) nd )
    : ( Slice f ) X0 ( slice_window [f] X 0 rd )
    : ~ i i 0
    ~ < i r {
        : ( Slice f ) Or ( slice_window [f] O * i rd rd )
        : f ph ( slice_at [f] phi i )
        : ~ i j 0
        ? < + i 1 r {
            : ( Slice f ) Xn ( slice_window [f] X * + i 1 rd rd )
            ~ < j rd { ( slice_put [f] Or j + * ph ( slice_at [f] X0 j ) ( slice_at [f] Xn j ) ) = j + j 1 }
        } {
            ~ < j rd { ( slice_put [f] Or j * ph ( slice_at [f] X0 j ) ) = j + j 1 }
        }
        = i + i 1
    }
    ? > nd 0 {
        // row r: Z X, accumulated over the differencing rows in order
        : ( Slice f ) Or ( slice_window [f] O * r rd rd )
        : ~ i j 0
        ~ < j rd { ( slice_put [f] Or j ( slice_at [f] X0 j ) ) = j + j 1 }
        : ~ i k 0
        ~ < k nd {
            : f dk ( slice_at [f] dl k )
            : ( Slice f ) Xk ( slice_window [f] X * + r k rd rd )
            = j 0
            ~ < j rd { ( slice_put [f] Or j + ( slice_at [f] Or j ) * dk ( slice_at [f] Xk j ) ) = j + j 1 }
            = k + k 1
        }
        = i + r 1
        ~ < i rd {
            : ( Slice f ) Oi ( slice_window [f] O * i rd rd )
            : ( Slice f ) Xp ( slice_window [f] X * - i 1 rd rd )
            = j 0
            ~ < j rd { ( slice_put [f] Oi j ( slice_at [f] Xp j ) ) = j + j 1 }
            = i + i 1
        }
    } {}
}

// out = M · Tᵀ: the same structure applied on the right.
@ __ar_tmul_right ArimaSS ss ( Vec f ) m ( Vec f ) out → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : ( Slice f ) M ( slice_from_vec [f] m )
    : ( Slice f ) O ( slice_from_vec [f] out )
    : ( Slice f ) phi ( slice_prefix [f] ( slice_from_vec [f] . ss phi ) r )
    : ( Slice f ) dl ( slice_prefix [f] ( slice_from_vec [f] . ss delta ) nd )
    : ~ i i 0
    ~ < i rd {
        : ( Slice f ) Mr ( slice_window [f] M * i rd rd )
        : ( Slice f ) Or ( slice_window [f] O * i rd rd )
        : ( Slice f ) Ma ( slice_prefix [f] Mr r )
        : f m0 ( slice_at [f] Mr 0 )
        : ~ i j 0
        ~ < j r {
            : ~ f v * ( slice_at [f] phi j ) m0
            ? < + j 1 r { = v + v ( slice_at [f] Ma + j 1 ) } {}
            ( slice_put [f] Or j v )
            = j + j 1
        }
        ? > nd 0 {
            : ( Slice f ) Md ( slice_window [f] Mr r nd )
            : ~ f v m0
            : ~ i k 0
            ~ < k nd { = v + v * ( slice_at [f] dl k ) ( slice_at [f] Md k ) = k + k 1 }
            ( slice_put [f] Or r v )
            = j + r 1
            ~ < j rd { ( slice_put [f] Or j ( slice_at [f] Mr - j 1 ) ) = j + j 1 }
        } {}
        = i + i 1
    }
}

// a ← T a.
@ __ar_tvec ArimaSS ss → v {
    : i r . ss r
    : i rd . ss rd
    : i nd . ss nd
    : ( Slice f ) A ( slice_prefix [f] ( slice_from_vec [f] . ss a ) rd )
    : ( Slice f ) O ( slice_prefix [f] ( slice_from_vec [f] . ss pz ) rd )
    : ( Slice f ) phi ( slice_prefix [f] ( slice_from_vec [f] . ss phi ) r )
    : ( Slice f ) dl ( slice_prefix [f] ( slice_from_vec [f] . ss delta ) nd )
    : ( Slice f ) Ar ( slice_prefix [f] A r )
    : f a0 ( slice_at [f] A 0 )
    : ~ i i 0
    ~ < i r {
        : ~ f v * ( slice_at [f] phi i ) a0
        ? < + i 1 r { = v + v ( slice_at [f] Ar + i 1 ) } {}
        ( slice_put [f] O i v )
        = i + i 1
    }
    ? > nd 0 {
        : ( Slice f ) Ad ( slice_window [f] A r nd )
        : ~ f v a0
        : ~ i k 0
        ~ < k nd { = v + v * ( slice_at [f] dl k ) ( slice_at [f] Ad k ) = k + k 1 }
        ( slice_put [f] O r v )
        = i + r 1
        ~ < i rd { ( slice_put [f] O i ( slice_at [f] A - i 1 ) ) = i + i 1 }
    } {}
    = i 0
    ~ < i rd { ( slice_put [f] A i ( slice_at [f] O i ) ) = i + i 1 }
}

// P ← T P Tᵀ + V, V = θ θᵀ on the ARMA block.
@ __ar_predict_cov ArimaSS ss → v {
    ( __ar_tmul ss . ss pm . ss scratch )
    ( __ar_tmul_right ss . ss scratch . ss pm )
    : i r . ss r
    : i rd . ss rd
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    : ( Slice f ) th ( slice_prefix [f] ( slice_from_vec [f] . ss theta ) r )
    : ~ i i 0
    ~ < i r {
        : ( Slice f ) Pr ( slice_window [f] P * i rd r )
        : f ti ( slice_at [f] th i )
        : ~ i j 0
        ~ < j r {
            ( slice_put [f] Pr j + ( slice_at [f] Pr j ) * ti ( slice_at [f] th j ) )
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
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    : ( Slice f ) pz ( slice_prefix [f] ( slice_from_vec [f] . ss pz ) rd )
    : ( Slice f ) dl ( slice_prefix [f] ( slice_from_vec [f] . ss delta ) nd )
    : ~ i i 0
    ~ < i rd {
        : ( Slice f ) Pr ( slice_window [f] P * i rd rd )
        : ( Slice f ) Pd ( slice_window [f] Pr r nd )
        : ~ f v ( slice_at [f] Pr 0 )
        : ~ i k 0
        ~ < k nd { = v + v * ( slice_at [f] dl k ) ( slice_at [f] Pd k ) = k + k 1 }
        ( slice_put [f] pz i v )
        = i + i 1
    }
    : ( Slice f ) pzd ( slice_window [f] pz r nd )
    : ~ f fv ( slice_at [f] pz 0 )
    : ~ i k 0
    ~ < k nd { = fv + fv * ( slice_at [f] dl k ) ( slice_at [f] pzd k ) = k + k 1 }
    ^ fv
}

@ __ar_predicted ArimaSS ss → f {
    : ( Slice f ) A ( slice_from_vec [f] . ss a )
    : ( Slice f ) dl ( slice_from_vec [f] . ss delta )
    : ~ f y ( slice_at [f] A 0 )
    : ~ i k 0
    ~ < k . ss nd { = y + y * ( slice_at [f] dl k ) ( slice_at [f] A + . ss r k ) = k + k 1 }
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
    : ( Slice f ) A ( slice_from_vec [f] . ss a )
    : ( Slice f ) fz ( slice_from_vec [f] . ss fz )
    ? != ( slice_at [f] fz 1 ) 0.0 {
        : f fss ( slice_at [f] fz 0 )
        : f pred ( __ar_predicted ss )
        : f v - y pred
        : ( Slice f ) G ( slice_from_vec [f] . ss kg )
        : ~ i i 0
        ~ < i rd { ( slice_put [f] A i + ( slice_at [f] A i ) * ( slice_at [f] G i ) v ) = i + i 1 }
        ( __ar_tvec ss )
        ^ @ ArimaStep { v fss pred }
    } {}
    : f fv ( __ar_observe ss )
    : f pred ( __ar_predicted ss )
    : f v - y pred
    ? > fv 0.0 {} { ^ @ ArimaStep { v -1.0 pred } }
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    : ( Slice f ) pz ( slice_prefix [f] ( slice_from_vec [f] . ss pz ) rd )
    : ( Slice f ) Ad ( slice_prefix [f] A rd )
    : f g / v fv
    : ~ i i 0
    ~ < i rd { ( slice_put [f] Ad i + ( slice_at [f] Ad i ) * ( slice_at [f] pz i ) g ) = i + i 1 }
    = i 0
    ~ < i rd {
        : f pi / ( slice_at [f] pz i ) fv
        : ( Slice f ) Pr ( slice_window [f] P * i rd rd )
        : ~ i j 0
        ~ < j rd { ( slice_put [f] Pr j - ( slice_at [f] Pr j ) * pi ( slice_at [f] pz j ) ) = j + j 1 }
        = i + i 1
    }
    ( __ar_tvec ss )
    ( __ar_predict_cov ss )
    // the steady-state test against the covariance a step ago
    : i rr * rd rd
    : ( Slice f ) Q ( slice_prefix [f] ( slice_from_vec [f] . ss prev ) rr )
    : ( Slice f ) Pa ( slice_prefix [f] P rr )
    : ~ f dmax 0.0
    = i 0
    ~ < i rr {
        : f dd ( float_abs - ( slice_at [f] Pa i ) ( slice_at [f] Q i ) )
        ? > dd dmax { = dmax dd } {}
        ( slice_put [f] Q i ( slice_at [f] Pa i ) )
        = i + i 1
    }
    ? <= dmax * 0.00000000000001 + 1.0 ( float_abs ( slice_at [f] P 0 ) ) {
        : f fss ( __ar_observe ss )
        ? > fss 0.0 {
            : ( Slice f ) G ( slice_from_vec [f] . ss kg )
            = i 0
            ~ < i rd { ( slice_put [f] G i / ( slice_at [f] pz i ) fss ) = i + i 1 }
            ( slice_put [f] fz 0 fss )
            ( slice_put [f] fz 1 1.0 )
        } {}
    } {}
    ^ @ ArimaStep { v fv pred }
}

// Solve M x = b for a small dense system by Gaussian elimination with
// partial pivoting; M and b are overwritten, x lands in b. F when singular.
@ _ar_solve ( Vec f ) M ( Vec f ) b i n → b {
    : ( Slice f ) pm ( slice_from_vec [f] M )
    : ( Slice f ) pb ( slice_prefix [f] ( slice_from_vec [f] b ) n )
    : ~ i c 0
    ~ < c n {
        : ~ i piv c
        : ~ f best ( float_abs ( slice_at [f] pm + * c n c ) )
        : ~ i rr + c 1
        ~ < rr n {
            : f a ( float_abs ( slice_at [f] pm + * rr n c ) )
            ? > a best { = best a = piv rr } {}
            = rr + rr 1
        }
        ? <= best 0.0 { ^ F } {}
        // rows as windows of n: the column loops below are checked once
        : ( Slice f ) Rc ( slice_window [f] pm * c n n )
        ? != piv c {
            : ( Slice f ) Rp ( slice_window [f] pm * piv n n )
            : ~ i j 0
            ~ < j n {
                : f t ( slice_at [f] Rc j )
                ( slice_put [f] Rc j ( slice_at [f] Rp j ) )
                ( slice_put [f] Rp j t )
                = j + j 1
            }
            : f tb ( slice_at [f] pb c )
            ( slice_put [f] pb c ( slice_at [f] pb piv ) )
            ( slice_put [f] pb piv tb )
        } {}
        : f pv ( slice_at [f] Rc c )
        = rr + c 1
        ~ < rr n {
            : ( Slice f ) Rr ( slice_window [f] pm * rr n n )
            : f fac / ( slice_at [f] Rr c ) pv
            ? != fac 0.0 {
                : ~ i j c
                ~ < j n { ( slice_put [f] Rr j - ( slice_at [f] Rr j ) * fac ( slice_at [f] Rc j ) ) = j + j 1 }
                ( slice_put [f] pb rr - ( slice_at [f] pb rr ) * fac ( slice_at [f] pb c ) )
            } {}
            = rr + rr 1
        }
        = c + c 1
    }
    : ~ i i - n 1
    ~ >= i 0 {
        : ( Slice f ) Ri ( slice_window [f] pm * i n n )
        : ~ f v ( slice_at [f] pb i )
        : ~ i j + i 1
        ~ < j n { = v - v * ( slice_at [f] Ri j ) ( slice_at [f] pb j ) = j + j 1 }
        ( slice_put [f] pb i / v ( slice_at [f] Ri i ) )
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
    : ( Slice f ) par ( slice_from_vec [f] ar )
    : ( Slice f ) pma ( slice_from_vec [f] ma )
    : ( Slice f ) pg ( slice_from_vec [f] gamma )
    : ( Slice f ) pp ( slice_from_vec [f] psi )
    // ψ
    ( slice_put [f] pp 0 1.0 )
    : ~ i k 1
    ~ < k m {
        : ~ f v ? <= k qf ( slice_at [f] pma - k 1 ) 0.0
        // ψ_k += φ_j ψ_{k−j}, j = 1 … min(p', k): the two runs as windows
        : i jm ? < pf k pf k
        : ( Slice f ) Pa ( slice_prefix [f] par jm )
        : ( Slice f ) Pw ( slice_window [f] pp - k jm jm )
        : ~ i jj 0
        ~ < jj jm { = v + v * ( slice_at [f] Pa jj ) ( slice_at [f] Pw - - jm 1 jj ) = jj + jj 1 }
        ( slice_put [f] pp k v )
        = k + k 1
    }
    // γ(0..p')
    : i n1 + pf 1
    : ( Vec f ) M ( vec_zeroed [f] * n1 n1 )
    : ( Vec f ) rhs ( vec_zeroed [f] n1 )
    : ( Slice f ) pM ( slice_from_vec [f] M )
    : ( Slice f ) pr ( slice_from_vec [f] rhs )
    = k 0
    ~ < k n1 {
        ( slice_put [f] pM + * k n1 k + ( slice_at [f] pM + * k n1 k ) 1.0 )
        : ~ i j 1
        ~ <= j pf {
            : i idx ? >= - k j 0 - k j - j k
            ( slice_put [f] pM + * k n1 idx - ( slice_at [f] pM + * k n1 idx ) ( slice_at [f] par - j 1 ) )
            = j + j 1
        }
        : ~ f v 0.0
        = j k
        ~ <= j qf {
            : f thj ? == j 0 1.0 ( slice_at [f] pma - j 1 )
            = v + v * thj ( slice_at [f] pp - j k )
            = j + j 1
        }
        ( slice_put [f] pr k v )
        = k + k 1
    }
    : b ok ( _ar_solve M rhs n1 )
    ? ok {
        = k 0
        ~ & < k n1 < k m { ( slice_put [f] pg k ( slice_at [f] pr k ) ) = k + k 1 }
        = k n1
        : ( Slice f ) Pa ( slice_prefix [f] par pf )
        ~ < k m {
            : ~ f v 0.0
            // γ_k += φ_j γ_{k−j}, j = 1 … p' (k > p')
            : ( Slice f ) Gw ( slice_window [f] pg - k pf pf )
            : ~ i jj 0
            ~ < jj pf { = v + v * ( slice_at [f] Pa jj ) ( slice_at [f] Gw - - pf 1 jj ) = jj + jj 1 }
            : ~ i j k
            ~ <= j qf { = v + v * ( slice_at [f] pma - j 1 ) ( slice_at [f] pp - j k ) = j + j 1 }
            ( slice_put [f] pg k v )
            = k + k 1
        }
    } {}
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
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    ( __ar_fill . ss pm 0.0 )
    : ( Slice f ) phi ( slice_from_vec [f] . ss phi )
    : ( Slice f ) th ( slice_from_vec [f] . ss theta )
    // the expanded polynomials back from the padded state form
    : ~ i pf r
    ~ & > pf 0 == ( slice_at [f] phi - pf 1 ) 0.0 { = pf - pf 1 }
    : ~ i qf - r 1
    ~ & > qf 0 == ( slice_at [f] th qf ) 0.0 { = qf - qf 1 }
    : ( Vec f ) ar ( vec_zeroed [f] pf )
    : ( Vec f ) ma ( vec_zeroed [f] qf )
    : ~ i k 0
    ~ < k pf { ( vec_set [f] ar k ( slice_at [f] phi k ) ) = k + k 1 }
    = k 0
    ~ < k qf { ( vec_set [f] ma k ( slice_at [f] th + k 1 ) ) = k + k 1 }
    : ( Vec f ) gamma ( vec_zeroed [f] r )
    : ( Vec f ) psi ( vec_zeroed [f] r )
    : b ok ( _ar_autocov ar ma r gamma psi )
    ? ok {
        : ( Slice f ) pg ( slice_from_vec [f] gamma )
        : ( Slice f ) pp ( slice_from_vec [f] psi )
        : ( Vec f ) A ( vec_zeroed [f] * r r )
        : ( Vec f ) B ( vec_zeroed [f] * r r )
        : ( Slice f ) pa ( slice_from_vec [f] A )
        : ( Slice f ) pb ( slice_from_vec [f] B )
        // A = Φ Γ, B = Φ C  (Φ[i][m] = φ_{i+1+m} = phi[i+m], zero past r)
        : ~ i i 0
        ~ < i r {
            : ( Slice f ) Phi ( slice_window [f] phi i - r i )
            : ( Slice f ) Ar ( slice_window [f] pa * i r r )
            : ( Slice f ) Br ( slice_window [f] pb * i r r )
            : ~ i l 0
            ~ < l r {
                : ~ f va 0.0
                : ~ f vb 0.0
                : ~ i m 0
                ~ < m - r i {
                    : f f1 ( slice_at [f] Phi m )
                    : i dlt ? >= - m l 0 - m l - l m
                    = va + va * f1 ( slice_at [f] pg dlt )
                    ? > l m { = vb + vb * f1 ( slice_at [f] pp - - l 1 m ) } {}
                    = m + m 1
                }
                ( slice_put [f] Ar l va )
                ( slice_put [f] Br l vb )
                = l + l 1
            }
            = i + i 1
        }
        // P = A Φᵀ + B Θᵀ + (B Θᵀ)ᵀ + Θ Θᵀ  (Θ[j][l] = θ_{j+l} = th[j+l])
        = i 0
        ~ < i r {
            : ( Slice f ) Ar ( slice_window [f] pa * i r r )
            : ( Slice f ) Br ( slice_window [f] pb * i r r )
            : ( Slice f ) Thi ( slice_window [f] th i - r i )
            : ( Slice f ) Pr ( slice_window [f] P * i rd r )
            : ~ i j 0
            ~ < j r {
                : i nl - r j
                : ( Slice f ) Phj ( slice_window [f] phi j nl )
                : ( Slice f ) Thj ( slice_window [f] th j nl )
                : ( Slice f ) Arl ( slice_prefix [f] Ar nl )
                : ( Slice f ) Brl ( slice_prefix [f] Br nl )
                : ~ f v 0.0
                : ~ i l 0
                ~ < l nl {
                    : f fj ( slice_at [f] Phj l )
                    : f tj ( slice_at [f] Thj l )
                    = v + v * ( slice_at [f] Arl l ) fj
                    = v + v * ( slice_at [f] Brl l ) tj
                    ? < l - r i { = v + v * ( slice_at [f] Thi l ) tj } {}
                    = l + l 1
                }
                ( slice_put [f] Pr j v )
                = j + j 1
            }
            = i + i 1
        }
        // the (B Θᵀ)ᵀ term: add B Θᵀ transposed
        = i 0
        ~ < i r {
            : i nl - r i
            : ( Slice f ) Thi ( slice_window [f] th i nl )
            : ( Slice f ) Pr ( slice_window [f] P * i rd r )
            : ~ i j 0
            ~ < j r {
                : ( Slice f ) Bj ( slice_window [f] pb * j r nl )
                : ~ f v 0.0
                : ~ i l 0
                ~ < l nl { = v + v * ( slice_at [f] Bj l ) ( slice_at [f] Thi l ) = l + l 1 }
                ( slice_put [f] Pr j + ( slice_at [f] Pr j ) v )
                = j + j 1
            }
            = i + i 1
        }
    } {}
    : ~ i i r
    ~ < i rd { ( slice_put [f] P + * i rd i ARIMA_KAPPA ) = i + i 1 }
    ^ ok
}

// The same by doubling (P_{k+1} = P_k + A_k P_k A_kᵀ, A_{k+1} = A_k²):
// kept as the independent check of the closed form.
@ _ar_init_cov_doubling ArimaSS ss → b {
    : i r . ss r
    : i rd . ss rd
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    ( __ar_fill . ss pm 0.0 )
    // Dense r × r work: A, X, and two temporaries.
    : ( Vec f ) A ( vec_zeroed [f] * r r )
    : ( Vec f ) X ( vec_zeroed [f] * r r )
    : ( Vec f ) T1 ( vec_zeroed [f] * r r )
    : ( Vec f ) T2 ( vec_zeroed [f] * r r )
    : ( Slice f ) pa ( slice_from_vec [f] A )
    : ( Slice f ) px ( slice_from_vec [f] X )
    : ( Slice f ) t1 ( slice_from_vec [f] T1 )
    : ( Slice f ) t2 ( slice_from_vec [f] T2 )
    : ( Slice f ) phi ( slice_from_vec [f] . ss phi )
    : ( Slice f ) th ( slice_from_vec [f] . ss theta )
    : ~ i i 0
    ~ < i r {
        ( slice_put [f] pa * i r ( slice_at [f] phi i ) )
        ? < + i 1 r { ( slice_put [f] pa + * i r + i 1 1.0 ) } {}
        : ~ i j 0
        ~ < j r { ( slice_put [f] px + * i r j * ( slice_at [f] th i ) ( slice_at [f] th j ) ) = j + j 1 }
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
                ~ < k r { = v + v * ( slice_at [f] pa + * i r k ) ( slice_at [f] px + * k r j ) = k + k 1 }
                ( slice_put [f] t1 + * i r j v )
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
                ~ < k r { = v + v * ( slice_at [f] t1 + * i r k ) ( slice_at [f] pa + * j r k ) = k + k 1 }
                ( slice_put [f] px + * i r j + ( slice_at [f] px + * i r j ) v )
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
                ~ < k r { = v + v * ( slice_at [f] pa + * i r k ) ( slice_at [f] pa + * k r j ) = k + k 1 }
                ( slice_put [f] t2 + * i r j v )
                : f av ( float_abs v )
                ? > av amax { = amax av } {}
                = j + j 1
            }
            = i + i 1
        }
        = i 0
        ~ < i * r r { ( slice_put [f] pa i ( slice_at [f] t2 i ) ) = i + i 1 }
        ? ( float_is_nan amax ) { = ok F = going F } {}
        ? < amax 0.0000000000000001 { = going F } {}
        = iter + iter 1
    }
    = i 0
    ~ < i r {
        : ~ i j 0
        ~ < j r { ( slice_put [f] P + * i rd j ( slice_at [f] px + * i r j ) ) = j + j 1 }
        = i + i 1
    }
    = i r
    ~ < i rd { ( slice_put [f] P + * i rd i ARIMA_KAPPA ) = i + i 1 }
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
    : ( Slice f ) pphi ( slice_from_vec [f] phi )
    : ( Slice f ) pth ( slice_from_vec [f] th )
    : ( Slice f ) par ( slice_from_vec [f] ar )
    : ( Slice f ) pma ( slice_from_vec [f] ma )
    : ~ i k 0
    ~ < k pf { ( slice_put [f] pphi k ( slice_at [f] par k ) ) = k + k 1 }
    ( slice_put [f] pth 0 1.0 )
    = k 0
    ~ < k qf { ( slice_put [f] pth + k 1 ( slice_at [f] pma k ) ) = k + k 1 }
    ^ @ ArimaArma { r phi th }
}

// Let go of `a` now (an owning struct).
@ _ar_arma_free sink ArimaArma a → v {}

// The first column of the stationary covariance, P e₀, in O(r²): the
// four terms of _ar_init_cov applied to the unit vector instead of
// multiplied out — Φ(Γ Φᵀe₀) + Φ(C Θᵀe₀) + Θ(Bᵀe₀) + Θ(Θᵀe₀) with B = ΦC.
// It is all the Chandrasekhar recursion needs of P.
@ _ar_init_col i r ( Vec f ) phiv ( Vec f ) thv ( Vec f ) out → b {
    : ( Slice f ) phi ( slice_from_vec [f] phiv )
    : ( Slice f ) th ( slice_from_vec [f] thv )
    : ( Slice f ) po ( slice_from_vec [f] out )
    // the expanded polynomials back from the padded state form
    : ~ i pf r
    ~ & > pf 0 == ( slice_at [f] phi - pf 1 ) 0.0 { = pf - pf 1 }
    : ~ i qf - r 1
    ~ & > qf 0 == ( slice_at [f] th qf ) 0.0 { = qf - qf 1 }
    : ( Vec f ) ar ( vec_zeroed [f] pf )
    : ( Vec f ) ma ( vec_zeroed [f] qf )
    : ~ i k 0
    ~ < k pf { ( vec_set [f] ar k ( slice_at [f] phi k ) ) = k + k 1 }
    = k 0
    ~ < k qf { ( vec_set [f] ma k ( slice_at [f] th + k 1 ) ) = k + k 1 }
    : ( Vec f ) gamma ( vec_zeroed [f] r )
    : ( Vec f ) psi ( vec_zeroed [f] r )
    : b ok ( _ar_autocov ar ma r gamma psi )
    ? ok {
        : ( Slice f ) pg ( slice_from_vec [f] gamma )
        : ( Slice f ) pp ( slice_from_vec [f] psi )
        // x = Γ Φᵀe₀, y = C Θᵀe₀, b = Bᵀe₀ — Φ[i][m] = φ_{i+m}, Θ[i][l] = θ_{i+l},
        // Γ[m][l] = γ(|m−l|), C[m][l] = ψ_{l−1−m} (l > m)
        : ( Vec f ) xv ( vec_zeroed [f] r )
        : ( Vec f ) yv ( vec_zeroed [f] r )
        : ( Vec f ) bv ( vec_zeroed [f] r )
        : ( Slice f ) x ( slice_from_vec [f] xv )
        : ( Slice f ) y ( slice_from_vec [f] yv )
        : ( Slice f ) b ( slice_from_vec [f] bv )
        : ~ i m 0
        ~ < m r {
            : ~ f sx 0.0
            : ~ f sy 0.0
            : ~ f sb 0.0
            : ~ i l 0
            ~ < l r {
                : i dlt ? >= - m l 0 - m l - l m
                = sx + sx * ( slice_at [f] pg dlt ) ( slice_at [f] phi l )
                ? > l m { = sy + sy * ( slice_at [f] pp - - l 1 m ) ( slice_at [f] th l ) } {}
                ? < l m { = sb + sb * ( slice_at [f] phi l ) ( slice_at [f] pp - - m 1 l ) } {}
                = l + l 1
            }
            ( slice_put [f] x m sx )
            ( slice_put [f] y m sy )
            ( slice_put [f] b m sb )
            = m + m 1
        }
        : ~ i i 0
        ~ < i r {
            : ~ f v 0.0
            : ~ i l 0
            ~ < l - r i {
                = v + v * ( slice_at [f] phi + i l ) + ( slice_at [f] x l ) ( slice_at [f] y l )
                = v + v * ( slice_at [f] th + i l ) + ( slice_at [f] b l ) ( slice_at [f] th l )
                = l + l 1
            }
            ( slice_put [f] po i v )
            = i + i 1
        }
    } {}
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
    // Every vector cut to r (the series to n): a loop to r indexes all of
    // them with no check per element.
    : ( Slice f ) phi ( slice_prefix [f] ( slice_from_vec [f] phiv ) r )
    : ( Slice f ) p0 ( slice_prefix [f] ( slice_from_vec [f] col ) r )
    : ( Slice f ) pw ( slice_prefix [f] ( slice_from_vec [f] w ) n )
    : f f0 ( slice_at [f] p0 0 )
    ? > f0 0.0 {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    : ( Vec f ) av ( vec_zeroed [f] r )
    : ( Vec f ) kv ( vec_zeroed [f] r )
    : ( Vec f ) wv ( vec_zeroed [f] r )
    : ( Vec f ) ov ( vec_zeroed [f] r )
    : ( Slice f ) A ( slice_prefix [f] ( slice_from_vec [f] av ) r )
    : ( Slice f ) K ( slice_prefix [f] ( slice_from_vec [f] kv ) r )
    : ( Slice f ) W ( slice_prefix [f] ( slice_from_vec [f] wv ) r )
    : ( Slice f ) O ( slice_prefix [f] ( slice_from_vec [f] ov ) r )
    // a[i+1] and w[i+1] for the rows below the last: windows from 1
    : i r1 - r 1
    : ( Slice f ) A1 ( slice_window [f] A 1 r1 )
    : ( Slice f ) W1 ( slice_window [f] W 1 r1 )
    : ~ i i 0
    ~ < i r {
        : ~ f v * ( slice_at [f] phi i ) ( slice_at [f] p0 0 )
        ? < + i 1 r { = v + v ( slice_at [f] p0 + i 1 ) } {}
        ( slice_put [f] K i / v f0 )
        ( slice_put [f] W i ( slice_at [f] K i ) )
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
        : f v - - ( slice_at [f] pw t ) mu ( slice_at [f] A 0 )
        = ssq + ssq / * v v fv
        = sumlog + sumlog logf
        // a ← T a + K v (the last row has no successor to add)
        : f a0 ( slice_at [f] A 0 )
        = i 0
        ~ < i r1 {
            ( slice_put [f] O i + + * ( slice_at [f] phi i ) a0 ( slice_at [f] A1 i ) * ( slice_at [f] K i ) v )
            = i + i 1
        }
        ( slice_put [f] O r1 + * ( slice_at [f] phi r1 ) a0 * ( slice_at [f] K r1 ) v )
        = i 0
        ~ < i r { ( slice_put [f] A i ( slice_at [f] O i ) ) = i + i 1 }
        ? frozen {} {
            : f w0 ( slice_at [f] W 0 )
            : f fn + fv * * w0 w0 mm
            : ~ f wmax 0.0
            = i 0
            ~ < i r1 {
                ( slice_put [f] O i + * ( slice_at [f] phi i ) w0 ( slice_at [f] W1 i ) )
                : f aw ( float_abs ( slice_at [f] W i ) )
                ? > aw wmax { = wmax aw } {}
                = i + i 1
            }
            ( slice_put [f] O r1 * ( slice_at [f] phi r1 ) w0 )
            : f awl ( float_abs ( slice_at [f] W r1 ) )
            ? > awl wmax { = wmax awl } {}
            ? <= * ( float_abs mm ) * wmax wmax * 0.00000000000001 + 1.0 fv { = frozen T } {
                ? > fn 0.0 {
                    = i 0
                    ~ < i r {
                        ( slice_put [f] K i / + * ( slice_at [f] K i ) fv * * ( slice_at [f] O i ) mm w0 fn )
                        ( slice_put [f] W i - ( slice_at [f] O i ) * ( slice_at [f] K i ) w0 )
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
    ? ok {} { ^ @ ArimaLik { F 0.0 0.0 0 } }
    ^ ( _ar_lik_ml_from ssq sumlog n )
}

@ __ar_loglik_ml ArimaSpec sp ArimaCoef c ( Vec f ) w → ArimaLik {
    : ( Vec f ) ar ( _ar_expand_ar . c phi . c sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . c theta . c stheta . sp s )
    : ArimaArma am ( _ar_arma_new ar ma )
    : ( Vec f ) col ( vec_zeroed [f] . am r )
    : ~ ArimaLik out @ ArimaLik { F 0.0 0.0 0 }
    ? ( _ar_init_col . am r . am phi . am theta col ) {
        = out ( _ar_filter_arma . am phi . am theta col w . c mu )
    } {}
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
        : ( Slice f ) pe ( slice_from_vec [f] e )
        : ( Slice f ) pw ( slice_from_vec [f] w )
        : ( Slice f ) par ( slice_from_vec [f] ar )
        : ( Slice f ) pma ( slice_from_vec [f] ma )
        // A seasonal polynomial is sparse — (p+1)(P+1)−1 terms across
        // s·P+p lags — and a zero coefficient's term is exactly zero, so
        // the lags that carry one are visited and the sums are the
        // dense recursion's bit for bit.
        : ( Vec i ) ari ( vec_new [i] )
        : ( Vec i ) mai ( vec_new [i] )
        : ~ i i 0
        ~ < i pf { ? == ( slice_at [f] par i ) 0.0 {} { ( vec_push [i] ari i ) } = i + i 1 }
        = i 0
        ~ < i qf { ? == ( slice_at [f] pma i ) 0.0 {} { ( vec_push [i] mai i ) } = i + i 1 }
        : i nar ( vec_len [i] ari )
        : i nma ( vec_len [i] mai )
        : ( Slice i ) pari ( slice_from_vec [i] ari )
        : ( Slice i ) pmai ( slice_from_vec [i] mai )
        : ~ f ssq 0.0
        : ~ i t nc
        ~ < t n {
            : ~ f v - ( slice_at [f] pw t ) . c mu
            = i 0
            ~ < i nar {
                : i lag ( slice_at [i] pari i )
                = v - v * ( slice_at [f] par lag ) - ( slice_at [f] pw - t + lag 1 ) . c mu
                = i + i 1
            }
            : ~ i j 0
            ~ < j nma {
                : i lag ( slice_at [i] pmai j )
                : i at - t + lag 1
                ? >= at nc { = v - v * ( slice_at [f] pma lag ) ( slice_at [f] pe at ) } {}
                = j + j 1
            }
            ( slice_put [f] pe t v )
            = ssq + ssq * v v
            = t + t 1
        }
        = out ( _ar_lik_css_from ssq - n nc )
    } {}
    ^ out
}

// ── The optimizer: BFGS over the transformed parameters ───────────────

// What the objective needs to see: the spec, the differenced series, the
// method (and CSS's conditioning count), and a count of evaluations.
: ArimaObj {
    ArimaSpec sp
    ( Arc ( Vec f ) ) w  // shared with the evaluations' threads
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

@ __ar_objective inout ArimaObj o ( Vec f ) raw → f {
    = . o evals + . o evals 1
    ^ ( __ar_eval . o sp ( arc_get [( Vec f )] . o w ) . o method . o ncond raw )
}

// One evaluation as a job: its parameters (raw, or — kind 1 — natural
// coefficients for the Hessian), and the series it is evaluated on,
// shared with the other jobs and their threads.
: ArimaJob {
    ArimaSpec sp
    ( Arc ( Vec f ) ) w
    i method
    i ncond
    ( Vec f ) raw
    i kind  // 0 raw objective, 1 natural objective, 2/3 prepare (raw/natural, ML), 4/5 prepare (raw/natural, CSS)
}

@ __ar_job_value ArimaJob j → f {
    : ( Vec f ) w ( arc_get [( Vec f )] . j w )
    ? == . j kind 1 { ^ ( __ar_eval_natural . j sp w . j method . j ncond . j raw ) } {}
    ^ ( __ar_eval . j sp w . j method . j ncond . j raw )
}

// Every job's objective value, by index: on __ar_threads threads
// (stdlib/std/par.nu) when `par`, else in place — the same numbers
// either way.
@ _ar_jobs_eval sink ( Vec ArimaJob ) jobs b par → ( Vec f ) {
    : i n ( vec_len [ArimaJob] jobs )
    : ( Arc ( Vec ArimaJob ) ) ja ( arc_new [( Vec ArimaJob )] jobs )
    ^ ( par_map_index [f] n ? par ( __ar_threads ) 1 \ i k → f { ^ ( __ar_job_value ( vec_at [ArimaJob] ( arc_get [( Vec ArimaJob )] ja ) k ) ) } )
}

// Every prepare job's state-space form, by index, likewise.
@ _ar_jobs_prep sink ( Vec ArimaJob ) jobs b par → ( Vec ArimaPrep ) {
    : i n ( vec_len [ArimaJob] jobs )
    : ( Arc ( Vec ArimaJob ) ) ja ( arc_new [( Vec ArimaJob )] jobs )
    ^ ( par_map_index [ArimaPrep] n ? par ( __ar_threads ) 1 \ i k → ArimaPrep {
        : ArimaJob j ( vec_at [ArimaJob] ( arc_get [( Vec ArimaJob )] ja ) k )
        ^ ( _ar_prep_at . j sp . j raw | == . j kind 3 == . j kind 5 < . j kind 4 )
    } )
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

// Prepare at `raw` (transformed parameters when natural = F, natural
// coefficients when T); with_cov adds the stationary covariance.
@ _ar_prep_at ArimaSpec sp ( Vec f ) raw b natural b with_cov → ArimaPrep {
    : ArimaCoef cf ? natural ( _ar_coef_of_natural sp raw ) ( _ar_coef_of_raw sp raw )
    : ( Vec f ) ar ( _ar_expand_ar . cf phi . cf sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . cf theta . cf stheta . sp s )
    : f mu . cf mu
    ? with_cov {
        : ArimaArma am ( _ar_arma_new ar ma )
        : ( Vec f ) p0 ( vec_zeroed [f] . am r )
        : b ok ( _ar_init_col . am r . am phi . am theta p0 )
        ^ @ ArimaPrep { ok . am r ( __ar_vec_copy . am phi ) ( __ar_vec_copy . am theta ) p0 ar ma mu }
    } {}
    ^ @ ArimaPrep { T 0 ( vec_new [f] ) ( vec_new [f] ) ( vec_new [f] ) ar ma mu }
}

// One job of a batch: what it reads (its own copy of the point).
@ _ar_job ArimaSpec sp ( Arc ( Vec f ) ) w i method i ncond ( Vec f ) raw i kind → ArimaJob {
    ^ @ ArimaJob { sp w method ncond ( __ar_vec_copy raw ) kind }
}

@ __ar_work ArimaObj o → i { ^ ( __ar_work_of . o sp ( vec_len [f] ( arc_get [( Vec f )] . o w ) ) . o method ) }

// The same for a spec, a series length and a method.
@ __ar_work_of ArimaSpec sp i n i method → i {
    : i pf + . sp p * . sp s . sp P
    : i qf + . sp q * . sp s . sp Q
    ? == method ARIMA_CSS { ^ * n + + pf qf 1 } {}
    : ~ i r pf
    ? > + qf 1 r { = r + qf 1 } {}
    // the Chandrasekhar step is O(r), the start O(r²) plus a (p'+1)-wide solve
    ^ + * n * 4 r + * r r * * pf pf pf
}

// Evaluate the objective at every row of `raws` into `out`: on threads,
// __ar_threads at a time, when an evaluation is worth one; otherwise
// in place. Either way the answers are the same numbers.
@ __ar_eval_batch inout ArimaObj o ( Vec ( Vec f ) ) raws ( Vec f ) out → v {
    : i m ( vec_len [( Vec f )] raws )
    = . o evals + . o evals m
    : b par & > ( __ar_work o ) ARIMA_PAR_WORK > m 1
    : ( Vec ArimaJob ) jobs ( vec_new [ArimaJob] )
    : ~ i i 0
    ~ < i m {
        ?? ( vec_get [( Vec f )] raws i ) {
            T rw → { ( vec_push [ArimaJob] jobs ( _ar_job . o sp . o w . o method . o ncond rw 0 ) ) }
            F _ → {}
        }
        = i + i 1
    }
    ( __ar_copy_into out ( _ar_jobs_eval jobs par ) )
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

@ __ar_bfgs_new ( Vec f ) raw0 → ArimaBfgs {
    : i k ( vec_len [f] raw0 )
    : ( Vec f ) H ( vec_zeroed [f] * k k )
    : ( Slice f ) pH ( slice_from_vec [f] H )
    : ~ i i 0
    ~ < i k { ( slice_put [f] pH + * i k i 1.0 ) = i + i 1 }
    ^ @ ArimaBfgs {
        k ( __ar_vec_copy raw0 ) ( vec_zeroed [f] k ) ( vec_zeroed [f] k ) ( vec_zeroed [f] k ) ( vec_zeroed [f] k )
        ( vec_zeroed [f] k ) ( vec_zeroed [f] k ) H ( vec_zeroed [f] k )
        0.0 0.0 1.0 0.0 0 0 ARIMA_PH_START F ? == k 0 T F
    }
}

// The 2k stencil points around raw, with the step of each coordinate
// recorded in hs.
@ __ar_bfgs_stencil inout ArimaBfgs st ( Vec ( Vec f ) ) out → v {
    : i k . st k
    : ( Slice f ) pr ( slice_from_vec [f] . st raw )
    : ( Slice f ) ph ( slice_from_vec [f] . st hs )
    : ~ i i 0
    ~ < i k {
        : f x ( slice_at [f] pr i )
        : ~ f h 0.00001
        : f ax ( float_abs x )
        ? > ax 1.0 { = h * h ax } {}
        ( slice_put [f] ph i h )
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
@ __ar_bfgs_requests inout ArimaBfgs st → ( Vec ( Vec f ) ) {
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
@ __ar_bfgs_take_grad inout ArimaBfgs st ( Vec f ) vals i off ( Vec f ) into → v {
    : i k . st k
    : ( Slice f ) pv ( slice_from_vec [f] vals )
    : ( Slice f ) ph ( slice_from_vec [f] . st hs )
    : ( Slice f ) pg ( slice_from_vec [f] into )
    : ~ i i 0
    ~ < i k {
        ( slice_put [f] pg i / - ( slice_at [f] pv + off * 2 i ) ( slice_at [f] pv + + off * 2 i 1 ) * 2.0 ( slice_at [f] ph i ) )
        = i + i 1
    }
}

// From a gradient at raw: the direction d = −H g, and the first trial —
// no coordinate moving by more than one, the transform saturating beyond
// a few units.
@ __ar_bfgs_direction inout ArimaBfgs st → v {
    : i k . st k
    : ( Slice f ) pg ( slice_from_vec [f] . st g )
    : ( Slice f ) pd ( slice_from_vec [f] . st d )
    : ( Slice f ) pH ( slice_from_vec [f] . st H )
    : ( Slice f ) pr ( slice_from_vec [f] . st raw )
    : ( Slice f ) pt ( slice_from_vec [f] . st trial )
    : ~ f gd 0.0
    : ~ i i 0
    ~ < i k {
        : ~ f v 0.0
        : ~ i j 0
        ~ < j k { = v + v * ( slice_at [f] pH + * i k j ) ( slice_at [f] pg j ) = j + j 1 }
        ( slice_put [f] pd i - 0.0 v )
        = gd + gd * ( slice_at [f] pg i ) ( slice_at [f] pd i )
        = i + i 1
    }
    ? >= gd 0.0 {
        = i 0
        ~ < i k {
            : ~ i j 0
            ~ < j k { ( slice_put [f] pH + * i k j ? == i j 1.0 0.0 ) = j + j 1 }
            ( slice_put [f] pd i - 0.0 ( slice_at [f] pg i ) )
            = i + i 1
        }
        = gd 0.0
        = i 0
        ~ < i k { = gd - gd * ( slice_at [f] pg i ) ( slice_at [f] pg i ) = i + i 1 }
    } {}
    = . st gd gd
    : ~ f dmax 0.0
    = i 0
    ~ < i k { : f a ( float_abs ( slice_at [f] pd i ) ) ? > a dmax { = dmax a } {} = i + i 1 }
    = . st alpha ? > dmax 1.0 / 1.0 dmax 1.0
    = . st tries 0
    = i 0
    ~ < i k { ( slice_put [f] pt i + ( slice_at [f] pr i ) * . st alpha ( slice_at [f] pd i ) ) = i + i 1 }
    = . st phase ARIMA_PH_TRIAL
}

// Take the values of the last request. Returns T when the machine is done.
@ __ar_bfgs_absorb inout ArimaBfgs st ( Vec f ) vals → b {
    ? . st done { ^ T } {}
    : i k . st k
    : ( Slice f ) pv ( slice_from_vec [f] vals )
    ? == . st phase ARIMA_PH_START {
        = . st f0 ( slice_at [f] pv 0 )
        ( __ar_bfgs_take_grad st vals 1 . st g )
        ( __ar_bfgs_direction st )
        ^ F
    } {}
    ? == . st phase ARIMA_PH_TRIAL {
        = . st fn ( slice_at [f] pv 0 )
        ? <= . st fn + . st f0 * * 0.0001 . st alpha . st gd {
            // accepted: move, then ask for the gradient there
            : ( Slice f ) pr ( slice_from_vec [f] . st raw )
            : ( Slice f ) pt ( slice_from_vec [f] . st trial )
            : ( Slice f ) ps ( slice_from_vec [f] . st s )
            : ~ i i 0
            ~ < i k { ( slice_put [f] ps i - ( slice_at [f] pt i ) ( slice_at [f] pr i ) ) ( slice_put [f] pr i ( slice_at [f] pt i ) ) = i + i 1 }
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
            : ( Slice f ) pr ( slice_from_vec [f] . st raw )
            : ( Slice f ) pt ( slice_from_vec [f] . st trial )
            : ( Slice f ) pd ( slice_from_vec [f] . st d )
            : ~ i i 0
            ~ < i k { ( slice_put [f] pt i + ( slice_at [f] pr i ) * . st alpha ( slice_at [f] pd i ) ) = i + i 1 }
            ^ F
        }
    } {}
    // ARIMA_PH_GRAD: the gradient at the accepted point — the update.
    : ( Vec f ) gn ( vec_zeroed [f] k )
    ( __ar_bfgs_take_grad st vals 0 gn )
    : ( Slice f ) pg ( slice_from_vec [f] . st g )
    : ( Slice f ) pgn ( slice_from_vec [f] gn )
    : ( Slice f ) ps ( slice_from_vec [f] . st s )
    : ( Slice f ) py ( slice_from_vec [f] . st yv )
    : ( Slice f ) phy ( slice_from_vec [f] . st hy )
    : ( Slice f ) pH ( slice_from_vec [f] . st H )
    : ~ f smax 0.0
    : ~ f sy 0.0
    : ~ f gmax 0.0
    : ~ i i 0
    ~ < i k {
        : f a ( float_abs ( slice_at [f] ps i ) )
        ? > a smax { = smax a } {}
        ( slice_put [f] py i - ( slice_at [f] pgn i ) ( slice_at [f] pg i ) )
        = sy + sy * ( slice_at [f] ps i ) ( slice_at [f] py i )
        : f ga ( float_abs ( slice_at [f] pgn i ) )
        ? > ga gmax { = gmax ga } {}
        = i + i 1
    }
    ? > sy 0.0000000001 {
        // The first update scales H to the curvature seen (Nocedal &
        // Wright 6.20), so the identity's unit scale never lingers.
        ? == . st iter 0 {
            : ~ f yy 0.0
            = i 0
            ~ < i k { = yy + yy * ( slice_at [f] py i ) ( slice_at [f] py i ) = i + i 1 }
            ? > yy 0.0 {
                : f sc / sy yy
                = i 0
                ~ < i k {
                    : ~ i j 0
                    ~ < j k { ( slice_put [f] pH + * i k j ? == i j sc 0.0 ) = j + j 1 }
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
            ~ < j k { = v + v * ( slice_at [f] pH + * i k j ) ( slice_at [f] py j ) = j + j 1 }
            ( slice_put [f] phy i v )
            = i + i 1
        }
        : ~ f yhy 0.0
        = i 0
        ~ < i k { = yhy + yhy * ( slice_at [f] py i ) ( slice_at [f] phy i ) = i + i 1 }
        = i 0
        ~ < i k {
            : ~ i j 0
            ~ < j k {
                : f hij ( slice_at [f] pH + * i k j )
                : f ss_term * * rho + 1.0 * rho yhy * ( slice_at [f] ps i ) ( slice_at [f] ps j )
                : f cross * rho + * ( slice_at [f] phy i ) ( slice_at [f] ps j ) * ( slice_at [f] ps i ) ( slice_at [f] phy j )
                ( slice_put [f] pH + * i k j - + hij ss_term cross )
                = j + j 1
            }
            = i + i 1
        }
    } {}
    : f df - . st f0 . st fn
    = . st f0 . st fn
    = i 0
    ~ < i k { ( slice_put [f] pg i ( slice_at [f] pgn i ) ) = i + i 1 }
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
@ __ar_bfgs inout ArimaObj o ( Vec f ) raw → ArimaOpt {
    : i k ( vec_len [f] raw )
    ? == k 0 { ^ @ ArimaOpt { T ( __ar_objective o raw ) 0 } } {}
    : ~ ArimaBfgs st ( __ar_bfgs_new raw )
    : ~ b done F
    ~ ! done {
        : ( Vec ( Vec f ) ) reqs ( __ar_bfgs_requests st )
        : ( Vec f ) vals ( vec_zeroed [f] ( vec_len [( Vec f )] reqs ) )
        ( __ar_eval_batch o reqs vals )
        = done ( __ar_bfgs_absorb st vals )
    }
    ( __ar_copy_into raw . st raw )
    ^ @ ArimaOpt { . st converged . st f0 . st iter }
}

// ── The model ─────────────────────────────────────────────────────────

: ArimaModelImpl {
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
    ( Vec i ) xper  // Fourier periods in rows — see arima_fit_regress
    i xk  // harmonics per period
    ( Vec f ) xcoef  // 1 + 2·xk·|xper| (+ 1 with a trend): the intercept, per period and harmonic the sine and cosine weights, the slope
    i xt  // rows since the fit's origin: the index the next observation has in the regressors
    i xtr  // 1 when a linear trend (drift) is among the regressors
}

// An ArimaModel is a handle on its state in a Locked (stdlib/std/thread.nu):
// every copy is the same state, stepped by any of them on any thread, and
// the last owner releases it. A call checks the state out (locked_take),
// works on it and puts it back; another thread's call waits meanwhile.
: ArimaModel { ( Locked ArimaModelImpl ) l }

@ ArimaModel_share ArimaModel h → ArimaModel { ^ @ ArimaModel { ( Locked_share [ArimaModelImpl] . h l ) } }

@ ArimaModel_drop sink ArimaModel h → v {}

@ __ar_model_of sink ArimaModelImpl m → ArimaModel { ^ @ ArimaModel { ( locked_new [ArimaModelImpl] m ) } }

// A model state with its fit statistics at zero and no regressors.
@ __ar_model_blank ArimaSpec sp ArimaCoef c ArimaSS ss i method → ArimaModelImpl {
    ^ @ ArimaModelImpl { sp c 0.0 0.0 0.0 0.0 0.0 0 0 0 method F 0 0 ss ( vec_new [f] ) 0.0 0.0 0.0 ( vec_new [i] ) 0 ( vec_new [f] ) 0 0 }
}

// Does the model carry regressors at all?
@ __ar_has_x ArimaModelImpl m → b {
    ^ > ( vec_len [f] . m xcoef ) 0
}

// Let go of `m` now rather than at the end of its owner's scope. The
// model's last owner releases its coefficients, state and statistics.
@ arima_free sink ArimaModel m → v {}

// The deterministic seasonal at row `t`: the intercept and the Fourier
// terms of every period (0.0 when the model has none).
@ __ar_fourier ArimaModelImpl m i t → f {
    ? ( __ar_has_x m ) {} { ^ 0.0 }
    : ( Slice f ) c ( slice_from_vec [f] . m xcoef )
    : ( Slice i ) per ( slice_from_vec [i] . m xper )
    : i np ( vec_len [i] . m xper )
    : ~ f mu ( slice_at [f] c 0 )
    : ~ i q 1
    : ~ i p 0
    ~ < p np {
        : f base / * TAU # f t # f ( slice_at [i] per p )
        : ~ i k 1
        ~ <= k . m xk {
            : f a * base # f k
            = mu + mu * ( slice_at [f] c q ) ( float_sin a )
            = mu + mu * ( slice_at [f] c + q 1 ) ( float_cos a )
            = q + q 2
            = k + k 1
        }
        = p + p 1
    }
    ? != . m xtr 0 { = mu + mu * ( slice_at [f] c q ) # f t } {}
    ^ mu
}

@ __arima_spec_of_in inout ArimaModelImpl m → ArimaSpec {
    ^ . m spec
}

@ arima_spec_of ArimaModel m__h → ArimaSpec {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ArimaSpec res ( __arima_spec_of_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_sigma2_in inout ArimaModelImpl m → f {
    ^ . m sigma2
}

@ arima_sigma2 ArimaModel m__h → f {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : f res ( __arima_sigma2_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_loglik_in inout ArimaModelImpl m → f {
    ^ . m loglik
}

@ arima_loglik ArimaModel m__h → f {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : f res ( __arima_loglik_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_aic_in inout ArimaModelImpl m → f {
    ^ . m aic
}

@ arima_aic ArimaModel m__h → f {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : f res ( __arima_aic_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_aicc_in inout ArimaModelImpl m → f {
    ^ . m aicc
}

@ arima_aicc ArimaModel m__h → f {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : f res ( __arima_aicc_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_n_in inout ArimaModelImpl m → i {
    ^ . m n
}

@ arima_n ArimaModel m__h → i {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : i res ( __arima_n_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_converged_in inout ArimaModelImpl m → b {
    ^ . m converged
}

@ arima_converged ArimaModel m__h → b {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : b res ( __arima_converged_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// Objective evaluations the fit took.
@ __arima_evals_in inout ArimaModelImpl m → i {
    ^ . m evals
}

@ arima_evals ArimaModel m__h → i {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : i res ( __arima_evals_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// Standard errors, coefficient order (may hold NaN). Borrowed: valid
// while the model is.
@ __arima_se_in inout ArimaModelImpl m → ( Vec f ) {
    ^ . m se
}

@ arima_se ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_se_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// The regressors (see arima_fit_regress): harmonics per period, the
// coefficients (borrowed), the next observation's row, 1 with a trend.
@ __arima_xk_in inout ArimaModelImpl m → i {
    ^ . m xk
}

@ arima_xk ArimaModel m__h → i {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : i res ( __arima_xk_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_xcoef_in inout ArimaModelImpl m → ( Vec f ) {
    ^ . m xcoef
}

@ arima_xcoef ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_xcoef_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_xt_in inout ArimaModelImpl m → i {
    ^ . m xt
}

@ arima_xt ArimaModel m__h → i {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : i res ( __arima_xt_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_xtr_in inout ArimaModelImpl m → i {
    ^ . m xtr
}

@ arima_xtr ArimaModel m__h → i {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : i res ( __arima_xtr_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_phi_in inout ArimaModelImpl m → ( Vec f ) {
    : ArimaCoef c . m coef ^ . c phi
}

@ arima_phi ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_phi_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_theta_in inout ArimaModelImpl m → ( Vec f ) {
    : ArimaCoef c . m coef ^ . c theta
}

@ arima_theta ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_theta_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_sphi_in inout ArimaModelImpl m → ( Vec f ) {
    : ArimaCoef c . m coef ^ . c sphi
}

@ arima_sphi ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_sphi_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_stheta_in inout ArimaModelImpl m → ( Vec f ) {
    : ArimaCoef c . m coef ^ . c stheta
}

@ arima_stheta ArimaModel m__h → ( Vec f ) {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ( Vec f ) res ( __ar_vec_copy ( __arima_stheta_in m ) )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

@ __arima_mu_in inout ArimaModelImpl m → f {
    : ArimaCoef c . m coef ^ . c mu
}

@ arima_mu ArimaModel m__h → f {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : f res ( __arima_mu_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// The full state-space form for the coefficients, with the differencing
// folded in, at its diffuse start.
@ __ar_full_ss ArimaSpec sp ArimaCoef c → ArimaSS {
    : ( Vec f ) ar ( _ar_expand_ar . c phi . c sphi . sp s )
    : ( Vec f ) ma ( _ar_expand_ma . c theta . c stheta . sp s )
    : ( Vec f ) delta ( _ar_delta . sp d . sp D . sp s )
    : ArimaSS ss ( _ar_ss_new ar ma delta )
    : b _ok ( _ar_init_cov ss )
    ^ ss
}

// Run the full model over the raw series to reach its end state. The
// mean is removed on the way in (the state holds y − μ).
@ __ar_run_full inout ArimaModelImpl m ( Vec f ) y → v {
    : i n ( vec_len [f] y )
    : ( Slice f ) py ( slice_from_vec [f] y )
    : ArimaCoef mc . m coef
    : ArimaSS ss . m ss
    : ~ i t 0
    ~ < t n {
        : ArimaStep st ( _ar_step ss - ( slice_at [f] py t ) . mc mu )
        = . m last_innovation . st innovation
        = . m last_variance * . st variance . m sigma2
        = . m last_predicted + . st predicted . mc mu
        = t + t 1
    }
}

// Numerical Hessian of −loglik over the natural coefficients at the
// optimum → standard errors. NaN where the curvature is not positive.
@ __ar_stderr ArimaModelImpl m ( Vec f ) w → ( Vec f ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    ? == k 0 { ^ ( vec_zeroed [f] 0 ) } {}
    : ( Vec ( Vec f ) ) pts ( __ar_hessian_points m )
    : i np ( vec_len [( Vec f )] pts )
    : ( Arc ( Vec f ) ) wa ( arc_new [( Vec f )] ( __ar_vec_copy w ) )
    : ( Vec ArimaJob ) jobs ( vec_new [ArimaJob] )
    : ~ i q 0
    ~ < q np {
        ?? ( vec_get [( Vec f )] pts q ) { T pt → { ( vec_push [ArimaJob] jobs ( _ar_job sp ( Arc_share [( Vec f )] wa ) . m method 0 pt 1 ) ) } F _ → {} }
        = q + q 1
    }
    : b par > * ( __ar_work_of sp ( vec_len [f] w ) . m method ) np ARIMA_PAR_WORK
    : ( Vec f ) vals ( _ar_jobs_eval jobs par )
    ^ ( __ar_hessian_fold m vals )
}

// The finite-difference step of coordinate x.
@ __ar_hstep f x → f {
    : f ax ( float_abs x )
    ^ ? > ax 1.0 * 0.0001 ax 0.0001
}

// The stencil of the Hessian of −loglik over the natural coefficients at
// the model's optimum: four points per (i ≤ j) pair, natural coordinates.
@ __ar_hessian_points ArimaModelImpl m → ( Vec ( Vec f ) ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    : ( Vec f ) x ( _ar_natural_of_coef sp . m coef )
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ( Vec ( Vec f ) ) pts ( vec_new [( Vec f )] )
    : ~ i i 0
    ~ < i k {
        : ~ i j i
        ~ < j k {
            : f hi ( __ar_hstep ( slice_at [f] px i ) )
            : f hj ( __ar_hstep ( slice_at [f] px j ) )
            : ~ i sgn 0
            ~ < sgn 4 {
                : ( Vec f ) pt ( __ar_vec_copy x )
                : ( Slice f ) pp ( slice_from_vec [f] pt )
                : f si ? < sgn 2 hi - 0.0 hi
                : f sj ? | == sgn 0 == sgn 2 hj - 0.0 hj
                ( slice_put [f] pp i + ( slice_at [f] pp i ) si )
                ( slice_put [f] pp j + ( slice_at [f] pp j ) sj )
                ( vec_push [( Vec f )] pts pt )
                = sgn + sgn 1
            }
            = j + j 1
        }
        = i + i 1
    }
    ^ pts
}

// The stencil's values → standard errors (NaN where the curvature is
// not positive, or the Hessian is singular).
@ __ar_hessian_fold ArimaModelImpl m ( Vec f ) vals → ( Vec f ) {
    : ArimaSpec sp . m spec
    : i k ( __ar_ncoef sp )
    : ( Vec f ) se ( vec_zeroed [f] k )
    ? == k 0 { ^ se } {}
    : ( Slice f ) pse ( slice_from_vec [f] se )
    : ( Vec f ) x ( _ar_natural_of_coef sp . m coef )
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ( Vec f ) Hm ( vec_zeroed [f] * k k )
    : ( Slice f ) pH ( slice_from_vec [f] Hm )
    : ( Slice f ) pv ( slice_from_vec [f] vals )
    : ~ i q 0
    : ~ i i 0
    ~ < i k {
        : ~ i j i
        ~ < j k {
            : f hi ( __ar_hstep ( slice_at [f] px i ) )
            : f hj ( __ar_hstep ( slice_at [f] px j ) )
            : f fpp ( slice_at [f] pv * 4 q )
            : f fpm ( slice_at [f] pv + * 4 q 1 )
            : f fmp ( slice_at [f] pv + * 4 q 2 )
            : f fmm ( slice_at [f] pv + * 4 q 3 )
            : f v / - - + fpp fmm fpm fmp * * 4.0 hi hj
            ( slice_put [f] pH + * i k j v )
            ( slice_put [f] pH + * j k i v )
            = q + q 1
            = j + j 1
        }
        = i + i 1
    }
    // Invert by Gauss–Jordan; a failure leaves NaN everywhere.
    : ( Vec f ) inv ( vec_zeroed [f] * k k )
    : ( Slice f ) pi ( slice_from_vec [f] inv )
    = i 0
    ~ < i k { ( slice_put [f] pi + * i k i 1.0 ) = i + i 1 }
    : ~ b ok T
    : ~ i c 0
    ~ & ok < c k {
        : ~ i piv c
        : ~ f best ( float_abs ( slice_at [f] pH + * c k c ) )
        : ~ i rr + c 1
        ~ < rr k {
            : f a ( float_abs ( slice_at [f] pH + * rr k c ) )
            ? > a best { = best a = piv rr } {}
            = rr + rr 1
        }
        ? <= best 0.0000000000001 { = ok F } {
            ? != piv c {
                : ~ i j 0
                ~ < j k {
                    : f t1 ( slice_at [f] pH + * c k j )
                    ( slice_put [f] pH + * c k j ( slice_at [f] pH + * piv k j ) )
                    ( slice_put [f] pH + * piv k j t1 )
                    : f t2 ( slice_at [f] pi + * c k j )
                    ( slice_put [f] pi + * c k j ( slice_at [f] pi + * piv k j ) )
                    ( slice_put [f] pi + * piv k j t2 )
                    = j + j 1
                }
            } {}
            : f pv ( slice_at [f] pH + * c k c )
            : ~ i j 0
            ~ < j k { ( slice_put [f] pH + * c k j / ( slice_at [f] pH + * c k j ) pv ) ( slice_put [f] pi + * c k j / ( slice_at [f] pi + * c k j ) pv ) = j + j 1 }
            = rr 0
            ~ < rr k {
                ? != rr c {
                    : f fac ( slice_at [f] pH + * rr k c )
                    ? != fac 0.0 {
                        = j 0
                        ~ < j k {
                            ( slice_put [f] pH + * rr k j - ( slice_at [f] pH + * rr k j ) * fac ( slice_at [f] pH + * c k j ) )
                            ( slice_put [f] pi + * rr k j - ( slice_at [f] pi + * rr k j ) * fac ( slice_at [f] pi + * c k j ) )
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
        : f vii ( slice_at [f] pi + * i k i )
        ( slice_put [f] pse i ? & ok > vii 0.0 ( float_sqrt vii ) / 0.0 0.0 )
        = i + i 1
    }
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
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ~ i off 0
    : ~ i i 0
    ~ < i . sp p { ( vec_set [f] . c phi i ( slice_at [f] px + off i ) ) = i + i 1 }
    = off + off . sp p
    = i 0
    ~ < i . sp q { ( vec_set [f] . c theta i ( slice_at [f] px + off i ) ) = i + i 1 }
    = off + off . sp q
    = i 0
    ~ < i . sp P { ( vec_set [f] . c sphi i ( slice_at [f] px + off i ) ) = i + i 1 }
    = off + off . sp P
    = i 0
    ~ < i . sp Q { ( vec_set [f] . c stheta i ( slice_at [f] px + off i ) ) = i + i 1 }
    = off + off . sp Q
    ^ @ ArimaCoef { . c phi . c theta . c sphi . c stheta ? . sp mean ( slice_at [f] px off ) 0.0 }
}

// The bundle → the natural vector.
@ _ar_natural_of_coef ArimaSpec sp ArimaCoef mc → ( Vec f ) {
    : i k ( __ar_ncoef sp )
    : ( Vec f ) x ( vec_zeroed [f] k )
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ~ i off 0
    : ~ i i 0
    ~ < i . sp p { ( slice_put [f] px + off i ( _ar_at . mc phi i ) ) = i + i 1 }
    = off + off . sp p
    = i 0
    ~ < i . sp q { ( slice_put [f] px + off i ( _ar_at . mc theta i ) ) = i + i 1 }
    = off + off . sp q
    = i 0
    ~ < i . sp P { ( slice_put [f] px + off i ( _ar_at . mc sphi i ) ) = i + i 1 }
    = off + off . sp P
    = i 0
    ~ < i . sp Q { ( slice_put [f] px + off i ( _ar_at . mc stheta i ) ) = i + i 1 }
    = off + off . sp Q
    ? . sp mean { ( slice_put [f] px off . mc mu ) } {}
    ^ x
}

@ arima_fit_method ( Vec f ) y ArimaSpec sp0 i method → ArimaModel {
    ^ ( __ar_fit_cond y sp0 method 0 T )
}

// The fit with CSS's conditioning count given (0 = the model's own
// order; the search passes the largest order it screens); without
// `with_se` the model has neither standard errors nor a filtered state —
// a screened candidate, judged by its AICc and discarded.
@ __ar_fit_cond ( Vec f ) y ArimaSpec sp0 i method i ncond b with_se → ArimaModel {
    : ArimaSpec sp ( arima_spec_with_mean sp0 . sp0 mean )
    : ( Vec f ) w ( arima_difference y . sp d . sp D . sp s )
    : ( Vec f ) raw ( __ar_raw_start w sp )
    // the objective's parameter block (it shares w with the evaluations)
    : ~ ArimaObj o @ ArimaObj { sp ( arc_new [( Vec f )] w ) ARIMA_CSS ncond 0 }
    : ~ ArimaOpt opt ( __ar_bfgs o raw )
    : ~ i iters . opt iterations
    ? == method ARIMA_ML {
        = . o method ARIMA_ML
        : ArimaOpt opt2 ( __ar_bfgs o raw )
        = opt opt2
        = iters + iters . opt2 iterations
    } {}
    ^ ( __ar_model_from_raw y ( arc_get [( Vec f )] . o w ) sp method ncond raw . opt converged iters . o evals with_se with_se )
}

// The model at an optimum: coefficients, statistics, standard errors,
// and the full state filtered over the raw series.
@ __ar_model_from_raw ( Vec f ) y ( Vec f ) w ArimaSpec sp i method i ncond ( Vec f ) raw b converged i iters i evals b with_se b with_state → ArimaModel {
    : i k ( __ar_ncoef sp )
    : ArimaCoef c ( _ar_coef_of_raw sp raw )
    : ArimaLik lk ? == method ARIMA_CSS ( __ar_loglik_css sp c w ncond ) ( __ar_loglik_ml sp c w )
    : ~ ArimaModelImpl m ( __ar_model_blank sp c ( __ar_full_ss sp c ) method )
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
    = . m converged & converged . lk ok
    = . m iterations iters
    = . m evals evals
    = . m se ? with_se ( __ar_stderr m w ) ( vec_zeroed [f] k )
    // The full model's pass over the raw series is O(n · r_d²) — for a
    // weekly season the cost of the fit itself over again — and a
    // candidate the search will discard has no use for a state.
    ? with_state { ( __ar_run_full m y ) } {}
    ^ ( __ar_model_of m )
}

// The starting parameters for a fit: zeros, the mean at the sample mean.
@ __ar_raw_start ( Vec f ) w ArimaSpec sp → ( Vec f ) {
    : i k ( __ar_ncoef sp )
    : ( Vec f ) raw ( vec_zeroed [f] k )
    ? . sp mean {
        : i n ( vec_len [f] w )
        : ( Slice f ) pw ( slice_from_vec [f] w )
        : ~ f sum 0.0
        : ~ i t 0
        ~ < t n { = sum + sum ( slice_at [f] pw t ) = t + t 1 }
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
    ( Arc ( Vec f ) ) w  // shared with the evaluations' threads
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
                        : i wk ( __ar_work_of . cx sp ( vec_len [f] ( arc_get [( Vec f )] . cx w ) ) . cx method )
                        ? > wk big { = big wk } {}
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
    : ( Vec ArimaJob ) jobs ( vec_new [ArimaJob] )
    = i 0
    ~ < i m {
        ?? ( vec_get [ArimaEvalItem] items i ) {
            T it → {
                ?? ( vec_get [ArimaCtx] ctxs . it ctx ) {
                    T cx → { ( vec_push [ArimaJob] jobs ( _ar_job . cx sp . cx w . cx method . cx ncond . it raw . it kind ) ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = i + i 1
    }
    ( __ar_copy_into out ( _ar_jobs_eval jobs par ) )
}

: ArimaFitState {
    ArimaBfgs st
    i stage  // 0 = CSS running, 1 = ML running, 2 = finished
    i iters
    i evals
    b converged
    i req_at  // where this model's requests start in the current batch
    i req_n
}

// Fit `series` (each a raw series) under `sp` by `method`, the
// evaluations batched through `evaluator`.
@ arima_fit_many_with ( Vec ( Vec f ) ) series ArimaSpec sp0 i method ( @ v ( Vec ArimaEvalItem ) ( Vec ArimaCtx ) ( Vec f ) ) evaluator → ( Vec ArimaModel ) {
    : ArimaSpec sp ( arima_spec_with_mean sp0 . sp0 mean )
    : i K ( vec_len [( Vec f )] series )
    // Per-model state: its context, and its optimizer, checked out of
    // the Vec while a round changes it (__ar_fs_take / __ar_fs_put).
    : ( Vec ArimaCtx ) ctxv ( vec_new [ArimaCtx] )
    : ( Vec ArimaFitState ) fsv ( vec_new [ArimaFitState] )
    : ~ i i 0
    ~ < i K {
        ?? ( vec_get [( Vec f )] series i ) {
            T y → {
                : ( Vec f ) w ( arima_difference y . sp d . sp D . sp s )
                : ( Vec f ) raw ( __ar_raw_start w sp )
                ( vec_push [ArimaCtx] ctxv @ ArimaCtx { sp ( arc_new [( Vec f )] w ) ARIMA_CSS 0 } )
                ( vec_push [ArimaFitState] fsv @ ArimaFitState { ( __ar_bfgs_new raw ) 0 0 0 F 0 0 } )
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
            : ~ ArimaFitState f ( __ar_fs_take fsv i )
            = . f req_at ( vec_len [ArimaEvalItem] items )
            = . f req_n 0
            ? < . f stage 2 {
                : ( Vec ( Vec f ) ) reqs ( __ar_bfgs_requests . f st )
                : i nr ( vec_len [( Vec f )] reqs )
                : ~ i q 0
                ~ < q nr {
                    ?? ( vec_get [( Vec f )] reqs q ) { T rw → { ( vec_push [ArimaEvalItem] items @ ArimaEvalItem { i ( __ar_vec_copy rw ) 0 } ) } F _ → {} }
                    = q + q 1
                }
                = . f req_n nr
                = . f evals + . f evals nr
                ? > nr 0 { = active T } {}
            } {}
            ( __ar_fs_put fsv i f )
            = i + i 1
        }
        ? active {
            : ( Vec f ) vals ( vec_zeroed [f] ( vec_len [ArimaEvalItem] items ) )
            ( evaluator items ctxv vals )
            : ( Slice f ) pv ( slice_from_vec [f] vals )
            = i 0
            ~ < i K {
                : ~ ArimaFitState f ( __ar_fs_take fsv i )
                ? & < . f stage 2 > . f req_n 0 {
                    : ( Vec f ) mine ( vec_zeroed [f] . f req_n )
                    : ( Slice f ) pm ( slice_from_vec [f] mine )
                    : ~ i q 0
                    ~ < q . f req_n { ( slice_put [f] pm q ( slice_at [f] pv + . f req_at q ) ) = q + q 1 }
                    ? ( __ar_bfgs_absorb . f st mine ) {
                        = . f iters + . f iters . . f st iter
                        = . f converged . . f st converged
                        ? & == . f stage 0 == method ARIMA_ML {
                            // CSS done: ML from there (the store lets the CSS state go)
                            = . f st ( __ar_bfgs_new . . f st raw )
                            = . f stage 1
                            : ArimaCtx cx ( vec_at [ArimaCtx] ctxv i )
                            ( vec_put [ArimaCtx] ctxv i @ ArimaCtx { . cx sp . cx w ARIMA_ML . cx ncond } )
                        } { = . f stage 2 }
                    } {}
                } {}
                ( __ar_fs_put fsv i f )
                = i + i 1
            }
        } {}
    }
    : ( Vec ArimaModel ) out ( vec_new [ArimaModel] )
    = i 0
    ~ < i K {
        : ArimaFitState f ( vec_at [ArimaFitState] fsv i )
        : ArimaCtx cx ( vec_at [ArimaCtx] ctxv i )
        ?? ( vec_get [( Vec f )] series i ) {
            T y → {
                ( vec_push [ArimaModel] out ( __ar_model_from_raw y ( arc_get [( Vec f )] . cx w ) sp method 0 . . f st raw . f converged . f iters . f evals F T ) )
            }
            F _ → {}
        }
        = i + i 1
    }
    // The standard errors: every model's Hessian stencil in one round.
    : ( Vec ArimaEvalItem ) hitems ( vec_new [ArimaEvalItem] )
    : ( Vec i ) hat ( vec_new [i] )
    : ( Vec i ) hn ( vec_new [i] )
    : ( Vec ArimaCtx ) hctx ( vec_new [ArimaCtx] )
    = i 0
    ~ < i K {
        : ArimaCtx cx ( vec_at [ArimaCtx] ctxv i )
        ( vec_push [ArimaCtx] hctx @ ArimaCtx { . cx sp . cx w method . cx ncond } )
        ( vec_push [i] hat ( vec_len [ArimaEvalItem] hitems ) )
        ?? ( vec_get [ArimaModel] out i ) {
            T mmh → {
                : ~ ArimaModelImpl mm ( locked_take [ArimaModelImpl] . mmh l )
                : ( Vec ( Vec f ) ) pts ( __ar_hessian_points mm )
                ( locked_restore [ArimaModelImpl] . mmh l mm )
                : i np ( vec_len [( Vec f )] pts )
                : ~ i q 0
                ~ < q np {
                    ?? ( vec_get [( Vec f )] pts q ) { T pt → { ( vec_push [ArimaEvalItem] hitems @ ArimaEvalItem { i ( __ar_vec_copy pt ) 1 } ) } F _ → {} }
                    = q + q 1
                }
                ( vec_push [i] hn np )
            }
            F _ → { ( vec_push [i] hn 0 ) }
        }
        = i + i 1
    }
    : ( Vec f ) hvals ( vec_zeroed [f] ( vec_len [ArimaEvalItem] hitems ) )
    ? > ( vec_len [ArimaEvalItem] hitems ) 0 { ( evaluator hitems hctx hvals ) } {}
    : ( Slice f ) phv ( slice_from_vec [f] hvals )
    = i 0
    ~ < i K {
        ?? ( vec_get [ArimaModel] out i ) {
            T mmh → {
                : ~ ArimaModelImpl mm ( locked_take [ArimaModelImpl] . mmh l )
                : i np ( _ar_geti hn i )
                : i at ( _ar_geti hat i )
                : ( Vec f ) mine ( vec_zeroed [f] np )
                : ( Slice f ) pm ( slice_from_vec [f] mine )
                : ~ i q 0
                ~ < q np { ( slice_put [f] pm q ( slice_at [f] phv + at q ) ) = q + q 1 }
                = . mm se ( __ar_hessian_fold mm mine )
                ( locked_restore [ArimaModelImpl] . mmh l mm )
            }
            F _ → {}
        }
        = i + i 1
    }
    ^ out
}

// Model `k`'s fit state, out of the Vec (the last one takes its place)…
@ __ar_fs_take ( Vec ArimaFitState ) v i k → ArimaFitState {
    : i last - ( vec_len [ArimaFitState] v ) 1
    ? != k last { ( vec_swap [ArimaFitState] v k last ) } {}
    ?? ( vec_pop [ArimaFitState] v ) { T x → { ^ x } F → { ( nurl_panic `arima: fit state out of range` ) ^ ( __ar_fs_take v k ) } }
}

// …and back in its place.
@ __ar_fs_put ( Vec ArimaFitState ) v i k sink ArimaFitState x → v {
    ( vec_push [ArimaFitState] v x )
    : i last - ( vec_len [ArimaFitState] v ) 1
    ? != k last { ( vec_swap [ArimaFitState] v k last ) } {}
}

@ _ar_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } }
}

// K series fitted together on the CPU's threads.
@ arima_fit_many ( Vec ( Vec f ) ) series ArimaSpec sp i method → ( Vec ArimaModel ) {
    ^ ( arima_fit_many_with series sp method \ ( Vec ArimaEvalItem ) items ( Vec ArimaCtx ) ctxs ( Vec f ) out → v { ( arima_eval_cpu items ctxs out ) } )
}

// Let go of `ms` now rather than at the end of its owner's scope (each
// model goes with its last owner).
@ arima_models_free sink ( Vec ArimaModel ) ms → v {}

@ arima_fit ( Vec f ) y ArimaSpec sp → ArimaModel {
    ^ ( arima_fit_method y sp ARIMA_ML )
}

// ── Forecasting and streaming ─────────────────────────────────────────

: ArimaForecast {
    ( Vec f ) mean
    ( Vec f ) se
}

// Let go of `fc` now rather than at the end of its owner's scope.
@ arima_forecast_free sink ArimaForecast fc → v {}

// h steps ahead from the model's current state: means and standard
// errors (σ² applied). The state is left where it was.
@ __arima_forecast_in inout ArimaModelImpl m i h → ArimaForecast {
    : ( Vec f ) mean ( vec_zeroed [f] h )
    : ( Vec f ) se ( vec_zeroed [f] h )
    : ArimaSS ss . m ss
    : ArimaCoef mc . m coef
    : ( Vec f ) a0 ( __ar_vec_copy . ss a )
    : ( Vec f ) p0 ( __ar_vec_copy . ss pm )
    : ( Slice f ) pm ( slice_from_vec [f] mean )
    : ( Slice f ) pse ( slice_from_vec [f] se )
    : ~ i j 0
    ~ < j h {
        : f fv ( __ar_observe ss )
        ( slice_put [f] pm j + ( __ar_predicted ss ) . mc mu )
        ? ( __ar_has_x m ) { ( slice_put [f] pm j + ( slice_at [f] pm j ) ( __ar_fourier m + . m xt j ) ) } {}
        : f vr * fv . m sigma2
        ( slice_put [f] pse j ? > vr 0.0 ( float_sqrt vr ) 0.0 )
        ( __ar_tvec ss )
        ( __ar_predict_cov ss )
        = j + j 1
    }
    // restore
    : ( Slice f ) A ( slice_from_vec [f] . ss a )
    : ( Slice f ) P ( slice_from_vec [f] . ss pm )
    : ( Slice f ) A0 ( slice_from_vec [f] a0 )
    : ( Slice f ) P0 ( slice_from_vec [f] p0 )
    : ~ i i 0
    ~ < i . ss rd { ( slice_put [f] A i ( slice_at [f] A0 i ) ) = i + i 1 }
    = i 0
    ~ < i * . ss rd . ss rd { ( slice_put [f] P i ( slice_at [f] P0 i ) ) = i + i 1 }
    ^ @ ArimaForecast { mean se }
}

@ arima_forecast ArimaModel m__h i h → ArimaForecast {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ArimaForecast res ( __arima_forecast_in m h )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
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
@ __arima_update_in inout ArimaModelImpl m f y → ArimaUpdate {
    : ArimaCoef mc . m coef
    : ArimaSS ss . m ss
    = . m n + . m n 1
    // with regressors the filter sees the reading less the seasonal
    // of this row, and the forecast is the filter's plus it
    : ~ f mu 0.0
    ? ( __ar_has_x m ) { = mu ( __ar_fourier m . m xt ) = . m xt + . m xt 1 } {}
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
    ? ( __ar_has_x m ) { = yy - y mu } {}
    : ArimaStep st ( _ar_step ss - yy . mc mu )
    : f vr * . st variance . m sigma2
    : f pred + + . st predicted . mc mu mu
    = . m last_innovation . st innovation
    = . m last_variance vr
    = . m last_predicted pred
    : f z ? > vr 0.0 / . st innovation ( float_sqrt vr ) 0.0
    ^ @ ArimaUpdate { pred . st innovation vr z }
}

@ arima_update ArimaModel m__h f y → ArimaUpdate {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ArimaUpdate res ( __arima_update_in m y )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// Forget the observations: the state goes back to where a freshly fitted
// model's stands before its first point (the stationary covariance for
// the ARMA part, diffuse for the differencing), `n` to 0. The
// coefficients stay. Feed the series again with arima_update and the
// state after n points is the state a fit over them would have left —
// which is how a caller replays a stored history through a model whose
// state has moved past it.
@ arima_restart ArimaModel m__h → v {
    ( arima_restart_at m__h 0 )
}

// The same, with the regressors' clock set: `t0` is the row the next
// observation has, counted from the fit's origin (negative for rows
// before it) — a replay that begins elsewhere than the fit did keeps the
// seasonal's phase. A model without regressors ignores it.
@ __arima_restart_at_in inout ArimaModelImpl m i t0 → v {
    ( _ar_ss_free . m ss )
    = . m ss ( __ar_full_ss . m spec . m coef )
    = . m n 0
    = . m last_innovation 0.0
    = . m last_variance 0.0
    = . m last_predicted 0.0
    = . m xt t0
}

@ arima_restart_at ArimaModel m__h i t0 → v {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    ( __arima_restart_at_in m t0 )
    ( locked_restore [ArimaModelImpl] . m__h l m )
}

// A deep copy: coefficients, fit statistics, standard errors and the
// state, so the copy can be stepped without moving the original.
@ __arima_clone_in inout ArimaModelImpl m → ArimaModel {
    : ArimaSS src . m ss
    : ~ ArimaModelImpl c ( __ar_model_blank . m spec ( __ar_coef_clone . m coef ) @ ArimaSS { . src r . src nd . src rd ( __ar_vec_copy . src phi ) ( __ar_vec_copy . src theta ) ( __ar_vec_copy . src delta ) ( __ar_vec_copy . src a ) ( __ar_vec_copy . src pm ) ( __ar_vec_copy . src scratch ) ( __ar_vec_copy . src scratch2 ) ( __ar_vec_copy . src pz ) ( __ar_vec_copy . src prev ) ( __ar_vec_copy . src kg ) ( __ar_vec_copy . src fz ) } . m method )
    = . c sigma2 . m sigma2
    = . c loglik . m loglik
    = . c aic . m aic
    = . c aicc . m aicc
    = . c bic . m bic
    = . c n . m n
    = . c n_fit . m n_fit
    = . c n_used . m n_used
    = . c converged . m converged
    = . c iterations . m iterations
    = . c evals . m evals
    = . c se ( __ar_vec_copy . m se )
    = . c last_innovation . m last_innovation
    = . c last_variance . m last_variance
    = . c last_predicted . m last_predicted
    = . c xper ( __ar_veci_copy . m xper )
    = . c xk . m xk
    = . c xcoef ( __ar_vec_copy . m xcoef )
    = . c xt . m xt
    = . c xtr . m xtr
    ^ ( __ar_model_of c )
}

@ arima_clone ArimaModel m__h → ArimaModel {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : ArimaModel res ( __arima_clone_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
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
@ arima_fit_harmonic ( Vec f ) y ( Vec i ) periods i k ArimaSpec sp i method → ArimaModel {
    ^ ( arima_fit_regress y periods k F sp method )
}

// The same with the residual model's order chosen by the stepwise
// search (`s` its season, 0 for none — the periods carry the long ones).
@ arima_auto_harmonic ( Vec f ) y ( Vec i ) periods i k i s → ArimaModel {
    ^ ( arima_auto_regress y periods k F s )
}

// The regressors in full: the Fourier terms of `periods` (none when
// empty) and, with `trend`, a linear drift — a series that climbs by a
// fixed amount a row is ARIMA(0,1,0) with drift exactly, and without the
// term the order search has only a unit root to climb with. Everything
// is least squares first, the ARIMA on the residuals after.
@ arima_fit_regress ( Vec f ) y ( Vec i ) periods i k b trend ArimaSpec sp i method → ArimaModel {
    : ( Vec f ) coef ( __ar_fourier_ols y periods k trend )
    : ( Vec f ) res ( __ar_fourier_residuals y periods k trend coef )
    : ArimaModel m ( arima_fit_method res sp method )
    : ~ ArimaModelImpl mi ( locked_take [ArimaModelImpl] . m l )
    ( __ar_attach_fourier mi periods k trend coef ( vec_len [f] y ) )
    ( locked_restore [ArimaModelImpl] . m l mi )
    ^ m
}

@ arima_auto_regress ( Vec f ) y ( Vec i ) periods i k b trend i s → ArimaModel {
    : ( Vec f ) coef ( __ar_fourier_ols y periods k trend )
    : ( Vec f ) res ( __ar_fourier_residuals y periods k trend coef )
    : ArimaModel m ( arima_auto res s )
    : ~ ArimaModelImpl mi ( locked_take [ArimaModelImpl] . m l )
    ( __ar_attach_fourier mi periods k trend coef ( vec_len [f] y ) )
    ( locked_restore [ArimaModelImpl] . m l mi )
    ^ m
}

@ __ar_attach_fourier inout ArimaModelImpl m ( Vec i ) periods i k b trend ( Vec f ) coef i n → v {
    ( vec_free [i] . m xper )
    ( vec_free [f] . m xcoef )
    = . m xper ( __ar_veci_copy periods )
    = . m xk ? > ( vec_len [i] periods ) 0 k 0
    = . m xcoef ( __ar_vec_copy coef )  // the model's own: `coef` stays the caller's
    = . m xt n
    = . m xtr ? trend 1 0
}

// One row of the design: 1, then per period and harmonic sin, cos,
// then t when a trend is fitted.
@ __ar_fourier_row ( Vec i ) periods i k b trend i t ( Vec f ) row → v {
    : ( Slice f ) x ( slice_from_vec [f] row )
    ( slice_put [f] x 0 1.0 )
    : ~ i q 1
    : i np ( vec_len [i] periods )
    : ~ i p 0
    ~ < p np {
        : f base / * TAU # f t # f ( _ar_geti periods p )
        : ~ i j 1
        ~ <= j k {
            : f a * base # f j
            ( slice_put [f] x q ( float_sin a ) )
            ( slice_put [f] x + q 1 ( float_cos a ) )
            = q + q 2
            = j + j 1
        }
        = p + p 1
    }
    ? trend { ( slice_put [f] x q # f t ) } {}
}

// Least squares by the normal equations (a handful of columns; rows
// with a NaN reading are left out). Zeros when the system is singular
// — fewer rows than columns.
@ __ar_fourier_ols ( Vec f ) y ( Vec i ) periods i k b trend → ( Vec f ) {
    : i n ( vec_len [f] y )
    : i nc + + 1 * 2 * k ( vec_len [i] periods ) ? trend 1 0
    : ( Vec f ) M ( vec_zeroed [f] * nc nc )
    : ( Vec f ) b ( vec_zeroed [f] nc )
    : ( Vec f ) row ( vec_zeroed [f] nc )
    : ( Slice f ) pm ( slice_from_vec [f] M )
    : ( Slice f ) pb ( slice_from_vec [f] b )
    : ( Slice f ) pr ( slice_from_vec [f] row )
    : ( Slice f ) py ( slice_from_vec [f] y )
    : ~ i t 0
    ~ < t n {
        : f v ( slice_at [f] py t )
        ? ( float_is_nan v ) {} {
            ( __ar_fourier_row periods k trend t row )
            : ~ i i 0
            ~ < i nc {
                ( slice_put [f] pb i + ( slice_at [f] pb i ) * ( slice_at [f] pr i ) v )
                : ~ i j 0
                ~ < j nc { ( slice_put [f] pm + * i nc j + ( slice_at [f] pm + * i nc j ) * ( slice_at [f] pr i ) ( slice_at [f] pr j ) ) = j + j 1 }
                = i + i 1
            }
        }
        = t + t 1
    }
    ? ( _ar_solve M b nc ) {} { ( __ar_fill b 0.0 ) }
    ^ b
}

@ __ar_fourier_residuals ( Vec f ) y ( Vec i ) periods i k b trend ( Vec f ) coef → ( Vec f ) {
    : i n ( vec_len [f] y )
    : i nc ( vec_len [f] coef )
    : ( Vec f ) res ( vec_zeroed [f] n )
    : ( Vec f ) row ( vec_zeroed [f] nc )
    : ( Slice f ) pr ( slice_from_vec [f] row )
    : ( Slice f ) pc ( slice_from_vec [f] coef )
    : ( Slice f ) py ( slice_from_vec [f] y )
    : ( Slice f ) po ( slice_from_vec [f] res )
    : ~ i t 0
    ~ < t n {
        ( __ar_fourier_row periods k trend t row )
        : ~ f mu 0.0
        : ~ i i 0
        ~ < i nc { = mu + mu * ( slice_at [f] pr i ) ( slice_at [f] pc i ) = i + i 1 }
        ( slice_put [f] po t - ( slice_at [f] py t ) mu )
        = t + t 1
    }
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
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ~ f mean 0.0
    : ~ i t 0
    ~ < t n { = mean + mean ( slice_at [f] px t ) = t + t 1 }
    = mean / mean # f n
    : ( Vec f ) e ( vec_zeroed [f] n )
    : ( Slice f ) pe ( slice_from_vec [f] e )
    : ~ f s 0.0
    : ~ f eta 0.0
    : ~ f s2 0.0
    = t 0
    ~ < t n {
        ( slice_put [f] pe t - ( slice_at [f] px t ) mean )
        = s + s ( slice_at [f] pe t )
        = eta + eta * s s
        = s2 + s2 * ( slice_at [f] pe t ) ( slice_at [f] pe t )
        = t + t 1
    }
    : i l # i ( float_floor * 4.0 ( float_pow / # f n 100.0 0.25 ) )
    : ~ f lrv s2
    : ~ i k 1
    ~ <= k l {
        : ~ f g 0.0
        = t k
        ~ < t n { = g + g * ( slice_at [f] pe t ) ( slice_at [f] pe - t k ) = t + t 1 }
        = lrv + lrv * * 2.0 - 1.0 / # f k # f + l 1 g
        = k + k 1
    }
    = lrv / lrv # f n
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
            = cur nxt
            = d + d 1
        } { = going F }
    }
    ^ d
}

// The sample autocorrelation of x at lag k.
@ arima_acf ( Vec f ) x i k → f {
    : i n ( vec_len [f] x )
    ? | <= k 0 >= k n { ^ 0.0 } {}
    : ( Slice f ) px ( slice_from_vec [f] x )
    : ~ f mean 0.0
    : ~ i t 0
    ~ < t n { = mean + mean ( slice_at [f] px t ) = t + t 1 }
    = mean / mean # f n
    : ~ f c0 0.0
    : ~ f ck 0.0
    = t 0
    ~ < t n {
        : f e - ( slice_at [f] px t ) mean
        = c0 + c0 * e e
        ? >= t k { = ck + ck * e - ( slice_at [f] px - t k ) mean } {}
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
    ^ ? > r 0.5 1 0
}

@ __ar_try ( Vec f ) y ArimaSpec sp i method i ncond → ArimaModel {
    ^ ( __ar_fit_cond y sp method ncond F )
}

// Is the candidate worth a look: within the bounds, not already tried.
// Hands back the better of `best` and the candidate; the other goes.
@ __ar_auto_step ( Vec f ) y ArimaSpec cand sink ArimaModel best ( Vec i ) tried i max_pq i max_PQ i method i ncond → ArimaModel {
    ? | | | | | < . cand p 0 < . cand q 0 > . cand p max_pq > . cand q max_pq < . cand P 0 < . cand Q 0 { ^ best } {}
    ? | > . cand P max_PQ > . cand Q max_PQ { ^ best } {}
    : i key + + + + * . cand p 1000000 * . cand q 10000 * . cand P 100 * . cand Q 10 ? . cand mean 1 0
    ? ( vec_contains [i] tried key \ i a i b → b { ^ == a b } ) { ^ best } {}
    ( vec_push [i] tried key )
    : ArimaModel m ( __ar_try y cand method ncond )
    ? & ( arima_converged m ) < ( arima_aicc m ) ( arima_aicc best ) { ^ m } {}
    ^ best
}

// Stepwise search; `s` is the season (0 = none), d and D chosen by the
// tests above. Returns the best model found.
@ arima_auto ( Vec f ) y i s → ArimaModel {
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

@ arima_auto_d ( Vec f ) y i s i d i D → ArimaModel {
    : b seasonal > s 1
    : i max_pq 5
    : i max_PQ ? seasonal 2 0
    : b mean0 == + d D 0
    : i n ( vec_len [f] y )
    : i method ? | > n ARIMA_SCREEN_N > s ARIMA_SCREEN_S ARIMA_CSS ARIMA_ML
    // every screened candidate conditions on the largest order in play
    : i ncond + max_pq * s max_PQ
    : ( Vec i ) tried ( vec_new [i] )
    : ~ ArimaModel best ( __ar_try y ( arima_spec_with_mean ( arima_spec_seasonal 2 d 2 ? seasonal 1 0 D ? seasonal 1 0 s ) mean0 ) method ncond )
    ( vec_push [i] tried + + + + * 2 1000000 * 2 10000 * ? seasonal 1 0 100 * ? seasonal 1 0 10 ? mean0 1 0 )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 0 d 0 0 D 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 1 d 0 ? seasonal 1 0 D 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    = best ( __ar_auto_step y ( arima_spec_with_mean ( arima_spec_seasonal 0 d 1 0 D ? seasonal 1 0 s ) mean0 ) best tried max_pq max_PQ method ncond )
    : ~ b improved T
    : ~ i rounds 0
    ~ & improved < rounds 30 {
        = improved F
        : ArimaSpec b ( arima_spec_of best )
        : f before ( arima_aicc best )
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
        ? < ( arima_aicc best ) before { = improved T } {}
        = rounds + rounds 1
    }
    // The chosen order fitted in full — exactly where the screening was
    // approximate, and with its standard errors and state either way.
    ^ ( arima_fit_method y ( arima_spec_of best ) ARIMA_ML )
}

// ── Reporting ─────────────────────────────────────────────────────────

@ _ar_jarr ( Vec f ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [f] v )
    : ( Slice f ) p ( slice_from_vec [f] v )
    : ~ i k 0
    ~ < k n { ( json_arr_push a ( json_float ( slice_at [f] p k ) ) ) = k + k 1 }
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
@ __arima_coef_in inout ArimaModelImpl m → Json {
    : Json o ( json_obj_new )
    : ArimaCoef mc . m coef
    ( json_obj_set o `order` ( __ar_jspec . m spec ) )
    ( json_obj_set o `phi` ( _ar_jarr . mc phi ) )
    ( json_obj_set o `theta` ( _ar_jarr . mc theta ) )
    ( json_obj_set o `seasonal_phi` ( _ar_jarr . mc sphi ) )
    ( json_obj_set o `seasonal_theta` ( _ar_jarr . mc stheta ) )
    ( json_obj_set o `mu` ( json_float . mc mu ) )
    ? ( __ar_has_x m ) {
        : Json fo ( json_obj_new )
        ( json_obj_set fo `periods` ( __ar_jints . m xper ) )
        ( json_obj_set fo `k` ( json_int . m xk ) )
        ( json_obj_set fo `trend` ( json_bool != . m xtr 0 ) )
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

@ arima_coef ArimaModel m__h → Json {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : Json res ( __arima_coef_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
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
    : ( Slice f ) p ( slice_from_vec [f] v )
    : ~ i k 0
    ~ < k n {
        ( json_arr_push a ( json_int ( f64_to_bits ( slice_at [f] p k ) ) ) )
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
    : ( Slice f ) p ( slice_from_vec [f] out )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get a k ) {
            T v → { ? ( json_is_num v ) { ( slice_put [f] p k ( bits_to_f64 ( json_as_int v ) ) ) } {} }
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

@ __arima_to_json_in inout ArimaModelImpl m → String {
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
    ? ( __ar_has_x m ) {
        : Json fo ( json_obj_new )
        ( json_obj_set fo `periods` ( __ar_jints . m xper ) )
        ( json_obj_set fo `k` ( json_int . m xk ) )
        ( json_obj_set fo `trend` ( json_bool != . m xtr 0 ) )
        ( json_obj_set fo `coef` ( __ar_jbits . m xcoef ) )
        ( json_obj_set fo `t` ( json_int . m xt ) )
        ( json_obj_set o `fourier` fo )
    } {}
    ( json_obj_set o `last_innovation` ( __ar_jbit . m last_innovation ) )
    ( json_obj_set o `last_variance` ( __ar_jbit . m last_variance ) )
    ( json_obj_set o `last_predicted` ( __ar_jbit . m last_predicted ) )
    : String s ( json_stringify o )
    ^ s
}

@ arima_to_json ArimaModel m__h → String {
    : ~ ArimaModelImpl m ( locked_take [ArimaModelImpl] . m__h l )
    : String res ( __arima_to_json_in m )
    ( locked_restore [ArimaModelImpl] . m__h l m )
    ^ res
}

// The order fields of a saved model: under `order`, or (older files) at
// the top level.
@ __ar_spec_of_json Json so → ArimaSpec {
    ^ @ ArimaSpec { ( __ar_jint so `p` ) ( __ar_jint so `d` ) ( __ar_jint so `q` ) ( __ar_jint so `P` ) ( __ar_jint so `D` ) ( __ar_jint so `Q` ) ( __ar_jint so `s` ) ?? ( json_obj_get so `mean` ) { T mv → ( json_as_bool mv ) F _ → F } }
}

@ arima_from_json s src → ?ArimaModel {
    ?? ( json_parse src ) {
        T o → {
            : ~ b ok ( json_is_obj o )
            ? ok {
                ?? ( json_obj_get o `format` ) {
                    T fv → { ? == ( nurl_str_eq ( json_str_data fv ) `arima-1` ) 1 {} { = ok F } }
                    F _ → { = ok F }
                }
            } {}
            ? ok {} { ^ @ ?ArimaModel { F } }
            : ArimaSpec sp ?? ( json_obj_get o `order` ) { T x → ( __ar_spec_of_json x ) F _ → ( __ar_spec_of_json o ) }
            : ( Vec f ) phi ?? ( json_obj_get o `phi` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) th ?? ( json_obj_get o `theta` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) sphi ?? ( json_obj_get o `seasonal_phi` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ( Vec f ) sth ?? ( json_obj_get o `seasonal_theta` ) { T a → ( __ar_unbits a ) F _ → ( vec_new [f] ) }
            : ArimaCoef c @ ArimaCoef { phi th sphi sth ( __ar_unbit o `mu` ) }
            : ArimaSS fss ( __ar_full_ss sp c )
            : ~ ArimaModelImpl m ( __ar_model_blank sp c fss ( __ar_jint o `method` ) )
            : ArimaSS ms . m ss
            = . m sigma2 ( __ar_unbit o `sigma2` )
            = . m loglik ( __ar_unbit o `loglik` )
            = . m aic ( __ar_unbit o `aic` )
            = . m aicc ( __ar_unbit o `aicc` )
            = . m bic ( __ar_unbit o `bic` )
            = . m n ( __ar_jint o `n` )
            = . m n_fit ( __ar_jint o `n_fit` )
            = . m n_used ( __ar_jint o `n_used` )
            = . m converged ?? ( json_obj_get o `converged` ) { T cv → ( json_as_bool cv ) F _ → F }
            = . m iterations ( __ar_jint o `iterations` )
            = . m evals ( __ar_jint o `evaluations` )
            ?? ( json_obj_get o `state_a` ) {
                T a → {
                    : ( Vec f ) av ( __ar_unbits a )
                    ? == ( vec_len [f] av ) . ms rd { ( __ar_copy_into . ms a av ) } {}
                }
                F _ → {}
            }
            ?? ( json_obj_get o `state_p` ) {
                T a → {
                    : ( Vec f ) pv ( __ar_unbits a )
                    ? == ( vec_len [f] pv ) * . ms rd . ms rd { ( __ar_copy_into . ms pm pv ) ( __ar_copy_into . ms prev pv ) } {}
                }
                F _ → {}
            }
            ?? ( json_obj_get o `steady_gain` ) {
                T a → {
                    : ( Vec f ) gv ( __ar_unbits a )
                    ? == ( vec_len [f] gv ) . ms rd {
                        ( __ar_copy_into . ms kg gv )
                        : ( Slice f ) fz ( slice_from_vec [f] . ms fz )
                        ( slice_put [f] fz 0 ( __ar_unbit o `steady_f` ) )
                        ( slice_put [f] fz 1 1.0 )
                    } {}
                }
                F _ → {}
            }
            = . m se ?? ( json_obj_get o `se` ) { T a → ( __ar_unbits a ) F _ → ( vec_zeroed [f] ( __ar_ncoef sp ) ) }
            = . m last_innovation ( __ar_unbit o `last_innovation` )
            = . m last_variance ( __ar_unbit o `last_variance` )
            = . m last_predicted ( __ar_unbit o `last_predicted` )
            = . m xper ( vec_new [i] )
            = . m xk 0
            = . m xcoef ( vec_new [f] )
            = . m xt 0
            = . m xtr 0
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
                    = . m xtr ?? ( json_obj_get fo `trend` ) { T tv → ? ( json_as_bool tv ) 1 0 F _ → 0 }
                    ?? ( json_obj_get fo `coef` ) { T a → { ( vec_free [f] . m xcoef ) = . m xcoef ( __ar_unbits a ) } F _ → {} }
                    = . m xt ( __ar_jint fo `t` )
                    ? == ( vec_len [f] . m xcoef ) + + 1 * 2 * . m xk ( vec_len [i] . m xper ) . m xtr {} {
                        = . m xk 0
                        = . m xtr 0
                        ( vec_free [f] . m xcoef )
                        = . m xcoef ( vec_new [f] )
                    }
                }
                F _ → {}
            }
            ^ @ ?ArimaModel { T ( __ar_model_of m ) }
        }
        F _ → { ^ @ ?ArimaModel { F } }
    }
}
