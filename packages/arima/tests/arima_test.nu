// arima_test.nu — the package's checks.
//
//   algebra   — differencing, the differencing polynomial, seasonal
//               expansion, the PACF transform and its inverse.
//   oracle    — every statsmodels fixture (tests/fixtures/statsmodels_cases.json,
//               made by make_fixtures.py): coefficients, σ², log-likelihood,
//               forecast means and standard errors, to the tolerances the
//               two optimizers' stopping rules allow.
//   stream    — the one-step forecast is what the next update measures
//               against; JSON round trip is bit-exact, state included.
//   select    — KPSS on noise and on a walk; the stepwise search finds a
//               model at least as good as the true order's.
// Run from the package directory (the fixture path is relative).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `src/arima.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ near f a f b f tol → b { ^ <= ( float_abs - a b ) tol }

@ fmt f x → String { : String s ( string_new ) ( string_push_float s x ) ^ s }

@ jf Json o s key → f {
    ?? ( json_obj_get o key ) { T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F _ → {} } } F _ → {} }
    ^ 0.0
}

@ jarr_i Json a i k → i {
    ?? ( json_arr_get a k ) { T v → { ^ ( json_as_int v ) } F _ → {} }
    ^ 0
}

@ jarr_f Json a i k → f {
    ?? ( json_arr_get a k ) { T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F _ → {} } } F _ → {} }
    ^ 0.0
}

@ jvec Json a → ( Vec f ) {
    : i n ( json_arr_len a )
    : ( Vec f ) out ( vec_zeroed [f] n )
    : ~ i k 0
    ~ < k n { ( vec_set [f] out k ( jarr_f a k ) ) = k + k 1 }
    ^ out
}

@ vec_of4 f a f b f c f d → ( Vec f ) {
    : ( Vec f ) v ( vec_zeroed [f] 4 )
    ( vec_set [f] v 0 a ) ( vec_set [f] v 1 b ) ( vec_set [f] v 2 c ) ( vec_set [f] v 3 d )
    ^ v
}

// ── algebra ───────────────────────────────────────────────────────────

