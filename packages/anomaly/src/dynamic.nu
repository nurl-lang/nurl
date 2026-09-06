// anomaly/dynamic.nu — dynamic streaming models (milestones M4 + M5).
//
// The headline feature: a named model that is created on first use, ingests
// one raw JSON point at a time, and trains itself once enough history has
// accumulated. Each model keeps:
//
//   - a bounded ring of raw points (`max_points`, default 150 000) persisted
//     as data.jsonl — raw records, so retrains learn new categories;
//   - schedule-driven retraining: whenever the lifetime point count
//     (`n_seen`, monotonic — unaffected by ring eviction) reaches the next
//     training mark, every enabled version retrains; the mark then advances
//     by `schedule.below_max` (default 50) or, once the ring is full,
//     `schedule.at_max` (default 1000);
//   - one forest per enabled version (M5): each version trains on its own
//     time window of the ring (`window_min` minutes back from "now", or the
//     last `window_pts` points), falling back to the most recent
//     `min_points` rows when the window is too thin;
//   - one shared scaler, fit over the full ring at each train.
//
// Verdicts follow the reference service: a point is anomalous if ANY
// enabled version flags it (decision_function <= -margin); the reported
// score is the most severe (lowest) decision_function. Before `min_points`
// points (default 50) the model is warming up: `ready = false`, no verdict.
//
// Every public entry point has an `_at` variant taking `now` in unix
// seconds — the injectable clock that makes window filtering and stamped
// timestamps reproducible in tests. The plain variants read the wall clock.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/autoenc.nu`
$ `src/store.nu`

// ── Types ─────────────────────────────────────────────────────────────

// One version's slice of a verdict. `margin` is the EFFECTIVE absolute
// band the score was compared against (the invariant `score <= -margin ⇒
// anomaly` holds for every version); `cfg_margin` is the number stored in
// the metadata. They differ only for the autoencoder, whose configured
// margin is relative to its reconstruction threshold — see ANOM_AE_MARGIN.
: VerVerdict {
    String vvname
    b anomaly
    f score
    f margin
    f cfg_margin
    i vv_feat  // the feature this verdict is about (range_guard); -1 = none
}

// What the flatline guard saw (see __an_flat_judge).
: FlatOut {
    b ready  // F when the ring is shorter than the window or nothing is fitted
    f worst  // the largest fraction over the watched features
    i feat  // the feature that gave it; -1 when none is watched
}

// The aggregate verdict for one point (SPEC §5.4).
: Verdict {
    b ready
    b anomaly
    f score  // the most severe version's decision value (own units)
    f severity  // that version's severity: the aggregate, unit-free
    ( Vec VerVerdict ) versions
}

// The one unit-free number every version shares (SPEC §5.4): how far past
// its own alert line a decision value sits, in margins — 1.0 exactly on
// the line, 2.0 twice as far, negative comfortably normal. A margin of 0
// gives 1.0 when flagged and 0.0 otherwise. The aggregate score is the
// score of the version that is most severe by this measure; a plain
// minimum over decision values would let a forest's ~1e-1 always outrank
// an autoencoder's ~1e-4 and hide the joint model's alarm.
@ anom_severity f df f margin → f {
    ? > margin 0.0 { ^ / - 0.0 df margin } {}
    ^ ? <= df 0.0 1.0 0.0
}

// A live dynamic model. Obtain with model_open, release with model_free.
: Model {
    Store store
    String mname
    * Meta meta
    ( Vec String ) lines
    ( Vec i ) times
    ( Vec VerModel ) forests
    Scaler sc
    AeModel ae
    b ae_stale  // the net names features the current encoding no longer makes
    i next_train_at
    i min_points
    i max_points
}

@ verdict_free Verdict vd → v {
    ( vec_free_with [VerVerdict] . vd versions \ VerVerdict vv → v { ( string_free . vv vvname ) } )
}

@ __an_vercfg_clone VerCfg vc → VerCfg {
    ^ @ VerCfg {
        ( string_from ( string_data . vc vname ) )
        . vc window_min
        . vc window_pts
        . vc window_size
        . vc step_size
        . vc n_estimators
        . vc max_samples
        . vc contamination
        . vc decision_margin
        . vc enabled
    }
}

// Ingest timestamp of a stored data.jsonl line (0 if unparsable).
@ _an_line_ts s line → i {
    : !Json JsonError r ( json_parse line )
    ?? r {
        T j → {
            : i ts ( _an_jint j `timestamp` 0 )
            ( json_free j )
            ^ ts
        }
        F _ → { ^ 0 }
    }
}

@ __an_free_forests * Model mo → v {
    ( vec_free_with [VerModel] . mo forests \ VerModel vm → v { ( anom_vermodel_free vm ) } )
    = . mo forests ( vec_new [VerModel] )
}

@ __an_free_lines ( Vec String ) xs → v {
    ( vec_free_with [String] xs \ String x → v { ( string_free x ) } )
}

// The schedule step from the current ring fill: at capacity, retrain less.
@ __an_sched_step * Model mo → i {
    : *Meta mm . mo meta
    ? >= ( vec_len [String] . mo lines ) . mo max_points { ^ . mm sched_at_max } {}
    ^ . mm sched_below
}

// ── Lifecycle ─────────────────────────────────────────────────────────

// Open (or create) the named model in the store: load metadata, the point
// ring, and every trained version's forest. Create-on-first-use: a missing
// model is initialised with fresh metadata and persisted immediately.
@ __an_is_ae_name s vname → b {
    ^ == ( nurl_str_eq vname `autoencoder` ) 1
}

// The versions that are not forests: the autoencoder and the guards have
// a VerCfg (margin, enabled) but no forest blob to load, train or drop.
@ __an_forestless s vname → b {
    ^ ( _an_forestless_name vname )
}

@ model_open_at Store st s name i now → *Model {
    : *Model mo # *Model ( nurl_malloc Z Model )
    = . mo store ( store_open ( string_data . st root ) )
    = . mo mname ( string_from name )
    = . mo forests ( vec_new [VerModel] )
    = . mo min_points ANOM_MIN_POINTS
    = . mo max_points ANOM_MAX_POINTS

    : ~ b loaded F
    ? ( store_exists st name ) {
        : ?*Meta mload ( store_load_meta st name )
        ?? mload {
            T got → {
                = . mo meta got
                = loaded T
            }
            F _ → {}
        }
    } {}
    ? loaded {} {
        : Time t ( time_from_unix now )
        : String iso ( time_format_iso t )
        = . mo meta ( meta_new name ( string_data iso ) )
        ( string_free iso )
        ( store_save_meta . mo store name . mo meta )
    }
    : *Meta mm . mo meta
    = . mo max_points . mm max_points

    // Ring: adopt the stored lines wholesale, then stamp times from them.
    : ( Vec String ) pts ( store_load_points . mo store name )
    = . mo lines pts
    = . mo times ( vec_new [i] )
    : i np ( vec_len [String] pts )
    : ~ i k 0
    ~ < k np {
        ?? ( vec_get [String] pts k ) {
            T l → { ( vec_push [i] . mo times ( _an_line_ts ( string_data l ) ) ) }
            F _ → {}
        }
        = k + k 1
    }

    // Trained versions: one forest blob per enabled version, if present.
    // The `autoencoder` version is not a forest: its VerCfg only carries
    // the margin and the enabled flag, and a forest blob under that name
    // is the leftover of a release that trained one anyway (an empty
    // forest whose verdict shadowed the real autoencoder's) — ignored here
    // and deleted by the next retrain.
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                ? & . vc enabled ! ( __an_forestless ( string_data . vc vname ) ) {
                    : ?VerModel got ( store_load_forest . mo store name ( string_data . vc vname ) )
                    ?? got {
                        T vm → { ( vec_push [VerModel] . mo forests vm ) }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = vi + vi 1
    }

    // Scaler from persisted metadata (empty scaler if never trained).
    = . mo sc ( meta_scaler mm )

    // The autoencoder version, if one has been trained for this model.
    ?? ( store_load_ae . mo store name ) {
        T ae → { = . mo ae ae }
        F → { = . mo ae ( ae_empty ) }
    }
    = . mo ae_stale ( an_ae_stale mm . mo ae )

    // Next scheduled training mark, from the lifetime counter.
    ? == ( vec_len [VerModel] . mo forests ) 0 {
        = . mo next_train_at . mo min_points
    } {
        = . mo next_train_at + . mm n_seen ( __an_sched_step mo )
    }
    ^ mo
}

@ model_open Store st s name → *Model {
    ^ ( model_open_at st name ( now_seconds ) )
}

// Set a version's sliding-window geometry (timevector). Takes effect at
// the NEXT retrain — detect derives the live window from the trained
// forest's width, so a config change can never desync scoring.
@ model_set_version_window * Model mo s vname i wsize i sstep → b {
    : *Meta mm . mo meta
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) vname ) 1 {
                    : ~ VerCfg nc vc
                    = . nc window_size wsize
                    = . nc step_size sstep
                    : b _o ( vec_set [VerCfg] . mm versions k nc )
                    ( store_save_meta . mo store ( string_data . mo mname ) mm )
                    ^ T
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// ── Which clock ───────────────────────────────────────────────────────

// The newest stored stamp, or 0 on an empty ring.
@ model_last_ts * Model mo → i {
    : i np ( vec_len [i] . mo times )
    ? > np 0 { ?? ( vec_get [i] . mo times - np 1 ) { T x → { ^ x } F _ → {} } } {}
    ^ 0
}

// The tick the NEXT point gets on the count clock: one past the newest.
@ model_next_tick * Model mo → i {
    ^ + ( model_last_ts mo ) ANOM_TICK
}

// "Now" for this model: the wall clock, or on the count clock the newest
// tick — the moment the last point arrived is the only present it has.
@ model_now * Model mo → i {
    : *Meta mm . mo meta
    ? . mm count_clock { ^ ( model_last_ts mo ) } {}
    ^ ( now_seconds )
}

@ model_free * Model mo → v {
    ( __an_free_forests mo )
    ( vec_free [VerModel] . mo forests )
    ( __an_free_lines . mo lines )
    ( vec_free [i] . mo times )
    ( scaler_free . mo sc )
    ( ae_free . mo ae )
    ( meta_free . mo meta )
    ( string_free . mo mname )
    ( store_free . mo store )
    ( nurl_free mo )
}

// Test hook: shrink the warm-up / ring limits so eviction and scheduling
// are exercisable without 150 000 points.
@ model_set_limits * Model mo i min_pts i max_pts → v {
    = . mo min_points min_pts
    = . mo max_points max_pts
    ? == ( vec_len [VerModel] . mo forests ) 0 {
        = . mo next_train_at min_pts
    } {}
}

@ model_metadata * Model mo → *Meta {
    ^ . mo meta
}

@ model_n_points * Model mo → i {
    ^ ( vec_len [String] . mo lines )
}

@ model_is_trained * Model mo → b {
    ^ > ( vec_len [VerModel] . mo forests ) 0
}

// ── Scoring ───────────────────────────────────────────────────────────

// Score an encoded point against every trained version. `ready` is false
// until the model has trained at least once AND the ring holds min_points.
// The `need` ring points ending just before ring position `end`, projected
// and standardised, concatenated in time order — the sliding window's tail.
// `end` is where the point being scored sits: the ring length at
// detect_only (the point is not in the ring), one less at ingest (it
// already is), and the row index when re-scoring stored history, so a
// timevector window is always the points BEFORE the one under judgement and
// never leaks the future into a replayed verdict. None when the ring is too
// short there, or a stored line no longer parses.
@ __an_window_tail * Model mo i need i end → ?( Vec f ) {
    : *Meta mm . mo meta
    : i n end
    ? < n need { ^ @ ?( Vec f ) { F } } {}
    : ( Vec f ) out ( vec_new [f] )
    : ~ b ok T
    : ~ i k - n need
    ~ & ok < k n {
        ?? ( vec_get [String] . mo lines k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → {
                        : !EncPoint String er ( anomaly_preprocess mm j )
                        ?? er {
                            T pt → {
                                : ( Vec f ) row ( anomaly_project pt . mm feats )
                                ( scaler_apply . mo sc row )
                                ( vec_extend [f] out row )
                                ( vec_free [f] row )
                                ( enc_free pt )
                            }
                            F e → { ( string_free e ) = ok F }
                        }
                        ( json_free j )
                    }
                    F _ → { = ok F }
                }
            }
            F _ → { = ok F }
        }
        = k + k 1
    }
    ? ok { ^ @ ?( Vec f ) { T out } } {}
    ( vec_free [f] out )
    ^ @ ?( Vec f ) { F }
}

// ── Encoded history ───────────────────────────────────────────────────
// A scan, a calibration and a fine-tune judge every stored row, and each
// row's verdict needs the row itself, the W−1 rows before it (the
// timevector window) and every forest's decision for it. Encoding a stored
// line costs a JSON parse and a name lookup per feature, so ring rows
// [base, base+n) are encoded ONCE here, and each forest scores the whole
// matrix in one call — the accelerated path — instead of a row at a time.
// The numbers are the per-row path's exactly (anom_decisions is
// bit-identical to anom_decision, and the window is the same projection
// of the same rows); only the work is shared.
: Hist {
    i base
    i n
    i nfeat
    ( Vec f ) x  // n × nfeat, standardised; a row that failed to parse is zeros
    ( Vec i ) ok  // 1 when the row parsed and encoded
    i ae_nfeat
    ( Vec f ) ae_x  // n × ae_nfeat, raw projection onto the autoencoder's own feature order
    ( Vec ( Vec f ) ) dfs  // per forest index: its decision for every row
    ( Vec ( Vec i ) ) dfs_ok  // per forest index: 1 where that decision stands (a timevector forest has none for a row whose window is not all here)
}

