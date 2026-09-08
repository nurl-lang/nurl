// anomaly/forecast.nu — the forecast version: a seasonal ARIMA model per
// numeric feature (packages/arima), judging every point against what
// the feature's own recent past said it would be.
//
// The forests see a point as a whole and the guards see one reading at
// a time; neither sees ORDER beyond the timevector's short window. A
// feature that follows a rhythm — a temperature with its day, a load
// with its week — is normal at a value that is ordinary for the feature
// and wrong for the moment, and only a model of the sequence can say
// so. This version fits one SARIMA per numeric feature at every retrain
// (`arima_auto`, the stepwise order search, with the season the
// version's `window_size` gives), keeps each model's Kalman state
// current point by point, and reports, per point, how many standard
// errors of its forecast the reading landed from the forecast: the
// decision value is −max|z| over the features, so the margin reads as a
// sigma count like the range guard's, and the version names the feature.
//
// State. The models' filtered states are persisted (forecast.json) with
// the absolute sequence number of the next ring row to absorb; the
// service opens a model per request, so a request catches the states up
// from the ring's stored rows before judging — a few rows, parsed on
// the spot — and writes the file every ANOM_FC_SAVE_EVERY rows absorbed.
// A row's reading that is missing is a gap to the model (arima_update
// with NaN): the forecast moves on, nothing is learned. A scan over
// stored rows replays a copy of each model from ANOM_FC_BURN rows before
// the window (a restart, then the rows), so the verdicts of a scan are
// those of a stream that began there; the live stream's are the same to
// the precision the burn-in leaves.
//
// Training. The fit window is the version's own (`window_points` rows
// back, default ANOM_FC_WINDOW; `window_minutes` too), the features fit
// on the machine's threads, and a feature is watched when it is a
// declared numeric column with enough distinct, present readings to fit.
// Gaps inside the fit window are bridged linearly for the fit only.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/sysinfo.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `deps/arima/src/arima.nu`

// Rows absorbed between two writes of forecast.json.
: i ANOM_FC_SAVE_EVERY 32
// Rows a scan's replay runs before the window it reports on.
: i ANOM_FC_BURN 500
// Fewer present readings than this in the fit window: not watched.
: i ANOM_FC_MIN_FIT 30
// A season up to this many rows is a SARIMA polynomial (the week at an
// hour's step); a longer one — the day at a minute's — is Fourier terms
// with `ANOM_FC_HARMONICS` harmonics, which cost O(K) a row where the
// polynomial's state would be the season squared (see arima_fit_harmonic).
: i ANOM_FC_SARIMA_MAX 168
: i ANOM_FC_HARMONICS 4
// The second season: the week, seven of the first, as Fourier terms
// when the fit window covers at least this many weeks.
: i ANOM_FC_WEEK_MIN 3
// A forecast variance past this many σ² is the diffuse start still
// speaking: no verdict.
: f ANOM_FC_DIFFUSE 1000.0

// The trained version. `models` holds *ArimaModel per watched feature;
// `feats` their names and `cols` their index in the metadata's feature
// order, both frozen at training. `pos` is the ring row the states have
// absorbed up to (exclusive) in the open model; `seq` the same as an
// absolute sequence number, which is what the file carries.
: FcModel {
    b trained
    ( Vec String ) feats
    ( Vec i ) cols
    ( Vec i ) models
    i nw
    i pos
    i seq
    i season
    i trained_at
    i trained_on
    i unsaved  // rows absorbed since the file was last written
    i origin_seq  // the absolute sequence number of the fit window's first row: the regressors' t = 0
}

@ fc_new → *FcModel {
    : *FcModel fc # *FcModel ( nurl_malloc Z FcModel )
    = . fc trained F
    = . fc feats ( vec_new [String] )
    = . fc cols ( vec_new [i] )
    = . fc models ( vec_new [i] )
    = . fc nw 0
    = . fc pos 0
    = . fc seq 0
    = . fc season 0
    = . fc trained_at 0
    = . fc trained_on 0
    = . fc unsaved 0
    = . fc origin_seq 0
    ^ fc
}

