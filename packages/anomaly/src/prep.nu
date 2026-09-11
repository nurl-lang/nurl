// anomaly/prep.nu — feature preprocessing, standardisation, model metadata.
//
// This is milestone M1 of the `anomaly` package (see SPEC.md): the pure,
// I/O-free foundation everything else builds on.
//
//   - A model's *metadata* (`*Meta`) records what it has learned about the
//     shape of its input: which columns exist, their types (numeric /
//     categorical / timestamp), the categories seen so far, the authoritative
//     feature order, and the scaler parameters. It round-trips through JSON.
//   - `anomaly_preprocess` turns one raw JSON record into named numeric
//     features, updating the metadata as new columns / categories appear:
//     numeric passthrough, categorical → deterministic one-hot (categories
//     kept sorted), ISO-8601 timestamp → hour/day/month/weekday.
//   - `anomaly_project` pins a named feature set onto the model's frozen
//     feature order: missing features become NaN (absent; the scaler
//     standardises them to 0, the mean), unknown extras are dropped.
//     This is the feature-order stability rule that keeps one-hot columns
//     aligned across retrains.
//   - `Scaler` is the StandardScaler analogue: per-feature zero-mean /
//     unit-variance, with zero-variance features passing through unscaled.
//
// Column types are detected once, on first sight, then frozen in metadata:
// a value that parses as a number is numeric, else a value that parses as
// ISO-8601 is a timestamp, else it is categorical (mirrors the Python
// reference's float()/fromisoformat()/str fallback chain).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`

// ── Column kinds ──────────────────────────────────────────────────────

: i COL_NUMERIC 0
: i COL_CATEGORICAL 1
: i COL_TIMESTAMP 2

// Reference defaults (carried over verbatim from the Python service).
: i ANOM_MIN_POINTS 50
: i ANOM_MAX_POINTS 150000
: i ANOM_SCHED_BELOW 50
: i ANOM_SCHED_AT_MAX 1000

// ── Types ─────────────────────────────────────────────────────────────

// Config of one time-window model version. `window_min` filters training
// data to the last N minutes (0 = no time filter); `window_pts` caps it to
// the last N points (0 = no cap; used by `timevector`). `contamination`
// < 0 means "auto" (offset pinned at -0.5, the sklearn convention).
: VerCfg {
    String vname
    i window_min
    i window_pts
    i window_size  // sliding-window LENGTH in points (timevector; 0 = plain)
    i step_size  // sliding-window step during training (timevector)
    i n_estimators
    i max_samples
    f contamination
    f decision_margin
    b enabled
}

// Everything a model knows about its input shape. Heap-allocated (`*Meta`)
// so counters and handles can be updated through any reference. `cols` /
// `kinds` / `cats` are parallel: cats[i] is the sorted category list of
// column i (empty unless categorical). `feats` is the authoritative feature
// order once non-empty (snapshotted at each train by meta_refresh_feats);
// until then the model is "unfrozen" and the order is derived on demand.
: Meta {
    String name
    String created
    String alias  // human-readable nickname; empty = go by `name`
    ( Vec String ) cols
    ( Vec i ) kinds
    ( Vec ( Vec String ) ) cats
    ( Vec String ) feats
    ( Vec f ) sc_mean
    ( Vec f ) sc_std
    i sched_below
    i sched_at_max
    b sched_ae  // retrain the autoencoder whenever the forests retrain
    b count_clock  // points are numbered, not timed: see ANOM_TICK
    i n_seen
    i n_stored  // rows in the ring right now (≤ max_points); n_seen minus the evicted
    i last_trained  // n_seen at the last train (a point count, not a time)
    i trained_time  // wall clock of the last train, unix seconds; 0 = never
    i tuned_at  // wall clock of the first margin calibration, unix seconds; 0 = never (see model_autotune_at)
    i max_points
    i score_epoch
    i feat_enc  // the calendar-feature encoding the stored feature order uses
    i train_span  // seconds the last train's rows covered; 0 = unknown, every cycle kept
    i votes  // versions that must agree before the model calls a point an anomaly (1 = any one; see ANOM_VOTES_DEFAULT)
    ( Vec f ) flat_run  // flatline reference per feature: the run length its training runs recur at (see ANOM_FLAT_RUN_Q; -1 = not watched)
    ( Vec f ) flat_sd  // flatline reference per feature: the quiet-window std of training (see ANOM_FLAT_SD_Q)
    ( Vec f ) absurd_n  // readings left out of the last fit per feature (see anomaly_mask_absurd)
    ( Vec VerCfg ) versions
}

// ── Calendar features ─────────────────────────────────────────────────
//
// A timestamp column becomes calendar features so the forests can learn
// that 03:00 on a Sunday is not 15:00 on a Tuesday. Two things matter:
//
//   1. The clock is the one the stamp was WRITTEN in. "2026-08-01T00:00:00
//      +03:00" is midnight to whoever sent it; folding the offset away and
//      reading the UTC fields would call it 21:00 the day before, and a
//      model fed local-offset stamps would learn a day shifted by the
//      offset — with a step every DST change. A stamp without an offset
//      is taken as written.
//   2. Cyclic quantities are encoded as (sin, cos) pairs, so 23:00 sits
//      next to 00:00 and Sunday next to Monday. A linear hour lets a
//      forest cut the day at midnight, where nothing changes.
//
// ANOM_FEAT_ENC numbers this scheme. A model trained under an older one
// keeps encoding its points the old way (its frozen feature order names
// the old features) until its next retrain, which re-encodes the ring
// under the current scheme; metadata reports `retrain_required` until
// then. Encoding 1 is the original: UTC fields, linear hour / day-of-month
// / month / weekday.
: i ANOM_FEAT_ENC 2

// One preprocessed record: parallel (feature name, value) pairs in
// encounter order. Project onto a feature order with anomaly_project.
: EncPoint {
    ( Vec String ) names
    ( Vec f ) vals
}

// Per-feature standardisation: y = (x - mean) * inv_std. Zero-variance
// features store inv_std = 1 so they pass through centred but unscaled.
: Scaler {
    ( Vec f ) mean
    ( Vec f ) inv_std
}

// ── Version defaults ──────────────────────────────────────────────────
//
// The five default versions of the reference service. `seasonal`'s 90 days
// are expressed in minutes; `timevector` is the sliding-window version: it
// trains on flattened windows of `window_size` consecutive points (stepped
// by `step_size`) and scores the window ENDING at the incoming point.

@ __an_vc s vname i wmin i wpts i est i samp f margin → VerCfg {
    ^ @ VerCfg { ( string_from vname ) wmin wpts 0 0 est samp -1.0 margin T }
}

// timevector: a REAL sliding window — window_size consecutive points
// flatten to one window_size×n_features vector; the forest is trained on
// the window vectors (stepped by step_size) and scores the LAST window.
@ __an_vc_tv s vname i wsize i sstep i est i samp f margin → VerCfg {
    ^ @ VerCfg { ( string_from vname ) 0 0 wsize sstep est samp -1.0 margin T }
}

// The range guard (SPEC §5.4): not a forest but the univariate check the
// forests cannot make — a point whose one feature sits further from its
// training mean than `decision_margin` standard deviations is an anomaly
// on that alone, whatever the joint picture. Its decision value is
// -max|z| over the standardised features, so the margin reads as a sigma
// count; ANOM_GUARD_SIGMA is the default line. It has no window or trees:
// the shared scaler every retrain refits is all it needs.
: s ANOM_GUARD_NAME `range_guard`
: f ANOM_GUARD_SIGMA 4.0

@ _an_is_guard_name s vname → b {
    ^ == ( nurl_str_eq vname ANOM_GUARD_NAME ) 1
}

@ _an_vc_guard → VerCfg {
    ^ @ VerCfg { ( string_from ANOM_GUARD_NAME ) 0 0 0 0 0 0 -1.0 ANOM_GUARD_SIGMA T }
}

// The flatline guard (SPEC §5.4): the stuck sensor is the commonest single
// fault in a sensor stream and structurally invisible to a point scorer —
// every row of a flat stretch is, on its own, an ordinary reading; the
// signal is that nothing moves. This version measures two things per
// numeric column against what a retrain learned from the ring:
//
//   run      how long the run of identical values ending at this row is,
//            as a fraction of the column's OWN reference run — twice the
//            length its runs reach in training (`flat_run`, the
//            ANOM_FLAT_RUN_Q row-weighted quantile of run length), or
//            ANOM_FLAT_MIN_RUN rows, whichever is longer.
//   collapse how far the window's standard deviation has fallen below the
//            stream's own quiet windows (the ANOM_FLAT_SD_Q-th quantile
//            of the training window stds over `window_size` rows).
//
// Both are fractions; the decision value is minus the larger, over the
// columns, so the margin reads as a fraction: 0.9 flags a column that has
// repeated one value for 90 % of its own reference run, or a window ten
// times flatter than the stream's quietest periods.
//
// The reference is PER FEATURE and it decides: a temperature quantised to
// whole degrees, sampled every minute, legitimately repeats for half an
// hour, and its reference says so; a smooth flow meter's reference is the
// floor, so a genuine freeze of ANOM_FLAT_MIN_RUN rows trips it while the
// coarse column beside it in the same bundle stays quiet. Scoring the run
// against the model-wide window instead — what this guard did until
// 0.32.0 — made one number mean two things: a column whose reference run
// passed half the window could never reach the margin at all (the run is
// counted over the window, so its fraction was capped below 1), and every
// other column needed 0.9 × window identical rows before it counted.
//
// The reference run must describe what the column DOES, not the longest
// thing that ever happened to it — otherwise one freeze inside the
// training ring teaches the guard that freezing is normal, and the guard
// immunises itself against the very fault it exists to catch. Two rules
// together make it a description of habit:
//
//   * every maximal run of L identical values is entered into the sample
//     min(L, ANOM_FLAT_RUN_CAP × n) times, so a run counts for MORE the
//     longer it is — a rain gauge's long dry stretches are its normal —
//     but no SINGLE stretch, however long, can weigh more than a
//     hundredth of the ring;
//   * the reference is the ANOM_FLAT_RUN_Q quantile of that sample.
//
// The two together say: a column's reference is set by behaviour that
// RECURS. A sensor that legitimately sits still for half an hour does it
// again and again, and every one of those runs votes; a fault does it
// once, and one stretch cannot outvote the rest of the ring no matter how
// long it lasts. A column whose reference run is longer than the guard can
// look back (ANOM_FLAT_TAIL_MAX) is left unwatched rather than watched
// with a bar it can never reach.
// How many enabled versions must flag a point before the MODEL calls it an
// anomaly. One is the historical rule and the default: any version alone
// is enough, which is what a guard is for — a single reading at ten sigma
// is an anomaly whether or not the forests agree. Raising it asks for
// CONSENSUS instead, and a stream where every version has a say is a
// stream where one loud version stops being the whole answer.
//
// The number is the model's, not a filter on a query: it decides what is
// stored as an anomaly, what calibration counts, and what fine-tune aims
// at. `anomalies?votes=N` still narrows further on top of it — the model
// says what an anomaly IS, a reader may ask for a stricter agreement.
: i ANOM_VOTES_DEFAULT 1
: i ANOM_VOTES_MAX 32