@ test_algebra → v {
    : ( Vec f ) y ( vec_of4 1.0 3.0 6.0 10.0 )
    : ( Vec f ) d1 ( arima_difference y 1 0 0 )
    ( check & == ( vec_len [f] d1 ) 3 & ( near ( _ar_at d1 0 ) 2.0 0.0 ) ( near ( _ar_at d1 2 ) 4.0 0.0 ) `algebra: first differences` )
    : ( Vec f ) d2 ( arima_difference y 2 0 0 )
    ( check & == ( vec_len [f] d2 ) 2 ( near ( _ar_at d2 1 ) 1.0 0.0 ) `algebra: second differences` )
    : ( Vec f ) ds ( arima_difference y 0 1 2 )
    ( check & == ( vec_len [f] ds ) 2 & ( near ( _ar_at ds 0 ) 5.0 0.0 ) ( near ( _ar_at ds 1 ) 7.0 0.0 ) `algebra: a seasonal difference at lag 2` )
    ( vec_free [f] y ) ( vec_free [f] d1 ) ( vec_free [f] d2 ) ( vec_free [f] ds )

    // (1 − B)(1 − B⁴) = 1 − B − B⁴ + B⁵ → δ = (1, 0, 0, 1, −1)
    : ( Vec f ) delta ( _ar_delta 1 1 4 )
    ( check & == ( vec_len [f] delta ) 5 & & ( near ( _ar_at delta 0 ) 1.0 0.0 ) ( near ( _ar_at delta 3 ) 1.0 0.0 ) ( near ( _ar_at delta 4 ) -1.0 0.0 ) `algebra: differencing polynomial` )
    ( vec_free [f] delta )

    // (1 − 0.5B)(1 − 0.6B¹²) → φ' = 0.5 at 1, 0.6 at 12, −0.3 at 13
    : ( Vec f ) phi ( vec_zeroed [f] 1 ) ( vec_set [f] phi 0 0.5 )
    : ( Vec f ) sphi ( vec_zeroed [f] 1 ) ( vec_set [f] sphi 0 0.6 )
    : ( Vec f ) full ( _ar_expand_ar phi sphi 12 )
    ( check & == ( vec_len [f] full ) 13 & & ( near ( _ar_at full 0 ) 0.5 0.0 ) ( near ( _ar_at full 11 ) 0.6 0.0 ) ( near ( _ar_at full 12 ) -0.3 0.000000000001 ) `algebra: seasonal AR expansion` )
    ( vec_free [f] full )
    : ( Vec f ) th ( vec_zeroed [f] 1 ) ( vec_set [f] th 0 -0.4 )
    : ( Vec f ) sth ( vec_zeroed [f] 1 ) ( vec_set [f] sth 0 -0.5 )
    : ( Vec f ) fma ( _ar_expand_ma th sth 12 )
    ( check & == ( vec_len [f] fma ) 13 & ( near ( _ar_at fma 11 ) -0.5 0.0 ) ( near ( _ar_at fma 12 ) 0.2 0.000000000001 ) `algebra: seasonal MA expansion` )
    ( vec_free [f] fma ) ( vec_free [f] phi ) ( vec_free [f] sphi ) ( vec_free [f] th ) ( vec_free [f] sth )

    // transform round trip
    : ( Vec f ) c ( vec_zeroed [f] 2 ) ( vec_set [f] c 0 0.5 ) ( vec_set [f] c 1 -0.3 )
    : ( Vec f ) raw ( vec_zeroed [f] 2 )
    ( check ( _ar_invpartrans c raw 0 ) `algebra: a stationary AR(2) has a preimage` )
    : ( Vec f ) back ( _ar_partrans raw 0 2 )
    ( check & ( near ( _ar_at back 0 ) 0.5 0.000000001 ) ( near ( _ar_at back 1 ) -0.3 0.000000001 ) `algebra: transform round trip` )
    ( vec_set [f] c 0 1.5 ) ( vec_set [f] c 1 0.0 )
    ( check ! ( _ar_invpartrans c raw 0 ) `algebra: a non-stationary polynomial has none` )
    ( vec_free [f] c ) ( vec_free [f] raw ) ( vec_free [f] back )

    // the closed-form stationary covariance equals the doubling recursion's
    : ( Vec f ) ar2 ( vec_zeroed [f] 13 ) ( vec_set [f] ar2 0 0.5 ) ( vec_set [f] ar2 11 0.6 ) ( vec_set [f] ar2 12 -0.3 )
    : ( Vec f ) ma2 ( vec_zeroed [f] 2 ) ( vec_set [f] ma2 0 0.4 ) ( vec_set [f] ma2 1 -0.2 )
    : ( Vec f ) nod ( vec_new [f] )
    : ArimaSS s1 ( _ar_ss_new ar2 ma2 nod )
    : ArimaSS s2 ( _ar_ss_new ar2 ma2 nod )
    ( check ( _ar_init_cov s1 ) `algebra: closed-form covariance solves` )
    ( check ( _ar_init_cov_doubling s2 ) `algebra: doubling converges` )
    : ~ f worst 0.0
    : ~ i k 0
    ~ < k ( vec_len [f] . s1 pm ) {
        : f dd ( float_abs - ( _ar_at . s1 pm k ) ( _ar_at . s2 pm k ) )
        ? > dd worst { = worst dd } {}
        = k + k 1
    }
    : String wl ( string_from `algebra: the two stationary covariances agree (worst ` )
    : String ws ( fmt worst ) ( string_push_str wl ( string_data ws ) ) ( string_free ws ) ( string_push_str wl `)` )
    ( check < worst 0.000000001 ( string_data wl ) )
    ( string_free wl )
    // the O(r²) first column equals the full covariance's
    : ( Vec f ) col ( vec_zeroed [f] . s1 r )
    ( check ( _ar_init_col . s1 r . s1 phi . s1 theta col ) `algebra: the first column solves` )
    : ~ f cworst 0.0
    = k 0
    ~ < k . s1 r {
        : f dd ( float_abs - ( _ar_at col k ) ( _ar_at . s1 pm * k . s1 rd ) )
        ? > dd cworst { = cworst dd } {}
        = k + k 1
    }
    ( check < cworst 0.000000001 `algebra: P e₀ from the column formula equals the covariance's first column` )
    // and the Chandrasekhar likelihood equals the covariance filter's
    : ( Vec f ) yy ( sim_ar1 300 0.5 7 )
    : ( Vec f ) delta0 ( vec_new [f] )
    : ArimaSS s3 ( _ar_ss_new ar2 ma2 delta0 )
    : b _c3 ( _ar_init_cov s3 )
    : ~ f ssq3 0.0
    : ~ f sl3 0.0
    : ~ i t 0
    ~ < t 300 {
        : ArimaStep st ( _ar_step s3 ( _ar_at yy t ) )
        = ssq3 + ssq3 / * . st innovation . st innovation . st variance
        = sl3 + sl3 ( float_log . st variance )
        = t + t 1
    }
    : ArimaLik lk3 ( _ar_lik_ml_from ssq3 sl3 300 )
    : ArimaLik lk4 ( _ar_filter_arma . s1 phi . s1 theta col yy 0.0 )
    : String cl ( string_from `algebra: the Chandrasekhar likelihood equals the covariance filter's (` )
    : String c1 ( fmt . lk3 loglik ) ( string_push_str cl ( string_data c1 ) ) ( string_free c1 )
    ( string_push_str cl ` vs ` )
    : String c2 ( fmt . lk4 loglik ) ( string_push_str cl ( string_data c2 ) ) ( string_free c2 )
    ( string_push_str cl `)` )
    ( check & . lk4 ok ( near . lk3 loglik . lk4 loglik * 0.000000001 ( float_abs . lk3 loglik ) ) ( string_data cl ) )
    ( string_free cl )
    ( _ar_ss_free s3 ) ( vec_free [f] delta0 ) ( vec_free [f] yy ) ( vec_free [f] col )
    ( _ar_ss_free s1 ) ( _ar_ss_free s2 )
    ( vec_free [f] ar2 ) ( vec_free [f] ma2 ) ( vec_free [f] nod )
}