@ __an_hist_free * Hist h → v {
    ? == # i h 0 { ^ } {}
    ( vec_free [f] . h x )
    ( vec_free [i] . h ok )
    ( vec_free [f] . h ae_x )
    ( vec_free_with [( Vec f )] . h dfs \ ( Vec f ) d → v { ( vec_free [f] d ) } )
    ( vec_free_with [( Vec i )] . h dfs_ok \ ( Vec i ) d → v { ( vec_free [i] d ) } )
    ( nurl_free # *u h )
}

// Widest timevector window over the trained forests (1 when there is none):
// the rows a scan of [lo, hi) needs encoded start at lo − width + 1.
@ __an_hist_width * Model mo → i {
    : i nfeat ( vec_len [String] . . mo meta feats )
    : ~ i w 1
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                ? & > nfeat 0 != . vm n_cols nfeat {
                    : i wk / . vm n_cols nfeat
                    ? > wk w { = w wk } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ w
}

// Encode ring rows [from, to) and score them through every forest.
@ __an_hist_build * Model mo i from i to → *Hist {
    : *Meta mm . mo meta
    : i nfeat ( vec_len [String] . mm feats )
    : AeModel cae . mo ae
    : ~ i ae_nfeat 0
    ? & . cae trained ! . mo ae_stale { = ae_nfeat ( vec_len [String] . cae feats ) } {}
    : ~ i lo from
    ? < lo 0 { = lo 0 } {}
    : ~ i hi to
    : i total ( vec_len [String] . mo lines )
    ? > hi total { = hi total } {}
    ? < hi lo { = hi lo } {}
    : i n - hi lo
    : ( Vec f ) x ( vec_with_cap [f] * n nfeat )
    : ( Vec i ) ok ( vec_with_cap [i] n )
    : ( Vec f ) ae_x ( vec_with_cap [f] * n ae_nfeat )
    : ~ i k lo
    ~ < k hi {
        : ~ b got F
        ?? ( vec_get [String] . mo lines k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → {
                        : !EncPoint String er ( anomaly_preprocess_ro mm j )
                        ?? er {
                            T p → {
                                : ( Vec f ) row ( anomaly_project p . mm feats )
                                ( scaler_apply . mo sc row )
                                ( vec_extend [f] x row )
                                ( vec_free [f] row )
                                ? > ae_nfeat 0 {
                                    : ( Vec f ) araw ( anomaly_project p . cae feats )
                                    ( vec_extend [f] ae_x araw )
                                    ( vec_free [f] araw )
                                } {}
                                ( enc_free p )
                                = got T
                            }
                            F e → { ( string_free e ) }
                        }
                        ( json_free j )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        ? got { ( vec_push [i] ok 1 ) } {
            ( vec_push [i] ok 0 )
            : ~ i z 0
            ~ < z nfeat { ( vec_push [f] x 0.0 ) = z + z 1 }
            = z 0
            ~ < z ae_nfeat { ( vec_push [f] ae_x 0.0 ) = z + z 1 }
        }
        = k + k 1
    }
    // Every forest over the whole matrix at once. A point-wide forest takes
    // the matrix as it is; a timevector forest takes each row's window —
    // the W−1 rows before it and itself, all encoded here — laid out in
    // batches sized to a few megabytes, so the accelerated path scores
    // them too and nothing is walked a row at a time.
    : ( Vec ( Vec f ) ) dfs ( vec_new [( Vec f )] )
    : ( Vec ( Vec i ) ) dfs_ok ( vec_new [( Vec i )] )
    : i nf ( vec_len [VerModel] . mo forests )
    = k 0
    ~ < k nf {
        : ~ ( Vec f ) d ( vec_new [f] )
        : ( Vec i ) dok ( vec_new [i] )
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                ? & > n 0 > nfeat 0 {
                    ? == . vm n_cols nfeat {
                        ( vec_free [f] d )
                        = d ( anom_decisions vm x n nfeat )
                        : ~ i r 0
                        ~ < r n { ( vec_push [i] dok ( _mlp_iget ok r ) ) = r + r 1 }
                    } {
                        : i W / . vm n_cols nfeat
                        : i need - W 1
                        : i wcols . vm n_cols
                        : ~ i r 0
                        ~ < r n { ( vec_push [f] d 0.0 ) ( vec_push [i] dok 0 ) = r + r 1 }
                        : ~ i per / 4194304 wcols
                        ? < per 1 { = per 1 } {}
                        : ( Vec f ) batch ( vec_with_cap [f] * per wcols )
                        : ( Vec i ) rows ( vec_with_cap [i] per )
                        : *f xp ( vec_data [f] x )
                        : *i okp ( vec_data [i] ok )
                        = r 0
                        ~ <= r n {
                            // Row r belongs to the batch when its whole
                            // window is encoded; a full batch, or the end,
                            // is scored and scattered back.
                            : ~ b take F
                            ? < r n {
                                ? >= r need {
                                    = take T
                                    : ~ i q - r need
                                    ~ & take <= q r {
                                        ? == . okp q 1 {} { = take F }
                                        = q + q 1
                                    }
                                } {}
                            } {}
                            ? take {
                                : i w0 * - r need nfeat
                                : ~ i c 0
                                ~ < c wcols { ( vec_push [f] batch . xp + w0 c ) = c + c 1 }
                                ( vec_push [i] rows r )
                            } {}
                            : i nb ( vec_len [i] rows )
                            ? & > nb 0 | >= nb per == r n {
                                : ( Vec f ) got ( anom_decisions vm batch nb wcols )
                                : ~ i q 0
                                ~ < q nb {
                                    : i at ( _mlp_iget rows q )
                                    ( vec_set [f] d at ( _mlp_fget got q ) )
                                    ( vec_set [i] dok at 1 )
                                    = q + q 1
                                }
                                ( vec_free [f] got )
                                ( vec_set_len [f] batch 0 )
                                ( vec_set_len [i] rows 0 )
                            } {}
                            = r + r 1
                        }
                        ( vec_free [f] batch )
                        ( vec_free [i] rows )
                    }
                } {}
            }
            F _ → {}
        }
        ( vec_push [( Vec f )] dfs d )
        ( vec_push [( Vec i )] dfs_ok dok )
        = k + k 1
    }
    : *Hist h # *Hist ( nurl_malloc Z Hist )
    = . h base lo
    = . h n n
    = . h nfeat nfeat
    = . h x x
    = . h ok ok
    = . h ae_nfeat ae_nfeat
    = . h ae_x ae_x
    = . h dfs dfs
    = . h dfs_ok dfs_ok
    ^ h
}

// Row `at` of the ring as a standardised point, copied out of the history.
@ __an_hist_row * Hist h i at → ( Vec f ) {
    : i r - at . h base
    : ( Vec f ) out ( vec_with_cap [f] . h nfeat )
    : *f xp ( vec_data [f] . h x )
    : ~ i c 0
    ~ < c . h nfeat { ( vec_push [f] out . xp + * r . h nfeat c ) = c + c 1 }
    ^ out
}

// The `need` rows ending just before `end`, from the history — None when
// any of them lies outside it or failed to encode (the caller then reads
// the ring, exactly as without a history).
@ __an_hist_tail * Hist h i need i end → ?( Vec f ) {
    : i first - end need
    ? | < first . h base > end + . h base . h n { ^ @ ?( Vec f ) { F } } {}
    : *i okp ( vec_data [i] . h ok )
    : ~ i k first
    ~ < k end {
        ? == . okp - k . h base 1 {} { ^ @ ?( Vec f ) { F } }
        = k + k 1
    }
    : ( Vec f ) out ( vec_with_cap [f] * need . h nfeat )
    : *f xp ( vec_data [f] . h x )
    : i from * - first . h base . h nfeat
    : i cnt * need . h nfeat
    = k 0
    ~ < k cnt { ( vec_push [f] out . xp + from k ) = k + k 1 }
    ^ @ ?( Vec f ) { T out }
}

// The timevector tail: out of the history when one covers it, else read
// from the ring.
@ __an_tail_for * Model mo * Hist h i need i end → ?( Vec f ) {
    ? != # i h 0 {
        ?? ( __an_hist_tail h need end ) {
            T t → { ^ @ ?( Vec f ) { T t } }
            F → {}
        }
    } {}
    ^ ( __an_window_tail mo need end )
}

// Score `p` as though it sat at ring position `end` — the point's own slot,
// exclusive: rows [0, end) are its past and everything from `end` on is
// future the verdict must not see.
@ __an_score_enc_upto * Model mo EncPoint p i end → Verdict {
    : *Meta mm . mo meta
    : ( Vec f ) x ( anomaly_project p . mm feats )
    ( scaler_apply . mo sc x )
    : AeModel cae . mo ae
    : ~ ( Vec f ) araw ( vec_new [f] )
    ? & . cae trained ! . mo ae_stale {
        ( vec_free [f] araw )
        = araw ( anomaly_project p . cae feats )
    } {}
    ^ ( __an_score_core mo x araw end # *Hist 0 )
}

// Score ring row `at` out of an encoded history that covers it.
@ __an_score_hist * Model mo * Hist h i at → Verdict {
    : i r - at . h base
    : ( Vec f ) x ( __an_hist_row h at )
    : ( Vec f ) araw ( vec_with_cap [f] . h ae_nfeat )
    : *f ap ( vec_data [f] . h ae_x )
    : ~ i c 0
    ~ < c . h ae_nfeat { ( vec_push [f] araw . ap + * r . h ae_nfeat c ) = c + c 1 }
    ^ ( __an_score_core mo x araw at h )
}

// The verdict of a standardised point `x` (owned, freed here) sitting at
// ring position `end`, with `araw` its raw projection onto the
// autoencoder's feature order (owned; empty when the AE is untrained).
// `h` is an encoded history covering the rows involved, or null: with one,
// a forest's decision and the timevector window come out of it; without,
// they are computed here and read from the ring.
@ __an_score_core * Model mo ( Vec f ) x ( Vec f ) araw i end * Hist h → Verdict {
    : ( Vec VerVerdict ) vvs ( vec_new [VerVerdict] )
    : b warm >= ( vec_len [String] . mo lines ) . mo min_points
    ? & ( model_is_trained mo ) warm {} {
        ( vec_free [f] x )
        ( vec_free [f] araw )
        ^ @ Verdict { F F 0.0 0.0 vvs }
    }

    : *Meta mm . mo meta
    : i nfeat ( vec_len [String] . mm feats )
    : b hist != # i h 0

    : ~ b any F
    // `worst` is the aggregate score: the decision value of the version
    // that is most severe in its own margins (anom_severity).
    : ~ f worst 0.0
    : ~ f top_sev 0.0
    : ~ b first T
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                // A forest wider than one point is a timevector forest:
                // its input is the WINDOW ending at the current point
                // (W·nfeat features, W derived from the trained forest so
                // a config change cannot desync until the next retrain).
                : ~ f hdf 0.0
                : ~ b have F
                ? hist {
                    : i r - end . h base
                    ?? ( vec_get [( Vec i )] . h dfs_ok k ) {
                        T okv → {
                            ? & >= r 0 < r ( vec_len [i] okv ) {
                                ? == ( _mlp_iget okv r ) 1 {
                                    ?? ( vec_get [( Vec f )] . h dfs k ) {
                                        T dv → { = hdf ( _mlp_fget dv r ) = have T }
                                        F _ → {}
                                    }
                                } {}
                            } {}
                        }
                        F _ → {}
                    }
                } {}
                ? & > nfeat 0 != . vm n_cols nfeat {
                    : i W / . vm n_cols nfeat
                    : ~ ? ( Vec f ) tailo @ ?( Vec f ) { F }
                    ? have {
                        // The history scored this window already; an
                        // empty tail stands for it and is not walked.
                        = tailo @ ?( Vec f ) { T ( vec_new [f] ) }
                    } { = tailo ( __an_tail_for mo h - W 1 end ) }
                    ?? tailo {
                        T tail → {
                            ? have {} { ( vec_extend [f] tail x ) }
                            ? | have == ( vec_len [f] tail ) . vm n_cols {
                                : ~ f dfw hdf
                                ? have {} { = dfw ( anom_decision vm tail ) }
                                : f marginw ( meta_version_margin mm ( string_data . vm vname ) . vm margin )
                                : b hitw <= dfw - 0.0 marginw
                                ? hitw { = any T } {}
                                : f sevw ( anom_severity dfw marginw )
                                ? || first > sevw top_sev { = worst dfw = top_sev sevw } {}
                                = first F
                                ( vec_push [VerVerdict] vvs @ VerVerdict {
                                    ( string_from ( string_data . vm vname ) )
                                    hitw
                                    dfw
                                    marginw
                                    marginw
                                    -1
                                } )
                            } {}
                            ( vec_free [f] tail )
                        }
                        F → {}
                        // ring shorter than the window → the version has
                        // no verdict this time (absent, never wrong)
                    }
                } {
                    : ~ f df hdf
                    ? have {} { = df ( anom_decision vm x ) }
                    : f margin ( meta_version_margin mm ( string_data . vm vname ) . vm margin )
                    : b hit <= df - 0.0 margin
                    ? hit { = any T } {}
                    : f sev ( anom_severity df margin )
                    ? || first > sev top_sev { = worst df = top_sev sev } {}
                    = first F
                    ( vec_push [VerVerdict] vvs @ VerVerdict {
                        ( string_from ( string_data . vm vname ) )
                        hit
                        df
                        margin
                        margin
                        -1
                    } )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    // The range guard: the feature furthest from its training mean, in
    // standard deviations (`x` is already standardised). A forest sees a
    // point as a whole and a single reading at ten sigma is one coordinate
    // among many to it; this version is the univariate check the forests
    // structurally cannot make, and it names the feature. Its decision
    // value is -max|z|, so the margin IS the sigma count of the line.
    ? & ( meta_version_enabled mm ANOM_GUARD_NAME F ) > ( vec_len [f] . . mo sc mean ) 0 {
        : ~ f gz 0.0
        : ~ i gi -1
        : *f xp ( vec_data [f] x )
        : ~ i j 0
        ~ < j nfeat {
            : f az ( float_abs . xp j )
            ? | < gi 0 > az gz { = gz az = gi j } {}
            = j + j 1
        }
        : f gdf - 0.0 gz
        : f gmargin ( meta_version_margin mm ANOM_GUARD_NAME ANOM_GUARD_SIGMA )
        : b ghit <= gdf - 0.0 gmargin
        ? ghit { = any T } {}
        : f gsev ( anom_severity gdf gmargin )
        ? || first > gsev top_sev { = worst gdf = top_sev gsev } {}
        = first F
        ( vec_push [VerVerdict] vvs @ VerVerdict {
            ( string_from ANOM_GUARD_NAME )
            ghit
            gdf
            gmargin
            gmargin
            gi
        } )
    } {}

    // The flatline guard: the column that has stopped moving, if one has.
    ? ( meta_version_enabled mm ANOM_FLAT_NAME F ) {
        : FlatOut fo ( __an_flat_judge mo x end h )
        ? . fo ready {
            : f fdf - 0.0 . fo worst
            : f fmargin ( meta_version_margin mm ANOM_FLAT_NAME ANOM_FLAT_MARGIN )
            : b fhit <= fdf - 0.0 fmargin
            ? fhit { = any T } {}
            : f fsev ( anom_severity fdf fmargin )
            ? || first > fsev top_sev { = worst fdf = top_sev fsev } {}
            = first F
            ( vec_push [VerVerdict] vvs @ VerVerdict {
                ( string_from ANOM_FLAT_NAME )
                fhit
                fdf
                fmargin
                fmargin
                . fo feat
            } )
        } {}
    } {}

    // The autoencoder verdict: reconstruction error against the trained
    // threshold, on the point projected onto the AE's OWN frozen feature
    // order (independent of the forests' scaler and current feats). Muted
    // while its VerCfg is disabled — the net is kept, only the verdict
    // goes away, because re-training it is not a checkbox-priced action.
    : AeModel cae . mo ae
    ? & & . cae trained ! . mo ae_stale ( meta_version_enabled mm `autoencoder` T ) {
        : f adf ( ae_decision cae araw )
        : f arel ( meta_version_margin mm `autoencoder` ANOM_AE_MARGIN )
        : f amargin ( anom_ae_margin cae arel )
        : b ahit <= adf - 0.0 amargin
        ? ahit { = any T } {}
        : f asev ( anom_severity adf amargin )
        ? || first > asev top_sev { = worst adf = top_sev asev } {}
        = first F
        ( vec_push [VerVerdict] vvs @ VerVerdict {
            ( string_from `autoencoder` )
            ahit
            adf
            amargin
            arel
            -1
        } )
    } {}
    ( vec_free [f] araw )
    ( vec_free [f] x )
    ^ @ Verdict { T any worst top_sev vvs }
}

// The live-point entry: `ring_has_current` is 1 when the point being scored
// has already been appended to the ring (ingest) and 0 when it has not
// (detect_only).
@ __an_score_enc * Model mo EncPoint p i ring_has_current → Verdict {
    ^ ( __an_score_enc_upto mo p - ( vec_len [String] . mo lines ) ring_has_current )
}

// ── Training ──────────────────────────────────────────────────────────

// Retrain every enabled version from the ring, as of `now`. Re-encodes the
// raw ring (so new categories/columns learned since the last train enter
// the feature order), refreshes the authoritative feature order, refits the
// shared scaler over the full ring, then trains each version on its window.
// Returns the number of ring points used (0 = not enough data, no change).
@ model_force_train_at * Model mo i now → i {
    : *Meta mm . mo meta
    : i n ( vec_len [String] . mo lines )
    ? < n . mo min_points { ^ 0 } {}

    // A retrain re-encodes the whole ring, so it is where a model built
    // under an older calendar encoding moves to the current one.
    = . mm feat_enc ANOM_FEAT_ENC

    // Pass 1: re-encode every raw point (learning), tracking timestamps.
    : ( Vec EncPoint ) encs ( vec_new [EncPoint] )
    : ( Vec i ) ets ( vec_new [i] )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . mo lines k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → {
                        : !EncPoint String er ( anomaly_preprocess mm j )
                        ?? er {
                            T p → {
                                ( vec_push [EncPoint] encs p )
                                : ~ i ts 0
                                ?? ( vec_get [i] . mo times k ) { T t2 → { = ts t2 } F _ → {} }
                                ( vec_push [i] ets ts )
                            }
                            F e → { ( string_free e ) }
                        }
                        ( json_free j )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i ne ( vec_len [EncPoint] encs )
    ? < ne . mo min_points {
        ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )
        ( vec_free [i] ets )
        ^ 0
    } {}

    // The span these rows cover decides which calendar cycles the
    // feature order keeps (__an_cycle_seen); a count clock has no span.
    = . mm train_span 0
    ? . mm count_clock {} {
        : *i sp ( vec_data [i] ets )
        : ~ i tmin . sp 0
        : ~ i tmax . sp 0
        = k 1
        ~ < k ne {
            ? < . sp k tmin { = tmin . sp k } {}
            ? > . sp k tmax { = tmax . sp k } {}
            = k + k 1
        }
        = . mm train_span - tmax tmin
    }

    // Freeze the (possibly grown) feature order, project the full matrix.
    ( meta_refresh_feats mm )
    : i nfeat ( vec_len [String] . mm feats )
    ? <= nfeat 0 {
        ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )
        ( vec_free [i] ets )
        ^ 0
    } {}
    : ( Vec f ) big ( vec_with_cap [f] * ne nfeat )
    = k 0
    ~ < k ne {
        ?? ( vec_get [EncPoint] encs k ) {
            T p → {
                : ( Vec f ) row ( anomaly_project p . mm feats )
                ( vec_extend [f] big row )
                ( vec_free [f] row )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )

    // Shared scaler over the whole ring; standardise in place.
    : Scaler snew ( scaler_fit big ne nfeat )
    ( meta_set_scaler mm snew )
    ( scaler_free . mo sc )
    = . mo sc snew
    ( scaler_apply_matrix snew big ne nfeat )

    // Per enabled forest version: pick window rows, train, persist. The
    // `autoencoder` VerCfg is skipped — it has no forest (see
    // model_train_autoencoder), and training one under its name put a
    // second, empty "autoencoder" verdict beside the real one.
    ( __an_free_forests mo )
    ( store_delete_forest . mo store ( string_data . mo mname ) `autoencoder` )
    // The range guard needs nothing but the scaler just fitted; a model
    // from before it existed gains the version here, at its next retrain,
    // where the epoch bump and the metadata save happen anyway.
    ( __an_ensure_guard_cfg mo )
    ( __an_ensure_flat_cfg mo )
    ( __an_flat_fit mo big ne nfeat )
    : *f bigp ( vec_data [f] big )
    : *i etsp ( vec_data [i] ets )
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                ? & . vc enabled ! ( __an_forestless ( string_data . vc vname ) ) {
                    // Window: time filter first, then point cap, then the
                    // most-recent-min_points fallback.
                    : ~ i from 0
                    ? > . vc window_min 0 {
                        : i cutoff - now * . vc window_min 60
                        : ~ i j 0
                        ~ & < j ne < . etsp j cutoff { = j + j 1 }
                        = from j
                    } {}
                    ? > . vc window_pts 0 {
                        : i tail - ne . vc window_pts
                        ? > tail from { = from tail } {}
                    } {}
                    ? > - ne from . mo min_points {} {
                        = from - ne . mo min_points
                        ? < from 0 { = from 0 } {}
                    }
                    : i cnt - ne from

                    ? > . vc window_size 0 {
                        // timevector: flatten each run of W consecutive
                        // rows (stepped by S) into ONE window vector of
                        // W·nfeat features and train the forest on those.
                        // The ring is ingest-ordered (timestamps ascend),
                        // so consecutive rows ARE the time sequence.
                        : i W . vc window_size
                        : ~ i S . vc step_size
                        ? < S 1 { = S 1 } {}
                        ? >= cnt W {
                            : i nwin + / - cnt W S 1
                            : i wdim * W nfeat
                            : ( Vec f ) wins ( vec_with_cap [f] * nwin wdim )
                            : *f winp ( vec_data [f] wins )
                            : ~ i wi 0
                            ~ < wi nwin {
                                : i base + from * wi S
                                : ~ i r2 0
                                ~ < r2 W {
                                    : ~ i c2 0
                                    ~ < c2 nfeat {
                                        = . winp + * wi wdim + * r2 nfeat c2 . bigp + * + base r2 nfeat c2
                                        = c2 + c2 1
                                    }
                                    = r2 + r2 1
                                }
                                = wi + wi 1
                            }
                            ( vec_set_len [f] wins * nwin wdim )
                            : VerModel vm ( anom_train_version wins nwin wdim vc )
                            ( store_save_forest . mo store ( string_data . mo mname ) vm )
                            ( vec_push [VerModel] . mo forests vm )
                            ( vec_free [f] wins )
                        } {}
                        // cnt < W: too little data for one window — the
                        // version simply has no forest this round (its
                        // verdict is absent, never silently wrong).
                    } {
                        : ( Vec f ) sub ( vec_with_cap [f] * cnt nfeat )
                        : *f subp ( vec_data [f] sub )
                        : ~ i r 0
                        ~ < r cnt {
                            : ~ i c 0
                            ~ < c nfeat {
                                = . subp + * r nfeat c . bigp + * + from r nfeat c
                                = c + c 1
                            }
                            = r + r 1
                        }
                        ( vec_set_len [f] sub * cnt nfeat )

                        : VerModel vm ( anom_train_version sub cnt nfeat vc )
                        ( store_save_forest . mo store ( string_data . mo mname ) vm )
                        ( vec_push [VerModel] . mo forests vm )
                        ( vec_free [f] sub )
                    }
                } {}
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( vec_free [f] big )
    ( vec_free [i] ets )

    = . mm last_trained . mm n_seen
    = . mm trained_time ( now_seconds )
    ( meta_bump_epoch mm )
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    = . mo next_train_at + . mm n_seen ( __an_sched_step mo )
    = . mo ae_stale ( an_ae_stale mm . mo ae )
    ( __an_retrain_ae mo now )
    ^ ne
}

// The autoencoder's place in the retrain schedule. Its threshold is the
// p95 reconstruction error of the data it was trained on, and sensor data
// drifts: a net trained on one week's weather reconstructs the next week's
// worse across the board, so a never-retrained autoencoder ends up
// flagging everything, whatever the margin. Opting in (schedule.autoencoder)
// retrains it with the same hidden layout and pre-filter rate every time
// the forests retrain. Margins are never touched. Requires an existing
// trained net: the first training stays an explicit choice, because it
// fixes the layout.
// A trained autoencoder is stale when its frozen feature order names a
// feature the model's current encoding no longer produces — the calendar
// features changed shape in 0.14.0, and a cycle the training span has
// not seen twice is left out (see __an_cycle_seen). Projecting a point
// onto such an order fills the lost features with 0, which for a value
// that was never 0 in training is a reconstruction error thousands of
// times the threshold, on every point. A stale net does not score; the
// next forest retrain replaces it whether or not the schedule says so.
@ an_ae_stale * Meta mm AeModel ae → b {
    ? . ae trained {} { ^ F }
    : ( Vec String ) now ( meta_derived_feats mm )
    : i n ( vec_len [String] . ae feats )
    : ~ b stale F
    : ~ i k 0
    ~ & ! stale < k n {
        ?? ( vec_get [String] . ae feats k ) {
            T f → { ? < ( __an_find_str now ( string_data f ) ) 0 { = stale T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] now \ String x → v { ( string_free x ) } )
    ^ stale
}

@ __an_find_str ( Vec String ) v s name → i {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) {
            T c → { ? == ( nurl_str_eq ( string_data c ) name ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

@ __an_retrain_ae * Model mo i now → v {
    : *Meta mm . mo meta
    : AeModel cae . mo ae
    ? & . cae trained | . mm sched_ae . mo ae_stale {} { ^ }
    : ( Vec i ) hidden ( ae_hidden cae )
    : String err ( model_train_autoencoder_at mo hidden . cae prefilter now )
    ( vec_free [i] hidden )
    ( string_free err )
}

@ model_force_train * Model mo → i {
    ^ ( model_force_train_at mo ( model_now mo ) )
}

// ── The autoencoder version ───────────────────────────────────────────

// Ensure an `autoencoder` VerCfg exists in the metadata (margin tunable
// through the same machinery as the forest versions; window fields 0).
@ __an_ensure_ae_cfg * Model mo → v {
    : *Meta mm . mo meta
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) `autoencoder` ) 1 { ^ } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_push [VerCfg] . mm versions
    @ VerCfg { ( string_from `autoencoder` ) 0 0 0 0 0 0 -1.0 0.05 T } )
}

// ── The range guard version ───────────────────────────────────────────

// Ensure a `range_guard` VerCfg exists (SPEC §5.4): margin in standard
// deviations, tunable like any other, window fields 0 — it has no
// training of its own beyond the shared scaler.
@ __an_ensure_guard_cfg * Model mo → v {
    : *Meta mm . mo meta
    ? < ( meta_find_version mm ANOM_GUARD_NAME ) 0 {} { ^ }
    ( vec_push [VerCfg] . mm versions ( _an_vc_guard ) )
}

// ── The flatline guard version ────────────────────────────────────────

// Ensure a `flatline` VerCfg exists (SPEC §5.4) — a model from before the
// version gains it at its next retrain, where the references are fitted.
@ __an_ensure_flat_cfg * Model mo → v {
    : *Meta mm . mo meta
    ? < ( meta_find_version mm ANOM_FLAT_NAME ) 0 {} { ^ }
    ( vec_push [VerCfg] . mm versions ( _an_vc_flat ) )
}

// The configured window, in rows.
@ __an_flat_window * Meta mm → i {
    : i at ( meta_find_version mm ANOM_FLAT_NAME )
    ? >= at 0 {
        ?? ( vec_get [VerCfg] . mm versions at ) {
            T vc → { ? >= . vc window_size 2 { ^ . vc window_size } {} }
            F _ → {}
        }
    } {}
    ^ ANOM_FLAT_WINDOW
}

// The references are fitted when there is one per feature of the frozen
// order (the retrain refits them; an edit that changes the features
// bumps the epoch and retrains).
@ __an_flat_fitted * Model mo → b {
    : *Meta mm . mo meta
    : i nf ( vec_len [String] . mm feats )
    ^ & > nf 0 == ( vec_len [f] . mm flat_sd ) nf
}

// Fit the references from the standardised training matrix: per watched
// feature, the longest run of identical values, and the
// ANOM_FLAT_QUANTILE-th quantile of the window standard deviations (the
// stream's own quiet periods). A feature that is not a numeric column, or
// a ring shorter than the window, gets -1: not watched.
@ __an_flat_fit * Model mo ( Vec f ) big i n i nfeat → v {
    : *Meta mm . mo meta
    : i W ( __an_flat_window mm )
    : ( Vec i ) mask ( meta_numeric_feat_mask mm )
    : ( Vec f ) runs ( vec_with_cap [f] nfeat )
    : ( Vec f ) sds ( vec_with_cap [f] nfeat )
    : *f bp ( vec_data [f] big )
    : *i mp ( vec_data [i] mask )
    : ~ i j 0
    ~ < j nfeat {
        ? | == . mp j 0 < n W {
            ( vec_push [f] runs -1.0 )
            ( vec_push [f] sds -1.0 )
        } {
            : ~ i best 1
            : ~ i run 1
            : ~ i r 1
            ~ < r n {
                ? == . bp + * r nfeat j . bp + * - r 1 nfeat j { = run + run 1 } { = run 1 }
                ? > run best { = best run } {}
                = r + r 1
            }
            ( vec_push [f] runs # f best )
            // Window stds by a sliding sum; the values are standardised,
            // so the sums do not cancel badly.
            : ( Vec f ) wsd ( vec_with_cap [f] + - n W 1 )
            : ~ f sum 0.0
            : ~ f sq 0.0
            = r 0
            ~ < r n {
                : f v . bp + * r nfeat j
                = sum + sum v
                = sq + sq * v v
                ? >= r W {
                    : f o . bp + * - r W nfeat j
                    = sum - sum o
                    = sq - sq * o o
                } {}
                ? >= r - W 1 {
                    : f mean / sum # f W
                    : ~ f var - / sq # f W * mean mean
                    ? < var 0.0 { = var 0.0 } {}
                    ( vec_push [f] wsd ( sqrt var ) )
                } {}
                = r + r 1
            }
            ( sort_by [f] wsd \ f a f b → i {
                ? < a b { ^ -1 } {}
                ? > a b { ^ 1 } {}
                ^ 0
            } )
            ( vec_push [f] sds ( _an_percentile wsd ANOM_FLAT_QUANTILE ) )
            ( vec_free [f] wsd )
        }
        = j + j 1
    }
    ( vec_free [i] mask )
    ( vec_free [f] . mm flat_run )
    ( vec_free [f] . mm flat_sd )
    = . mm flat_run runs
    = . mm flat_sd sds
}

// Judge the standardised point `x` at ring position `end` (exclusive) —
// the window is the W−1 rows before it plus the point itself. Per watched
// feature: the run of values identical to this one, as a fraction of
// max(W, 2·reference run), and — when the window is not one value
// throughout — its std collapse below the reference, 1 − sd/ref (0 when
// the reference is 0: a column that never moved in training is not
// expected to). The larger of the two, over the features, is the
// verdict's fraction.
@ __an_flat_judge * Model mo ( Vec f ) x i end * Hist h → FlatOut {
    : *Meta mm . mo meta
    ? ( __an_flat_fitted mo ) {} { ^ @ FlatOut { F 0.0 -1 } }
    : i nfeat ( vec_len [String] . mm feats )
    : i W ( __an_flat_window mm )
    ?? ( __an_tail_for mo h - W 1 end ) {
        T tail → {
            ? == ( vec_len [f] tail ) * - W 1 nfeat {} {
                ( vec_free [f] tail )
                ^ @ FlatOut { F 0.0 -1 }
            }
            : *f tp ( vec_data [f] tail )
            : *f xp ( vec_data [f] x )
            : *f rrp ( vec_data [f] . mm flat_run )
            : *f rsp ( vec_data [f] . mm flat_sd )
            : ~ f worst 0.0
            : ~ i wf -1
            : ~ i j 0
            ~ < j nfeat {
                ? < . rrp j 0.0 {} {
                    : f cur . xp j
                    : ~ i run 1
                    : ~ b same T
                    : ~ i r - W 2
                    ~ & same >= r 0 {
                        ? == . tp + * r nfeat j cur { = run + run 1 } { = same F }
                        = r - r 1
                    }
                    : ~ f ref_run * 2.0 . rrp j
                    ? < ref_run # f W { = ref_run # f W } {}
                    : ~ f frac / # f run ref_run
                    // The collapse rule is for the sensor that hangs
                    // with dither; a window that is one value throughout
                    // is the run rule's case alone, so a column that sat
                    // flat in training (a rain gauge) answers to its own
                    // reference run and not to a spread of zero.
                    : f ref_sd . rsp j
                    ? & > ref_sd 0.0 < run W {
                        : ~ f sum cur
                        : ~ f sq * cur cur
                        = r 0
                        ~ < r - W 1 {
                            : f v . tp + * r nfeat j
                            = sum + sum v
                            = sq + sq * v v
                            = r + r 1
                        }
                        : f mean / sum # f W
                        : ~ f var - / sq # f W * mean mean
                        ? < var 0.0 { = var 0.0 } {}
                        : f collapse - 1.0 / ( sqrt var ) ref_sd
                        ? > collapse frac { = frac collapse } {}
                    } {}
                    ? | < wf 0 > frac worst { = worst frac = wf j } {}
                }
                = j + j 1
            }
            ( vec_free [f] tail )
            ? < wf 0 { ^ @ FlatOut { F 0.0 -1 } } {}
            ^ @ FlatOut { T worst wf }
        }
        F → { ^ @ FlatOut { F 0.0 -1 } }
    }
}

// Train the autoencoder from the ring: encode + project the raw points
// (the same pass model_force_train_at runs, minus the standardising
// scaler — the AE recipe MinMax-scales after anomaly filtering), then
// hand the matrix to ae_train_matrix. `hidden` empty → 64-32-64.
// Explicit by default; with `schedule.autoencoder` on, every forest
// retrain repeats it with the same layout and pre-filter (see
// __an_retrain_ae). Returns the error text ("" = success).
@ model_train_autoencoder * Model mo ( Vec i ) hidden f contamination → String {
    ^ ( model_train_autoencoder_at mo hidden contamination ( model_now mo ) )
}

@ model_train_autoencoder_at * Model mo ( Vec i ) hidden f contamination i now → String {
    : *Meta mm . mo meta
    : i n ( vec_len [String] . mo lines )
    ? < n . mo min_points { ^ ( string_from `not enough data points` ) } {}

    : ( Vec EncPoint ) encs ( vec_new [EncPoint] )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . mo lines k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → {
                        : !EncPoint String er ( anomaly_preprocess mm j )
                        ?? er {
                            T p → { ( vec_push [EncPoint] encs p ) }
                            F e → { ( string_free e ) }
                        }
                        ( json_free j )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i ne ( vec_len [EncPoint] encs )
    ? < ne . mo min_points {
        ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )
        ^ ( string_from `not enough decodable data points` )
    } {}

    // The net freezes its own feature order: what the metadata encodes
    // today, which may have grown past the forests' frozen order since
    // their last train. That order is theirs — refreshing it here would
    // shift the columns their scaler and trees were fitted to.
    : ( Vec String ) afeats ( meta_derived_feats mm )
    : i nfeat ( vec_len [String] afeats )
    ? <= nfeat 0 {
        ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )
        ( vec_free_with [String] afeats \ String x → v { ( string_free x ) } )
        ^ ( string_from `no numeric features` )
    } {}
    : ( Vec f ) raw ( vec_with_cap [f] * ne nfeat )
    = k 0
    ~ < k ne {
        ?? ( vec_get [EncPoint] encs k ) {
            T p → {
                : ( Vec f ) row ( anomaly_project p afeats )
                ( vec_extend [f] raw row )
                ( vec_free [f] row )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )

    : AeTrainOut out ( ae_train_matrix raw ne nfeat afeats hidden contamination . mo min_points )
    ( vec_free_with [String] afeats \ String x → v { ( string_free x ) } )
    ( vec_free [f] raw )
    : ~ AeModel nae . out ae
    ? . nae trained {
        = . nae trained_at now
        ( ae_free . mo ae )
        = . mo ae nae
        = . mo ae_stale F
        ( __an_ensure_ae_cfg mo )
        ( meta_bump_epoch mm )
        ( store_save_ae . mo store ( string_data . mo mname ) . mo ae )
        ( store_save_meta . mo store ( string_data . mo mname ) mm )
        ( string_free . out err )
        ^ ( string_new )
    } {
        ( ae_free nae )
        ^ . out err
    }
}

// ── Ingest / detect ───────────────────────────────────────────────────

// Add one raw point: encode (learning), stamp `timestamp`, append to the
// ring (evicting the oldest at capacity), persist, retrain if the schedule
// says so, then score it. Errors (bad numeric / timestamp values) leave the
// model completely untouched.
@ model_ingest_at * Model mo Json raw i now → !Verdict String {
    : *Meta mm . mo meta
    : !EncPoint String er ( anomaly_preprocess mm raw )
    ?? er {
        T p → {
            // Record the point: raw fields + server-side timestamp stamp.
            : Json rec ( json_clone raw )
            ( json_obj_set rec `timestamp` ( json_int now ) )
            : String line ( json_stringify rec )
            ( json_free rec )
            ( store_append_point . mo store ( string_data . mo mname ) ( string_data line ) )
            ( vec_push [String] . mo lines line )
            ( vec_push [i] . mo times now )
            = . mm n_seen + . mm n_seen 1

            // Ring eviction: drop the oldest beyond capacity, rewrite log.
            ? > ( vec_len [String] . mo lines ) . mo max_points {
                ?? ( vec_remove [String] . mo lines 0 ) {
                    T old → { ( string_free old ) }
                    F _ → {}
                }
                ?? ( vec_remove [i] . mo times 0 ) { T _ → {} F _ → {} }
                ( store_write_points . mo store ( string_data . mo mname ) . mo lines )
            } {}
            ( store_save_meta . mo store ( string_data . mo mname ) mm )

            // Schedule: lifetime counter reaching the mark retrains all.
            ? & >= . mm n_seen . mo next_train_at >= ( vec_len [String] . mo lines ) . mo min_points {
                ( model_force_train_at mo now )
            } {}

            : Verdict vd ( __an_score_enc mo p 1 )
            ( enc_free p )
            ^ @ !Verdict String { T vd }
        }
        F e → { ^ @ !Verdict String { F e } }
    }
}

@ model_ingest * Model mo Json raw → !Verdict String {
    : *Meta mm . mo meta
    ? . mm count_clock { ^ ( model_ingest_at mo raw ( model_next_tick mo ) ) } {}
    ^ ( model_ingest_at mo raw ( now_seconds ) )
}

// Score without ingesting: no metadata learning, no ring append, no
// retrain, no disk writes. Unknown columns/categories project to zeros;
// a column the trained model knows and the point leaves out is an
// error, named — a question about a point must carry the whole point.
@ model_detect_only * Model mo Json raw → !Verdict String {
    ? ( meta_is_frozen . mo meta ) {
        : ( Vec String ) miss ( anomaly_missing_cols . mo meta raw )
        ? > ( vec_len [String] miss ) 0 {
            : String names ( string_join miss `, ` )
            : String e ( string_from `Missing columns: ` )
            ( string_push_str e ( string_data names ) )
            ( string_push_str e `. A point to score carries every column the model knows; columns it does not know are ignored.` )
            ( string_free names )
            ( vec_free_with [String] miss \ String x → v { ( string_free x ) } )
            ^ @ !Verdict String { F e }
        } {}
        ( vec_free_with [String] miss \ String x → v { ( string_free x ) } )
    } {}
    : !EncPoint String er ( anomaly_preprocess_ro . mo meta raw )
    ?? er {
        T p → {
            : Verdict vd ( __an_score_enc mo p 0 )
            ( enc_free p )
            ^ @ !Verdict String { T vd }
        }
        F e → { ^ @ !Verdict String { F e } }
    }
}

// ── Importing a file of history ───────────────────────────────────────
//
// The ingest path is built for one point at a time: append, persist, and
// retrain whenever the schedule says so. Replaying ten thousand stored
// points through it would retrain two hundred times and rewrite the log
// once per point, which is not slow by accident — it is the streaming
// design being asked to do a bulk job.
//
// So importing has its own path. It differs in exactly three ways, and
// each is the reason it exists:
//
//   * the log is written ONCE at the end, not once per point;
//   * a point keeps the timestamp the FILE gave it, because history that
//     all lands at "now" is not history — every time window would see one
//     instant, and `seasonal` would be as blind as `short_term`;
//   * training happens once, after everything has landed.
//
// Ordering is the price of keeping those timestamps. The ring is assumed
// ingest-ordered — the window filters and the timevector windows all read
// it as a time sequence — so imported points cannot simply be appended.
// Both sides are sorted, so they are merged.

: ImpRow {
    i ir_ts
    String ir_line
}

@ __an_imp_cmp ImpRow a ImpRow b → i {
    ? < . a ir_ts . b ir_ts { ^ -1 } {}
    ? > . a ir_ts . b ir_ts { ^ 1 } {}
    ^ 0
}

: ImportReport {
    i accepted
    i rejected
    i stored  // points in the ring afterwards
    b trained
    String err  // non-empty ⇒ nothing was imported
    ( Vec String ) notes
}

@ import_report_free ImportReport r → v {
    ( string_free . r err )
    ( vec_free_with [String] . r notes \ String s → v { ( string_free s ) } )
}

// The timestamp a record carries, or 0 when it names none. A number is
// unix seconds; a string is left to the preprocessing layer, which knows
// ISO-8601 — but a point still needs a position in the ring, so a record
// timestamped only by a string is placed by the fallback.
@ __an_imp_ts Json rec → i {
    ?? ( json_obj_get rec `timestamp` ) {
        T v → {
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
        }
        F _ → {}
    }
    ^ 0
}

// Import `recs` into the model. Records keep their own `timestamp` when
// they carry one; the rest are placed at `now`. On the count clock a
// record's own stamp is ignored: the file's order is its time, and the
// rows take the ticks after the newest stored point, one each. Returns
// what happened.
@ model_import_at * Model mo ( Vec Json ) recs i now → ImportReport {
    : *Meta mm . mo meta
    : ~ i tick ( model_next_tick mo )
    : i nrec ( vec_len [Json] recs )
    ? > nrec 0 {} {
        ^ @ ImportReport { 0 0 ( vec_len [String] . mo lines ) F
            ( string_from `nothing to import` ) ( vec_new [String] ) }
    }

    : ( Vec ImpRow ) fresh ( vec_new [ImpRow] )
    : ( Vec String ) notes ( vec_new [String] )
    : ~ i rejected 0
    : ~ i k 0
    ~ < k nrec {
        ?? ( vec_get [Json] recs k ) {
            T rec → {
                // Preprocessing is what LEARNS: columns, categories and
                // their order all come from the records as they arrive, so
                // an import teaches the model its shape exactly as a stream
                // would.
                : !EncPoint String er ( anomaly_preprocess mm rec )
                ?? er {
                    T p → {
                        ( enc_free p )
                        : i given ( __an_imp_ts rec )
                        : ~ i ts ? > given 0 given now
                        ? . mm count_clock { = ts tick = tick + tick ANOM_TICK } {}
                        : Json out ( json_clone rec )
                        ( json_obj_set out `timestamp` ( json_int ts ) )
                        : String line ( json_stringify out )
                        ( json_free out )
                        ( vec_push [ImpRow] fresh @ ImpRow { ts line } )
                    }
                    F e → {
                        = rejected + rejected 1
                        ? < ( vec_len [String] notes ) 5 {
                            : String m ( string_from `row ` )
                            ( string_push_int m + k 1 )
                            ( string_push_str m `: ` )
                            ( string_push_str m ( string_data e ) )
                            ( vec_push [String] notes m )
                        } {}
                        ( string_free e )
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }

    : i accepted ( vec_len [ImpRow] fresh )
    ? > accepted 0 {} {
        ( vec_free [ImpRow] fresh )
        ^ @ ImportReport { 0 rejected ( vec_len [String] . mo lines ) F
            ( string_from `no row could be read as a data point` ) notes }
    }
    ( sort_by [ImpRow] fresh \ ImpRow a ImpRow b → i { ^ ( __an_imp_cmp a b ) } )

    // Merge with the ring. Both sides are ordered, so this is one pass —
    // and it is a merge rather than an append because an import of last
    // year's history must land before this morning's points, not after
    // them.
    : i have ( vec_len [String] . mo lines )
    : ~ ( Vec String ) mlines ( vec_with_cap [String] + have accepted )
    : ~ ( Vec i ) mtimes ( vec_with_cap [i] + have accepted )
    : ~ i a 0
    : ~ i b 0
    ~ | < a have < b accepted {
        : ~ i ta 9223372036854775807
        : ~ i tb 9223372036854775807
        ? < a have { ?? ( vec_get [i] . mo times a ) { T x → { = ta x } F _ → {} } } {}
        ? < b accepted { ?? ( vec_get [ImpRow] fresh b ) { T r → { = tb . r ir_ts } F _ → {} } } {}
        ? <= ta tb {
            ?? ( vec_get [String] . mo lines a ) {
                T l → { ( vec_push [String] mlines ( string_from ( string_data l ) ) ) }
                F _ → {}
            }
            ( vec_push [i] mtimes ta )
            = a + a 1
        } {
            ?? ( vec_get [ImpRow] fresh b ) {
                T r → {
                    ( vec_push [String] mlines ( string_from ( string_data . r ir_line ) ) )
                    ( vec_push [i] mtimes . r ir_ts )
                }
                F _ → {}
            }
            = b + b 1
        }
    }
    ( vec_free_with [ImpRow] fresh \ ImpRow r → v { ( string_free . r ir_line ) } )

    // Ring eviction: the OLDEST go, which after a merge may well be
    // imported ones. A file bigger than the ring is a file whose tail is
    // what the model keeps.
    : ~ i drop - ( vec_len [String] mlines ) . mo max_points
    ? > drop 0 {
        : ( Vec String ) kl ( vec_new [String] )
        : ( Vec i ) kt ( vec_new [i] )
        : i tot ( vec_len [String] mlines )
        : ~ i j drop
        ~ < j tot {
            ?? ( vec_get [String] mlines j ) {
                T l → { ( vec_push [String] kl ( string_from ( string_data l ) ) ) }
                F _ → {}
            }
            ?? ( vec_get [i] mtimes j ) { T x → { ( vec_push [i] kt x ) } F _ → {} }
            = j + j 1
        }
        ( __an_free_lines mlines )
        ( vec_free [i] mtimes )
        = mlines kl
        = mtimes kt
    } {}

    ( __an_free_lines . mo lines )
    ( vec_free [i] . mo times )
    = . mo lines mlines
    = . mo times mtimes
    = . mm n_seen + . mm n_seen accepted

    // One write for the whole file, not one per point.
    ( store_write_points . mo store ( string_data . mo mname ) . mo lines )
    ( store_save_meta . mo store ( string_data . mo mname ) mm )

    // And one train, if there is now enough to train on. An import that
    // doubles a model's history should not leave it scoring against the
    // forests it had before.
    : ~ b trained F
    ? >= ( vec_len [String] . mo lines ) . mo min_points {
        // On the count clock the present moved with the import.
        : i tnow ? . mm count_clock ( model_now mo ) now
        ? > ( model_force_train_at mo tnow ) 0 { = trained T } {}
    } {}
    ^ @ ImportReport { accepted rejected ( vec_len [String] . mo lines ) trained
        ( string_new ) notes }
}

@ model_import * Model mo ( Vec Json ) recs → ImportReport {
    ^ ( model_import_at mo recs ( model_now mo ) )
}

// ── Calibration and fine-tuning ───────────────────────────────────────
//
// Every version answers "anomaly?" with the same rule, `decision_function
// <= -margin`, but nobody can tell from the number 0.16 how many alerts it
// buys: the decision scale is data-dependent for a forest (and with
// contamination "auto" the zero line is too), and the autoencoder's margin
// is a fraction of a threshold nobody remembers. What a person can reason
// about is a RATE — "one point in a hundred" — so calibration turns the
// decision values of a recent window into that currency: for each version
// it sorts the values and reads off (a) how many the current margin flags
// and (b) the margin that would flag any requested fraction. Fine-tuning is
// then nothing more than calibrating and writing the margin for one target
// rate back, rounded to three significant digits, because a margin that
// separates two neighbouring points to 17 digits is not a setting, it is a
// fingerprint of one particular ring.
//
// Units are each version's OWN margin units (a forest's absolute decision
// value; the autoencoder's `(threshold − mse) / threshold`, so its
// relative margin drops straight in), which is what makes the numbers here
// directly editable in the metadata.

// One version's decision values over the calibration window.
: CalVer {
    String cvname
    f cur_margin  // the configured margin (own units)
    i n  // rows this version had a verdict for
    i flagged  // rows the current margin flags
    f worst  // the most negative decision value
    f median
    ( Vec f ) dfs  // ascending
}

: CalReport {
    ( Vec CalVer ) items
    i from_ts  // resolved window (0 = unbounded)
    i to_ts
    i n_rows  // rows scored
    i agg_flagged  // rows some enabled version flagged at the current margins
    i excluded  // rows in the window left out: labelled false positives
}

@ cal_free CalReport rep → v {
    ( vec_free_with [CalVer] . rep items \ CalVer x → v {
        ( string_free . x cvname )
        ( vec_free [f] . x dfs )
    } )
}

// Round to `digits` significant decimal digits, through an exact integer
// mantissa and a power of ten so the result is the double nearest to the
// short decimal (the same double the literal "0.106" parses to — division
// by an exactly representable power of ten is correctly rounded), and
// therefore prints as that short decimal.
@ round_sig f x i digits → f {
    ^ ( round_sig_dir x digits 0 )
}

// `dir` picks the rounding: 0 nearest, -1 toward zero, +1 away from zero
// (on the magnitude; the sign is restored afterwards).
@ round_sig_dir f x i digits i dir → f {
    ? == x 0.0 { ^ 0.0 } {}
    : f ax ( float_abs x )
    : i e # i ( float_floor ( float_log10 ax ) )
    : i p - - digits 1 e
    : ~ f m 0.0
    ? >= p 0 {
        : f scale ( float_pow 10.0 # f p )
        : f scaled * ax scale
        : f q ? < dir 0 ( float_floor scaled ) ? > dir 0 ( float_ceil scaled ) ( float_round scaled )
        = m / q scale
    } {
        : f scale ( float_pow 10.0 # f - 0 p )
        : f scaled / ax scale
        : f q ? < dir 0 ( float_floor scaled ) ? > dir 0 ( float_ceil scaled ) ( float_round scaled )
        = m * q scale
    }
    ^ ? < x 0.0 - 0.0 m m
}

// Rows the version would flag at `margin`: count of dfs <= -margin.
@ cal_flagged_at CalVer cv f margin → i {
    : i n ( vec_len [f] . cv dfs )
    : *f dp ( vec_data [f] . cv dfs )
    : f line - 0.0 margin
    : ~ i c 0
    ~ & < c n <= . dp c line { = c + c 1 }
    ^ c
}

// The margin at which a fraction `rate` of the window is flagged. The
// request is k = round(rate·n) rows; the margins a sorted list of decision
// values can supply are its gaps, so when the k-th most negative value is
// one of a run of TIES (a stuck sensor, a categorical feed, a forest that
// gives one path length to whole days of identical points) the request
// falls inside the run and only its two edges are achievable: everything
// before the run, or the run entire. The closer edge to k wins — a run of
// 221 equal values at k = 10 is answered with the 9 rows before it, not
// with 231 — and on a tie between the edges the run is flagged, so the
// request is at least met. rate 0 asks for a margin just above the worst
// point. The chosen margin is then rounded to the FEWEST significant
// digits (2 to 6) that still flag the chosen count, give or take a tenth
// of it — a margin is a setting a person reads and retypes, and "0.13" is
// one where the data allows it, "0.1284" where the decision values are
// packed too densely for fewer digits. Never negative: a negative margin
// would flag points the forest itself calls normal, and a rate the data
// cannot supply is answered by the honest count next to the margin, not
// by a margin below zero.
@ cal_margin_for_rate CalVer cv f rate → f {
    : i n ( vec_len [f] . cv dfs )
    ? <= n 0 { ^ . cv cur_margin } {}
    : *f dp ( vec_data [f] . cv dfs )
    : ~ f r rate
    ? < r 0.0 { = r 0.0 } {}
    ? > r 1.0 { = r 1.0 } {}
    : ~ i k # i ( float_round * r # f n )
    ? > k n { = k n } {}
    // The run of ties the k-th value sits in: [lo, hi] inclusive.
    : ~ i kt k
    : ~ b incl T
    ? > k 0 {
        : f tv . dp - k 1
        : ~ i lo - k 1
        ~ & > lo 0 == . dp - lo 1 tv { = lo - lo 1 }
        : ~ i hi - k 1
        ~ & < + hi 1 n == . dp + hi 1 tv { = hi + hi 1 }
        : i whole + hi 1
        = incl <= - whole k - k lo
        = kt ? incl whole lo
    } {}
    : ~ f exact 0.0
    ? <= kt 0 {
        // Just above the worst point, by a hair that survives rounding.
        : f w - 0.0 . dp 0
        = exact + w + * ( float_abs w ) 0.000000001 0.000000000001
    } {
        = exact - 0.0 . dp - kt 1
    }
    ? < exact 0.0 { ^ 0.0 } {}
    : i tol / kt 10
    // Nearest first at each precision, then the rounding that stays on
    // the chosen side of the run: a smaller margin flags more, so it is
    // the one to try when the run was taken (the other way would drop it
    // whole); a larger one when it was left out (and for rate 0, which
    // flags none).
    : i lean ? & incl > kt 0 -1 1
    : ~ i digits 2
    ~ < digits 6 {
        : f m ( round_sig exact digits )
        : i off - ( cal_flagged_at cv m ) kt
        ? & >= off - 0 tol <= off tol { ^ m } {}
        : f m2 ( round_sig_dir exact digits lean )
        : i off2 - ( cal_flagged_at cv m2 ) kt
        ? & >= off2 - 0 tol <= off2 tol { ^ m2 } {}
        = digits + digits 1
    }
    // Values packed tighter than five digits resolve: six digits, and the
    // reported count says how far off that lands.
    ^ ( round_sig_dir exact 6 lean )
}

@ __an_cal_find ( Vec CalVer ) items s name → i {
    : i n ( vec_len [CalVer] items )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [CalVer] items k ) {
            T cv → { ? == ( nurl_str_eq ( string_data . cv cvname ) name ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

// Score every ring row in [from_ts, to_ts] (0 = unbounded) through the
// live verdict path and collect each version's decision values. Rows are
// scored as of their own ring position, exactly as the scan does, so a
// timevector window never sees the future.
@ model_calibrate * Model mo i from_ts i to_ts → CalReport {
    : ( Vec CalVer ) items ( vec_new [CalVer] )
    : ~ i n_rows 0
    : ~ i agg 0
    ? ( model_is_trained mo ) {} { ^ @ CalReport { items from_ts to_ts 0 0 0 } }

    // A row a reader has called a false positive is left out: a margin
    // fitted over it would be paid for by known noise.
    : ( Vec Label ) labels ( model_labels mo )
    : ( Vec i ) label_of ( model_label_map mo labels )
    : ~ i excluded 0

    : *Meta mm . mo meta
    : AeModel cae . mo ae
    : f athr . cae threshold
    : i n ( vec_len [String] . mo lines )
    // The window's rows, encoded once and scored by every forest at once;
    // the ring is ingest-ordered, so the window is one contiguous span.
    : ~ i lo 0
    : ~ i hi n
    ? > from_ts 0 {
        : ~ i q 0
        : ~ b run T
        ~ & run < q n {
            : ~ i t 0
            ?? ( vec_get [i] . mo times q ) { T x → { = t x } F _ → {} }
            ? < t from_ts { = q + q 1 } { = run F }
        }
        = lo q
    } {}
    ? > to_ts 0 {
        : ~ i q lo
        : ~ b run T
        ~ & run < q n {
            : ~ i t 0
            ?? ( vec_get [i] . mo times q ) { T x → { = t x } F _ → {} }
            ? <= t to_ts { = q + q 1 } { = run F }
        }
        = hi q
    } {}
    : *Hist h ( __an_hist_build mo + - lo ( __an_hist_width mo ) 1 hi )
    : ~ i k lo
    ~ < k hi {
        : ~ i ts 0
        ?? ( vec_get [i] . mo times k ) { T t → { = ts t } F _ → {} }
        : ~ b inside & || <= from_ts 0 >= ts from_ts || <= to_ts 0 <= ts to_ts
        ? & inside ( _an_label_is labels ( _mlp_iget label_of k ) ANOM_LABEL_FP ) { = inside F = excluded + excluded 1 } {}
        ? & inside == ( _mlp_iget . h ok - k . h base ) 1 {
            : Verdict vd ( __an_score_hist mo h k )
            ? . vd ready {
                = n_rows + n_rows 1
                ? . vd anomaly { = agg + agg 1 } {}
                : i nvv ( vec_len [VerVerdict] . vd versions )
                : ~ i q 0
                ~ < q nvv {
                    ?? ( vec_get [VerVerdict] . vd versions q ) {
                        T vv → {
                            : s nm ( string_data . vv vvname )
                            : b is_ae == ( nurl_str_eq nm `autoencoder` ) 1
                            : ~ f own . vv score
                            ? & is_ae > athr 0.0 { = own / own athr } {}
                            : ~ i at ( __an_cal_find items nm )
                            ? < at 0 {
                                = at ( vec_len [CalVer] items )
                                ( vec_push [CalVer] items @ CalVer {
                                    ( string_from nm ) . vv cfg_margin 0 0 0.0 0.0 ( vec_new [f] )
                                } )
                            } {}
                            ?? ( vec_get [CalVer] items at ) {
                                T cv → { ( vec_push [f] . cv dfs own ) }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = q + q 1
                }
            } {}
            ( verdict_free vd )
        } {}
        = k + k 1
    }
    ( __an_hist_free h )

    // Sort, then read the summary numbers off the sorted values.
    : i ni ( vec_len [CalVer] items )
    = k 0
    ~ < k ni {
        ?? ( vec_get [CalVer] items k ) {
            T cv → {
                : ~ CalVer u cv
                ( sort_by [f] . u dfs \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
                : i nd ( vec_len [f] . u dfs )
                = . u n nd
                ? > nd 0 {
                    : *f dp ( vec_data [f] . u dfs )
                    = . u worst . dp 0
                    = . u median . dp / nd 2
                } {}
                = . u flagged ( cal_flagged_at u . u cur_margin )
                ( vec_set [CalVer] items k u )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [i] label_of )
    ( labels_free labels )
    ^ @ CalReport { items from_ts to_ts n_rows agg excluded }
}

// The window fine-tune and calibration default to: the newest 24 hours of
// stored data, anchored on the newest stored point rather than the clock,
// so a model whose feed stopped still calibrates on its last day.
: i ANOM_CAL_WINDOW 86400

// Resolve (from, to, last) the way the HTTP layer spells it: `last` seconds
// back from `to`, or from the newest stored point when `to` is unbounded.
@ model_window_from_last * Model mo i to_ts i last → i {
    ? <= last 0 { ^ 0 } {}
    : ~ i anchor to_ts
    ? > anchor 0 {} {
        : i np ( model_n_points mo )
        ? > np 0 {
            ?? ( vec_get [i] . mo times - np 1 ) { T x → { = anchor x } F _ → {} }
        } {}
    }
    // A window reaching past the beginning of time is the whole ring (0).
    ? > anchor 0 { : i f - anchor last ^ ? > f 0 f 0 } { ^ 0 }
}

// One version's fine-tune outcome.
: FtVer {
    String ftname
    f old_margin
    f new_margin
    i n  // rows in the window with a verdict
    i before  // flagged at old_margin
    i after  // flagged at new_margin
    f worst
    b applied  // F on a dry run, or when the version was filtered out
    i ft_from  // the window's lower bound this version was tuned over
    i ft_n_rows  // ring rows inside that window
}

: FineTuneReport {
    ( Vec FtVer ) items
    f rate
    i from_ts
    i to_ts
    i n_rows
    b applied
    i excluded  // labelled false positives left out of the window
}

@ finetune_free FineTuneReport rep → v {
    ( vec_free_with [FtVer] . rep items \ FtVer x → v { ( string_free . x ftname ) } )
}

// Set every enabled, trained version's margin so that a fraction `rate` of
// the window [from_ts, to_ts] is flagged, or only report what would change
// when `apply` is F. `only` (empty = all) restricts which versions are
// written; the rest are still reported, unapplied, so a dry run and a
// partial apply show the same picture. Margins are written in the
// version's own units, rounded to three significant digits, and take
// effect at the next detect. The flatline guard is left out: its margin
// is a fraction with a fixed meaning (SPEC §5.4), and a stuck sensor is
// not a 1 % property of a window — set it with the version editor.
@ model_finetune_at * Model mo f rate i from_ts i to_ts b apply ( Vec String ) only → FineTuneReport {
    : ( Vec FtVer ) items ( vec_new [FtVer] )
    : CalReport cal ( model_calibrate mo from_ts to_ts )
    : i ni ( vec_len [CalVer] . cal items )
    : ~ i k 0
    ~ < k ni {
        ?? ( vec_get [CalVer] . cal items k ) {
            T cv → {
                : s nm ( string_data . cv cvname )
                ? ( _an_is_flat_name nm ) {} {
                    : f nm_new ( cal_margin_for_rate cv rate )
                    : ~ b wanted T
                    : i nonly ( vec_len [String] only )
                    ? > nonly 0 {
                        = wanted F
                        : ~ i q 0
                        ~ < q nonly {
                            ?? ( vec_get [String] only q ) {
                                T o → { ? == ( nurl_str_eq ( string_data o ) nm ) 1 { = wanted T } {} }
                                F _ → {}
                            }
                            = q + q 1
                        }
                    } {}
                    : ~ b did F
                    ? & apply wanted { = did ( model_set_margin mo nm nm_new ) } {}
                    ( vec_push [FtVer] items @ FtVer {
                        ( string_from nm )
                        . cv cur_margin
                        nm_new
                        . cv n
                        . cv flagged
                        ( cal_flagged_at cv nm_new )
                        . cv worst
                        did
                        from_ts
                        . cal n_rows
                    } )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nr . cal n_rows
    : i nex . cal excluded
    ( cal_free cal )
    ^ @ FineTuneReport { items rate from_ts to_ts nr apply nex }
}

// The lower bound of a version's OWN window, anchored on the newest stored
// point: window_min minutes back for a forest version, window_size points
// back for timevector, and the whole ring (0) for the autoencoder, whose
// training set is the whole ring too.
@ model_version_from * Model mo s vname → i {
    : *Meta mm . mo meta
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) vname ) 1 {
                    ? > . vc window_min 0 {
                        // On a count clock the window is exactly window_min
                        // points; the lower bound is inclusive, so the span
                        // is one tick short (as `last=N` is in the service).
                        : ~ i span * . vc window_min 60
                        ? . mm count_clock { = span - span ANOM_TICK } {}
                        ^ ( model_window_from_last mo 0 span )
                    } {}
                    ? > . vc window_size 0 {
                        : i np ( model_n_points mo )
                        : i at - np . vc window_size
                        ? > at 0 { ?? ( vec_get [i] . mo times at ) { T x → { ^ x } F _ → {} } } {}
                    } {}
                    ^ 0
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ 0
}

// Fine-tune every version over ITS OWN window — the one it trains on —
// so short_term's margin answers for the last three hours and seasonal's
// for the last ninety days, each at the same rate. One calibration per
// version; the report's window is the widest of them.
@ model_finetune_own * Model mo f rate b apply ( Vec String ) only → FineTuneReport {
    : ( Vec FtVer ) items ( vec_new [FtVer] )
    : ( Vec String ) names ( model_scan_versions mo )
    : i nn ( vec_len [String] names )
    : ~ i lo 0
    : ~ b first T
    : ~ i rows 0
    : ~ i excluded 0
    : ~ i k 0
    ~ < k nn {
        ?? ( vec_get [String] names k ) {
            T nm → {
                : i from_ts ( model_version_from mo ( string_data nm ) )
                : ( Vec String ) one ( vec_new [String] )
                ( vec_push [String] one ( string_from ( string_data nm ) ) )
                : ~ b wanted T
                : i nonly ( vec_len [String] only )
                ? > nonly 0 {
                    = wanted F
                    : ~ i q 0
                    ~ < q nonly {
                        ?? ( vec_get [String] only q ) {
                            T o → { ? == ( nurl_str_eq ( string_data o ) ( string_data nm ) ) 1 { = wanted T } {} }
                            F _ → {}
                        }
                        = q + q 1
                    }
                } {}
                : FineTuneReport part ( model_finetune_at mo rate from_ts 0 & apply wanted one )
                : i np ( vec_len [FtVer] . part items )
                : ~ i j 0
                ~ < j np {
                    ?? ( vec_get [FtVer] . part items j ) {
                        T ft → {
                            ? == ( nurl_str_eq ( string_data . ft ftname ) ( string_data nm ) ) 1 {
                                : ~ FtVer c ft
                                = . c ftname ( string_from ( string_data . ft ftname ) )
                                ( vec_push [FtVer] items c )
                                ? | first < from_ts lo { = lo from_ts = first F } {}
                                ? > . part n_rows rows { = rows . part n_rows = excluded . part excluded } {}
                            } {}
                        }
                        F _ → {}
                    }
                    = j + j 1
                }
                ( finetune_free part )
                ( vec_free_with [String] one \ String x → v { ( string_free x ) } )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ^ @ FineTuneReport { items rate lo 0 rows apply excluded }
}

// ── Labels ────────────────────────────────────────────────────────────
//
// A reader's word on a stored point (store.nu: Label). Points are
// addressed by ring index at the API and by lifetime sequence number on
// disk; the base of the ring is n_seen minus the rows it holds.

@ model_seq_base * Model mo → i {
    : *Meta mm . mo meta
    ^ - . mm n_seen ( vec_len [String] . mo lines )
}

// Record what a reader said about the row at `index`. Returns the row's
// sequence number, -1 for an index outside the ring, -2 for a label
// that is not one of ANOM_LABEL_*. Verdicts do not change, so the epoch
// does not move.
@ model_label_point * Model mo i index s label s by s note i at → i {
    ? ( label_known label ) {} { ^ -2 }
    : i n ( vec_len [String] . mo lines )
    ? | < index 0 >= index n { ^ -1 } {}
    : i seq + ( model_seq_base mo ) index
    : ~ i ts 0
    ?? ( vec_get [i] . mo times index ) { T t → { = ts t } F _ → {} }
    : Label l @ Label { seq ts ( string_from label ) ( string_from by ) at ( string_from note ) }
    : b ok ( store_append_label . mo store ( string_data . mo mname ) l )
    ( label_free l )
    ^ ? ok seq -1
}

// The labels in force (store_load_labels), evicted rows included.
@ model_labels * Model mo → ( Vec Label ) {
    ^ ( store_load_labels . mo store ( string_data . mo mname ) )
}

// Per ring position, the index into `labels` of its label, -1 for none.
@ model_label_map * Model mo ( Vec Label ) labels → ( Vec i ) {
    : i n ( vec_len [String] . mo lines )
    : i base ( model_seq_base mo )
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n { ( vec_push [i] out -1 ) = k + k 1 }
    : i nl ( vec_len [Label] labels )
    = k 0
    ~ < k nl {
        ?? ( vec_get [Label] labels k ) {
            T l → {
                : i idx - . l seq base
                ? & >= idx 0 < idx n { : b _s ( vec_set [i] out idx k ) } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// Does label `li` of `labels` (as model_label_map hands it out) say `what`?
@ _an_label_is ( Vec Label ) labels i li s what → b {
    ? < li 0 { ^ F } {}
    ?? ( vec_get [Label] labels li ) {
        T l → { ^ == ( nurl_str_eq ( string_data . l label ) what ) 1 }
        F _ → { ^ F }
    }
}

// The one-call form: 1 % of the last 24 hours, applied to every version.
: f ANOM_FT_RATE 0.01

// A `last` as a caller says it — seconds on a time clock, points on a count
// clock — as the span model_window_from_last takes. N points back from the
// newest is N ticks INCLUDING it, so the span is one short of N whole ticks.
@ model_last_span * Model mo i last → i {
    : *Meta mm . mo meta
    ? & . mm count_clock > last 0 { ^ - * last ANOM_TICK 1 } {}
    ^ last
}

// The default window: a day, or its worth of points (1440) on a count clock.
@ model_default_last * Model mo → i {
    : *Meta mm . mo meta
    ^ ? . mm count_clock / ANOM_CAL_WINDOW ANOM_TICK ANOM_CAL_WINDOW
}

@ model_finetune * Model mo → FineTuneReport {
    : i from_ts ( model_window_from_last mo 0 ( model_last_span mo ( model_default_last mo ) ) )
    : ( Vec String ) none ( vec_new [String] )
    : FineTuneReport rep ( model_finetune_at mo ANOM_FT_RATE from_ts 0 T none )
    ( vec_free [String] none )
    ^ rep
}

// ── Training on everything at once ────────────────────────────────────
//
// A model fed by a stream trains itself as points arrive, each version
// over its own window back from "now". A model built from a FILE — a
// batch analysis, or a fork of another model's history — has no present:
// the data is the whole world, and the stock windows (three hours, a
// day, a week, ninety days back from the newest stamp) would each miss
// most of it and fall back to the last fifty rows, a forest that
// saturates on everything else. So every window opens to the whole ring,
// every forest trains once, the autoencoder trains over the
// forest-filtered points, and every margin is set so `rate` of the data
// is flagged. The result is a model that describes the data it was given.

: WholeTrain {
    Json margins  // version name → decision margin, as fine-tune set it
    Json notes  // strings: what could not be done, and why
}

@ whole_train_free WholeTrain w → v {
    ( json_free . w margins )
    ( json_free . w notes )
}

//
// The windows are opened for this one training only: the version
// configuration the model keeps is the one it was given (its own, or the
// source's when it is a fork), so a fork that goes on receiving points
// retrains its short_term over three hours like its source, not over
// everything it has ever seen. The autoencoder takes `hidden` as its
// layout (empty = the 64-16-64 default) and `rate` as its pre-filter.
@ model_train_whole * Model mo f rate ( Vec i ) hidden → WholeTrain {
    : *Meta mm . mo meta
    : i nv ( vec_len [VerCfg] . mm versions )
    : ( Vec i ) wmins ( vec_with_cap [i] nv )
    : ( Vec i ) wptss ( vec_with_cap [i] nv )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                ( vec_push [i] wmins . vc window_min )
                ( vec_push [i] wptss . vc window_pts )
                : ~ VerCfg o vc
                = . o window_min 0
                = . o window_pts 0
                : b _o ( vec_set [VerCfg] . mm versions vi o )
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( model_force_train_at mo ( model_last_ts mo ) )
    = vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                : ~ VerCfg o vc
                = . o window_min ( _mlp_iget wmins vi )
                = . o window_pts ( _mlp_iget wptss vi )
                : b _o ( vec_set [VerCfg] . mm versions vi o )
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( vec_free [i] wmins )
    ( vec_free [i] wptss )
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    : Json notes ( json_arr_new )
    : ( Vec i ) layout ( vec_new [i] )
    ? > ( vec_len [i] hidden ) 0 { ( vec_extend [i] layout hidden ) } {
        ( vec_push [i] layout 64 )
        ( vec_push [i] layout 16 )
        ( vec_push [i] layout 64 )
    }
    : String aerr ( model_train_autoencoder mo layout rate )
    ( vec_free [i] layout )
    ? > ( string_len aerr ) 0 {
        : String m ( string_from `autoencoder not trained: ` )
        ( string_push_str m ( string_data aerr ) )
        ( json_arr_push notes ( json_str_lit ( string_data m ) ) )
        ( string_free m )
    } {}
    ( string_free aerr )
    : ( Vec String ) none ( vec_new [String] )
    : FineTuneReport ft ( model_finetune_at mo rate 0 0 T none )
    ( vec_free [String] none )
    : Json margins ( json_obj_new )
    : i nft ( vec_len [FtVer] . ft items )
    : ~ i k 0
    ~ < k nft {
        ?? ( vec_get [FtVer] . ft items k ) {
            T fv → { ( json_obj_set margins ( string_data . fv ftname ) ( json_float . fv new_margin ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ( finetune_free ft )
    // The flatline guard keeps its configured margin (finetune leaves it
    // alone); it is reported so the list is every version that judged.
    ? & ( meta_version_enabled . mo meta ANOM_FLAT_NAME F ) ( __an_flat_fitted mo ) {
        ( json_obj_set margins ANOM_FLAT_NAME ( json_float ( meta_version_margin . mo meta ANOM_FLAT_NAME ANOM_FLAT_MARGIN ) ) )
    } {}
    ^ @ WholeTrain { margins notes }
}

// ── Scanning the stored ring ──────────────────────────────────────────
//
// The dashboard's job is "show me which of my stored points are
// anomalies", and the honest way to answer it is to score every stored
// point. Doing that one /detect_only at a time costs a full model load
// (metadata + ring + every forest blob) per point, which is why the naive
// loop is quadratic in the ring. model_scan_at loads the model once and
// scores in one pass, with the epoch-stamped cache underneath: on a second
// visit nothing is recomputed at all unless the model actually changed.

// One scored ring point.
: ScoredPt {
    i sp_idx  // ring index
    i sp_ts  // ingest timestamp (unix seconds)
    f sp_score  // aggregate decision_function (the most severe version)
    f sp_severity  // that version's severity — comparable across rows
    b sp_anomaly
    i sp_present  // bitmask over ScanOut.vnames: versions that had a verdict
    i sp_flagged  // bitmask over ScanOut.vnames: versions that flagged it
}

: ScanOut {
    ( Vec ScoredPt ) pts
    ( Vec String ) vnames
    i epoch
    i total  // ring size
    i considered  // rows inside the requested time window
    i hits  // verdicts answered from the cache
    i misses  // verdicts computed this call
    i anomalies  // anomalous rows among `considered`
}

// ── Runs ──────────────────────────────────────────────────────────────
//
// Calibration is a marginal quantile: 1 % of rows flagged says nothing
// about whether they are 1 % of the rows scattered singly or one burst
// of consecutive rows — and a burst is one event to whoever reads the
// list. A run is a maximal sequence of consecutive stored rows every one
// of which counts as an anomaly (with `minvotes` versions agreeing, see
// scan_agreed); the scan reports each row's run and the runs
// themselves, so a hundred flagged rows can read as three events.

// Does a scored row count as an anomaly when `minvotes` versions have
// to agree? The bit count of the flagged mask is the vote.
@ scan_agreed ScoredPt r i minvotes → b {
    ? . r sp_anomaly {} { ^ F }
    : ~ i votes 0
    : ~ i m . r sp_flagged
    ~ != m 0 {
        ? != & m 1 0 { = votes + votes 1 } {}
        = m >> m 1
    }
    ^ >= votes minvotes
}

: ScanRun {
    i run  // 1-based, in ring order
    i first_k  // positions in ScanOut.pts
    i last_k
    i rows
    i worst_k  // the row with the highest severity
    f worst_sev
    i flagged  // union of the rows' flagged masks
}

: ScanRuns {
    ( Vec ScanRun ) runs
    ( Vec i ) run_of  // per position in ScanOut.pts: its run, 0 = none
}

@ scan_runs ScanOut so i minvotes → ScanRuns {
    : i np ( vec_len [ScoredPt] . so pts )
    : ( Vec ScanRun ) runs ( vec_new [ScanRun] )
    : ( Vec i ) run_of ( vec_with_cap [i] np )
    : ~ b in_run F
    : ~ i k 0
    ~ < k np {
        : ~ i id 0
        ?? ( vec_get [ScoredPt] . so pts k ) {
            T r → {
                ? ( scan_agreed r minvotes ) {
                    ? in_run {
                        : i last - ( vec_len [ScanRun] runs ) 1
                        ?? ( vec_get [ScanRun] runs last ) {
                            T cur → {
                                : ~ ScanRun u cur
                                = . u last_k k
                                = . u rows + . u rows 1
                                = . u flagged | . u flagged . r sp_flagged
                                ? > . r sp_severity . u worst_sev { = . u worst_k k = . u worst_sev . r sp_severity } {}
                                : b _s ( vec_set [ScanRun] runs last u )
                            }
                            F _ → {}
                        }
                    } {
                        ( vec_push [ScanRun] runs @ ScanRun {
                            + ( vec_len [ScanRun] runs ) 1 k k 1 k . r sp_severity . r sp_flagged
                        } )
                    }
                    = in_run T
                    = id ( vec_len [ScanRun] runs )
                } { = in_run F }
            }
            F _ → { = in_run F }
        }
        ( vec_push [i] run_of id )
        = k + k 1
    }
    ^ @ ScanRuns { runs run_of }
}

@ scan_runs_free ScanRuns sr → v {
    ( vec_free [ScanRun] . sr runs )
    ( vec_free [i] . sr run_of )
}

@ scan_free ScanOut so → v {
    ( vec_free [ScoredPt] . so pts )
    ( vec_free_with [String] . so vnames \ String x → v { ( string_free x ) } )
}

// The canonical version order a scan's bitmasks are indexed by: every
// enabled version that could produce a verdict, in metadata order. It is
// stable within an epoch by construction — anything that adds, removes or
// toggles a version bumps the epoch — and it is written into the cache so a
// mismatch is caught rather than silently misread as different versions.
@ model_scan_versions * Model mo → ( Vec String ) {
    : *Meta mm . mo meta
    : AeModel cae . mo ae
    : ( Vec String ) out ( vec_new [String] )
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? . vc enabled {
                    : s nm ( string_data . vc vname )
                    ? == ( nurl_str_eq nm `autoencoder` ) 1 {
                        ? & . cae trained ! . mo ae_stale { ( vec_push [String] out ( string_from nm ) ) } {}
                    } { ? ( _an_is_guard_name nm ) {
                            ? > ( vec_len [f] . . mo sc mean ) 0 { ( vec_push [String] out ( string_from nm ) ) } {}
                        } { ? ( _an_is_flat_name nm ) {
                                ? ( __an_flat_fitted mo ) { ( vec_push [String] out ( string_from nm ) ) } {}
                            } {
                                : ~ b has F
                                : i nf ( vec_len [VerModel] . mo forests )
                                : ~ i j 0
                                ~ < j nf {
                                    ?? ( vec_get [VerModel] . mo forests j ) {
                                        T vm → {
                                            ? == ( nurl_str_eq ( string_data . vm vname ) nm ) 1 { = has T } {}
                                        }
                                        F _ → {}
                                    }
                                    = j + j 1
                                }
                                ? has { ( vec_push [String] out ( string_from nm ) ) } {}
                            } } }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

@ __an_vname_bit ( Vec String ) vnames s nm → i {
    : i n ( vec_len [String] vnames )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] vnames k ) {
            T a → { ? == ( nurl_str_eq ( string_data a ) nm ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

// Score ring row `at` out of the encoded history `h`, returning the
// verdict folded into cache words. `at` is the row being scored, so the
// ring entries AFTER it are the future: a timevector window ends at `at`,
// not at the ring tip.
@ __an_scan_row * Model mo * Hist h ( Vec String ) vnames i at → ScoredPt {
    : ~ i st ANOM_SC_NOT_READY
    : ~ f sc 0.0
    : ~ f sv 0.0
    : ~ b anom F
    : ~ i pres 0
    : ~ i flag 0
    : i r - at . h base
    ? & >= r 0 < r . h n {
        ? == ( _mlp_iget . h ok r ) 1 {
            : Verdict vd ( __an_score_hist mo h at )
            ? . vd ready {
                = st ANOM_SC_SCORED
                = sc . vd score
                = sv . vd severity
                = anom . vd anomaly
                : i nvv ( vec_len [VerVerdict] . vd versions )
                : ~ i q 0
                ~ < q nvv {
                    ?? ( vec_get [VerVerdict] . vd versions q ) {
                        T vv → {
                            : i bit ( __an_vname_bit vnames ( string_data . vv vvname ) )
                            ? >= bit 0 {
                                = pres | pres << 1 bit
                                ? . vv anomaly { = flag | flag << 1 bit } {}
                            } {}
                        }
                        F _ → {}
                    }
                    = q + q 1
                }
            } {}
            ( verdict_free vd )
        } {}
    } {}
    : ~ i ts 0
    ?? ( vec_get [i] . mo times at ) { T t → { = ts t } F _ → {} }
    ^ @ ScoredPt { at ts sc sv anom pres flag }
}

// Score every ring point whose timestamp falls in [from_ts, to_ts]
// (0 = unbounded on either side), newest-last, capped at `limit` rows
// (<= 0 = no cap) taken from the END of the window. `force` recomputes
// even when the cache is warm — the escape hatch for verifying the cache
// itself, never needed for correctness.
@ model_scan_at * Model mo i from_ts i to_ts i limit b force → ScanOut {
    : *Meta mm . mo meta
    : ( Vec String ) vnames ( model_scan_versions mo )
    : i total ( vec_len [String] . mo lines )
    : i epoch . mm score_epoch
    : i base - . mm n_seen total

    // Load the cache, keeping it only if it is stamped with this epoch and
    // the same version order. Anything else starts empty.
    : ~ ScoreCache cache ( scorecache_new epoch base )
    : ~ i cbase base
    ?? ( store_load_scores . mo store ( string_data . mo mname ) ) {
        T got → {
            : b same_epoch == . got epoch epoch
            : b same_vers ( scorecache_vnames_match got vnames )
            ? & & same_epoch same_vers == force F {
                ( scorecache_free cache )
                = cache got
                = cbase . got base_seen
            } { ( scorecache_free got ) }
        }
        F → {}
    }

    // Rows in the requested time window. The ring is ingest-ordered, so
    // both bounds are a prefix scan: skip while below `from_ts`, advance
    // while at or below `to_ts`. An unparsable line stamps timestamp 0 and
    // therefore falls outside any bounded window, which is the safe side.
    : ~ i lo 0
    : ~ i hi total
    ? > from_ts 0 {
        : ~ i k 0
        : ~ b run T
        ~ & run < k total {
            : ~ i t 0
            ?? ( vec_get [i] . mo times k ) { T x → { = t x } F _ → {} }
            ? < t from_ts { = k + k 1 } { = run F }
        }
        = lo k
    } {}
    ? > to_ts 0 {
        : ~ i k lo
        : ~ b run T
        ~ & run < k total {
            : ~ i t 0
            ?? ( vec_get [i] . mo times k ) { T x → { = t x } F _ → {} }
            ? <= t to_ts { = k + k 1 } { = run F }
        }
        = hi k
    } {}
    ? < hi lo { = hi lo } {}
    : i considered - hi lo
    ? > limit 0 {
        ? > considered limit { = lo - hi limit } {}
    } {}

    : ( Vec ScoredPt ) pts ( vec_new [ScoredPt] )
    : ~ i hits 0
    : ~ i misses 0
    : ~ i anoms 0
    : ~ b dirty F
    // The rows the misses need, encoded once — on the first miss, so a scan
    // the cache answers in full parses nothing. A timevector window reaches
    // back width−1 rows before the first row in the window.
    : ~ * Hist h # *Hist 0
    : ~ i j lo
    ~ < j hi {
        // Cache index of ring row j: lifetime index minus the cache's base.
        : i ci - + base j cbase
        : ~ b hit F
        : ~ i st ANOM_SC_UNSCORED
        : ~ f sc 0.0
        : ~ f sv 0.0
        : ~ i pres 0
        : ~ i flag 0
        ? & >= ci 0 < ci ( scorecache_rows cache ) {
            ?? ( vec_get [i] . cache state ci ) {
                T stv → {
                    ? != stv ANOM_SC_UNSCORED {
                        = hit T
                        = st stv
                        ?? ( vec_get [f] . cache score ci ) { T x → { = sc x } F _ → {} }
                        ?? ( vec_get [f] . cache severity ci ) { T x → { = sv x } F _ → {} }
                        ?? ( vec_get [i] . cache present ci ) { T x → { = pres x } F _ → {} }
                        ?? ( vec_get [i] . cache flagged ci ) { T x → { = flag x } F _ → {} }
                    } {}
                }
                F _ → {}
            }
        } {}
        : ~ i ts 0
        ?? ( vec_get [i] . mo times j ) { T x → { = ts x } F _ → {} }
        ? hit {
            = hits + hits 1
            : b scored == st ANOM_SC_SCORED
            : b anom & scored != flag 0
            ? anom { = anoms + anoms 1 } {}
            ( vec_push [ScoredPt] pts @ ScoredPt { j ts sc sv anom pres flag } )
        } {
            = misses + misses 1
            ? == # i h 0 { = h ( __an_hist_build mo + - lo ( __an_hist_width mo ) 1 hi ) } {}
            : ScoredPt row ( __an_scan_row mo h vnames j )
            ? . row sp_anomaly { = anoms + anoms 1 } {}
            ( vec_push [ScoredPt] pts row )
            = dirty T
        }
        = j + j 1
    }

    // Fold what we computed back into a full ring-length cache and persist
    // it, so the next scan of ANY window benefits from this one.
    ? dirty {
        : ScoreCache nc ( scorecache_new epoch base )
        ( scorecache_resize nc total )
        : ~ i k 0
        ~ < k total {
            : i ci - + base k cbase
            ? & >= ci 0 < ci ( scorecache_rows cache ) {
                : ~ i st ANOM_SC_UNSCORED
                : ~ f sc 0.0
                : ~ f sv 0.0
                : ~ i pres 0
                : ~ i flag 0
                ?? ( vec_get [i] . cache state ci ) { T x → { = st x } F _ → {} }
                ?? ( vec_get [f] . cache score ci ) { T x → { = sc x } F _ → {} }
                ?? ( vec_get [f] . cache severity ci ) { T x → { = sv x } F _ → {} }
                ?? ( vec_get [i] . cache present ci ) { T x → { = pres x } F _ → {} }
                ?? ( vec_get [i] . cache flagged ci ) { T x → { = flag x } F _ → {} }
                ( scorecache_set nc k st sc sv pres flag )
            } {}
            = k + k 1
        }
        : i np ( vec_len [ScoredPt] pts )
        = k 0
        ~ < k np {
            ?? ( vec_get [ScoredPt] pts k ) {
                T r → {
                    : ~ i st ANOM_SC_NOT_READY
                    ? != . r sp_present 0 { = st ANOM_SC_SCORED } {}
                    ( scorecache_set nc . r sp_idx st . r sp_score . r sp_severity . r sp_present . r sp_flagged )
                }
                F _ → {}
            }
            = k + k 1
        }
        : i nvn ( vec_len [String] vnames )
        = k 0
        ~ < k nvn {
            ?? ( vec_get [String] vnames k ) {
                T nm → { ( vec_push [String] . nc vnames ( string_from ( string_data nm ) ) ) }
                F _ → {}
            }
            = k + k 1
        }
        : b _w ( store_save_scores . mo store ( string_data . mo mname ) nc )
        ( scorecache_free nc )
    } {}
    ( scorecache_free cache )
    ( __an_hist_free h )

    ^ @ ScanOut { pts vnames epoch total considered hits misses anoms }
}

@ model_scan * Model mo i from_ts i to_ts i limit b force → ScanOut {
    ^ ( model_scan_at mo from_ts to_ts limit force )
}

// The raw stored record at a ring index, parsed (None when out of range or
// no longer parsable).
@ model_point_json * Model mo i at → ?Json {
    ?? ( vec_get [String] . mo lines at ) {
        T l → {
            : !Json JsonError jr ( json_parse ( string_data l ) )
            ?? jr {
                T j → { ^ @ ?Json { T j } }
                F _ → { ^ @ ?Json { F } }
            }
        }
        F _ → { ^ @ ?Json { F } }
    }
}

// ── Why a point is a relational anomaly ───────────────────────────────

// One feature's share of an autoencoder reconstruction error, with the
// value the point carried and the one the autoencoder expected of it
// given the other features (raw units — the MinMax undone).
: AeContrib {
    String ac_name
    f ac_err
    f ac_share
    f ac_value
    f ac_expected
}

@ ae_contrib_free ( Vec AeContrib ) xs → v {
    ( vec_free_with [AeContrib] xs \ AeContrib c → v { ( string_free . c ac_name ) } )
}

// The `topk` features carrying the most of a point's reconstruction error,
// largest first, with each one's share of the total. This is the answer
// the forests structurally cannot give: the autoencoder's per-feature error
// is how badly that feature failed to be predictable FROM THE OTHERS, so
// the top entries name the broken relationship rather than the extreme
// value. Empty when the model has no trained autoencoder.
@ model_ae_contrib * Model mo Json raw i topk → ( Vec AeContrib ) {
    : ( Vec AeContrib ) out ( vec_new [AeContrib] )
    : AeModel cae . mo ae
    ? & . cae trained ! . mo ae_stale {} { ^ out }
    : !EncPoint String er ( anomaly_preprocess_ro . mo meta raw )
    ?? er {
        T p → {
            : ( Vec f ) araw ( anomaly_project p . cae feats )
            : ( Vec f ) errs ( ae_feature_errors cae araw )
            : ( Vec f ) recon ( ae_reconstruct cae araw )
            ( enc_free p )
            : i d ( vec_len [f] errs )
            : ~ f tot 0.0
            : ~ i k 0
            ~ < k d {
                ?? ( vec_get [f] errs k ) { T e → { = tot + tot e } F _ → {} }
                = k + k 1
            }
            : ~ i want topk
            ? < want 1 { = want 1 } {}
            ? > want d { = want d } {}
            // Selection sort over `want` picks: d is the feature count, and
            // want is 3-5, so this beats sorting the whole vector.
            : ( Vec b ) taken ( vec_new [b] )
            = k 0
            ~ < k d { ( vec_push [b] taken F ) = k + k 1 }
            : ~ i picked 0
            ~ < picked want {
                : ~ i best -1
                : ~ f bestv -1.0
                = k 0
                ~ < k d {
                    : ~ b used T
                    ?? ( vec_get [b] taken k ) { T x → { = used x } F _ → {} }
                    ? used {} {
                        : ~ f e 0.0
                        ?? ( vec_get [f] errs k ) { T x → { = e x } F _ → {} }
                        ? > e bestv { = bestv e = best k } {}
                    }
                    = k + k 1
                }
                ? < best 0 { = picked want } {
                    : b _t ( vec_set [b] taken best T )
                    : ~ f share 0.0
                    ? > tot 0.0 { = share / bestv tot } {}
                    : ~ String nm ( string_new )
                    ?? ( vec_get [String] . cae feats best ) {
                        T x → { ( string_free nm ) = nm ( string_from ( string_data x ) ) }
                        F _ → {}
                    }
                    : f val ( _mlp_fget araw best )
                    : f exp ( _mlp_fget recon best )
                    ( vec_push [AeContrib] out @ AeContrib { nm bestv share val exp } )
                    = picked + picked 1
                }
            }
            ( vec_free [b] taken )
            ( vec_free [f] errs )
            ( vec_free [f] recon )
            ( vec_free [f] araw )
        }
        F e → { ( string_free e ) }
    }
    ^ out
}

// ── Management ────────────────────────────────────────────────────────

// Drop all data and trained forests but keep the model's name, schedule
// and version configs. Learned columns/categories/features/scaler reset.
@ model_reset * Model mo → v {
    : *Meta old . mo meta

    // Fresh metadata, carrying over identity + configuration.
    : *Meta fresh ( meta_new ( string_data . old name ) ( string_data . old created ) )
    = . fresh sched_below . old sched_below
    = . fresh sched_at_max . old sched_at_max
    = . fresh sched_ae . old sched_ae
    = . fresh count_clock . old count_clock
    // Carry the scoring epoch across the reset, bumped: cached verdicts for
    // the discarded points must never be mistaken for verdicts of the new
    // ones that will reuse their ring positions.
    = . fresh score_epoch + . old score_epoch 1
    ( vec_free_with [VerCfg] . fresh versions \ VerCfg vc → v { ( _an_vercfg_free vc ) } )
    = . fresh versions ( vec_new [VerCfg] )
    : i nv ( vec_len [VerCfg] . old versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . old versions vi ) {
            T vc → {
                ( vec_push [VerCfg] . fresh versions ( __an_vercfg_clone vc ) )
                // Remove the version's forest blob from disk as we go.
                ( store_delete_forest . mo store ( string_data . mo mname ) ( string_data . vc vname ) )
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( meta_free old )
    = . mo meta fresh

    ( __an_free_forests mo )
    ( __an_free_lines . mo lines )
    = . mo lines ( vec_new [String] )
    ( vec_free [i] . mo times )
    = . mo times ( vec_new [i] )
    ( scaler_free . mo sc )
    = . mo sc ( meta_scaler fresh )
    = . mo next_train_at . mo min_points

    : ( Vec String ) none ( vec_new [String] )
    ( store_write_points . mo store ( string_data . mo mname ) none )
    ( vec_free [String] none )
    // Sequence numbers start over with the ring, so labels keyed on the
    // old ones would name rows that never were.
    ( store_delete_labels . mo store ( string_data . mo mname ) )
    ( store_save_meta . mo store ( string_data . mo mname ) fresh )
}

// Delete a model from the store entirely (the Model handle, if any, should
// be freed separately with model_free).
@ model_delete Store st s name → b {
    ^ ( store_delete st name )
}

// Set one version's decision margin in the metadata (persisted, effective
// immediately at scoring — no retrain needed). Returns F for an unknown
// version name.
@ model_set_margin * Model mo s vname f margin → b {
    : *Meta mm . mo meta
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) vname ) 1 {
                    : ~ VerCfg upd vc
                    = . upd decision_margin margin
                    ( vec_set [VerCfg] . mm versions k upd )
                    ( meta_bump_epoch mm )
                    ( store_save_meta . mo store ( string_data . mo mname ) mm )
                    ^ T
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// Update the retraining schedule (persisted immediately).
@ model_set_schedule * Model mo i below_max i at_max → v {
    : *Meta mm . mo meta
    ? > below_max 0 { = . mm sched_below below_max } {}
    ? > at_max 0 { = . mm sched_at_max at_max } {}
    ? ( model_is_trained mo ) {
        = . mo next_train_at + . mm last_trained ( __an_sched_step mo )
    } {}
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
}

// ── Editing a live model's metadata ───────────────────────────────────

// Drop `vname`'s forest, in memory and on disk. A disabled version starts
// from scratch when it is re-enabled: keeping the blob would resurrect a
// forest trained against a feature order and scaler the model has since
// moved past, and a stale width reads as a timevector window at scoring
// time — a wrong verdict rather than an absent one.
@ __an_drop_forest * Model mo s vname → v {
    : ( Vec VerModel ) kept ( vec_new [VerModel] )
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                ? == ( nurl_str_eq ( string_data . vm vname ) vname ) 1 {
                    ( anom_vermodel_free vm )
                } { ( vec_push [VerModel] kept vm ) }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [VerModel] . mo forests )
    = . mo forests kept
    ( store_delete_forest . mo store ( string_data . mo mname ) vname )
}

// Every forest whose version is now off (or gone from the metadata) loses
// its blob. The autoencoder has no forest, so it is never touched here.
@ __an_prune_disabled * Model mo → v {
    : *Meta mm . mo meta
    : ( Vec String ) doomed ( vec_new [String] )
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                ? ( meta_version_enabled mm ( string_data . vm vname ) F ) {} {
                    ( vec_push [String] doomed ( string_from ( string_data . vm vname ) ) )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nd ( vec_len [String] doomed )
    = k 0
    ~ < k nd {
        ?? ( vec_get [String] doomed k ) {
            T d → { ( __an_drop_forest mo ( string_data d ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] doomed \ String x → v { ( string_free x ) } )
}

// Turn one version on or off (persisted immediately). Disabling drops the
// version's forest, so its verdict is gone from the very next detect and
// re-enabling it costs a retrain. The `autoencoder` version is only muted:
// its net carries its OWN frozen feature order, so it stays valid across
// retrains and is far too expensive to throw away on a checkbox. Returns F
// for an unknown version name.
@ model_set_version_enabled * Model mo s vname b on → b {
    : *Meta mm . mo meta
    : i at ( meta_find_version mm vname )
    ? < at 0 { ^ F } {}
    ?? ( vec_get [VerCfg] . mm versions at ) {
        T vc → {
            : ~ VerCfg upd vc
            = . upd enabled on
            : b _o ( vec_set [VerCfg] . mm versions at upd )
        }
        F _ → {}
    }
    ? on {} {
        ? ( __an_forestless vname ) {} { ( __an_drop_forest mo vname ) }
    }
    ( meta_bump_epoch mm )
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    ^ T
}

// Apply an editable-metadata patch:
//
//   { "alias": "boiler room",
//     "schedule": { "below_max": N, "at_max": N, "autoencoder": bool },
//     "max_data_points": N,
//     "versions": { "<name>": { <any VerCfg field> }, ... },
//     "replace_versions": bool }
//
// All top-level keys are optional but at least one must be present. The
// learned parts of the metadata (columns, categories, feature order,
// scaler) are never taken from the client — see prep.nu. Lowering
// `max_data_points` below the current fill evicts the oldest points and
// rewrites the log before returning, so the cap holds at once instead of
// converging one point per ingest. Per-version
// fields split two ways: `enabled` and `decision_margin` bite at the very
// next detect, the geometry and forest-size fields at the next retrain.
// Returns "" on success, else the reason (400-worthy).
// The top-level keys `model_apply_meta_patch` accepts, published with every
// metadata response so a client does not have to keep its own copy of the
// list. The dashboard kept one, and it went stale the moment
// `max_data_points` became editable: the field was patchable through the
// API and invisible in the JSON editor that exists to reach it. One list,
// named here beside the code that reads the patch, is what stops that from
// happening again — the editor is generated from it.
//
// Deliberately NOT part of `meta_to_json`: that is also the on-disk meta.json
// writer, and a service-shaped descriptor has no business in the stored file.
@ meta_editable_fields → Json {
    : Json a ( json_arr_new )
    ( json_arr_push a ( json_str_lit `alias` ) )
    ( json_arr_push a ( json_str_lit `clock` ) )
    ( json_arr_push a ( json_str_lit `schedule` ) )
    ( json_arr_push a ( json_str_lit `max_data_points` ) )
    ( json_arr_push a ( json_str_lit `versions` ) )
    ^ a
}

@ model_apply_meta_patch * Model mo Json patch → String {
    ? ( json_is_obj patch ) {} { ^ ( string_from `metadata must be a JSON object` ) }
    : *Meta mm . mo meta
    : ~ b touched F

    // The alias is a display name, nothing more: it never reaches the
    // store, the feature order or a file path, so unlike `name` it is free
    // to be edited, contain spaces, or be cleared back to empty.
    ?? ( json_obj_get patch `alias` ) {
        T aj → {
            ? ( json_is_str aj ) {} { ^ ( string_from `alias must be a string` ) }
            : s araw ( json_str_data aj )
            ? > ( nurl_str_len araw ) ANOM_ALIAS_MAX {
                ^ ( string_from `alias is too long (max 120 characters)` )
            } {}
            ( string_free . mm alias )
            = . mm alias ( string_from araw )
            = touched T
        }
        F _ → {}
    }

    ?? ( json_obj_get patch `schedule` ) {
        T sj → {
            ? ( json_is_obj sj ) {} { ^ ( string_from `schedule must be a JSON object` ) }
            : i below ( _an_jint sj `below_max` . mm sched_below )
            : i atmax ( _an_jint sj `at_max` . mm sched_at_max )
            ? & > below 0 > atmax 0 {} {
                ^ ( string_from `schedule.below_max and schedule.at_max must be positive` )
            }
            = . mm sched_below below
            = . mm sched_at_max atmax
            ?? ( json_obj_get sj `autoencoder` ) { T aj → { = . mm sched_ae ( json_as_bool aj ) } F _ → {} }
            = touched T
        }
        F _ → {}
    }

    ?? ( json_obj_get patch `clock` ) {
        T cj → {
            ? ( json_is_str cj ) {} { ^ ( string_from `clock must be "time" or "count"` ) }
            : s cs ( json_str_data cj )
            : ~ b want F
            ? == ( nurl_str_eq cs `count` ) 1 { = want T } {
                ? == ( nurl_str_eq cs `time` ) 1 {} { ^ ( string_from `clock must be "time" or "count"` ) }
            }
            ? == want . mm count_clock {} {
                // Ticks and wall-clock stamps must never share a ring.
                ? == ( vec_len [String] . mo lines ) 0 {} {
                    ^ ( string_from `clock can only change on a model with no stored points (reset it first)` )
                }
                = . mm count_clock want
                = touched T
            }
        }
        F _ → {}
    }

    ?? ( json_obj_get patch `max_data_points` ) {
        T _ → {
            : i mx ( _an_jint patch `max_data_points` . mm max_points )
            ? > mx 0 {} {
                ^ ( string_from `max_data_points must be positive` )
            }
            ? >= mx . mo min_points {} {
                ^ ( string_from `max_data_points must be at least min_points` )
            }
            = . mm max_points mx
            = . mo max_points mx
            : ~ b trimmed F
            ~ > ( vec_len [String] . mo lines ) mx {
                ?? ( vec_remove [String] . mo lines 0 ) {
                    T old → { ( string_free old ) }
                    F _ → {}
                }
                ?? ( vec_remove [i] . mo times 0 ) { T _ → {} F _ → {} }
                = trimmed T
            }
            ? trimmed {
                ( store_write_points . mo store ( string_data . mo mname ) . mo lines )
            } {}
            = touched T
        }
        F _ → {}
    }

    ?? ( json_obj_get patch `versions` ) {
        T vj → {
            : ~ b repl F
            ?? ( json_obj_get patch `replace_versions` ) {
                T rj → { = repl ( json_as_bool rj ) }
                F _ → {}
            }
            ? < ( meta_apply_versions_json mm vj repl ) 0 {
                ^ ( string_from `versions must be a JSON object of version configs` )
            } {}
            = touched T
        }
        F _ → {}
    }

    ? touched {} {
        ^ ( string_from `nothing to update: expected alias, schedule, max_data_points and/or versions` )
    }

    ( __an_prune_disabled mo )
    ? ( model_is_trained mo ) {
        = . mo next_train_at + . mm last_trained ( __an_sched_step mo )
    } {}
    ( meta_bump_epoch mm )
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    ^ ( string_new )
}