: s ANOM_FLAT_NAME `flatline`
: i ANOM_FLAT_WINDOW 60
: f ANOM_FLAT_MARGIN 0.9
: f ANOM_FLAT_SD_Q 0.05
: f ANOM_FLAT_RUN_Q 0.9
: f ANOM_FLAT_RUN_CAP 0.01
: i ANOM_FLAT_MIN_RUN 20
: i ANOM_FLAT_TAIL_MAX 600

@ _an_is_flat_name s vname → b {
    ^ == ( nurl_str_eq vname ANOM_FLAT_NAME ) 1
}

@ _an_vc_flat → VerCfg {
    ^ @ VerCfg { ( string_from ANOM_FLAT_NAME ) 0 0 ANOM_FLAT_WINDOW 1 0 0 -1.0 ANOM_FLAT_MARGIN T }
}

// The forecast version (src/forecast.nu): a seasonal ARIMA per numeric
// feature, judging each reading against the forecast its own past made.
// Its decision value is −max|z| over the features — the reading's
// distance from the forecast in the forecast's standard errors — so the
// margin reads as a sigma count like the range guard's, and it names
// the feature. `window_points` / `window_minutes` are its fit window,
// `window_size` the seasonal period in rows (0 = none). Off until a
// reader turns it on: a model per feature is a cost a stream should
// choose.
: s ANOM_FC_NAME `forecast`
: f ANOM_FC_SIGMA 4.0
: i ANOM_FC_WINDOW 2000

@ _an_is_fc_name s vname → b {
    ^ == ( nurl_str_eq vname ANOM_FC_NAME ) 1
}

@ _an_vc_fc → VerCfg {
    ^ @ VerCfg { ( string_from ANOM_FC_NAME ) 0 ANOM_FC_WINDOW 0 0 0 0 -1.0 ANOM_FC_SIGMA F }
}

// The versions that are not forests: the autoencoder, the two guards
// and the forecast have a VerCfg (margin, enabled) but no forest blob to
// load, train or drop.
@ _an_forestless_name s vname → b {
    ? == ( nurl_str_eq vname `autoencoder` ) 1 { ^ T } {}
    ? ( _an_is_guard_name vname ) { ^ T } {}
    ? ( _an_is_fc_name vname ) { ^ T } {}
    ^ ( _an_is_flat_name vname )
}

@ meta_default_versions → ( Vec VerCfg ) {
    : ( Vec VerCfg ) vs ( vec_new [VerCfg] )
    ( vec_push [VerCfg] vs ( __an_vc `short_term` 180 0 200 256 0.16 ) )
    ( vec_push [VerCfg] vs ( __an_vc `daily` 1440 0 300 256 0.12 ) )
    ( vec_push [VerCfg] vs ( __an_vc `weekly` 10080 0 350 256 0.06 ) )
    ( vec_push [VerCfg] vs ( __an_vc `seasonal` 129600 0 400 256 0.08 ) )
    ( vec_push [VerCfg] vs ( __an_vc_tv `timevector` 100 1 200 256 0.10 ) )
    ( vec_push [VerCfg] vs ( _an_vc_guard ) )
    ( vec_push [VerCfg] vs ( _an_vc_flat ) )
    ( vec_push [VerCfg] vs ( _an_vc_fc ) )
    ^ vs
}

@ _an_vercfg_free sink VerCfg vc → v {
    ( string_free . vc vname )
}

