// anomaly/model.nu — the stateless scoring core (milestone M2).
//
// Wraps the `iforest` package's forest behind the M1 preprocessing layer
// and the scikit-learn decision conventions the reference service uses:
//
//   score_samples(x)      = -iforest_score(x)          (more negative = worse)
//   decision_function(x)  = score_samples(x) - offset_
//   offset_               = -0.5                        for contamination "auto"
//                         = percentile(score_samples of the training set,
//                                      100 * contamination)   otherwise
//   predict(x) == -1      ⇔ decision_function(x) < 0
//   version verdict       : decision_function(x) <= -decision_margin
//
// A `VerModel` is one trained forest + its offset and margin — the unit that
// M4/M5 instantiate per time window. `anomaly_batch` is the stateless batch
// path: fit a scaler over a numeric matrix, train, and score every row.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`
$ `src/prep.nu`
$ `deps/iforest/src/iforest.nu`

// The reference's fixed random_state: a given training set always yields a
// byte-identical forest, hence identical scores, on every platform.
: i ANOM_SEED 42

// One trained model version: forest + decision offset + margin.
: VerModel {
    String vname
    IForest forest
    f offset
    f margin
    i n_cols
    b trained
}

// Batch verdict over a matrix (see SPEC §6): anomaly ⇔ predict == -1,
// i.e. decision_function < 0 (margin 0), matching the reference batch path.
: BatchReport {
    i total_rows
    i anomaly_count
    f anomaly_percentage
    ( Vec i ) anomaly_indices
    b has_anomalies
    ( Vec f ) scores
}

// ── Percentile (numpy 'linear' interpolation, for contamination) ──────

// q in [0,1] over an ASCENDING-sorted vector.
@ __an_percentile ( Vec f ) sorted f q → f {
    : i n ( vec_len [f] sorted )
    ? <= n 0 { ^ 0.0 } {}
    : *f dp ( vec_data [f] sorted )
    ? <= n 1 { ^ . dp 0 } {}
    : ~ f pos * q # f - n 1
    ? < pos 0.0 { = pos 0.0 } {}
    : ~ i lo # i ( float_floor pos )
    ? >= lo - n 1 { ^ . dp - n 1 } {}
    : f frac - pos # f lo
    ^ + . dp lo * - . dp + lo 1 . dp lo frac
}

// ── Version training / scoring ────────────────────────────────────────

// Train one version's forest over an ALREADY-STANDARDISED row-major matrix.
// `cfg.max_samples` is clamped to the row count; contamination < 0 = "auto"
// (offset pinned at -0.5), else offset_ is the 100*c percentile of the
// training set's score_samples — so `predict == -1` flags ~c of training.
@ anom_train_version ( Vec f ) scaled i n_rows i n_cols VerCfg cfg → VerModel {
    : ~ i samp . cfg max_samples
    ? > samp n_rows { = samp n_rows } {}
    : IForest fo ( iforest_train scaled n_rows n_cols . cfg n_estimators samp ANOM_SEED )
    : ~ f off -0.5
    ? >= . cfg contamination 0.0 {
        : ( Vec f ) ss ( vec_with_cap [f] n_rows )
        : ~ i r 0
        ~ < r n_rows {
            ( vec_push [f] ss - 0.0 ( iforest_score_row fo scaled r ) )
            = r + r 1
        }
        ( sort_by [f] ss \ f a f b → i {
            ? < a b { ^ -1 } {}
            ? > a b { ^ 1 } {}
            ^ 0
        } )
        = off ( __an_percentile ss . cfg contamination )
        ( vec_free [f] ss )
    } {}
    ^ @ VerModel {
        ( string_from ( string_data . cfg vname ) )
        fo
        off
        . cfg decision_margin
        n_cols
        T
    }
}

// decision_function of an already-standardised point.
@ anom_decision VerModel vm ( Vec f ) scaled_point → f {
    ^ - - 0.0 ( iforest_score . vm forest scaled_point ) . vm offset
}

// decision_function of row `r` of an already-standardised matrix.
@ anom_decision_row VerModel vm ( Vec f ) scaled i r → f {
    ^ - - 0.0 ( iforest_score_row . vm forest scaled r ) . vm offset
}

// The per-version verdict convention: below (or at) the margin ⇒ anomaly.
@ anom_is_anomaly VerModel vm f df → b {
    ^ <= df - 0.0 . vm margin
}

@ anom_vermodel_free VerModel vm → v {
    ( string_free . vm vname )
    ( iforest_free . vm forest )
}

// ── Batch (stateless) scoring ─────────────────────────────────────────

// Fit a scaler over the raw matrix, train one version on the standardised
// copy, then score every row. Anomaly ⇔ decision_function <= -cfg.margin
// (margin 0 reproduces the reference's predict == -1 batch rule).
@ anomaly_batch ( Vec f ) data i n_rows i n_cols VerCfg cfg → BatchReport {
    : Scaler sc ( scaler_fit data n_rows n_cols )
    : ( Vec f ) scaled ( vec_clone [f] data )
    ( scaler_apply_matrix sc scaled n_rows n_cols )
    : VerModel vm ( anom_train_version scaled n_rows n_cols cfg )

    : ( Vec f ) scores ( vec_with_cap [f] n_rows )
    : ( Vec i ) hits ( vec_new [i] )
    : ~ i r 0
    ~ < r n_rows {
        : f df ( anom_decision_row vm scaled r )
        ( vec_push [f] scores df )
        ? ( anom_is_anomaly vm df ) { ( vec_push [i] hits r ) } {}
        = r + r 1
    }
    ( anom_vermodel_free vm )
    ( vec_free [f] scaled )
    ( scaler_free sc )

    : i n_hits ( vec_len [i] hits )
    : ~ f pct 0.0
    ? > n_rows 0 { = pct / * # f n_hits 100.0 # f n_rows } {}
    ^ @ BatchReport { n_rows n_hits pct hits > n_hits 0 scores }
}

@ anomaly_report_free BatchReport rep → v {
    ( vec_free [i] . rep anomaly_indices )
    ( vec_free [f] . rep scores )
}