// ── oracle ────────────────────────────────────────────────────────────

@ test_oracle → v {
    ?? ( read_file `tests/fixtures/statsmodels_cases.json` ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T cases → {
                    : ( Vec String ) names ( json_obj_keys cases )
                    : i nc ( vec_len [String] names )
                    : ~ i c 0
                    ~ < c nc {
                        ?? ( vec_get [String] names c ) {
                            T nm → { ?? ( json_obj_get cases ( string_data nm ) ) { T cs → { ( oracle_case ( string_data nm ) cs ) } F _ → {} } }
                            F _ → {}
                        }
                        = c + c 1
                    }
                    ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
                    ( json_free cases )
                }
                F _ → { ( check F `oracle: fixture parses` ) }
            }
            ( string_free txt )
        }
        F _ → { ( check F `oracle: fixture file present` ) }
    }
}

@ oracle_case s nm Json cs → v {
    : Json order ?? ( json_obj_get cs `order` ) { T o → o F _ → cs }
    : Json sorder ?? ( json_obj_get cs `seasonal_order` ) { T o → o F _ → cs }
    : ( Vec f ) y ?? ( json_obj_get cs `y` ) { T a → ( jvec a ) F _ → ( vec_new [f] ) }
    : b mean ?? ( json_obj_get cs `trend` ) { T tv → == ( nurl_str_eq ( json_str_data tv ) `c` ) 1 F _ → F }
    : ArimaSpec sp ( arima_spec_with_mean ( arima_spec_seasonal ( jarr_i order 0 ) ( jarr_i order 1 ) ( jarr_i order 2 ) ( jarr_i sorder 0 ) ( jarr_i sorder 1 ) ( jarr_i sorder 2 ) ( jarr_i sorder 3 ) ) mean )
    : i t0 ( now_ms )
    : *ArimaModel m ( arima_fit y sp )
    : i dt - ( now_ms ) t0
    : String label ( string_from `oracle ` )
    ( string_push_str label nm )
    : String l1 ( string_clone label ) ( string_push_str l1 `: converged` )
    ( check . m converged ( string_data l1 ) )
    ( string_free l1 )
    // coefficients, in statsmodels' naming
    : Json params ?? ( json_obj_get cs `params` ) { T p → p F _ → cs }
    : ~ b coef_ok T
    : ~ f worst 0.0
    : i season ( jarr_i sorder 3 )
    : ( Vec String ) keys ( json_obj_keys params )
    : i nk ( vec_len [String] keys )
    : ~ i k 0
    ~ < k nk {
        ?? ( vec_get [String] keys k ) {
            T key → {
                : s ks ( string_data key )
                : f want ( jf params ks )
                : ~ f got 0.0
                : ~ b known T
                ? ( string_starts_with key `ar.S.L` ) { = got ( _ar_at ( arima_sphi m ) - / ( ar_lag ks ) season 1 ) } {
                    ? ( string_starts_with key `ma.S.L` ) { = got ( _ar_at ( arima_stheta m ) - / ( ar_lag ks ) season 1 ) } {
                        ? ( string_starts_with key `ar.L` ) { = got ( _ar_at ( arima_phi m ) - ( ar_lag ks ) 1 ) } {
                            ? ( string_starts_with key `ma.L` ) { = got ( _ar_at ( arima_theta m ) - ( ar_lag ks ) 1 ) } {
                                ? == ( nurl_str_eq ks `const` ) 1 { = got ( arima_mu m ) } {
                                    ? == ( nurl_str_eq ks `sigma2` ) 1 { = got ( arima_sigma2 m ) } { = known F } } } } } }
                ? known {
                    : f tol ? == ( nurl_str_eq ks `sigma2` ) 1 * 0.001 ( float_abs want ) 0.002
                    : f err ( float_abs - got want )
                    ? > err worst { = worst err } {}
                    ? > err tol { = coef_ok F } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
    : String l2 ( string_clone label ) ( string_push_str l2 `: coefficients match statsmodels (worst ` )
    : String w ( fmt worst ) ( string_push_str l2 ( string_data w ) ) ( string_free w ) ( string_push_str l2 `)` )
    ( check coef_ok ( string_data l2 ) )
    ( string_free l2 )
    : f llf ( jf cs `llf` )
    : String l3 ( string_clone label ) ( string_push_str l3 `: log-likelihood matches` )
    ( check ( near ( arima_loglik m ) llf 0.01 ) ( string_data l3 ) )
    ( string_free l3 )
    // forecasts
    : Json fj ?? ( json_obj_get cs `forecast` ) { T a → a F _ → cs }
    : Json sj ?? ( json_obj_get cs `forecast_se` ) { T a → a F _ → cs }
    : i h ( json_arr_len fj )
    : ArimaForecast fc ( arima_forecast m h )
    : ~ b fc_ok T
    = k 0
    ~ < k h {
        : f scale + 1.0 ( float_abs ( jarr_f fj k ) )
        ? ( near ( _ar_at . fc mean k ) ( jarr_f fj k ) * 0.001 scale ) {} { = fc_ok F }
        ? ( near ( _ar_at . fc se k ) ( jarr_f sj k ) * 0.002 + 1.0 ( jarr_f sj k ) ) {} { = fc_ok F }
        = k + k 1
    }
    : String l4 ( string_clone label ) ( string_push_str l4 `: forecast means and standard errors match` )
    ( check fc_ok ( string_data l4 ) )
    ( string_free l4 )
    : String l5 ( string_clone label ) ( string_push_str l5 `: fit took ` )
    : String dts ( string_new ) ( string_push_int dts dt ) ( string_push_str l5 ( string_data dts ) ) ( string_free dts ) ( string_push_str l5 ` ms` )
    ( check < dt 2000 ( string_data l5 ) )
    ( string_free l5 )
    ( arima_forecast_free fc )
    ( arima_free m )
    ( vec_free [f] y )
    ( string_free label )
}

// "ar.L2" → 2, "ma.S.L12" → 12
@ ar_lag s key → i {
    : i n ( nurl_str_len key )
    : ~ i k 0
    : ~ i at -1
    ~ < k n { ? == ( nurl_str_get key k ) 76 { = at k } {} = k + k 1 }
    ? < at 0 { ^ 1 } {}
    : ~ i v 0
    = k + at 1
    ~ < k n { = v + * v 10 - ( nurl_str_get key k ) 48 = k + k 1 }
    ^ v
}

// ── stream ────────────────────────────────────────────────────────────

@ sim_ar1 i n f phi i seed0 → ( Vec f ) {
    : ( Vec f ) y ( vec_zeroed [f] n )
    : ~ f prev 0.0
    : ~ i seed seed0
    : ~ i t 0
    ~ < t n {
        = seed % + * seed 1103515245 12345 2147483648
        : f u / + # f seed 1.0 2147483649.0
        = seed % + * seed 1103515245 12345 2147483648
        : f u2 / # f seed 2147483648.0
        : f e * ( float_sqrt * -2.0 ( float_log u ) ) ( float_cos * 6.283185307179586 u2 )
        = prev + * phi prev e
        ( vec_set [f] y t prev )
        = t + t 1
    }
    ^ y
}

@ test_stream → v {
    : ( Vec f ) y ( sim_ar1 400 0.6 99 )
    : ( Vec f ) head ( vec_zeroed [f] 390 )
    : ~ i t 0
    ~ < t 390 { ( vec_set [f] head t ( _ar_at y t ) ) = t + t 1 }
    : *ArimaModel m ( arima_fit head ( arima_spec 1 0 1 ) )
    ( check == ( arima_n m ) 390 `stream: n counts the fitted points` )
    : ~ b pred_ok T
    : ~ b var_ok T
    : ~ b z_ok T
    = t 390
    ~ < t 400 {
        : ArimaForecast fc ( arima_forecast m 1 )
        : ArimaUpdate u ( arima_update m ( _ar_at y t ) )
        ? == ( f64_to_bits . u predicted ) ( f64_to_bits ( _ar_at . fc mean 0 ) ) {} { = pred_ok F }
        ? ( near . u variance * ( _ar_at . fc se 0 ) ( _ar_at . fc se 0 ) 0.000000001 ) {} { = var_ok F }
        ? ( near . u z / . u innovation ( float_sqrt . u variance ) 0.000000001 ) {} { = z_ok F }
        ( arima_forecast_free fc )
        = t + t 1
    }
    ( check pred_ok `stream: an update measures against the forecast just made` )
    ( check var_ok `stream: with the forecast's variance` )
    ( check z_ok `stream: z = innovation / √variance` )
    ( check == ( arima_n m ) 400 `stream: n counts the updates` )
    // the streamed model's state equals the state of a filter run over all 400 at once
    : *ArimaModel m2 ( arima_fit head ( arima_spec 1 0 1 ) )
    : String js ( arima_to_json m2 )
    ( arima_free m2 )
    ?? ( arima_from_json ( string_data js ) ) {
        T m3 → {
            = t 390
            ~ < t 400 { : ArimaUpdate _u ( arima_update m3 ( _ar_at y t ) ) = t + t 1 }
            : ArimaForecast fa ( arima_forecast m 5 )
            : ArimaForecast fb ( arima_forecast m3 5 )
            : ~ b same T
            : ~ i k 0
            ~ < k 5 {
                ? == ( f64_to_bits ( _ar_at . fa mean k ) ) ( f64_to_bits ( _ar_at . fb mean k ) ) {} { = same F }
                ? == ( f64_to_bits ( _ar_at . fa se k ) ) ( f64_to_bits ( _ar_at . fb se k ) ) {} { = same F }
                = k + k 1
            }
            ( check same `stream: a model reloaded from JSON streams on bit-for-bit` )
            ( arima_forecast_free fa ) ( arima_forecast_free fb )
            ( arima_free m3 )
        }
        F _ → { ( check F `stream: JSON reload` ) }
    }
    ( string_free js )
    // round trip of everything
    : String j1 ( arima_to_json m )
    ?? ( arima_from_json ( string_data j1 ) ) {
        T m4 → {
            : String j2 ( arima_to_json m4 )
            ( check ( string_eq j1 j2 ) `stream: JSON round trip is exact` )
            ( check == ( f64_to_bits ( arima_loglik m4 ) ) ( f64_to_bits ( arima_loglik m ) ) `stream: log-likelihood survives the trip` )
            ( string_free j2 )
            ( arima_free m4 )
        }
        F _ → { ( check F `stream: JSON round trip` ) }
    }
    ( string_free j1 )
    ?? ( arima_from_json `{"format":"other"}` ) { T mx → { ( check F `stream: a foreign document is refused` ) ( arima_free mx ) } F _ → { ( check T `stream: a foreign document is refused` ) } }
    // restart + replay: the state after the 400 points equals the streamed one
    : *ArimaModel m5 ( arima_clone m )
    ( arima_restart m5 )
    ( check == ( arima_n m5 ) 0 `stream: a restarted model has absorbed nothing` )
    ( check == ( arima_n m ) 400 `stream: cloning then restarting the clone leaves the original alone` )
    = t 0
    ~ < t 400 { : ArimaUpdate _u ( arima_update m5 ( _ar_at y t ) ) = t + t 1 }
    : String j5 ( arima_to_json m5 )
    : String j6 ( arima_to_json m )
    ( check ( string_eq j5 j6 ) `stream: restart + replay reproduces the streamed state bit for bit` )
    ( string_free j5 ) ( string_free j6 )
    ( arima_free m5 )
    // a missing observation: the clock ticks, the uncertainty grows, nothing is learned
    : *ArimaModel m6 ( arima_clone m )
    : ArimaForecast f2 ( arima_forecast m6 2 )
    : ArimaUpdate um ( arima_update m6 ( float_nan ) )
    ( check & ( float_is_nan . um innovation ) ( float_is_nan . um z ) `stream: a NaN observation answers with NaN innovation and z` )
    ( check == ( f64_to_bits . um predicted ) ( f64_to_bits ( _ar_at . f2 mean 0 ) ) `stream: and with the forecast the model had made` )
    : ArimaForecast f1 ( arima_forecast m6 1 )
    ( check == ( f64_to_bits ( _ar_at . f1 mean 0 ) ) ( f64_to_bits ( _ar_at . f2 mean 1 ) ) `stream: after the gap the next forecast is the two-step forecast from before it` )
    ( check == ( f64_to_bits ( _ar_at . f1 se 0 ) ) ( f64_to_bits ( _ar_at . f2 se 1 ) ) `stream: with the two-step forecast's standard error` )
    ( check == ( arima_n m6 ) 401 `stream: the gap counts as a step` )
    ( arima_forecast_free f1 ) ( arima_forecast_free f2 )
    ( arima_free m6 )
    // CSS alone lands near ML
    : *ArimaModel mc ( arima_fit_method head ( arima_spec 1 0 1 ) ARIMA_CSS )
    ( check ( near ( _ar_at ( arima_phi mc ) 0 ) ( _ar_at ( arima_phi m ) 0 ) 0.1 ) `stream: CSS lands near ML` )
    ( arima_free mc )
    ( arima_free m )
    ( vec_free [f] head ) ( vec_free [f] y )
}

// ── harmonic ──────────────────────────────────────────────────────────

// A day of 1 440 rows and a week of 7 × 1 440, both as sines, over AR(1)
// noise: a seasonal polynomial at lag 1 440 is not a state a filter can
// carry, the Fourier terms are a few numbers.
@ test_harmonic → v {
    : i n 12000
    : ( Vec f ) noise ( sim_ar1 n 0.5 31 )
    : ( Vec f ) y ( vec_zeroed [f] n )
    : ~ i t 0
    ~ < t n {
        : f day * 5.0 ( float_sin / * 6.283185307179586 # f t 1440.0 )
        : f week * 2.0 ( float_cos / * 6.283185307179586 # f t 10080.0 )
        ( vec_set [f] y t + + + 20.0 day week ( _ar_at noise t ) )
        = t + t 1
    }
    : ( Vec f ) head ( vec_zeroed [f] 11000 )
    = t 0
    ~ < t 11000 { ( vec_set [f] head t ( _ar_at y t ) ) = t + t 1 }
    : ( Vec i ) periods ( vec_new [i] )
    ( vec_push [i] periods 1440 )
    ( vec_push [i] periods 10080 )
    : i t0 ( now_ms )
    : *ArimaModel m ( arima_auto_harmonic head periods 3 0 )
    : i dt - ( now_ms ) t0
    : String tl ( string_from `harmonic: two periods of 1 440 and 10 080 rows fitted on 11 000 points in ` )
    ( string_push_int tl dt ) ( string_push_str tl ` ms` )
    ( check < dt 5000 ( string_data tl ) )
    ( string_free tl )
    ( check == ( arima_n m ) 11000 `harmonic: the fit absorbed every point` )
    ( check == . m xk 3 `harmonic: three harmonics per period` )
    // the day's first sine weight is the 5 the series was made with
    ( check ( near ( _ar_at . m xcoef 1 ) 5.0 0.15 ) `harmonic: the day's amplitude is recovered` )
    ( check ( near ( _ar_at . m xcoef 8 ) 2.0 0.15 ) `harmonic: the week's amplitude is recovered` )
    // forecasts follow the seasonal a day ahead, and the naive does not
    : ArimaForecast fc ( arima_forecast m 1000 )
    : ~ f e_model 0.0
    : ~ f e_naive 0.0
    : f last ( _ar_at head 10999 )
    : ~ i k 0
    ~ < k 1000 {
        = e_model + e_model ( float_abs - ( _ar_at y + 11000 k ) ( _ar_at . fc mean k ) )
        = e_naive + e_naive ( float_abs - ( _ar_at y + 11000 k ) last )
        = k + k 1
    }
    : String sl ( string_from `harmonic: a thousand steps ahead the model's error is a fraction of the naive's (` )
    : String s1 ( fmt / e_model 1000.0 ) ( string_push_str sl ( string_data s1 ) ) ( string_free s1 )
    ( string_push_str sl ` vs ` )
    : String s2 ( fmt / e_naive 1000.0 ) ( string_push_str sl ( string_data s2 ) ) ( string_free s2 )
    ( string_push_str sl `)` )
    ( check < e_model * 0.4 e_naive ( string_data sl ) )
    ( string_free sl )
    ( arima_forecast_free fc )
    // streaming keeps the phase: updates over the held-out rows are judged against the seasonal
    : ~ f worst_z 0.0
    = k 0
    ~ < k 1000 {
        : ArimaUpdate u ( arima_update m ( _ar_at y + 11000 k ) )
        : f az ( float_abs . u z )
        ? > az worst_z { = worst_z az } {}
        = k + k 1
    }
    ( check < worst_z 5.0 `harmonic: no held-out reading is a surprise past five sigma` )
    ( check == . m xt 12000 `harmonic: the regressors' clock counts the rows` )
    // the JSON carries the terms and the clock; a copy restarted at the fit's origin replays to the same state
    : String j1 ( arima_to_json m )
    ?? ( arima_from_json ( string_data j1 ) ) {
        T m2 → {
            : String j2 ( arima_to_json m2 )
            ( check ( string_eq j1 j2 ) `harmonic: JSON round trip is exact` )
            ( string_free j2 )
            ( arima_free m2 )
        }
        F _ → { ( check F `harmonic: JSON parses back` ) }
    }
    ( string_free j1 )
    : *ArimaModel m3 ( arima_clone m )
    ( arima_restart_at m3 0 )
    = k 0
    ~ < k n { : ArimaUpdate _u ( arima_update m3 ( _ar_at y k ) ) = k + k 1 }
    : ArimaForecast fa ( arima_forecast m 3 )
    : ArimaForecast fb ( arima_forecast m3 3 )
    ( check == ( f64_to_bits ( _ar_at . fa mean 2 ) ) ( f64_to_bits ( _ar_at . fb mean 2 ) ) `harmonic: a restart at the origin and a replay reach the streamed forecast bit for bit` )
    : f next1 ( _ar_at . fa mean 0 )
    ( arima_forecast_free fa ) ( arima_forecast_free fb )
    // a restart elsewhere keeps the phase through t0
    : *ArimaModel m4 ( arima_clone m )
    ( arima_restart_at m4 6000 )
    = k 6000
    ~ < k n { : ArimaUpdate _u ( arima_update m4 ( _ar_at y k ) ) = k + k 1 }
    : ArimaForecast fd ( arima_forecast m4 1 )
    ( check ( near ( _ar_at . fd mean 0 ) next1 0.05 ) `harmonic: a replay from the middle, phased by t0, forecasts the same next value` )
    ( arima_forecast_free fd )
    ( arima_free m3 ) ( arima_free m4 ) ( arima_free m )
    ( vec_free [i] periods ) ( vec_free [f] head ) ( vec_free [f] y ) ( vec_free [f] noise )
}

// ── select ────────────────────────────────────────────────────────────

@ test_select → v {
    : ( Vec f ) noise ( sim_ar1 400 0.0 5 )
    ( check < ( arima_kpss noise ) 0.463 `select: KPSS accepts white noise as level-stationary` )
    : ( Vec f ) walk ( vec_zeroed [f] 400 )
    : ~ f acc 0.0
    : ~ i t 0
    ~ < t 400 { = acc + acc ( _ar_at noise t ) ( vec_set [f] walk t acc ) = t + t 1 }
    ( check > ( arima_kpss walk ) 0.463 `select: KPSS rejects a random walk` )
    ( check == ( arima_ndiffs walk ) 1 `select: a walk needs one difference` )
    ( check == ( arima_ndiffs noise ) 0 `select: noise needs none` )
    ( vec_free [f] walk )
    ( vec_free [f] noise )

    : ( Vec f ) y ( sim_ar1 600 0.7 77 )
    : *ArimaModel truth ( arima_fit y ( arima_spec_with_mean ( arima_spec 1 0 0 ) T ) )
    : *ArimaModel best ( arima_auto y 0 )
    : ArimaSpec bs . best spec
    : String sl ( string_from `select: the search does at least as well as the true order (found ` )
    : String s1 ( fmt ( arima_aicc best ) ) ( string_push_str sl ( string_data s1 ) ) ( string_free s1 )
    ( string_push_str sl ` vs ` )
    : String s2 ( fmt ( arima_aicc truth ) ) ( string_push_str sl ( string_data s2 ) ) ( string_free s2 )
    ( string_push_str sl `; order ` ) ( string_push_int sl . bs p ) ( string_push_str sl `,` ) ( string_push_int sl . bs d ) ( string_push_str sl `,` ) ( string_push_int sl . bs q )
    ( string_push_str sl ? . bs mean ` mean)` ` no mean)` )
    ( check <= ( arima_aicc best ) + ( arima_aicc truth ) 0.01 ( string_data sl ) )
    ( string_free sl )
    ( check | > . bs p 0 > . bs q 0 `select: and finds a dynamic model` )
    ( check == . bs d 0 `select: no difference for a stationary AR(1)` )
    ( arima_free best ) ( arima_free truth ) ( vec_free [f] y )

    ?? ( read_file `tests/fixtures/statsmodels_cases.json` ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T cases → {
                    ?? ( json_obj_get cases `airline` ) {
                        T cs → {
                            : ( Vec f ) air ?? ( json_obj_get cs `y` ) { T a → ( jvec a ) F _ → ( vec_new [f] ) }
                            ( check == ( arima_ndiffs air ) 1 `select: log airline needs one difference` )
                            ( check == ( arima_nsdiffs air 12 1 ) 1 `select: and one seasonal difference` )
                            : *ArimaModel known ( arima_fit air ( arima_spec_seasonal 0 1 1 0 1 1 12 ) )
                            : i t0 ( now_ms )
                            : *ArimaModel found ( arima_auto air 12 )
                            : i dt - ( now_ms ) t0
                            ( check <= ( arima_aicc found ) + ( arima_aicc known ) 0.01 `select: airline search matches or beats (0,1,1)(0,1,1)` )
                            ( check < dt 20000 `select: airline search under 20 s` )
                            ( arima_free known ) ( arima_free found )
                            ( vec_free [f] air )
                        }
                        F _ → {}
                    }
                    ( json_free cases )
                }
                F _ → {}
            }
            ( string_free txt )
        }
        F _ → {}
    }
}

// ── many ──────────────────────────────────────────────────────────────

@ test_many → v {
    : ( Vec ( Vec f ) ) series ( vec_new [( Vec f )] )
    ( vec_push [( Vec f )] series ( sim_ar1 700 0.6 11 ) )
    ( vec_push [( Vec f )] series ( sim_ar1 500 -0.4 12 ) )
    ( vec_push [( Vec f )] series ( sim_ar1 900 0.8 13 ) )
    : ArimaSpec sp ( arima_spec 1 0 1 )
    : i t0 ( now_ms )
    : ( Vec * ArimaModel ) ms ( arima_fit_many series sp ARIMA_ML )
    : i dt - ( now_ms ) t0
    ( check == ( vec_len [* ArimaModel] ms ) 3 `many: three models back` )
    : ~ b same T
    : ~ i i 0
    ~ < i 3 {
        ?? ( vec_get [( Vec f )] series i ) {
            T y → {
                : *ArimaModel alone ( arima_fit y sp )
                ?? ( vec_get [* ArimaModel] ms i ) {
                    T mm → {
                        ? == ( f64_to_bits ( arima_loglik mm ) ) ( f64_to_bits ( arima_loglik alone ) ) {} { = same F }
                        ? == ( f64_to_bits ( _ar_at ( arima_phi mm ) 0 ) ) ( f64_to_bits ( _ar_at ( arima_phi alone ) 0 ) ) {} { = same F }
                        ? == ( f64_to_bits ( _ar_at ( arima_theta mm ) 0 ) ) ( f64_to_bits ( _ar_at ( arima_theta alone ) 0 ) ) {} { = same F }
                        ? == . mm evals . alone evals {} { = same F }
                        ? == ( f64_to_bits ( _ar_at . mm se 0 ) ) ( f64_to_bits ( _ar_at . alone se 0 ) ) {} { = same F }
                    }
                    F _ → { = same F }
                }
                ( arima_free alone )
            }
            F _ → {}
        }
        = i + i 1
    }
    ( check same `many: each model is bit-identical to its own fit` )
    ( check < dt 5000 `many: batch fit under 5 s` )
    ( arima_models_free ms )
    ( vec_free_with [( Vec f )] series \ ( Vec f ) v → v { ( vec_free [f] v ) } )
}

@ main → i {
    ( test_algebra )
    ( test_oracle )
    ( test_stream )
    ( test_many )
    ( test_harmonic )
    ( test_select )
    ( nurl_print `arima_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