// An owned copy of a model's version configuration — what a fork takes
// from its source.
@ meta_clone_versions * Meta m → ( Vec VerCfg ) {
    : i nv ( vec_len [VerCfg] . m versions )
    : ( Vec VerCfg ) out ( vec_with_cap [VerCfg] nv )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . m versions k ) {
            T vc → {
                : ~ VerCfg c vc
                = . c vname ( string_from ( string_data . vc vname ) )
                ( vec_push [VerCfg] out c )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// An alias is a label, so it is bounded by what a human will read rather
// than by anything structural. Long enough for a sentence, short enough that
// it cannot be used to bloat every metadata response.
: i ANOM_ALIAS_MAX 120

// ── The count clock ───────────────────────────────────────────────────
//
// Data without a clock — a file of readings nobody dated, a sequence of
// measurements where only the order matters — is a model whose time is
// its point count. Such a model runs on the COUNT clock: every point is
// stamped one tick after the previous one, ticks are ANOM_TICK seconds
// apart, and nothing in it ever reads the wall clock. One tick is one
// minute on purpose: every version window is written in minutes, so on
// the count clock "180 minutes" reads as "the last 180 points", and every
// window, scan and calibration falls out of the same code unchanged.
// The number a point shows is its ordinal, timestamp ÷ ANOM_TICK.
: i ANOM_TICK 60

// ── Meta lifecycle ────────────────────────────────────────────────────

@ meta_new s name s created → *Meta {
    : *Meta m # *Meta ( nurl_malloc Z Meta )
    = . m name ( string_from name )
    = . m created ( string_from created )
    = . m alias ( string_new )
    = . m cols ( vec_new [String] )
    = . m kinds ( vec_new [i] )
    = . m cats ( vec_new [( Vec String )] )
    = . m feats ( vec_new [String] )
    = . m sc_mean ( vec_new [f] )
    = . m sc_std ( vec_new [f] )
    = . m absurd_n ( vec_new [f] )
    = . m sched_below ANOM_SCHED_BELOW
    = . m sched_at_max ANOM_SCHED_AT_MAX
    = . m sched_ae F
    = . m count_clock F
    = . m n_seen 0
    = . m n_stored 0
    = . m last_trained 0
    = . m trained_time 0
    = . m tuned_at 0
    = . m max_points ANOM_MAX_POINTS
    = . m score_epoch 1
    = . m votes ANOM_VOTES_DEFAULT
    = . m feat_enc ANOM_FEAT_ENC
    = . m train_span 0
    = . m flat_run ( vec_new [f] )
    = . m flat_sd ( vec_new [f] )
    = . m versions ( meta_default_versions )
    ^ m
}

@ meta_free sink * Meta m → v {
    ( string_free . m name )
    ( string_free . m created )
    ( string_free . m alias )
    ( vec_free_with [String] . m cols \ String x → v { ( string_free x ) } )
    ( vec_free [i] . m kinds )
    ( vec_free_with [( Vec String )] . m cats \ ( Vec String ) cv → v {
        ( vec_free_with [String] cv \ String x → v { ( string_free x ) } )
    } )
    ( vec_free_with [String] . m feats \ String x → v { ( string_free x ) } )
    ( vec_free [f] . m sc_mean )
    ( vec_free [f] . m sc_std )
    ( vec_free [f] . m flat_run )
    ( vec_free [f] . m flat_sd )
    ( vec_free [f] . m absurd_n )
    ( vec_free_with [VerCfg] . m versions \ VerCfg vc → v { ( _an_vercfg_free vc ) } )
    ( nurl_free m )
}

// Index of column `name` in the metadata, or -1.
@ __an_col_find * Meta m s name → i {
    : i n ( vec_len [String] . m cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . m cols k ) {
            T c → { ? == ( nurl_str_eq ( string_data c ) name ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

// Column kind at index `ci` (COL_NUMERIC if somehow missing).
@ __an_kind_at * Meta m i ci → i {
    ?? ( vec_get [i] . m kinds ci ) { T k → { ^ k } F _ → { ^ COL_NUMERIC } }
}

// A model is "frozen" once it has an authoritative feature order (set at
// first train). Before that, feature order is derived from the metadata.
@ meta_is_frozen * Meta m → b {
    ^ > ( vec_len [String] . m feats ) 0
}

// Whether any column is a timestamp — the only kind whose encoding has
// changed between ANOM_FEAT_ENC schemes.
@ meta_has_timestamp * Meta m → b {
    : i n ( vec_len [i] . m kinds )
    : ~ i k 0
    ~ < k n {
        ? == ( __an_kind_at m k ) COL_TIMESTAMP { ^ T } {}
        = k + k 1
    }
    ^ F
}

// A trained model whose frozen feature order was built under an older
// calendar encoding: it still scores, the old way, but its next retrain
// changes what it learns.
@ meta_retrain_required * Meta m → b {
    ? >= . m feat_enc ANOM_FEAT_ENC { ^ F } {}
    ? ! ( meta_is_frozen m ) { ^ F } {}
    ^ ( meta_has_timestamp m )
}

// Declare a column's kind before its first value is seen — the one way
// to make a numeric-looking column categorical: a coordinate or a station
// code that should be an identity, not a magnitude. A column the model
// already knows keeps its kind (its encoding is settled); returns T only
// when the declaration took.
@ meta_declare_column * Meta m s name i kind → b {
    ? >= ( __an_col_find m name ) 0 { ^ F } {}
    ? | | == kind COL_NUMERIC == kind COL_CATEGORICAL == kind COL_TIMESTAMP {} { ^ F }
    ( vec_push [String] . m cols ( string_from name ) )
    ( vec_push [i] . m kinds kind )
    ( vec_push [( Vec String )] . m cats ( vec_new [String] ) )
    ^ T
}

// ── Value coercion ────────────────────────────────────────────────────

// Kind of a column, judged from its first-seen value: number (or bool, or
// numeric string) → numeric; ISO-8601 string → timestamp; else categorical.
@ __an_detect_kind Json jv → i {
    ? ( json_is_num jv ) { ^ COL_NUMERIC } {}
    ? ( json_is_bool jv ) { ^ COL_NUMERIC } {}
    ? ( json_is_str jv ) {
        : String tmp ( string_from ( json_str_data jv ) )
        : ?f fx ( string_to_float tmp )
        ( string_free tmp )
        ?? fx { T _ → { ^ COL_NUMERIC } F _ → {} }
        : !i ParseErr r ( time_parse_iso ( json_str_data jv ) )
        ?? r { T _ → { ^ COL_TIMESTAMP } F _ → {} }
        ^ COL_CATEGORICAL
    } {}
    ^ COL_CATEGORICAL
}

// Numeric view of a JSON value: number, bool (1/0), or numeric string.
@ __an_num_of Json jv → ?f {
    ? ( json_is_num jv ) { ^ ( json_num_as_f jv ) } {}
    ? ( json_is_bool jv ) {
        ? ( json_bool_val jv ) { ^ @ ?f { T 1.0 } } { ^ @ ?f { T 0.0 } }
    } {}
    ? ( json_is_str jv ) {
        : String tmp ( string_from ( json_str_data jv ) )
        : ?f fx ( string_to_float tmp )
        ( string_free tmp )
        ^ fx
    } {}
    ^ @ ?f { F 0.0 }
}

// String view of a JSON value (categorical stringification): a JSON string
// unquoted, anything else in its literal JSON spelling.
@ __an_str_of Json jv → String {
    ? ( json_is_str jv ) { ^ ( string_from ( json_str_data jv ) ) } {}
    ^ ( json_stringify jv )
}

// Insert `val` into the sorted category list if new. Returns T if added.
@ __an_cat_add ( Vec String ) cats s val → b {
    : i n ( vec_len [String] cats )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] cats k ) {
            T c → {
                : i cmp ( nurl_str_cmp ( string_data c ) val )
                ? == cmp 0 { ^ F } {}
                ? > cmp 0 {
                    ( vec_insert [String] cats k ( string_from val ) )
                    ^ T
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_push [String] cats ( string_from val ) )
    ^ T
}

// ── Feature naming ────────────────────────────────────────────────────

// "<col>_<suffix>" as an owned String.
@ __an_feat_name s col s suffix → String {
    : String fname ( string_from col )
    ( string_push_char fname 95 )
    ( string_push_str fname suffix )
    ^ fname
}

// Whether the rows the model last trained on covered a calendar cycle of
// `period` seconds at least twice. A cycle the data has not been round
// twice is not a cycle the forests can learn, it is a date: eight days of
// readings that straddle a month boundary would carry a month feature
// that splits them into "before" and "after", and every point on the
// rare side of the split scores as unusual for the day it was taken. So
// the feature order keeps only the cycles the training span has seen —
// hour needs two days, weekday two weeks, month two years — and a later
// retrain over a longer span brings the rest in. An unknown span (0: a
// count clock, or a model from before the field) keeps every cycle.
@ __an_cycle_seen * Meta m i period → b {
    ? <= . m train_span 0 { ^ T } {}
    ^ >= . m train_span * 2 period
}

// Append column `ci`'s feature names (in canonical order) to `out`.
@ __an_push_col_feats * Meta m i ci ( Vec String ) out → v {
    ?? ( vec_get [String] . m cols ci ) {
        T c → {
            : s cn ( string_data c )
            : i kind ( __an_kind_at m ci )
            ? == kind COL_NUMERIC {
                ( vec_push [String] out ( string_from cn ) )
            } {}
            ? == kind COL_CATEGORICAL {
                ?? ( vec_get [( Vec String )] . m cats ci ) {
                    T cv → {
                        : i nc ( vec_len [String] cv )
                        : ~ i k 0
                        ~ < k nc {
                            ?? ( vec_get [String] cv k ) {
                                T cat → { ( vec_push [String] out ( __an_feat_name cn ( string_data cat ) ) ) }
                                F _ → {}
                            }
                            = k + k 1
                        }
                    }
                    F _ → {}
                }
            } {}
            ? == kind COL_TIMESTAMP {
                ? < . m feat_enc 2 {
                    ( vec_push [String] out ( __an_feat_name cn `hour` ) )
                    ( vec_push [String] out ( __an_feat_name cn `day` ) )
                    ( vec_push [String] out ( __an_feat_name cn `month` ) )
                    ( vec_push [String] out ( __an_feat_name cn `weekday` ) )
                } {
                    ? ( __an_cycle_seen m 86400 ) {
                        ( vec_push [String] out ( __an_feat_name cn `hour_sin` ) )
                        ( vec_push [String] out ( __an_feat_name cn `hour_cos` ) )
                    } {}
                    ? ( __an_cycle_seen m 604800 ) {
                        ( vec_push [String] out ( __an_feat_name cn `weekday_sin` ) )
                        ( vec_push [String] out ( __an_feat_name cn `weekday_cos` ) )
                    } {}
                    ? ( __an_cycle_seen m 31557600 ) {
                        ( vec_push [String] out ( __an_feat_name cn `month_sin` ) )
                        ( vec_push [String] out ( __an_feat_name cn `month_cos` ) )
                    } {}
                }
            } {}
        }
        F _ → {}
    }
}

// The feature order implied by the current metadata: columns in first-seen
// order, each expanded canonically (categoricals over their sorted
// categories). Deterministic for a given metadata state. Owned result.
@ meta_derived_feats * Meta m → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] . m cols )
    : ~ i k 0
    ~ < k n {
        ( __an_push_col_feats m k out )
        = k + k 1
    }
    ^ out
}

// Which features are a numeric column as it came in — 1 per feature, 0
// for a one-hot level or a calendar feature. The flatline guard watches
// only these: a category that does not change and a month that does not
// change are not sensors.
@ meta_numeric_feat_mask * Meta m → ( Vec i ) {
    : i nf ( vec_len [String] . m feats )
    : ( Vec i ) out ( vec_with_cap [i] nf )
    : i nc ( vec_len [String] . m cols )
    : ~ i k 0
    ~ < k nf {
        : ~ i hit 0
        ?? ( vec_get [String] . m feats k ) {
            T fname → {
                : ~ i c 0
                ~ & == hit 0 < c nc {
                    ? == ( __an_kind_at m c ) COL_NUMERIC {
                        ?? ( vec_get [String] . m cols c ) {
                            T cn → { ? ( string_eq cn fname ) { = hit 1 } {} }
                            F _ → {}
                        }
                    } {}
                    = c + c 1
                }
            }
            F _ → {}
        }
        ( vec_push [i] out hit )
        = k + k 1
    }
    ^ out
}

// Snapshot the derived feature order as authoritative (called at train
// time). From now on scoring projects onto exactly this vector.
@ meta_refresh_feats * Meta m → v {
    ( vec_free_with [String] . m feats \ String x → v { ( string_free x ) } )
    = . m feats ( meta_derived_feats m )
}

// ── Preprocessing ─────────────────────────────────────────────────────

@ enc_free sink EncPoint p → v {
    ( vec_free_with [String] . p names \ String x → v { ( string_free x ) } )
    ( vec_free [f] . p vals )
}

// Index of feature `name` in the encoded point, or -1.
@ enc_find EncPoint p s name → i {
    : i n ( vec_len [String] . p names )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . p names k ) {
            T c → { ? == ( nurl_str_eq ( string_data c ) name ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

// "Parameter '<col>' must be <what>." as an owned String.
@ __an_err_param s col s what → String {
    : String msg ( string_from `Parameter '` )
    ( string_push_str msg col )
    ( string_push_str msg `' must be ` )
    ( string_push_str msg what )
    ( string_push_char msg 46 )
    ^ msg
}

// The zone offset an ISO-8601 stamp ends in, in seconds: "+03:00" → 10800,
// "-05:30" → -19800, "Z" or no designator → 0. The stamp has already
// passed time_parse_iso, so the tail is well-formed.
@ _an_iso_offset s stamp → i {
    : i n ( nurl_str_len stamp )
    : ~ i k 19
    // Skip fractional seconds.
    ? & < k n == ( nurl_str_at stamp n k ) 46 {
        = k + k 1
        ~ & < k n & >= ( nurl_str_at stamp n k ) 48 <= ( nurl_str_at stamp n k ) 57 { = k + k 1 }
    } {}
    ? >= k n { ^ 0 } {}
    : i sc ( nurl_str_at stamp n k )
    ? & != sc 43 != sc 45 { ^ 0 } {}
    : ~ i hh 0
    : ~ i mm 0
    : ~ i seen 0
    = k + k 1
    ~ < k n {
        : i c ( nurl_str_at stamp n k )
        ? & >= c 48 <= c 57 {
            ? < seen 2 { = hh + * hh 10 - c 48 } { = mm + * mm 10 - c 48 }
            = seen + seen 1
        } {}
        = k + k 1
    }
    : i off + * hh 3600 * mm 60
    ^ ? == sc 45 - 0 off off
}

// "<col>_<what>_sin" / "<col>_<what>_cos" for position `pos` of a cycle
// of `period` steps: the pair puts the last step next to the first.
@ __an_push_cyclic s cn s what i pos i period ( Vec String ) names ( Vec f ) vals → v {
    : f ang / * 2.0 * PI # f pos # f period
    : String sn ( __an_feat_name cn what )
    ( string_push_str sn `_sin` )
    ( vec_push [String] names sn )
    ( vec_push [f] vals ( float_sin ang ) )
    : String cs ( __an_feat_name cn what )
    ( string_push_str cs `_cos` )
    ( vec_push [String] names cs )
    ( vec_push [f] vals ( float_cos ang ) )
}

// Encode one column's value into (names, vals). When `learn` is set, new
// categories are recorded in the metadata; otherwise an unseen category
// just yields an all-zero one-hot. Returns an error message, or an empty
// String on success.
@ __an_encode_col * Meta m i ci s cn Json jv ( Vec String ) names ( Vec f ) vals b learn → String {
    : i kind ( __an_kind_at m ci )
    ? == kind COL_NUMERIC {
        : ?f fx ( __an_num_of jv )
        ?? fx {
            T x → {
                // JSON has no infinity, but "1e999" parses to one, and an
                // infinite reading has no place in a mean, a split or a
                // forecast: refused here, once, for every path that
                // encodes a point (ingest, import, score, retrain).
                ? ( _an_finite x ) {} { ^ ( __an_err_param cn `a finite number (a boolean reads as 1/0 and a numeric string as its number, but nothing here has a finite value)` ) }
                ( vec_push [String] names ( string_from cn ) )
                ( vec_push [f] vals x )
            }
            F _ → { ^ ( __an_err_param cn `a number, a numeric string ("12.5"), or true/false for a 0/1 channel` ) }
        }
    } {}
    ? == kind COL_CATEGORICAL {
        : String sval ( __an_str_of jv )
        ?? ( vec_get [( Vec String )] . m cats ci ) {
            T cv → {
                ? learn { ( __an_cat_add cv ( string_data sval ) ) } {}
                : i nc ( vec_len [String] cv )
                : ~ i k 0
                ~ < k nc {
                    ?? ( vec_get [String] cv k ) {
                        T cat → {
                            : ~ f hot 0.0
                            ? == ( nurl_str_eq ( string_data cat ) ( string_data sval ) ) 1 { = hot 1.0 } {}
                            ( vec_push [String] names ( __an_feat_name cn ( string_data cat ) ) )
                            ( vec_push [f] vals hot )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
            }
            F _ → {}
        }
        ( string_free sval )
    } {}
    ? == kind COL_TIMESTAMP {
        ? ( json_is_str jv ) {
            : s stamp ( json_str_data jv )
            : !i ParseErr r ( time_parse_iso stamp )
            ?? r {
                T secs → {
                    ? < . m feat_enc 2 {
                        // Encoding 1: the UTC fields, linear.
                        : Time t ( time_from_unix secs )
                        ( vec_push [String] names ( __an_feat_name cn `hour` ) )
                        ( vec_push [f] vals # f . t hour )
                        ( vec_push [String] names ( __an_feat_name cn `day` ) )
                        ( vec_push [f] vals # f . t day )
                        ( vec_push [String] names ( __an_feat_name cn `month` ) )
                        ( vec_push [f] vals # f . t month )
                        // Monday = 0 … Sunday = 6, like Python's weekday().
                        ( vec_push [String] names ( __an_feat_name cn `weekday` ) )
                        ( vec_push [f] vals # f % + . t wday 6 7 )
                    } {
                        // The clock the stamp was written in: UTC plus
                        // the offset it carries.
                        : Time t ( time_from_unix + secs ( _an_iso_offset stamp ) )
                        ( __an_push_cyclic cn `hour` . t hour 24 names vals )
                        ( __an_push_cyclic cn `weekday` % + . t wday 6 7 7 names vals )
                        ( __an_push_cyclic cn `month` - . t month 1 12 names vals )
                    }
                }
                F _ → { ^ ( __an_err_param cn `a valid ISO timestamp` ) }
            }
        } {
            ^ ( __an_err_param cn `a valid ISO timestamp` )
        }
    } {}
    ^ ( string_new )
}

@ __an_preprocess * Meta m Json raw b learn → !EncPoint String {
    : ( Vec String ) names ( vec_new [String] )
    : ( Vec f ) vals ( vec_new [f] )
    : ( Vec String ) keys ( json_obj_keys raw )
    : i nk ( vec_len [String] keys )
    : ~ String err ( string_new )
    : ~ i ki 0
    ~ & == ( string_len err ) 0 < ki nk {
        ?? ( vec_get [String] keys ki ) {
            T kstr → {
                : s cn ( string_data kstr )
                ? == ( nurl_str_eq cn `timestamp` ) 1 {} {
                    ?? ( json_obj_get raw cn ) {
                        T jv → {
                            : ~ i ci ( __an_col_find m cn )
                            ? & < ci 0 learn {
                                = ci ( vec_len [String] . m cols )
                                ( vec_push [String] . m cols ( string_from cn ) )
                                ( vec_push [i] . m kinds ( __an_detect_kind jv ) )
                                ( vec_push [( Vec String )] . m cats ( vec_new [String] ) )
                            } {}
                            : ~ String e2 ( string_new )
                            ? >= ci 0 {
                                ( string_free e2 )
                                = e2 ( __an_encode_col m ci cn jv names vals learn )
                            } {}
                            ? > ( string_len e2 ) 0 {
                                ( string_free err )
                                = err e2
                            } {
                                ( string_free e2 )
                            }
                        }
                        F _ → {}
                    }
                }
            }
            F _ → {}
        }
        = ki + ki 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ? > ( string_len err ) 0 {
        ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        ( vec_free [f] vals )
        ^ @ !EncPoint String { F err }
    } {}
    ( string_free err )
    ^ @ !EncPoint String { T @ EncPoint { names vals } }
}

// Encode one raw JSON record into named numeric features, updating the
// metadata as new columns / categories appear. The reserved key
// `timestamp` is the point's own clock and is never a feature. Numeric
// parse failure and bad timestamps are hard errors (owned message).
@ anomaly_preprocess * Meta m Json raw → !EncPoint String {
    ^ ( __an_preprocess m raw T )
}

// The model's columns a point does not carry — absent, or carried as
// null. A trained model expects every column it learned: a numeric one
// the point leaves out would otherwise encode as 0, which after
// standardisation is however many standard deviations 0 is from the
// column's mean, and the range guard would then blame a value nobody
// sent. Owned; empty when the point is complete.
@ anomaly_missing_cols * Meta m Json raw → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] . m cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . m cols k ) {
            T c → {
                : ~ b have F
                ?? ( json_obj_get raw ( string_data c ) ) {
                    T jv → { = have ! ( json_is_null jv ) }
                    F _ → {}
                }
                ? have {} { ( vec_push [String] out ( string_clone c ) ) }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Of the columns `anomaly_missing_cols` named, the ones the point DID
// carry — as null. A JSON null is not a reading, so it counts as absent;
// but "Missing columns: TW" over a point that says `"TW": null` reads as
// the service not seeing what the caller plainly sent, and the caller
// looks for a transport bug instead of for the null.
@ anomaly_null_cols * Meta m Json raw ( Vec String ) missing → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] missing )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] missing k ) {
            T c → {
                ?? ( json_obj_get raw ( string_data c ) ) {
                    T jv → { ? ( json_is_null jv ) { ( vec_push [String] out ( string_clone c ) ) } {} }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Read-only encode: never touches the metadata. Unknown columns are
// skipped, unseen categories one-hot to all-zeros — exactly what the
// frozen-feature projection would do with them anyway. For detect-only
// paths that must not mutate model state.
@ anomaly_preprocess_ro * Meta m Json raw → !EncPoint String {
    ^ ( __an_preprocess m raw F )
}

// Project an encoded point onto an authoritative feature order: features
// not in `feats` are dropped, and a feature the point does not carry is
// NaN — "absent", which the scaler turns into 0 (the training mean, the
// one value that says nothing) and which the forecast reads as a gap. It
// used to be 0 in RAW units, which after standardisation was however many
// standard deviations zero lies from the column's mean: a sensor that
// skipped a tick read as a reading of nothing, the range guard blamed it,
// and every forest saw a point nobody sent. Owned result.
@ anomaly_project EncPoint p ( Vec String ) feats → ( Vec f ) {
    : i nf ( vec_len [String] feats )
    : ( Vec f ) out ( vec_with_cap [f] nf )
    : ~ i k 0
    ~ < k nf {
        : ~ f x ( float_nan )
        ?? ( vec_get [String] feats k ) {
            T fname → {
                : i at ( enc_find p ( string_data fname ) )
                ? >= at 0 {
                    ?? ( vec_get [f] . p vals at ) { T v2 → { = x v2 } F _ → {} }
                } {}
            }
            F _ → {}
        }
        ( vec_push [f] out x )
        = k + k 1
    }
    ^ out
}

// ── Absurd readings ───────────────────────────────────────────────────
//
// A reading that cannot be a measurement of the same quantity — a sensor
// that answered 1e200, a unit conversion that multiplied by a googol —
// must not set anybody's boundaries. It is still stored, still scored and
// still flagged; it is flagged HARDER, because the range guard now sees it
// against a scale it did not move. It simply takes no part in FITTING.
//
// Why it has to be left out rather than merely survived. The fitted scale
// is a mean and a standard deviation, and one reading D robust sigmas out
// inflates the std to about D/√n. Every real reading then standardises to
// z ≈ √n/D, so a few hundred sigmas is where the feature stops being
// watched at all — and it stays unwatched until the reading leaves the
// ring, which at a minute's step and the 150 000-point default is fourteen
// weeks. The forests fare no better: a split is drawn uniformly between a
// column's min and max, so one absurd reading makes nearly every split of
// that column useless. The autoencoder's MinMax and the forecast's ARIMA
// go the same way.
//
// "Absurd" is measured against the feature's OWN robust statistics — the
// median and 1.4826·MAD, neither of which one reading can move — over a
// bounded, evenly spaced sample, so the cost does not grow with the ring.
// A cell past ANOM_ABSURD_SIGMAS of those becomes NaN in the TRAINING
// MATRIX only; the stored point keeps its value. Everything downstream
// already knows what NaN means there (0.29.0): the scaler leaves it out of
// the fit, the standardiser reads it as the mean, the autoencoder fills it
// with the midpoint of its column's range, and the forecast reads it as a
// gap in the series.
//
// The threshold is not an anomaly threshold and must not be read as one.
// A hundred sigmas is a spectacular anomaly and belongs in the fit; a
// thousand is past where the fit survives at all, for any ring size this
// service supports.
: f ANOM_ABSURD_SIGMAS 1000.0
: i ANOM_ABSURD_SAMPLE 2000
: i ANOM_ABSURD_MIN_SAMPLE 8

// The median of `xs`, which is SORTED in place.
@ __an_median_of ( Vec f ) xs → f {
    : i n ( vec_len [f] xs )
    ? > n 0 {} { ^ 0.0 }
    ( sort_by [f] xs \ f a f b → i { ? < a b { ^ -1 } {} ? > a b { ^ 1 } {} ^ 0 } )
    : ~ f m 0.0
    ?? ( vec_get [f] xs / n 2 ) { T v → { = m v } F _ → {} }
    ^ m
}

// Replace every absurd cell of a row-major training matrix with NaN, in
// place. One entry per column is pushed onto `counts`. Returns the total
// number of cells masked. A column with too few readings to say, or with
// no spread at all, is left exactly as it is: not being able to tell is
// not a licence to erase.
@ anomaly_mask_absurd ( Vec f ) data i n_rows i n_cols ( Vec i ) counts → i {
    ? & > n_rows 0 > n_cols 0 {} { ^ 0 }
    : ~ i total 0
    : ~ i c 0
    ~ < c n_cols {
        : ~ i stride / n_rows ANOM_ABSURD_SAMPLE
        ? < stride 1 { = stride 1 } {}
        : ( Vec f ) sample ( vec_new [f] )
        : *f dp ( vec_data [f] data )
        : ~ i r 0
        ~ < r n_rows {
            : f v . dp + * r n_cols c
            ? ( float_is_nan v ) {} { ( vec_push [f] sample v ) }
            = r + r stride
        }
        : i ns ( vec_len [f] sample )
        : ~ i masked 0
        ? >= ns ANOM_ABSURD_MIN_SAMPLE {
            : f med ( __an_median_of sample )
            : ( Vec f ) dev ( vec_with_cap [f] ns )
            : ~ i k 0
            ~ < k ns {
                ?? ( vec_get [f] sample k ) { T v → { ( vec_push [f] dev ( float_abs - v med ) ) } F _ → {} }
                = k + k 1
            }
            : ~ f sigma * 1.4826 ( __an_median_of dev )
            ? > sigma 0.0 {} {
                // More than half the sample is the same number, so the MAD
                // says nothing. The mean absolute deviation still does,
                // unless the column really is constant — and then there is
                // no scale to be absurd against.
                : ~ f tot 0.0
                = k 0
                ~ < k ns {
                    ?? ( vec_get [f] dev k ) { T d → { = tot + tot d } F _ → {} }
                    = k + k 1
                }
                = sigma / tot # f ns
            }
            ( vec_free [f] dev )
            ? & > sigma 0.0 ( _an_finite sigma ) {
                : f lim * ANOM_ABSURD_SIGMAS sigma
                : *f wp ( vec_data [f] data )
                = r 0
                ~ < r n_rows {
                    : i off + * r n_cols c
                    : f v . wp off
                    ? ( float_is_nan v ) {} {
                        ? > ( float_abs - v med ) lim {
                            = . wp off ( float_nan )
                            = masked + masked 1
                        } {}
                    }
                    = r + r 1
                }
            } {}
        } {}
        ( vec_free [f] sample )
        ( vec_push [i] counts masked )
        = total + total masked
        = c + c 1
    }
    ^ total
}

// ── Standardisation ───────────────────────────────────────────────────

// A finite float: neither NaN nor an infinity.
@ _an_finite f x → b {
    ? ( float_is_nan x ) { ^ F } {}
    ^ ! ( float_is_inf x )
}

// The largest finite double, for the one std that would overflow it.
: f ANOM_FLOAT_MAX 1.7976931348623157e308

// The standardised value furthest from the mean a point can carry: a
// million standard deviations. Past that a reading is not more anomalous,
// only more likely to be a broken sensor, and the cap keeps every z-score
// — and every JSON score computed from one — a finite number: a reading
// of 1e308 against a std of 1e-3 would otherwise standardise to infinity
// and serialise as null.
: f ANOM_Z_CAP 1000000.0

// Fit per-feature mean and 1/std over a row-major matrix (population
// variance, like sklearn's StandardScaler). Zero-variance features get
// inv_std = 1 so they centre but never divide by ~0. A NaN cell is an
// absent reading (anomaly_project) and is left out of its column's
// statistics; a column with no readings at all gets mean 0, inv_std 1.
//
// The arithmetic cannot overflow on finite input. The mean is a sum of
// v/m, not a sum divided by m; the deviations are taken as halves
// (v/2 − mu/2 is always finite) and squared only after being scaled by
// the largest of them, so a single reading of 1e200 gives a std of about
// 1e199 and not the infinity that once turned the persisted scaler into
// JSON nulls the model could no longer be opened from.
@ scaler_fit ( Vec f ) data i n_rows i n_cols → Scaler {
    : ( Vec f ) mean ( vec_with_cap [f] n_cols )
    : ( Vec f ) inv ( vec_with_cap [f] n_cols )
    : *f dp ( vec_data [f] data )
    : ~ i c 0
    ~ < c n_cols {
        // Pass 1: the readings present, and their mean.
        : ~ i m 0
        : ~ i r 0
        ~ < r n_rows {
            ? ( float_is_nan . dp + * r n_cols c ) {} { = m + m 1 }
            = r + r 1
        }
        : ~ f mu 0.0
        ? > m 0 {
            : f fm # f m
            = r 0
            ~ < r n_rows {
                : f v . dp + * r n_cols c
                ? ( float_is_nan v ) {} { = mu + mu / v fm }
                = r + r 1
            }
        } {}
        // Pass 2: the largest half-deviation, the scale of pass 3.
        : f muh / mu 2.0
        : ~ f scale 0.0
        = r 0
        ~ < r n_rows {
            : f v . dp + * r n_cols c
            ? ( float_is_nan v ) {} {
                : f dh ( float_abs - / v 2.0 muh )
                ? > dh scale { = scale dh } {}
            }
            = r + r 1
        }
        // Pass 3: the sum of squared deviations in units of that scale.
        : ~ f ss 0.0
        ? > scale 0.0 {
            = r 0
            ~ < r n_rows {
                : f v . dp + * r n_cols c
                ? ( float_is_nan v ) {} {
                    : f u / - / v 2.0 muh scale
                    = ss + ss * u u
                }
                = r + r 1
            }
        } {}
        ( vec_push [f] mean mu )
        ? & > scale 0.0 > ss 0.0 {
            : ~ f sd * * 2.0 scale ( float_sqrt / ss # f m )
            ? ( _an_finite sd ) {} { = sd ANOM_FLOAT_MAX }
            ( vec_push [f] inv / 1.0 sd )
        } {
            ( vec_push [f] inv 1.0 )
        }
        = c + c 1
    }
    ^ @ Scaler { mean inv }
}

// One cell standardised: (x − mean)·inv_std, an absent reading (NaN) as
// 0 — the mean, the value that says nothing — and the result capped at
// ±ANOM_Z_CAP so it is finite whatever the reading was.
@ __an_standardise f x f mu f inv → f {
    ? ( float_is_nan x ) { ^ 0.0 } {}
    : f z * - x mu inv
    ? > z ANOM_Z_CAP { ^ ANOM_Z_CAP } {}
    ? < z - 0.0 ANOM_Z_CAP { ^ - 0.0 ANOM_Z_CAP } {}
    ? ( float_is_nan z ) { ^ 0.0 } {}
    ^ z
}

// Standardise one point in place: x → (x - mean) * inv_std.
@ scaler_apply Scaler sc ( Vec f ) point → v {
    : i n ( vec_len [f] point )
    : i nm ( vec_len [f] . sc mean )
    : *f pp ( vec_data [f] point )
    : *f mp ( vec_data [f] . sc mean )
    : *f ip ( vec_data [f] . sc inv_std )
    : ~ i k 0
    ~ & < k n < k nm {
        = . pp k ( __an_standardise . pp k . mp k . ip k )
        = k + k 1
    }
}

// Standardise a whole row-major matrix in place.
@ scaler_apply_matrix Scaler sc ( Vec f ) data i n_rows i n_cols → v {
    : i nm ( vec_len [f] . sc mean )
    : *f dp ( vec_data [f] data )
    : *f mp ( vec_data [f] . sc mean )
    : *f ip ( vec_data [f] . sc inv_std )
    : ~ i r 0
    ~ < r n_rows {
        : ~ i c 0
        ~ & < c n_cols < c nm {
            : i off + * r n_cols c
            = . dp off ( __an_standardise . dp off . mp c . ip c )
            = c + c 1
        }
        = r + r 1
    }
}

@ scaler_free sink Scaler sc → v {
    ( vec_free [f] . sc mean )
    ( vec_free [f] . sc inv_std )
}

// Persist a fitted scaler into metadata (stored as mean + std; zero
// variance is stored as std = 1, matching its inv_std = 1).
@ meta_set_scaler * Meta m Scaler sc → v {
    ( vec_free [f] . m sc_mean )
    ( vec_free [f] . m sc_std )
    : i n ( vec_len [f] . sc mean )
    : ( Vec f ) ms ( vec_with_cap [f] n )
    : ( Vec f ) ss ( vec_with_cap [f] n )
    : *f mp ( vec_data [f] . sc mean )
    : *f ip ( vec_data [f] . sc inv_std )
    : ~ i k 0
    ~ < k n {
        // The file must parse back: a std that is not a positive finite
        // number is written as 1 (and the mean as 0), never as the JSON
        // null a NaN or an infinity would become.
        : ~ f mu . mp k
        ? ( _an_finite mu ) {} { = mu 0.0 }
        : ~ f sd / 1.0 . ip k
        ? & ( _an_finite sd ) > sd 0.0 {} { = sd 1.0 }
        ( vec_push [f] ms mu )
        ( vec_push [f] ss sd )
        = k + k 1
    }
    = . m sc_mean ms
    = . m sc_std ss
}

// Rebuild a usable Scaler from persisted metadata. Owned result.
@ meta_scaler * Meta m → Scaler {
    : i n ( vec_len [f] . m sc_mean )
    : ( Vec f ) mean ( vec_with_cap [f] n )
    : ( Vec f ) inv ( vec_with_cap [f] n )
    : *f mp ( vec_data [f] . m sc_mean )
    : *f sp ( vec_data [f] . m sc_std )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] mean . mp k )
        : ~ f sd . sp k
        ? & ( _an_finite sd ) > sd 0.0 {} { = sd 1.0 }
        ( vec_push [f] inv / 1.0 sd )
        = k + k 1
    }
    ^ @ Scaler { mean inv }
}

// ── Metadata ⇄ JSON ───────────────────────────────────────────────────

@ __an_kind_str i kind → s {
    ? == kind COL_CATEGORICAL { ^ `categorical` } {}
    ? == kind COL_TIMESTAMP { ^ `timestamp` } {}
    ^ `numeric`
}

@ __an_kind_parse s kstr → i {
    ? == ( nurl_str_eq kstr `categorical` ) 1 { ^ COL_CATEGORICAL } {}
    ? == ( nurl_str_eq kstr `timestamp` ) 1 { ^ COL_TIMESTAMP } {}
    ? == ( nurl_str_eq kstr `numeric` ) 1 { ^ COL_NUMERIC } {}
    ^ -1
}

// ( Vec f ) → JSON array of numbers.
@ _an_jarr_of_floats ( Vec f ) xs → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [f] xs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [f] xs k ) { T x → { ( json_arr_push a ( json_float x ) ) } F _ → {} }
        = k + k 1
    }
    ^ a
}

// ( Vec String ) → JSON array of strings.
@ _an_jarr_of_strs ( Vec String ) xs → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [String] xs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] xs k ) { T x → { ( json_arr_push a ( json_str_lit ( string_data x ) ) ) } F _ → {} }
        = k + k 1
    }
    ^ a
}

// JSON array of numbers → ( Vec f ); None if any element is not a number.
@ __an_floats_of_jarr Json a → ?( Vec f ) {
    ? ( json_is_arr a ) {} { ^ @ ?( Vec f ) { F } }
    : i n ( json_arr_len a )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get a k ) {
            T e → {
                : ?f fx ( json_num_as_f e )
                ?? fx {
                    T x → { ( vec_push [f] out x ) }
                    F _ → { ( vec_free [f] out ) ^ @ ?( Vec f ) { F } }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?( Vec f ) { T out }
}

// JSON array of strings → ( Vec String ); None if any element is not a string.
@ __an_strs_of_jarr Json a → ?( Vec String ) {
    ? ( json_is_arr a ) {} { ^ @ ?( Vec String ) { F } }
    : i n ( json_arr_len a )
    : ( Vec String ) out ( vec_with_cap [String] n )
    : ~ i k 0
    ~ < k n {
        ?? ( json_arr_get a k ) {
            T e → {
                ? ( json_is_str e ) {
                    ( vec_push [String] out ( string_from ( json_str_data e ) ) )
                } {
                    ( vec_free_with [String] out \ String x → v { ( string_free x ) } )
                    ^ @ ?( Vec String ) { F }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ ?( Vec String ) { T out }
}

// Serialise metadata to an owned Json object (fixed field order, so the
// same metadata always stringifies identically).
@ meta_to_json * Meta m → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `name` ( json_str_lit ( string_data . m name ) ) )
    ( json_obj_set o `created` ( json_str_lit ( string_data . m created ) ) )
    ( json_obj_set o `alias` ( json_str_lit ( string_data . m alias ) ) )
    ( json_obj_set o `clock` ( json_str_lit ? . m count_clock `count` `time` ) )

    : Json types ( json_obj_new )
    : Json cats ( json_obj_new )
    : i ncol ( vec_len [String] . m cols )
    : ~ i k 0
    ~ < k ncol {
        ?? ( vec_get [String] . m cols k ) {
            T c → {
                : i kind ( __an_kind_at m k )
                ( json_obj_set types ( string_data c ) ( json_str_lit ( __an_kind_str kind ) ) )
                ? == kind COL_CATEGORICAL {
                    ?? ( vec_get [( Vec String )] . m cats k ) {
                        T cv → { ( json_obj_set cats ( string_data c ) ( _an_jarr_of_strs cv ) ) }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `column_types` types )
    ( json_obj_set o `categories` cats )
    ( json_obj_set o `feature_names` ( _an_jarr_of_strs . m feats ) )

    : Json sc ( json_obj_new )
    ( json_obj_set sc `mean` ( _an_jarr_of_floats . m sc_mean ) )
    ( json_obj_set sc `std` ( _an_jarr_of_floats . m sc_std ) )
    ( json_obj_set o `scaler` sc )

    : Json fl ( json_obj_new )
    ( json_obj_set fl `ref_run` ( _an_jarr_of_floats . m flat_run ) )
    ( json_obj_set fl `ref_sd` ( _an_jarr_of_floats . m flat_sd ) )
    ( json_obj_set o `flatline` fl )

    // What the last fit refused to learn from, by feature. Named rather
    // than positional: it is read by people and by agents, and a count
    // nobody can attach to a feature says nothing.
    : Json ab ( json_obj_new )
    : i nab ( vec_len [f] . m absurd_n )
    : ~ i ai 0
    ~ & < ai nab < ai ( vec_len [String] . m feats ) {
        ?? ( vec_get [f] . m absurd_n ai ) {
            T cnt → {
                ? > cnt 0.0 {
                    ?? ( vec_get [String] . m feats ai ) {
                        T fn → { ( json_obj_set ab ( string_data fn ) ( json_int # i cnt ) ) }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = ai + ai 1
    }
    ( json_obj_set o `absurd_readings` ab )

    : Json sched ( json_obj_new )
    ( json_obj_set sched `below_max` ( json_int . m sched_below ) )
    ( json_obj_set sched `at_max` ( json_int . m sched_at_max ) )
    ( json_obj_set sched `autoencoder` ( json_bool . m sched_ae ) )
    ( json_obj_set o `schedule` sched )

    : Json vers ( json_obj_new )
    : i nv ( vec_len [VerCfg] . m versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . m versions vi ) {
            T vc → {
                : Json vo ( json_obj_new )
                ( json_obj_set vo `window_minutes` ( json_int . vc window_min ) )
                ( json_obj_set vo `window_points` ( json_int . vc window_pts ) )
                ( json_obj_set vo `window_size` ( json_int . vc window_size ) )
                ( json_obj_set vo `step_size` ( json_int . vc step_size ) )
                ( json_obj_set vo `n_estimators` ( json_int . vc n_estimators ) )
                ( json_obj_set vo `max_samples` ( json_int . vc max_samples ) )
                ? < . vc contamination 0.0 {
                    ( json_obj_set vo `contamination` ( json_str_lit `auto` ) )
                } {
                    ( json_obj_set vo `contamination` ( json_float . vc contamination ) )
                }
                ( json_obj_set vo `decision_margin` ( json_float . vc decision_margin ) )
                ( json_obj_set vo `enabled` ( json_bool . vc enabled ) )
                ( json_obj_set vers ( string_data . vc vname ) vo )
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( json_obj_set o `versions` vers )
    ( json_obj_set o `votes` ( json_int . m votes ) )

    ( json_obj_set o `n_points_seen` ( json_int . m n_seen ) )
    ( json_obj_set o `n_points_stored` ( json_int . m n_stored ) )
    ( json_obj_set o `last_trained_at` ( json_int . m last_trained ) )
    ( json_obj_set o `last_trained_time` ( json_int . m trained_time ) )
    ( json_obj_set o `tuned_at` ( json_int . m tuned_at ) )
    ( json_obj_set o `max_data_points` ( json_int . m max_points ) )
    ( json_obj_set o `score_epoch` ( json_int . m score_epoch ) )
    ( json_obj_set o `feature_encoding` ( json_int . m feat_enc ) )
    ( json_obj_set o `train_span` ( json_int . m train_span ) )
    ( json_obj_set o `retrain_required` ( json_bool ( meta_retrain_required m ) ) )
    ^ o
}

// Integer field of a JSON object, or `dflt` when absent/mistyped.
@ _an_jint Json o s key i dflt → i {
    ?? ( json_obj_get o key ) {
        T e → {
            : ?i r ( json_num_as_i e )
            ?? r { T n → { ^ n } F _ → { ^ dflt } }
        }
        F _ → { ^ dflt }
    }
}

// One version config out of its JSON object.
@ _an_vercfg_of_json s vname Json vo → VerCfg {
    : ~ f cont -1.0
    ?? ( json_obj_get vo `contamination` ) {
        T cj → {
            ? ( json_is_num cj ) {
                : ?f cf ( json_num_as_f cj )
                ?? cf { T x → { = cont x } F _ → {} }
            } {}
        }
        F _ → {}
    }
    : ~ f margin 0.0
    ?? ( json_obj_get vo `decision_margin` ) {
        T dj → {
            : ?f df ( json_num_as_f dj )
            ?? df { T x → { = margin x } F _ → {} }
        }
        F _ → {}
    }
    : ~ b on T
    ?? ( json_obj_get vo `enabled` ) { T ej → { = on ( json_as_bool ej ) } F _ → {} }
    : b is_tv == ( nurl_str_eq vname `timevector` ) 1
    ^ @ VerCfg {
        ( string_from vname )
        ( _an_jint vo `window_minutes` 0 )
        ? is_tv 0 ( _an_jint vo `window_points` 0 )
        ( _an_jint vo `window_size` ? is_tv 100 0 )
        ( _an_jint vo `step_size` ? is_tv 1 0 )
        ( _an_jint vo `n_estimators` 100 )
        ( _an_jint vo `max_samples` 256 )
        cont
        margin
        on
    }
}

// Parse metadata back from JSON. None on malformed shape (missing/mistyped
// required fields); the partially-built Meta is freed on failure.
@ meta_from_json Json j → ?*Meta {
    ? ( json_is_obj j ) {} { ^ @ ?*Meta { F } }

    : ~ b ok T
    : ~ String mname ( string_new )
    : ~ String mcreated ( string_new )
    ?? ( json_obj_get j `name` ) {
        T e → {
            ? ( json_is_str e ) {
                ( string_free mname )
                = mname ( string_from ( json_str_data e ) )
            } { = ok F }
        }
        F _ → { = ok F }
    }
    ?? ( json_obj_get j `created` ) {
        T e → {
            ? ( json_is_str e ) {
                ( string_free mcreated )
                = mcreated ( string_from ( json_str_data e ) )
            } { = ok F }
        }
        F _ → { = ok F }
    }
    ? ok {} {
        ( string_free mname )
        ( string_free mcreated )
        ^ @ ?*Meta { F }
    }

    : *Meta m ( meta_new ( string_data mname ) ( string_data mcreated ) )
    ( string_free mname )
    ( string_free mcreated )

    // Columns: column_types drives order; categories fills categorical cols.
    ?? ( json_obj_get j `column_types` ) {
        T types → {
            ? ( json_is_obj types ) {
                : ( Vec String ) tkeys ( json_obj_keys types )
                : i nk ( vec_len [String] tkeys )
                : ~ i k 0
                ~ & ok < k nk {
                    ?? ( vec_get [String] tkeys k ) {
                        T c → {
                            : ~ i kind -1
                            ?? ( json_obj_get types ( string_data c ) ) {
                                T kv → {
                                    ? ( json_is_str kv ) { = kind ( __an_kind_parse ( json_str_data kv ) ) } {}
                                }
                                F _ → {}
                            }
                            ? < kind 0 { = ok F } {
                                : ~ ( Vec String ) colcats ( vec_new [String] )
                                ? == kind COL_CATEGORICAL {
                                    ?? ( json_obj_get j `categories` ) {
                                        T catso → {
                                            ?? ( json_obj_get catso ( string_data c ) ) {
                                                T ca → {
                                                    : ?( Vec String ) cs ( __an_strs_of_jarr ca )
                                                    ?? cs {
                                                        T got → {
                                                            ( vec_free [String] colcats )
                                                            = colcats got
                                                        }
                                                        F junk → { ( vec_free [String] junk ) = ok F }
                                                    }
                                                }
                                                F _ → {}
                                            }
                                        }
                                        F _ → {}
                                    }
                                } {}
                                ( vec_push [String] . m cols ( string_from ( string_data c ) ) )
                                ( vec_push [i] . m kinds kind )
                                ( vec_push [( Vec String )] . m cats colcats )
                            }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free_with [String] tkeys \ String x → v { ( string_free x ) } )
            } { = ok F }
        }
        F _ → {}
    }

    // Authoritative feature order (may be empty for an untrained model).
    ?? ( json_obj_get j `feature_names` ) {
        T fa → {
            : ?( Vec String ) fs ( __an_strs_of_jarr fa )
            ?? fs {
                T got → {
                    ( vec_free_with [String] . m feats \ String x → v { ( string_free x ) } )
                    = . m feats got
                }
                F junk → { ( vec_free [String] junk ) = ok F }
            }
        }
        F _ → {}
    }

    // Scaler (mean and std must be present together and equal length).
    ?? ( json_obj_get j `scaler` ) {
        T sc → {
            ?? ( json_obj_get sc `mean` ) {
                T ma → {
                    : ?( Vec f ) mm ( __an_floats_of_jarr ma )
                    ?? mm {
                        T got → { ( vec_free [f] . m sc_mean ) = . m sc_mean got }
                        F junk → { ( vec_free [f] junk ) = ok F }
                    }
                }
                F _ → {}
            }
            ?? ( json_obj_get sc `std` ) {
                T sa → {
                    : ?( Vec f ) ssv ( __an_floats_of_jarr sa )
                    ?? ssv {
                        T got → { ( vec_free [f] . m sc_std ) = . m sc_std got }
                        F junk → { ( vec_free [f] junk ) = ok F }
                    }
                }
                F _ → {}
            }
            ? == ( vec_len [f] . m sc_mean ) ( vec_len [f] . m sc_std ) {} { = ok F }
        }
        F _ → {}
    }

    // Flatline references (a model from before the version has none;
    // its next retrain fits them).
    ?? ( json_obj_get j `flatline` ) {
        T fl → {
            ?? ( json_obj_get fl `ref_run` ) {
                T ra → {
                    ?? ( __an_floats_of_jarr ra ) {
                        T got → { ( vec_free [f] . m flat_run ) = . m flat_run got }
                        F junk → { ( vec_free [f] junk ) = ok F }
                    }
                }
                F _ → {}
            }
            ?? ( json_obj_get fl `ref_sd` ) {
                T sa → {
                    ?? ( __an_floats_of_jarr sa ) {
                        T got → { ( vec_free [f] . m flat_sd ) = . m flat_sd got }
                        F junk → { ( vec_free [f] junk ) = ok F }
                    }
                }
                F _ → {}
            }
            ? == ( vec_len [f] . m flat_run ) ( vec_len [f] . m flat_sd ) {} { = ok F }
        }
        F _ → {}
    }

    // The readings the last fit left out, by feature name, back onto the
    // frozen order. A feature the object does not mention had none.
    ?? ( json_obj_get j `absurd_readings` ) {
        T abj → {
            ? ( json_is_obj abj ) {
                ( vec_free [f] . m absurd_n )
                = . m absurd_n ( vec_new [f] )
                : i nf2 ( vec_len [String] . m feats )
                : ~ i ai 0
                ~ < ai nf2 {
                    : ~ f cnt 0.0
                    ?? ( vec_get [String] . m feats ai ) {
                        T fn → {
                            ?? ( json_obj_get abj ( string_data fn ) ) {
                                T cv → { ? ( json_is_num cv ) { = cnt # f ( json_as_int cv ) } {} }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    ( vec_push [f] . m absurd_n cnt )
                    = ai + ai 1
                }
            } {}
        }
        F _ → {}
    }

    // Schedule.
    ?? ( json_obj_get j `schedule` ) {
        T sched → {
            = . m sched_below ( _an_jint sched `below_max` ANOM_SCHED_BELOW )
            = . m sched_at_max ( _an_jint sched `at_max` ANOM_SCHED_AT_MAX )
            ?? ( json_obj_get sched `autoencoder` ) { T aj → { = . m sched_ae ( json_as_bool aj ) } F _ → {} }
        }
        F _ → {}
    }

    // Versions: when present, replace the defaults entirely.
    ?? ( json_obj_get j `versions` ) {
        T vers → {
            ? ( json_is_obj vers ) {
                ( vec_free_with [VerCfg] . m versions \ VerCfg vc → v { ( _an_vercfg_free vc ) } )
                = . m versions ( vec_new [VerCfg] )
                : ( Vec String ) vkeys ( json_obj_keys vers )
                : i nvk ( vec_len [String] vkeys )
                : ~ i vk 0
                ~ < vk nvk {
                    ?? ( vec_get [String] vkeys vk ) {
                        T vn → {
                            ?? ( json_obj_get vers ( string_data vn ) ) {
                                T vo → {
                                    ? ( json_is_obj vo ) {
                                        ( vec_push [VerCfg] . m versions ( _an_vercfg_of_json ( string_data vn ) vo ) )
                                    } {}
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = vk + vk 1
                }
                ( vec_free_with [String] vkeys \ String x → v { ( string_free x ) } )
            } {}
        }
        F _ → {}
    }

    = . m n_seen ( _an_jint j `n_points_seen` 0 )
    = . m last_trained ( _an_jint j `last_trained_at` 0 )
    = . m trained_time ( _an_jint j `last_trained_time` 0 )
    = . m tuned_at ( _an_jint j `tuned_at` 0 )
    = . m max_points ( _an_jint j `max_data_points` ANOM_MAX_POINTS )
    // Metadata from before the key existed: the ring holds every point
    // seen until it is full, then exactly `max_points` — the only ways a
    // ring shrinks (a reset, a lowered cap) rewrite the metadata too.
    = . m n_stored ( _an_jint j `n_points_stored` -1 )
    ? < . m n_stored 0 {
        = . m n_stored ? < . m n_seen . m max_points . m n_seen . m max_points
    } {}
    = . m score_epoch ( _an_jint j `score_epoch` 1 )
    // A model written before the setting existed agrees with every model
    // that has never touched it: one version is enough.
    = . m votes ( _an_jint j `votes` ANOM_VOTES_DEFAULT )
    ? < . m votes 1 { = . m votes 1 } {}
    // Metadata written before the key existed was trained under encoding 1.
    = . m feat_enc ( _an_jint j `feature_encoding` 1 )
    = . m train_span ( _an_jint j `train_span` 0 )
    ?? ( json_obj_get j `clock` ) {
        T cv → { ? ( json_is_str cv ) { = . m count_clock == ( nurl_str_eq ( json_str_data cv ) `count` ) 1 } {} }
        F _ → {}
    }
    ?? ( json_obj_get j `alias` ) {
        T av → {
            ? ( json_is_str av ) {
                ( string_free . m alias )
                = . m alias ( string_from ( json_str_data av ) )
            } {}
        }
        F _ → {}
    }

    ? ok {} {
        ( meta_free m )
        ^ @ ?*Meta { F }
    }
    ^ @ ?*Meta { T m }
}

// Convenience: metadata → compact JSON text (owned).
@ meta_to_json_str * Meta m → String {
    : Json o ( meta_to_json m )
    : String out ( json_stringify o )
    ( json_free o )
    ^ out
}

// Convenience: JSON text → metadata; None on parse or shape errors.
@ meta_from_json_str s src → ?*Meta {
    : !Json JsonError r ( json_parse src )
    ?? r {
        T j → {
            : ?*Meta mm ( meta_from_json j )
            ( json_free j )
            ^ mm
        }
        F _ → { ^ @ ?*Meta { F } }
    }
}

// ── Editable metadata (dashboard / API) ───────────────────────────────
//
// Two parts of the metadata are the user's to set: the retrain schedule
// and the per-version configs. Everything else — column kinds, category
// vocabularies, the authoritative feature order, the scaler — is learned
// from the data at each train, and a hand-edited copy would silently
// desync every trained forest. The helpers below therefore only ever
// touch `versions`; the schedule lives on Meta directly.

// Index of the version named `vname`, or -1.
@ meta_find_version * Meta m s vname → i {
    : i nv ( vec_len [VerCfg] . m versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . m versions k ) {
            T vc → { ? == ( nurl_str_eq ( string_data . vc vname ) vname ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

// Is version `vname` enabled? `dflt` when there is no such version.
@ meta_version_enabled * Meta m s vname b dflt → b {
    : i at ( meta_find_version m vname )
    ? < at 0 { ^ dflt } {}
    ?? ( vec_get [VerCfg] . m versions at ) { T vc → { ^ . vc enabled } F _ → { ^ dflt } }
}

// Version `vname`'s decision margin; `dflt` when there is no such version.
// The live margin of a version always comes from the CURRENT metadata, not
// from its forest blob — so margin changes (fine-tune, a config PUT) take
// effect immediately, without a retrain. The blob's stored margin is only
// the fallback for versions no longer present in the metadata.
@ meta_version_margin * Meta m s vname f dflt → f {
    : i at ( meta_find_version m vname )
    ? < at 0 { ^ dflt } {}
    ?? ( vec_get [VerCfg] . m versions at ) { T vc → { ^ . vc decision_margin } F _ → { ^ dflt } }
}

// Bump the scoring epoch: the token every cached verdict is stamped with.
// Anything that can change what a stored point scores — a retrain, a new
// autoencoder, a margin edit, a version toggled on or off, a reset — bumps
// it, and every cache entry carrying an older epoch is stale by
// construction. One counter beats trying to reason about which caches a
// given edit could have invalidated.
@ meta_bump_epoch * Meta m → v {
    = . m score_epoch + . m score_epoch 1
}

// Clamp a config into the range the trainer can actually honour, so a
// hand-written JSON patch can never produce a version that fails to train
// (or trains something nonsensical). `contamination` < 0 means "auto".
@ _an_vercfg_sane VerCfg vc → VerCfg {
    : ~ VerCfg o vc
    ? < . o window_min 0 { = . o window_min 0 } {}
    ? < . o window_pts 0 { = . o window_pts 0 } {}
    // The forecast's window_size is a seasonal period: 0 takes it from
    // the ring's step, -1 is no season at all, one row is no season.
    : b fcv ( _an_is_fc_name ( string_data . o vname ) )
    ? & fcv < . o window_size 0 { = . o window_size -1 } {}
    ? & ! fcv < . o window_size 0 { = . o window_size 0 } {}
    ? > . o window_size 0 {
        ? < . o step_size 1 { = . o step_size 1 } {}
    } { = . o step_size 0 }
    ? & fcv == . o window_size 1 { = . o window_size 0 } {}
    // The autoencoder and the guards have no forest: their tree counts
    // stay 0 so the config round-trips unchanged. Every other version
    // must be trainable. The flatline guard's window is a run of rows and
    // needs at least two of them.
    ? ( _an_forestless_name ( string_data . o vname ) ) {
        ? < . o n_estimators 0 { = . o n_estimators 0 } {}
        ? < . o max_samples 0 { = . o max_samples 0 } {}
        ? & ( _an_is_flat_name ( string_data . o vname ) ) < . o window_size 2 { = . o window_size ANOM_FLAT_WINDOW = . o step_size 1 } {}
    } {
        ? < . o n_estimators 1 { = . o n_estimators 1 } {}
        ? > . o n_estimators 5000 { = . o n_estimators 5000 } {}
        ? < . o max_samples 1 { = . o max_samples 1 } {}
    }
    ? <= . o contamination 0.0 { = . o contamination -1.0 } {
        ? > . o contamination 0.5 { = . o contamination 0.5 } {}
    }
    ? < . o decision_margin 0.0 { = . o decision_margin 0.0 } {}
    ^ o
}

// Patch one version config from a JSON object. Every field is optional:
// what the object omits keeps its current value, so the dashboard can PUT
// `{"enabled": false}` without restating the whole config.
@ _an_vercfg_patch VerCfg vc Json vo → VerCfg {
    : ~ VerCfg o vc
    = . o window_min ( _an_jint vo `window_minutes` . vc window_min )
    = . o window_pts ( _an_jint vo `window_points` . vc window_pts )
    = . o window_size ( _an_jint vo `window_size` . vc window_size )
    = . o step_size ( _an_jint vo `step_size` . vc step_size )
    = . o n_estimators ( _an_jint vo `n_estimators` . vc n_estimators )
    = . o max_samples ( _an_jint vo `max_samples` . vc max_samples )
    ?? ( json_obj_get vo `contamination` ) {
        T cj → {
            ? ( json_is_num cj ) {
                : ?f cf ( json_num_as_f cj )
                ?? cf { T x → { = . o contamination x } F _ → {} }
            } { = . o contamination -1.0 }
        }
        F _ → {}
    }
    ?? ( json_obj_get vo `decision_margin` ) {
        T dj → {
            : ?f df ( json_num_as_f dj )
            ?? df { T x → { = . o decision_margin x } F _ → {} }
        }
        F _ → {}
    }
    ?? ( json_obj_get vo `enabled` ) { T ej → { = . o enabled ( json_as_bool ej ) } F _ → {} }
    ^ ( _an_vercfg_sane o )
}

// The keys a JSON object carries that are not in `allowed` (a
// space-separated list), as "<prefix>.<key>" joined with ", "; empty when
// every key is known. A patch is a statement of intent, and a key the
// service does not read — a typo, a field from a later version, a
// setting that lives somewhere else — used to vanish without a word
// while the rest of the patch went through.
@ _an_unknown_keys Json o s allowed s prefix → String {
    : String out ( string_new )
    ? ( json_is_obj o ) {} { ^ out }
    : ( Vec String ) keys ( json_obj_keys o )
    : String allowed_s ( string_from allowed )
    : ( Vec String ) ok ( string_split allowed_s ` ` )
    ( string_free allowed_s )
    : i nk ( vec_len [String] keys )
    : i na ( vec_len [String] ok )
    : ~ i k 0
    ~ < k nk {
        ?? ( vec_get [String] keys k ) {
            T key → {
                : ~ b known F
                : ~ i a 0
                ~ < a na {
                    ?? ( vec_get [String] ok a ) {
                        T al → { ? == ( nurl_str_eq ( string_data al ) ( string_data key ) ) 1 { = known T } {} }
                        F _ → {}
                    }
                    = a + a 1
                }
                ? known {} {
                    ? > ( string_len out ) 0 { ( string_push_str out `, ` ) } {}
                    ( string_push_str out prefix )
                    ( string_push_char out 46 )
                    ( string_push_str out ( string_data key ) )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] ok \ String x → v { ( string_free x ) } )
    ^ out
}

// The fields a version config accepts in a patch, one string for the
// checker and the tool descriptions alike.
: s ANOM_VERCFG_FIELDS `enabled decision_margin window_minutes window_points window_size step_size n_estimators max_samples contamination`

// Check a `versions` patch before applying it: every value an object,
// every field a VerCfg field. Returns the reason to refuse, or "".
// A `versions` patch, checked before anything is applied: every key must
// name a version the model has, and every field inside it must be one a
// VerCfg carries. A name the model does not have is a typo far more often
// than a new version — `{"autoenocder": {"enabled": false}}` used to
// answer success and leave the real autoencoder on — so it is refused
// here, with the names that do exist. Creating a version is still
// possible and still one flag away: `replace_versions` makes the object
// the WHOLE list, which is how the dashboard's JSON editor adds and
// removes them, and there the names it does not know are the point.
@ meta_versions_patch_check * Meta m Json vers b replace → String {
    ? ( json_is_obj vers ) {} { ^ ( string_from `versions must be a JSON object of version configs` ) }
    : ( Vec String ) keys ( json_obj_keys vers )
    : i nk ( vec_len [String] keys )
    : ~ String why ( string_new )
    : ~ i k 0
    ~ & < k nk == ( string_len why ) 0 {
        ?? ( vec_get [String] keys k ) {
            T vn → {
                ?? ( json_obj_get vers ( string_data vn ) ) {
                    T vo → {
                        ? ( json_is_obj vo ) {
                            ? | replace >= ( meta_find_version m ( string_data vn ) ) 0 {} {
                                ( string_free why )
                                = why ( string_from `versions.` )
                                ( string_push_str why ( string_data vn ) )
                                ( string_push_str why ` is not a version of this model (it has: ` )
                                : ( Vec String ) have ( vec_new [String] )
                                : i nvv ( vec_len [VerCfg] . m versions )
                                : ~ i vk 0
                                ~ < vk nvv {
                                    ?? ( vec_get [VerCfg] . m versions vk ) {
                                        T vc → { ( vec_push [String] have ( string_clone . vc vname ) ) }
                                        F _ → {}
                                    }
                                    = vk + vk 1
                                }
                                : String names ( string_join have `, ` )
                                ( string_push_str why ( string_data names ) )
                                ( string_free names )
                                ( vec_free_with [String] have \ String x → v { ( string_free x ) } )
                                ( string_push_str why `). To ADD a version, send the whole list with replace_versions: true.` )
                            }
                            : String pre ( string_from `versions.` )
                            ( string_push_str pre ( string_data vn ) )
                            : String bad ( _an_unknown_keys vo ANOM_VERCFG_FIELDS ( string_data pre ) )
                            ( string_free pre )
                            ? > ( string_len bad ) 0 {
                                ( string_free why )
                                = why ( string_from `unknown field ` )
                                ( string_push_str why ( string_data bad ) )
                                ( string_push_str why ` (a version config has: ` )
                                ( string_push_str why ANOM_VERCFG_FIELDS )
                                ( string_push_char why 41 )
                            } {}
                            ( string_free bad )
                        } {
                            ( string_free why )
                            = why ( string_from `versions.` )
                            ( string_push_str why ( string_data vn ) )
                            ( string_push_str why ` must be a JSON object` )
                        }
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ^ why
}

// Apply a `versions` JSON object (the shape meta_to_json emits) to the
// metadata. Each key names a version and its value is a PARTIAL config;
// a key naming no existing version ADDS one, with `_an_vercfg_of_json`'s
// defaults filling the gaps. With `replace`, the resulting list is exactly
// the keys given — versions the object omits are dropped, which is how the
// advanced JSON editor deletes one. Returns the version count afterwards,
// or -1 when `vers` is not a JSON object.
//
// Creation is gated ABOVE this, in `meta_versions_patch_check`: a partial
// patch may only edit versions the model has, and only a whole-list patch
// (`replace_versions`) may name one it does not. This function is the
// mechanism; the rule about who may use it lives with the patch.
@ meta_apply_versions_json * Meta m Json vers b replace → i {
    ? ( json_is_obj vers ) {} { ^ -1 }
    : ( Vec String ) keys ( json_obj_keys vers )
    : i nk ( vec_len [String] keys )
    : ~ i k 0
    ~ < k nk {
        ?? ( vec_get [String] keys k ) {
            T vn → {
                ?? ( json_obj_get vers ( string_data vn ) ) {
                    T vo → {
                        ? ( json_is_obj vo ) {
                            : i at ( meta_find_version m ( string_data vn ) )
                            ? >= at 0 {
                                ?? ( vec_get [VerCfg] . m versions at ) {
                                    T cur → {
                                        : b _o ( vec_set [VerCfg] . m versions at ( _an_vercfg_patch cur vo ) )
                                    }
                                    F _ → {}
                                }
                            } {
                                ( vec_push [VerCfg] . m versions
                                ( _an_vercfg_sane ( _an_vercfg_of_json ( string_data vn ) vo ) ) )
                            }
                        } {}
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ? replace {
        : ( Vec VerCfg ) kept ( vec_new [VerCfg] )
        : i nv ( vec_len [VerCfg] . m versions )
        = k 0
        ~ < k nv {
            ?? ( vec_get [VerCfg] . m versions k ) {
                T vc → {
                    ? ( json_obj_has vers ( string_data . vc vname ) ) {
                        ( vec_push [VerCfg] kept vc )
                    } { ( _an_vercfg_free vc ) }
                }
                F _ → {}
            }
            = k + k 1
        }
        ( vec_free [VerCfg] . m versions )
        = . m versions kept
    } {}
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ^ ( vec_len [VerCfg] . m versions )
}
