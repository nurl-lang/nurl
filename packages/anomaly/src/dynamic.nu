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
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`

// ── Types ─────────────────────────────────────────────────────────────

// One version's slice of a verdict.
: VerVerdict {
    String vvname
    b anomaly
    f score
    f margin
}

// The aggregate verdict for one point (SPEC §5.4).
: Verdict {
    b ready
    b anomaly
    f score
    ( Vec VerVerdict ) versions
}

// A live dynamic model. Obtain with model_open, release with model_free.
: Model {
    Store store
    String mname
    *Meta meta
    ( Vec String ) lines
    ( Vec i ) times
    ( Vec VerModel ) forests
    Scaler sc
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
        . vc n_estimators
        . vc max_samples
        . vc contamination
        . vc decision_margin
        . vc enabled
    }
}

// Ingest timestamp of a stored data.jsonl line (0 if unparsable).
@ __an_line_ts s line → i {
    : !Json JsonError r ( json_parse line )
    ?? r {
        T j → {
            : i ts ( __an_jint j `timestamp` 0 )
            ( json_free j )
            ^ ts
        }
        F _ → { ^ 0 }
    }
}

@ __an_free_forests *Model mo → v {
    ( vec_free_with [VerModel] . mo forests \ VerModel vm → v { ( anom_vermodel_free vm ) } )
    = . mo forests ( vec_new [VerModel] )
}

@ __an_free_lines ( Vec String ) xs → v {
    ( vec_free_with [String] xs \ String x → v { ( string_free x ) } )
}

// The schedule step from the current ring fill: at capacity, retrain less.
@ __an_sched_step *Model mo → i {
    : *Meta mm . mo meta
    ? >= ( vec_len [String] . mo lines ) . mo max_points { ^ . mm sched_at_max } {}
    ^ . mm sched_below
}

// ── Lifecycle ─────────────────────────────────────────────────────────

// Open (or create) the named model in the store: load metadata, the point
// ring, and every trained version's forest. Create-on-first-use: a missing
// model is initialised with fresh metadata and persisted immediately.
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

    // Ring: adopt the stored lines wholesale, then stamp times from them.
    : ( Vec String ) pts ( store_load_points . mo store name )
    = . mo lines pts
    = . mo times ( vec_new [i] )
    : i np ( vec_len [String] pts )
    : ~ i k 0
    ~ < k np {
        ?? ( vec_get [String] pts k ) {
            T l → { ( vec_push [i] . mo times ( __an_line_ts ( string_data l ) ) ) }
            F _ → {}
        }
        = k + k 1
    }

    // Trained versions: one forest blob per enabled version, if present.
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                ? . vc enabled {
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

@ model_free *Model mo → v {
    ( __an_free_forests mo )
    ( vec_free [VerModel] . mo forests )
    ( __an_free_lines . mo lines )
    ( vec_free [i] . mo times )
    ( scaler_free . mo sc )
    ( meta_free . mo meta )
    ( string_free . mo mname )
    ( store_free . mo store )
    ( nurl_free mo )
}

// Test hook: shrink the warm-up / ring limits so eviction and scheduling
// are exercisable without 150 000 points.
@ model_set_limits *Model mo i min_pts i max_pts → v {
    = . mo min_points min_pts
    = . mo max_points max_pts
    ? == ( vec_len [VerModel] . mo forests ) 0 {
        = . mo next_train_at min_pts
    } {}
}

@ model_metadata *Model mo → *Meta {
    ^ . mo meta
}

@ model_n_points *Model mo → i {
    ^ ( vec_len [String] . mo lines )
}

@ model_is_trained *Model mo → b {
    ^ > ( vec_len [VerModel] . mo forests ) 0
}

// ── Scoring ───────────────────────────────────────────────────────────

// The live decision margin of a version comes from the CURRENT metadata,
// not from the forest blob — so margin changes (fine-tune, config PUT)
// take effect immediately, without a retrain. The blob's stored margin is
// only the fallback for versions no longer present in the metadata.
@ __an_margin_of *Meta mm s vname f dflt → f {
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) vname ) 1 {
                    ^ . vc decision_margin
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ dflt
}

// Score an encoded point against every trained version. `ready` is false
// until the model has trained at least once AND the ring holds min_points.
@ __an_score_enc *Model mo EncPoint p → Verdict {
    : ( Vec VerVerdict ) vvs ( vec_new [VerVerdict] )
    : b warm >= ( vec_len [String] . mo lines ) . mo min_points
    ? & ( model_is_trained mo ) warm {} {
        ^ @ Verdict { F F 0.0 vvs }
    }

    : *Meta mm . mo meta
    : ( Vec f ) x ( anomaly_project p . mm feats )
    ( scaler_apply . mo sc x )

    : ~ b any F
    : ~ f worst 0.0
    : ~ b first T
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                : f df ( anom_decision vm x )
                : f margin ( __an_margin_of mm ( string_data . vm vname ) . vm margin )
                : b hit <= df - 0.0 margin
                ? hit { = any T } {}
                ? || first < df worst { = worst df } {}
                = first F
                ( vec_push [VerVerdict] vvs @ VerVerdict {
                    ( string_from ( string_data . vm vname ) )
                    hit
                    df
                    margin
                } )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [f] x )
    ^ @ Verdict { T any worst vvs }
}

// ── Training ──────────────────────────────────────────────────────────

// Retrain every enabled version from the ring, as of `now`. Re-encodes the
// raw ring (so new categories/columns learned since the last train enter
// the feature order), refreshes the authoritative feature order, refits the
// shared scaler over the full ring, then trains each version on its window.
// Returns the number of ring points used (0 = not enough data, no change).
@ model_force_train_at *Model mo i now → i {
    : *Meta mm . mo meta
    : i n ( vec_len [String] . mo lines )
    ? < n . mo min_points { ^ 0 } {}

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

    // Per enabled version: pick window rows, train, persist.
    ( __an_free_forests mo )
    : *f bigp ( vec_data [f] big )
    : *i etsp ( vec_data [i] ets )
    : i nv ( vec_len [VerCfg] . mm versions )
    : ~ i vi 0
    ~ < vi nv {
        ?? ( vec_get [VerCfg] . mm versions vi ) {
            T vc → {
                ? . vc enabled {
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
                } {}
            }
            F _ → {}
        }
        = vi + vi 1
    }
    ( vec_free [f] big )
    ( vec_free [i] ets )

    = . mm last_trained . mm n_seen
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    = . mo next_train_at + . mm n_seen ( __an_sched_step mo )
    ^ ne
}

@ model_force_train *Model mo → i {
    ^ ( model_force_train_at mo ( now_seconds ) )
}

// ── Ingest / detect ───────────────────────────────────────────────────

// Add one raw point: encode (learning), stamp `timestamp`, append to the
// ring (evicting the oldest at capacity), persist, retrain if the schedule
// says so, then score it. Errors (bad numeric / timestamp values) leave the
// model completely untouched.
@ model_ingest_at *Model mo Json raw i now → !Verdict String {
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

            : Verdict vd ( __an_score_enc mo p )
            ( enc_free p )
            ^ @ !Verdict String { T vd }
        }
        F e → { ^ @ !Verdict String { F e } }
    }
}

@ model_ingest *Model mo Json raw → !Verdict String {
    ^ ( model_ingest_at mo raw ( now_seconds ) )
}

// Score without ingesting: no metadata learning, no ring append, no
// retrain, no disk writes. Unknown columns/categories project to zeros.
@ model_detect_only *Model mo Json raw → !Verdict String {
    : !EncPoint String er ( anomaly_preprocess_ro . mo meta raw )
    ?? er {
        T p → {
            : Verdict vd ( __an_score_enc mo p )
            ( enc_free p )
            ^ @ !Verdict String { T vd }
        }
        F e → { ^ @ !Verdict String { F e } }
    }
}

// ── Fine-tuning ───────────────────────────────────────────────────────

// One version's fine-tune outcome.
: FtVer {
    String ftname
    f min_score
    f old_margin
    f new_margin
}

: FineTuneReport {
    ( Vec FtVer ) items
}

@ finetune_free FineTuneReport rep → v {
    ( vec_free_with [FtVer] . rep items \ FtVer x → v { ( string_free . x ftname ) } )
}

// The ring, read-only encoded, projected onto the current feature order and
// standardised with the current scaler — the exact view scoring uses.
// Returns a row-major matrix of (result length / nfeat) rows.
@ __an_ring_scaled *Model mo → ( Vec f ) {
    : *Meta mm . mo meta
    : i nfeat ( vec_len [String] . mm feats )
    : ( Vec f ) big ( vec_new [f] )
    ? <= nfeat 0 { ^ big } {}
    : i n ( vec_len [String] . mo lines )
    : ~ i k 0
    ~ < k n {
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
                                ( vec_extend [f] big row )
                                ( vec_free [f] row )
                                ( enc_free p )
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
    ^ big
}

// Recalibrate every trained version's decision margin against the observed
// ring: margin becomes 95% of the magnitude of the most-negative
// decision_function over the ring, so the most anomalous point seen so far
// lands just inside the anomaly band. (This is the documented INTENT of the
// reference's finetune — its own accumulator never updates due to an
// inverted comparison against -inf, so it never adjusts anything; we
// implement what the code meant, in place, per SPEC §5.2.) Margins are
// persisted and take effect immediately. Returns per-version details.
@ model_finetune *Model mo → FineTuneReport {
    : ( Vec FtVer ) items ( vec_new [FtVer] )
    : *Meta mm . mo meta
    ? ( model_is_trained mo ) {} { ^ @ FineTuneReport { items } }

    : i nfeat ( vec_len [String] . mm feats )
    : ( Vec f ) big ( __an_ring_scaled mo )
    : ~ i rows 0
    ? > nfeat 0 { = rows / ( vec_len [f] big ) nfeat } {}
    ? <= rows 0 {
        ( vec_free [f] big )
        ^ @ FineTuneReport { items }
    } {}

    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i k 0
    ~ < k nf {
        ?? ( vec_get [VerModel] . mo forests k ) {
            T vm → {
                : ( Vec f ) dfs ( anom_decisions vm big rows nfeat )
                : *f dfp ( vec_data [f] dfs )
                : ~ f lowest 0.0
                : ~ b first T
                : ~ i r 0
                ~ < r rows {
                    ? || first < . dfp r lowest { = lowest . dfp r } {}
                    = first F
                    = r + r 1
                }
                ( vec_free [f] dfs )
                : f old ( __an_margin_of mm ( string_data . vm vname ) . vm margin )
                : f adjusted * ( float_abs lowest ) 0.95
                : b applied ( model_set_margin mo ( string_data . vm vname ) adjusted )
                ( vec_push [FtVer] items @ FtVer {
                    ( string_from ( string_data . vm vname ) )
                    lowest
                    old
                    adjusted
                } )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [f] big )
    ^ @ FineTuneReport { items }
}

// ── Management ────────────────────────────────────────────────────────

// Drop all data and trained forests but keep the model's name, schedule
// and version configs. Learned columns/categories/features/scaler reset.
@ model_reset *Model mo → v {
    : *Meta old . mo meta

    // Fresh metadata, carrying over identity + configuration.
    : *Meta fresh ( meta_new ( string_data . old name ) ( string_data . old created ) )
    = . fresh sched_below . old sched_below
    = . fresh sched_at_max . old sched_at_max
    ( vec_free_with [VerCfg] . fresh versions \ VerCfg vc → v { ( __an_vercfg_free vc ) } )
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
@ model_set_margin *Model mo s vname f margin → b {
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
@ model_set_schedule *Model mo i below_max i at_max → v {
    : *Meta mm . mo meta
    ? > below_max 0 { = . mm sched_below below_max } {}
    ? > at_max 0 { = . mm sched_at_max at_max } {}
    ? ( model_is_trained mo ) {
        = . mo next_train_at + . mm last_trained ( __an_sched_step mo )
    } {}
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
}