@ _fc_model_at * FcModel fc i j → *ArimaModel {
    ^ # *ArimaModel ( _fc_geti . fc models j )
}

@ _fc_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } }
}

@ _fc_getf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F _ → { ^ 0.0 } }
}

// Drop the trained models; the handle stays, untrained.
@ fc_clear * FcModel fc → v {
    : i n ( vec_len [i] . fc models )
    : ~ i k 0
    ~ < k n { ( arima_free ( _fc_model_at fc k ) ) = k + k 1 }
    ( vec_free [i] . fc models )
    = . fc models ( vec_new [i] )
    ( vec_free_with [String] . fc feats \ String x → v { ( string_free x ) } )
    = . fc feats ( vec_new [String] )
    ( vec_free [i] . fc cols )
    = . fc cols ( vec_new [i] )
    = . fc nw 0
    = . fc trained F
    = . fc pos 0
    = . fc seq 0
    = . fc unsaved 0
}

@ fc_free * FcModel fc → v {
    ( fc_clear fc )
    ( vec_free [i] . fc models )
    ( vec_free [String] . fc feats )
    ( vec_free [i] . fc cols )
    ( nurl_free # s fc )
}

// The watched features' readings of an encoded point, NaN where the
// point has none (a projection fills a missing feature with 0, which for
// a forecast would be a reading).
@ fc_project EncPoint p ( Vec String ) feats → ( Vec f ) {
    : i nf ( vec_len [String] feats )
    : ( Vec f ) out ( vec_with_cap [f] nf )
    : ~ i k 0
    ~ < k nf {
        : ~ f x ( float_nan )
        ?? ( vec_get [String] feats k ) {
            T fname → {
                : i at ( enc_find p ( string_data fname ) )
                ? >= at 0 { ?? ( vec_get [f] . p vals at ) { T v2 → { = x v2 } F _ → {} } } {}
            }
            F _ → {}
        }
        ( vec_push [f] out x )
        = k + k 1
    }
    ^ out
}

// ── Training ──────────────────────────────────────────────────────────

// One feature's fit, as a job for a worker thread: the series (gaps
// bridged), the season, the Fourier periods, the slot for the model.
: FcJob {
    ( Vec f ) y
    i season  // the SARIMA season (0 = none)
    ( Vec i ) periods  // Fourier periods in rows (empty = none)
    i out  // *ArimaModel, 0 until fitted
}

// How a season is modelled for a fit window of `n` rows: a polynomial
// up to ANOM_FC_SARIMA_MAX, Fourier terms beyond; the week as Fourier
// terms too when the window holds ANOM_FC_WEEK_MIN of them.
: FcPlan {
    i sarima
    ( Vec i ) periods
}

@ fc_plan i season i n → FcPlan {
    : ( Vec i ) periods ( vec_new [i] )
    : ~ i sarima 0
    ? > season 0 {
        ? <= season ANOM_FC_SARIMA_MAX { = sarima season } { ( vec_push [i] periods season ) }
        : i week * 7 season
        ? & != week season >= n * ANOM_FC_WEEK_MIN week { ( vec_push [i] periods week ) } {}
    } {}
    ^ @ FcPlan { sarima periods }
}

: FcLane {
    ( Vec i ) jobs
    i lane
    i stride
}

@ __fc_job_run * FcJob j → v {
    : *ArimaModel m ? > ( vec_len [i] . j periods ) 0 ( arima_auto_harmonic . j y . j periods ANOM_FC_HARMONICS . j season ) ( arima_auto . j y . j season )
    = . j out # i m
}

@ __fc_lane_run * FcLane ln → v {
    : i n ( vec_len [i] . ln jobs )
    : ~ i k . ln lane
    ~ < k n {
        ( __fc_job_run # *FcJob ( _fc_geti . ln jobs k ) )
        = k + k . ln stride
    }
}

@ __fc_threads i njobs → i {
    : i n ( sys_cpu_count )
    : ~ i t ? > n 16 16 n
    ? > t njobs { = t njobs } {}
    ? < t 1 { = t 1 } {}
    ^ t
}

// Run the fits, one thread per lane of jobs (the arima package's own
// idiom: the runtime frees a spawned closure's env after the body; a
// spawn that fails runs the lane here and frees it by hand).
@ __fc_jobs_run ( Vec i ) jobs → v {
    : i n ( vec_len [i] jobs )
    : i nt ( __fc_threads n )
    ? > nt 1 {
        : ( Vec Thread ) ts ( vec_new [Thread] )
        : ( Vec i ) lanes ( vec_new [i] )
        : ~ i l 0
        ~ < l nt {
            : *FcLane ln # *FcLane ( nurl_malloc Z FcLane )
            = . ln jobs jobs
            = . ln lane l
            = . ln stride nt
            ( vec_push [i] lanes # i ln )
            : ( @ v ) body \ → v { ( __fc_lane_run ln ) }
            ?? ( thread_spawn_owned body ) {
                T t → { ( vec_push [Thread] ts t ) }
                F _ → { ( __fc_lane_run ln ) ( nurl_free # s # *u body 1 ) }
            }
            = l + l 1
        }
        = l 0
        ~ < l ( vec_len [Thread] ts ) { ?? ( vec_get [Thread] ts l ) { T t → { : i _j ( thread_join t ) } F _ → {} } = l + l 1 }
        = l 0
        ~ < l ( vec_len [i] lanes ) { ( nurl_free # s ( _fc_geti lanes l ) ) = l + l 1 }
        ( vec_free [Thread] ts )
        ( vec_free [i] lanes )
    } {
        : ~ i k 0
        ~ < k n { ( __fc_job_run # *FcJob ( _fc_geti jobs k ) ) = k + k 1 }
    }
}

// One feature's fit series over rows [from, n) of the hist: the present
// readings with the gaps between them bridged linearly (a gap at either
// end takes the nearest reading); how many readings were real, and
// whether they were not all one value.
: FcSeries {
    ( Vec f ) y
    i present
    b distinct
}

@ __fc_fit_series ( Vec f ) hist i nw i j i from i n → FcSeries {
    : i len - n from
    : ( Vec f ) y ( vec_zeroed [f] len )
    : *f py ( vec_data [f] y )
    : *f ph ( vec_data [f] hist )
    : ~ i cnt 0
    : ~ f first ( float_nan )
    : ~ b diff F
    : ~ i t 0
    ~ < t len {
        : f v . ph + * + from t nw j
        = . py t v
        ? ( float_is_nan v ) {} {
            = cnt + cnt 1
            ? ( float_is_nan first ) { = first v } { ? != v first { = diff T } {} }
        }
        = t + t 1
    }
    ? > cnt 0 {
        // bridge: walk the gaps
        : ~ i last -1
        = t 0
        ~ < t len {
            ? ( float_is_nan . py t ) {} {
                ? < last - t 1 {
                    // rows (last, t) are a gap
                    : ~ i g + last 1
                    ~ < g t {
                        ? < last 0 { = . py g . py t } {
                            : f a . py last
                            : f b . py t
                            : f frac / # f - g last # f - t last
                            = . py g + a * frac - b a
                        }
                        = g + g 1
                    }
                } {}
                = last t
            }
            = t + t 1
        }
        ? < last - len 1 {
            : ~ i g + last 1
            ~ < g len { = . py g . py last = g + g 1 }
        } {}
    } {}
    ^ @ FcSeries { y cnt diff }
}

// Train from the encoded ring: `encs` are every ring row in order,
// `from` the first row of the fit window, `season` the period in rows
// (0 = none), `now` the clock. Every declared numeric feature of the
// frozen order with ANOM_FC_MIN_FIT present, not-all-equal readings in
// the window gets a model; the models are then filtered over the whole
// ring so their states stand at its end. Returns the number of features
// watched.
@ fc_train * FcModel fc * Meta mm ( Vec EncPoint ) encs i from i season i now i base_seq → i {
    ( fc_clear fc )
    : i ne ( vec_len [EncPoint] encs )
    : ( Vec i ) mask ( meta_numeric_feat_mask mm )
    : i nfeat ( vec_len [String] . mm feats )
    : ( Vec String ) cand ( vec_new [String] )
    : ( Vec i ) ccols ( vec_new [i] )
    : ~ i j 0
    ~ < j nfeat {
        ? == ( _fc_geti mask j ) 1 {
            ?? ( vec_get [String] . mm feats j ) {
                T fn → { ( vec_push [String] cand ( string_from ( string_data fn ) ) ) ( vec_push [i] ccols j ) }
                F _ → {}
            }
        } {}
        = j + j 1
    }
    ( vec_free [i] mask )
    : i nc ( vec_len [String] cand )
    ? | == nc 0 <= - ne from ANOM_FC_MIN_FIT {
        ( vec_free_with [String] cand \ String x → v { ( string_free x ) } )
        ( vec_free [i] ccols )
        ^ 0
    } {}
    // the candidates' readings over the ring
    : ( Vec f ) hist ( vec_with_cap [f] * ne nc )
    : ~ i k 0
    ~ < k ne {
        ?? ( vec_get [EncPoint] encs k ) {
            T p → {
                : ( Vec f ) row ( fc_project p cand )
                ( vec_extend [f] hist row )
                ( vec_free [f] row )
            }
            F _ → {}
        }
        = k + k 1
    }
    // the fit jobs, one per feature worth fitting
    : ( Vec i ) jobs ( vec_new [i] )
    : ( Vec i ) jfeat ( vec_new [i] )
    = j 0
    ~ < j nc {
        : FcSeries fs ( __fc_fit_series hist nc j from ne )
        : ( Vec f ) y . fs y
        ? & >= . fs present ANOM_FC_MIN_FIT . fs distinct {
            : *FcJob jb # *FcJob ( nurl_malloc Z FcJob )
            = . jb y y
            : FcPlan plan ( fc_plan season - ne from )
            = . jb season . plan sarima
            = . jb periods . plan periods
            = . jb out 0
            ( vec_push [i] jobs # i jb )
            ( vec_push [i] jfeat j )
        } { ( vec_free [f] y ) }
        = j + j 1
    }
    ( __fc_jobs_run jobs )
    // keep the fits that converged; bring each state to the ring's end
    : i nj ( vec_len [i] jobs )
    = k 0
    ~ < k nj {
        : *FcJob jb # *FcJob ( _fc_geti jobs k )
        : i cj ( _fc_geti jfeat k )
        : *ArimaModel m # *ArimaModel . jb out
        : ~ b keep F
        ? != . jb out 0 { ? & . m converged > ( arima_sigma2 m ) 0.0 { = keep T } {} } {}
        ? keep {
            // the whole ring, from its first row: the regressors' clock
            // runs from the fit window's first row, so rows before it
            // count down from zero
            ( arima_restart_at m - 0 from )
            : *f ph ( vec_data [f] hist )
            : ~ i t 0
            ~ < t ne { : ArimaUpdate _u ( arima_update m . ph + * t nc cj ) = t + t 1 }
            ?? ( vec_get [String] cand cj ) {
                T fn → { ( vec_push [String] . fc feats ( string_from ( string_data fn ) ) ) }
                F _ → {}
            }
            ( vec_push [i] . fc cols ( _fc_geti ccols cj ) )
            ( vec_push [i] . fc models # i m )
        } { ? != . jb out 0 { ( arima_free m ) } {} }
        ( vec_free [f] . jb y )
        ( vec_free [i] . jb periods )
        ( nurl_free # s jb )
        = k + k 1
    }
    ( vec_free [i] jobs )
    ( vec_free [i] jfeat )
    ( vec_free [f] hist )
    ( vec_free_with [String] cand \ String x → v { ( string_free x ) } )
    ( vec_free [i] ccols )
    = . fc nw ( vec_len [i] . fc models )
    = . fc trained > . fc nw 0
    = . fc pos ne
    = . fc season season
    = . fc trained_at now
    = . fc trained_on - ne from
    = . fc unsaved 0
    = . fc origin_seq + base_seq from
    ^ . fc nw
}

// ── Streaming ─────────────────────────────────────────────────────────

// Absorb one row of readings (the watched features' values, NaN = gap).
@ fc_absorb * FcModel fc ( Vec f ) raw → v {
    : i nw . fc nw
    : ~ i j 0
    ~ < j nw {
        : ArimaUpdate _u ( arima_update ( _fc_model_at fc j ) ( _fc_getf raw j ) )
        = j + j 1
    }
    = . fc pos + . fc pos 1
    = . fc unsaved + . fc unsaved 1
}

// The ring evicted its oldest row.
@ fc_evict * FcModel fc → v {
    ? > . fc pos 0 { = . fc pos - . fc pos 1 } {}
}

// What the version saw of a point.
: FcOut {
    b ready  // at least one feature judged
    f worst  // the largest |z|
    i feat  // its index in the metadata's feature order; -1 = none
    ( Vec f ) z  // per watched feature; NaN where not judged
}

@ fc_out_free FcOut o → v {
    ( vec_free [f] . o z )
}

// Judge a row of readings against the models' current forecasts. With
// `absorb` the readings are then absorbed (the live ingest: the row is
// the ring's newest); without, the states stay (detect_only).
@ fc_judge * FcModel fc ( Vec f ) raw b absorb → FcOut {
    : i nw . fc nw
    : ( Vec f ) z ( vec_zeroed [f] nw )
    : *f pz ( vec_data [f] z )
    : ~ b ready F
    : ~ f worst 0.0
    : ~ i wf -1
    : ~ i j 0
    ~ < j nw {
        : *ArimaModel m ( _fc_model_at fc j )
        : f y ( _fc_getf raw j )
        : ~ f zj ( float_nan )
        ? absorb {
            : ArimaUpdate u ( arima_update m y )
            ? & ! ( float_is_nan y ) <= . u variance * ANOM_FC_DIFFUSE ( arima_sigma2 m ) { = zj . u z } {}
        } {
            ? ( float_is_nan y ) {} {
                : ArimaForecast f1 ( arima_forecast m 1 )
                : f se ( _fc_getf . f1 se 0 )
                : f vr * se se
                ? & > se 0.0 <= vr * ANOM_FC_DIFFUSE ( arima_sigma2 m ) { = zj / - y ( _fc_getf . f1 mean 0 ) se } {}
                ( arima_forecast_free f1 )
            }
        }
        = . pz j zj
        ? ( float_is_nan zj ) {} {
            = ready T
            : f az ( float_abs zj )
            ? | < wf 0 > az worst { = worst az = wf ( _fc_geti . fc cols j ) } {}
        }
        = j + j 1
    }
    ? absorb {
        = . fc pos + . fc pos 1
        = . fc unsaved + . fc unsaved 1
    } {}
    ^ @ FcOut { ready worst wf z }
}

// The next `h` forecasts of every watched feature, from the states as
// they stand: means and standard errors, feature-major.
: FcForecast {
    ( Vec String ) feats
    ( Vec ( Vec f ) ) mean
    ( Vec ( Vec f ) ) se
}

@ fc_forecast_free FcForecast o → v {
    ( vec_free_with [String] . o feats \ String x → v { ( string_free x ) } )
    ( vec_free_with [( Vec f )] . o mean \ ( Vec f ) v → v { ( vec_free [f] v ) } )
    ( vec_free_with [( Vec f )] . o se \ ( Vec f ) v → v { ( vec_free [f] v ) } )
}

@ fc_forecast * FcModel fc i h → FcForecast {
    : ( Vec String ) feats ( vec_new [String] )
    : ( Vec ( Vec f ) ) means ( vec_new [( Vec f )] )
    : ( Vec ( Vec f ) ) ses ( vec_new [( Vec f )] )
    : i nw . fc nw
    : ~ i j 0
    ~ < j nw {
        ?? ( vec_get [String] . fc feats j ) { T fn → { ( vec_push [String] feats ( string_from ( string_data fn ) ) ) } F _ → {} }
        : ArimaForecast f1 ( arima_forecast ( _fc_model_at fc j ) h )
        ( vec_push [( Vec f )] means . f1 mean )
        ( vec_push [( Vec f )] ses . f1 se )
        = j + j 1
    }
    ^ @ FcForecast { feats means ses }
}

// ── Replay (scans) ────────────────────────────────────────────────────

// A copy of every model, restarted: the stream begins again at the row
// whose absolute sequence number is `seq` (the regressors' phase
// follows from it).
@ fc_replay_begin * FcModel fc i seq → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i nw . fc nw
    : ~ i j 0
    ~ < j nw {
        : *ArimaModel c ( arima_clone ( _fc_model_at fc j ) )
        ( arima_restart_at c - seq . fc origin_seq )
        ( vec_push [i] out # i c )
        = j + j 1
    }
    ^ out
}

// One row through the copies; the z per feature (NaN = not judged)
// written into `z` when it is not empty.
@ fc_replay_step ( Vec i ) copies ( Vec f ) raw ( Vec f ) z → v {
    : i nw ( vec_len [i] copies )
    : *f pz ( vec_data [f] z )
    : b want == ( vec_len [f] z ) nw
    : ~ i j 0
    ~ < j nw {
        : *ArimaModel m # *ArimaModel ( _fc_geti copies j )
        : f y ( _fc_getf raw j )
        : ArimaUpdate u ( arima_update m y )
        ? want {
            : ~ f zj ( float_nan )
            ? & ! ( float_is_nan y ) <= . u variance * ANOM_FC_DIFFUSE ( arima_sigma2 m ) { = zj . u z } {}
            = . pz j zj
        } {}
        = j + j 1
    }
}

@ fc_replay_end ( Vec i ) copies → v {
    : i nw ( vec_len [i] copies )
    : ~ i j 0
    ~ < j nw { ( arima_free # *ArimaModel ( _fc_geti copies j ) ) = j + j 1 }
    ( vec_free [i] copies )
}

// The verdict a row of z-scores gives: the largest |z| and the feature
// (its index in the metadata's order; -1 when no feature was judged).
: FcPick {
    f worst
    i feat
}

@ fc_worst ( Vec f ) z ( Vec i ) cols → FcPick {
    : i nw ( vec_len [f] z )
    : ~ i wf -1
    : ~ f w 0.0
    : ~ i j 0
    ~ < j nw {
        : f zj ( _fc_getf z j )
        ? ( float_is_nan zj ) {} {
            : f az ( float_abs zj )
            ? | < wf 0 > az w { = w az = wf ( _fc_geti cols j ) } {}
        }
        = j + j 1
    }
    ^ @ FcPick { w wf }
}

// ── Persistence ───────────────────────────────────────────────────────

: s FC_FORMAT `anomaly-forecast-1`

@ fc_to_json_str * FcModel fc → String {
    : Json o ( json_obj_new )
    ( json_obj_set o `format` ( json_str_lit FC_FORMAT ) )
    ( json_obj_set o `trained` ( json_bool . fc trained ) )
    ( json_obj_set o `features` ( _an_jarr_of_strs . fc feats ) )
    : Json cols ( json_arr_new )
    : i nw . fc nw
    : ~ i j 0
    ~ < j nw { ( json_arr_push cols ( json_int ( _fc_geti . fc cols j ) ) ) = j + j 1 }
    ( json_obj_set o `columns` cols )
    ( json_obj_set o `season` ( json_int . fc season ) )
    ( json_obj_set o `trained_at` ( json_int . fc trained_at ) )
    ( json_obj_set o `trained_on` ( json_int . fc trained_on ) )
    ( json_obj_set o `seq` ( json_int . fc seq ) )
    ( json_obj_set o `origin_seq` ( json_int . fc origin_seq ) )
    : Json ms ( json_arr_new )
    = j 0
    ~ < j nw {
        : String mj ( arima_to_json ( _fc_model_at fc j ) )
        ?? ( json_parse ( string_data mj ) ) {
            T mo → { ( json_arr_push ms mo ) }
            F _ → {}
        }
        ( string_free mj )
        = j + j 1
    }
    ( json_obj_set o `models` ms )
    : String out ( json_stringify o )
    ( json_free o )
    ^ out
}

// None on a malformed document; a document whose models do not parse
// is untrained.
@ fc_from_json_str s src → ?*FcModel {
    ?? ( json_parse src ) {
        T o → {
            : ~ b ok ( json_is_obj o )
            ? ok {
                ?? ( json_obj_get o `format` ) {
                    T fv → { ? & ( json_is_str fv ) == ( nurl_str_eq ( json_str_data fv ) FC_FORMAT ) 1 {} { = ok F } }
                    F _ → { = ok F }
                }
            } {}
            ? ok {} { ( json_free o ) ^ @ ?*FcModel { F } }
            : *FcModel fc ( fc_new )
            = . fc season ( _an_jint o `season` 0 )
            = . fc trained_at ( _an_jint o `trained_at` 0 )
            = . fc trained_on ( _an_jint o `trained_on` 0 )
            = . fc seq ( _an_jint o `seq` 0 )
            = . fc origin_seq ( _an_jint o `origin_seq` 0 )
            : ~ b good T
            ?? ( json_obj_get o `features` ) {
                T fa → {
                    ? ( json_is_arr fa ) {
                        : i n ( json_arr_len fa )
                        : ~ i k 0
                        ~ < k n {
                            ?? ( json_arr_get fa k ) {
                                T e → { ? ( json_is_str e ) { ( vec_push [String] . fc feats ( string_from ( json_str_data e ) ) ) } { = good F } }
                                F _ → { = good F }
                            }
                            = k + k 1
                        }
                    } { = good F }
                }
                F _ → { = good F }
            }
            ?? ( json_obj_get o `columns` ) {
                T ca → {
                    ? ( json_is_arr ca ) {
                        : i n ( json_arr_len ca )
                        : ~ i k 0
                        ~ < k n {
                            ?? ( json_arr_get ca k ) {
                                T e → { ?? ( json_num_as_i e ) { T x → { ( vec_push [i] . fc cols x ) } F _ → { = good F } } }
                                F _ → { = good F }
                            }
                            = k + k 1
                        }
                    } { = good F }
                }
                F _ → { = good F }
            }
            ?? ( json_obj_get o `models` ) {
                T ma → {
                    ? ( json_is_arr ma ) {
                        : i n ( json_arr_len ma )
                        : ~ i k 0
                        ~ < k n {
                            ?? ( json_arr_get ma k ) {
                                T e → {
                                    : String es ( json_stringify e )
                                    ?? ( arima_from_json ( string_data es ) ) {
                                        T m → { ( vec_push [i] . fc models # i m ) }
                                        F _ → { = good F }
                                    }
                                    ( string_free es )
                                }
                                F _ → { = good F }
                            }
                            = k + k 1
                        }
                    } { = good F }
                }
                F _ → { = good F }
            }
            ( json_free o )
            : i nw ( vec_len [i] . fc models )
            ? & & good == ( vec_len [String] . fc feats ) nw == ( vec_len [i] . fc cols ) nw {} { = good F }
            ? & good > nw 0 {
                = . fc nw nw
                = . fc trained T
            } { ( fc_clear fc ) }
            ^ @ ?*FcModel { T fc }
        }
        F _ → { ^ @ ?*FcModel { F } }
    }
}

// What a reader sees of the version (the metadata response's block).
@ fc_info_json * FcModel fc → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `trained` ( json_bool . fc trained ) )
    ? . fc trained {
        ( json_obj_set o `features` ( _an_jarr_of_strs . fc feats ) )
        ( json_obj_set o `season` ( json_int . fc season ) )
        ( json_obj_set o `trained_at` ( json_int . fc trained_at ) )
        ( json_obj_set o `training_data_points` ( json_int . fc trained_on ) )
        ( json_obj_set o `points_absorbed` ( json_int . fc pos ) )
        : Json ms ( json_arr_new )
        : i nw . fc nw
        : ~ i j 0
        ~ < j nw {
            : *ArimaModel m ( _fc_model_at fc j )
            : Json c ( arima_coef m )
            ?? ( vec_get [String] . fc feats j ) { T fn → { ( json_obj_set c `feature` ( json_str_lit ( string_data fn ) ) ) } F _ → {} }
            ( json_arr_push ms c )
            = j + j 1
        }
        ( json_obj_set o `models` ms )
    } {}
    ^ o
}
