// autoenc.nu — the autoencoder model version.
//
// The reference recipe (model_training.py train_autoencoder_model), in
// pure NURL over the mlp package:
//
//   1. a TEMPORARY Isolation Forest (contamination 10 %) is trained on the
//      standardised ring and every point it flags is dropped — the
//      autoencoder must learn only NORMAL behaviour, and unlabeled rings
//      contain the very anomalies we want it to spot later;
//   2. the surviving rows are MinMax-scaled and an MLP autoencoder
//      (default 64-32-64, ReLU, Adam, early stopping — sklearn
//      MLPRegressor semantics via mlp_fit with deterministic restarts)
//      learns to reconstruct them;
//   3. the detection threshold is the 95th percentile (nearest-rank) of
//      the training reconstruction errors.
//
// Detection scores a point as threshold − mse: negative ⇒ anomaly — the
// same decision_function orientation as the forest versions, so the
// service's "any version flags it" aggregation needs no special case.
//
// The autoencoder is NEVER part of the automatic retrain schedule: it is
// trained explicitly (CLI `anomaly train-ae`, HTTP POST
// /train/autoencoder/<model>) and stays enabled until the model is reset —
// mirroring the reference, where a heavier, deliberately-trained version
// coexists with the self-training forests.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/aegpu.nu`
$ `deps/mlp/src/mlp.nu`

// ── The trained artifact ──────────────────────────────────────────────

: AeModel {
    Mlp net
    MinMax mm
    ( Vec String ) feats  // feature order frozen at AE train time
    f threshold  // p95 of the training reconstruction errors
    i trained_on  // normal rows the net was fitted on
    i filtered  // rows the pre-filter dropped as anomalous
    f prefilter  // the pre-filter's contamination rate actually used
    i trained_at  // unix seconds (0 = unknown, pre-0.10 file)
    b trained
}

// A structurally-valid untrained placeholder (freeable, never scored).
@ ae_empty → AeModel {
    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz 1 ) ( vec_push [i] sz 1 )
    : Mlp net ( mlp_new sz 0 )
    ( vec_free [i] sz )
    : ( Vec f ) e ( vec_new [f] )
    : MinMax mm ( minmax_fit e 0 0 )
    ( vec_free [f] e )
    ^ @ AeModel { net mm ( vec_new [String] ) 0.0 0 0 0.0 0 F }
}

@ ae_free AeModel ae → v {
    ( mlp_free . ae net )
    ( minmax_free . ae mm )
    ( vec_free_with [String] . ae feats \ String s2 → v { ( string_free s2 ) } )
}

// ── Training ──────────────────────────────────────────────────────────

// Reconstruction MSE of one already-MinMax-scaled row (length d) held in
// `X` at row r.
@ __ae_row_mse Mlp net ( Vec f ) X i d i r → f {
    : ( Vec f ) x ( vec_new [f] )
    : ~ i k 0
    ~ < k d { ( vec_push [f] x ( _mlp_fget X + * r d k ) ) = k + k 1 }
    : ( Vec f ) y ( mlp_predict net x )
    : ~ f se 0.0
    = k 0
    ~ < k d {
        : f e - ( _mlp_fget y k ) ( _mlp_fget x k )
        = se + se * e e
        = k + k 1
    }
    ( vec_free [f] x ) ( vec_free [f] y )
    ^ / se # f d
}

// Train from the RAW (unscaled) projected matrix `raw` (n×d, row-major)
// with its feature order `feats` (borrowed; copied into the result).
// `hidden` lists the hidden layer widths (empty → 64-32-64);
// `contamination` is the pre-filter rate (<=0 → 0.10); `min_rows` gates
// both the input and the post-filter survivor count. On failure the
// returned AeModel has trained=F and `err` (owned) says why.
: AeTrainOut {
    AeModel ae
    String err
}

