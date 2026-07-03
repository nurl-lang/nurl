// anomaly/model.nu — the per-point scoring core (milestone M2).
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
// M4/M5 instantiate per time window. Training and the bulk/batch scoring
// paths (GPU-accelerated when available) live in src/score.nu; this file is
// the small, dependency-light core they build on.

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

// ── Per-point scoring ─────────────────────────────────────────────────

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