@ ae_train_matrix ( Vec f ) raw i n i d ( Vec String ) feats ( Vec i ) hidden f contamination i min_rows → AeTrainOut {
    ? < n min_rows {
        ^ @ AeTrainOut { ( ae_empty ) ( string_from `not enough data points to train the autoencoder` ) }
    } {}

    // 1. the anomaly pre-filter: a temporary forest at a FIXED
    // contamination (the reference found 'auto' unreliable here).
    : ~ f cont contamination
    ? <= cont 0.0 { = cont 0.10 } {}
    : ( Vec f ) scaled ( vec_clone [f] raw )
    : Scaler fsc ( scaler_fit scaled n d )
    ( scaler_apply_matrix fsc scaled n d )
    ( scaler_free fsc )
    : VerCfg fcfg @ VerCfg { ( string_from `aefilter` ) 0 0 0 0 200 256 cont 0.0 T }
    : VerModel fvm ( anom_train_version scaled n d fcfg )
    ( _an_vercfg_free fcfg )
    : ( Vec i ) keep ( vec_new [i] )
    : ~ i r 0
    ~ < r n {
        ? >= ( anom_decision_row fvm scaled r ) 0.0 { ( vec_push [i] keep r ) } {}
        = r + r 1
    }
    ( anom_vermodel_free fvm )
    ( vec_free [f] scaled )
    : i nk ( vec_len [i] keep )
    ? < nk min_rows {
        ( vec_free [i] keep )
        ^ @ AeTrainOut { ( ae_empty ) ( string_from `too few normal points remain after anomaly filtering` ) }
    } {}

    // 2. MinMax over the surviving raw rows, then the autoencoder.
    : ( Vec f ) Xn ( vec_with_cap [f] * nk d )
    : *f rawp ( vec_data [f] raw )
    : ~ i k 0
    ~ < k nk {
        : i row ( _mlp_iget keep k )
        : ~ i c 0
        ~ < c d {
            ( vec_push [f] Xn . rawp + * row d c )
            = c + c 1
        }
        = k + k 1
    }
    ( vec_free [i] keep )
    : MinMax mm ( minmax_fit Xn nk d )
    ( minmax_apply mm Xn nk )

    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz d )
    : i nh ( vec_len [i] hidden )
    ? > nh 0 {
        : ~ i h 0
        ~ < h nh { ( vec_push [i] sz ( _mlp_iget hidden h ) ) = h + h 1 }
    } {
        ( vec_push [i] sz 64 ) ( vec_push [i] sz 32 ) ( vec_push [i] sz 64 )
    }
    ( vec_push [i] sz d )
    : ~ MlpCfg cfg ( mlp_cfg_default )
    // GPU when a CUDA device is present, CPU otherwise — bit-identical either
    // way (aegpu.nu), so the backend can never change the trained model.
    : MlpFit fit ( aegpu_fit sz Xn nk d cfg 3 )
    ( vec_free [i] sz )

    // 3. threshold = p95 (nearest-rank) of the training errors.
    : ( Vec f ) errs ( vec_with_cap [f] nk )
    = k 0
    ~ < k nk {
        ( vec_push [f] errs ( __ae_row_mse . fit model Xn d k ) )
        = k + k 1
    }
    ( sort_by [f] errs \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : i p95i # i * 0.95 # f nk
    : f thr ( _mlp_fget errs p95i )
    ( vec_free [f] errs )
    ( vec_free [f] Xn )

    : ( Vec String ) fcopy ( vec_new [String] )
    : i nf ( vec_len [String] feats )
    = k 0
    ~ < k nf {
        ?? ( vec_get [String] feats k ) {
            T fs → { ( vec_push [String] fcopy ( string_from ( string_data fs ) ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ AeTrainOut {
        @ AeModel { . fit model mm fcopy thr nk - n nk cont 0 T }
        ( string_new )
    }
}

// The hidden layer widths the net was built with (sizes minus the input
// and output layers) — what a retrain needs to rebuild the same shape.
@ ae_hidden AeModel ae → ( Vec i ) {
    : Mlp anet . ae net
    : ( Vec i ) out ( vec_new [i] )
    : i nl ( vec_len [i] . anet sizes )
    : ~ i k 1
    ~ < k - nl 1 {
        ( vec_push [i] out ( _mlp_iget . anet sizes k ) )
        = k + k 1
    }
    ^ out
}

// ── Scoring ───────────────────────────────────────────────────────────

// Reconstruction MSE of one RAW projected point (the AE's own feature
// order and MinMax are applied here — independent of the forests'
// standardising scaler).
@ ae_mse AeModel ae ( Vec f ) raw_point → f {
    : MinMax amm . ae mm
    : i d . amm n_cols
    : ( Vec f ) x ( vec_clone [f] raw_point )
    ( minmax_apply amm x 1 )
    : Mlp anet . ae net
    : ( Vec f ) y ( mlp_predict anet x )
    : ~ f se 0.0
    : ~ i k 0
    ~ < k d {
        : f e - ( _mlp_fget y k ) ( _mlp_fget x k )
        = se + se * e e
        = k + k 1
    }
    ( vec_free [f] x ) ( vec_free [f] y )
    ^ / se # f d
}

// ── The decision margin, and why it is RELATIVE ───────────────────────
//
// Every forest version's `decision_margin` is an absolute offset on a
// decision_function whose scale is fixed by construction: sklearn's
// convention puts normal points near 0 and anomalies below it, so 0.06
// means the same thing for every model. The autoencoder's score is
// `threshold − mse`, and MSE has no such fixed scale — it is the mean
// squared error of MinMax-scaled features, which lands wherever the data
// puts it (1e-3 for one model, 2e-4 for another).
//
// The Python reference (model_training.py) nevertheless applies its shared
// absolute-margin rule to the autoencoder too: the branch computes
// `is_anomaly = mse > reconstruction_threshold`, and thirty lines later,
// at the same indentation as the branch itself, `is_anomaly = bool(score
// <= -decision_margin)` overwrites it unconditionally — with the
// autoencoder default margin of 0.05. Against a threshold of ~5e-4 that
// demands a reconstruction error a HUNDRED times the p95 of the training
// errors, which mutes the one version that models the joint distribution.
// The reference ships that version disabled by default, so the muting was
// never noticed.
//
// We keep the tunable knob and put it on the only scale that travels:
// `decision_margin` for the autoencoder is a FRACTION of the model's own
// reconstruction threshold. The stored default 0.05 now reads "flag at 5 %
// above the p95 training error" — the documented intent — instead of
// "flag at p95 + 0.05", and the same number means the same thing on every
// model. See SPEC §5.5.
: f ANOM_AE_MARGIN 0.05

// The effective ABSOLUTE margin for `rel`, so the verdict rule stays the
// one every version shares: `decision_function <= -margin ⇒ anomaly`.
// Substituting `ae_decision` gives `mse >= threshold * (1 + rel)`.
@ anom_ae_margin AeModel ae f rel → f {
    : ~ f r rel
    ? < r 0.0 { = r 0.0 } {}
    ^ * . ae threshold r
}

// Turn an effective absolute margin back into the relative one stored in
// the metadata (the inverse of anom_ae_margin; 0 when untrained).
@ anom_ae_rel_margin AeModel ae f abs_margin → f {
    ? > . ae threshold 0.0 {} { ^ 0.0 }
    ^ / abs_margin . ae threshold
}

// Per-feature squared reconstruction error of one RAW projected point, in
// the AE's own feature order (length = ae.mm.n_cols). This is the
// attribution the forests cannot give: the autoencoder's error is the
// amount by which each feature failed to be predictable from the others,
// so the largest entries name the RELATIONSHIP that broke, not merely the
// value that was extreme. `ae_mse` is the mean of this vector; it keeps
// its own loop because it is on the per-point scoring path and this one
// allocates.
@ ae_feature_errors AeModel ae ( Vec f ) raw_point → ( Vec f ) {
    : MinMax amm . ae mm
    : i d . amm n_cols
    : ( Vec f ) x ( vec_clone [f] raw_point )
    ( minmax_apply amm x 1 )
    : Mlp anet . ae net
    : ( Vec f ) y ( mlp_predict anet x )
    : ( Vec f ) out ( vec_with_cap [f] d )
    : ~ i k 0
    ~ < k d {
        : f e - ( _mlp_fget y k ) ( _mlp_fget x k )
        ( vec_push [f] out * e e )
        = k + k 1
    }
    ( vec_free [f] x ) ( vec_free [f] y )
    ^ out
}

// decision_function orientation: threshold − mse (negative ⇒ anomaly).
@ ae_decision AeModel ae ( Vec f ) raw_point → f {
    ^ - . ae threshold ( ae_mse ae raw_point )
}

// ── Persistence (one JSON file per model) ─────────────────────────────

@ ae_to_json_str AeModel ae → String {
    : Json o ( json_obj_new )
    : String nj ( mlp_save . ae net )
    : String mj ( minmax_save . ae mm )
    ( json_obj_set o `net` ( json_str_lit ( string_data nj ) ) )
    ( json_obj_set o `minmax` ( json_str_lit ( string_data mj ) ) )
    ( string_free nj ) ( string_free mj )
    ( json_obj_set o `threshold_bits` ( json_int ( f64_to_bits . ae threshold ) ) )
    ( json_obj_set o `trained_on` ( json_int . ae trained_on ) )
    ( json_obj_set o `filtered` ( json_int . ae filtered ) )
    ( json_obj_set o `prefilter` ( json_float . ae prefilter ) )
    ( json_obj_set o `trained_at` ( json_int . ae trained_at ) )
    : Json fa ( json_arr_new )
    : i nf ( vec_len [String] . ae feats )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [String] . ae feats k ) {
            T fs → { ( json_arr_push fa ( json_str_lit ( string_data fs ) ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `features` fa )
    : String out ( json_stringify o )
    ( json_free o )
    ^ out
}

@ ae_from_json_str s src → ?AeModel {
    : !Json JsonError r ( json_parse src )
    ?? r {
        F _ → { ^ @ ?AeModel { F } }
        T j → {
            : ~ b ok T
            : ~ s njs ``
            : ~ s mjs ``
            ?? ( json_obj_get j `net` ) { T e → { = njs ( json_str_data e ) } F _ → { = ok F } }
            ?? ( json_obj_get j `minmax` ) { T e → { = mjs ( json_str_data e ) } F _ → { = ok F } }
            ? ! ok { ( json_free j ) ^ @ ?AeModel { F } } {}
            : ?Mlp neto ( mlp_load njs )
            : ?MinMax mmo ( minmax_load mjs )
            : ~ b have_net F
            ?? neto { T _ → { = have_net T } F → {} }
            : ~ b have_mm F
            ?? mmo { T _ → { = have_mm T } F → {} }
            ? & have_net have_mm {} {
                ?? neto { T n2 → { ( mlp_free n2 ) } F → {} }
                ?? mmo { T m2 → { ( minmax_free m2 ) } F → {} }
                ( json_free j )
                ^ @ ?AeModel { F }
            }
            : Mlp net ?? neto { T n2 → n2 F → ( ae_dummy_net ) }
            : MinMax mm ?? mmo { T m2 → m2 F → ( ae_dummy_mm ) }
            : f thr ( bits_to_f64 ?? ( json_obj_get j `threshold_bits` ) { T e → ?? ( json_num_as_i e ) { T x → x F → 0 } F _ → 0 } )
            : i ton ?? ( json_obj_get j `trained_on` ) { T e → ( json_as_int e ) F _ → 0 }
            : i fil ?? ( json_obj_get j `filtered` ) { T e → ( json_as_int e ) F _ → 0 }
            : f pre ?? ( json_obj_get j `prefilter` ) { T e → ?? ( json_num_as_f e ) { T x → x F → 0.1 } F _ → 0.1 }
            : i tat ?? ( json_obj_get j `trained_at` ) { T e → ( json_as_int e ) F _ → 0 }
            : ( Vec String ) feats ( vec_new [String] )
            ?? ( json_obj_get j `features` ) {
                T fa → {
                    : i nf ( json_arr_len fa )
                    : ~ i k 0
                    ~ < k nf {
                        ?? ( json_arr_get fa k ) {
                            T e → { ( vec_push [String] feats ( string_from ( json_str_data e ) ) ) }
                            F → {}
                        }
                        = k + k 1
                    }
                }
                F _ → {}
            }
            ( json_free j )
            ^ @ ?AeModel { T @ AeModel { net mm feats thr ton fil pre tat T } }
        }
    }
}

// Fallback constructors for the load path's option unwrap (never used on
// the success path; both arms above guarantee have_net/have_mm).
@ ae_dummy_net → Mlp {
    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz 1 ) ( vec_push [i] sz 1 )
    : Mlp m ( mlp_new sz 0 )
    ( vec_free [i] sz )
    ^ m
}

@ ae_dummy_mm → MinMax {
    : ( Vec f ) e ( vec_new [f] )
    : MinMax m ( minmax_fit e 0 0 )
    ( vec_free [f] e )
    ^ m
}
