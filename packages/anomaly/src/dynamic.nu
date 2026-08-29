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
$ `src/autoenc.nu`
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
    * Meta meta
    ( Vec String ) lines
    ( Vec i ) times
    ( Vec VerModel ) forests
    Scaler sc
    AeModel ae
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
@ __an_line_ts s line → i {
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

    // The autoencoder version, if one has been trained for this model.
    ?? ( store_load_ae . mo store name ) {
        T ae → { = . mo ae ae }
        F → { = . mo ae ( ae_empty ) }
    }

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
// The last window_size−1 ring points before the current one, projected and
// standardised, concatenated in time order — the sliding window's tail.
// `skip_last` skips the ring's newest entry (at ingest the current point is
// already IN the ring; at detect_only it is not). None when the ring is too
// short or a stored line no longer parses.
@ __an_window_tail * Model mo i need i skip_last → ?( Vec f ) {
    : *Meta mm . mo meta
    : i n - ( vec_len [String] . mo lines ) skip_last
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

@ __an_score_enc * Model mo EncPoint p i ring_has_current → Verdict {
    : ( Vec VerVerdict ) vvs ( vec_new [VerVerdict] )
    : b warm >= ( vec_len [String] . mo lines ) . mo min_points
    ? & ( model_is_trained mo ) warm {} {
        ^ @ Verdict { F F 0.0 vvs }
    }

    : *Meta mm . mo meta
    : i nfeat ( vec_len [String] . mm feats )
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
                // A forest wider than one point is a timevector forest:
                // its input is the WINDOW ending at the current point
                // (W·nfeat features, W derived from the trained forest so
                // a config change cannot desync until the next retrain).
                ? & > nfeat 0 != . vm n_cols nfeat {
                    : i W / . vm n_cols nfeat
                    ?? ( __an_window_tail mo - W 1 ring_has_current ) {
                        T tail → {
                            ( vec_extend [f] tail x )
                            ? == ( vec_len [f] tail ) . vm n_cols {
                                : f dfw ( anom_decision vm tail )
                                : f marginw ( meta_version_margin mm ( string_data . vm vname ) . vm margin )
                                : b hitw <= dfw - 0.0 marginw
                                ? hitw { = any T } {}
                                ? || first < dfw worst { = worst dfw } {}
                                = first F
                                ( vec_push [VerVerdict] vvs @ VerVerdict {
                                    ( string_from ( string_data . vm vname ) )
                                    hitw
                                    dfw
                                    marginw
                                } )
                            } {}
                            ( vec_free [f] tail )
                        }
                        F → {}
                        // ring shorter than the window → the version has
                        // no verdict this time (absent, never wrong)
                    }
                } {
                    : f df ( anom_decision vm x )
                    : f margin ( meta_version_margin mm ( string_data . vm vname ) . vm margin )
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
            }
            F _ → {}
        }
        = k + k 1
    }
    // The autoencoder verdict: reconstruction error against the trained
    // threshold, on the point projected onto the AE's OWN frozen feature
    // order (independent of the forests' scaler and current feats). Muted
    // while its VerCfg is disabled — the net is kept, only the verdict
    // goes away, because re-training it is not a checkbox-priced action.
    : AeModel cae . mo ae
    ? & . cae trained ( meta_version_enabled mm `autoencoder` T ) {
        : ( Vec f ) araw ( anomaly_project p . cae feats )
        : f adf ( ae_decision cae araw )
        : f amargin ( meta_version_margin mm `autoencoder` 0.05 )
        : b ahit <= adf - 0.0 amargin
        ? ahit { = any T } {}
        ? || first < adf worst { = worst adf } {}
        = first F
        ( vec_push [VerVerdict] vvs @ VerVerdict {
            ( string_from `autoencoder` )
            ahit
            adf
            amargin
        } )
        ( vec_free [f] araw )
    } {}
    ( vec_free [f] x )
    ^ @ Verdict { T any worst vvs }
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
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    = . mo next_train_at + . mm n_seen ( __an_sched_step mo )
    ^ ne
}

@ model_force_train * Model mo → i {
    ^ ( model_force_train_at mo ( now_seconds ) )
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

// Train the autoencoder from the ring: encode + project the raw points
// (the same pass model_force_train_at runs, minus the standardising
// scaler — the AE recipe MinMax-scales after anomaly filtering), then
// hand the matrix to ae_train_matrix. `hidden` empty → 64-32-64.
// Explicit-only: never part of the retrain schedule. Returns the error
// text ("" = success).
@ model_train_autoencoder * Model mo ( Vec i ) hidden f contamination → String {
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

    ( meta_refresh_feats mm )
    : i nfeat ( vec_len [String] . mm feats )
    ? <= nfeat 0 {
        ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )
        ^ ( string_from `no numeric features` )
    } {}
    : ( Vec f ) raw ( vec_with_cap [f] * ne nfeat )
    = k 0
    ~ < k ne {
        ?? ( vec_get [EncPoint] encs k ) {
            T p → {
                : ( Vec f ) row ( anomaly_project p . mm feats )
                ( vec_extend [f] raw row )
                ( vec_free [f] row )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [EncPoint] encs \ EncPoint p → v { ( enc_free p ) } )

    : AeTrainOut out ( ae_train_matrix raw ne nfeat . mm feats hidden contamination . mo min_points )
    ( vec_free [f] raw )
    : AeModel nae . out ae
    ? . nae trained {
        ( ae_free . mo ae )
        = . mo ae nae
        ( __an_ensure_ae_cfg mo )
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
    ^ ( model_ingest_at mo raw ( now_seconds ) )
}

// Score without ingesting: no metadata learning, no ring append, no
// retrain, no disk writes. Unknown columns/categories project to zeros.
@ model_detect_only * Model mo Json raw → !Verdict String {
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
@ __an_ring_scaled * Model mo → ( Vec f ) {
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
@ model_finetune * Model mo → FineTuneReport {
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
                : f old ( meta_version_margin mm ( string_data . vm vname ) . vm margin )
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
@ model_reset * Model mo → v {
    : *Meta old . mo meta

    // Fresh metadata, carrying over identity + configuration.
    : *Meta fresh ( meta_new ( string_data . old name ) ( string_data . old created ) )
    = . fresh sched_below . old sched_below
    = . fresh sched_at_max . old sched_at_max
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
        ? == ( nurl_str_eq vname `autoencoder` ) 1 {} { ( __an_drop_forest mo vname ) }
    }
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    ^ T
}

// Apply an editable-metadata patch:
//
//   { "schedule": { "below_max": N, "at_max": N },
//     "versions": { "<name>": { <any VerCfg field> }, ... },
//     "replace_versions": bool }
//
// Both top-level keys are optional but at least one must be present. The
// learned parts of the metadata (columns, categories, feature order,
// scaler) are never taken from the client — see prep.nu. Per-version
// fields split two ways: `enabled` and `decision_margin` bite at the very
// next detect, the geometry and forest-size fields at the next retrain.
// Returns "" on success, else the reason (400-worthy).
@ model_apply_meta_patch * Model mo Json patch → String {
    ? ( json_is_obj patch ) {} { ^ ( string_from `metadata must be a JSON object` ) }
    : *Meta mm . mo meta
    : ~ b touched F

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
        ^ ( string_from `nothing to update: expected a schedule and/or versions object` )
    }

    ( __an_prune_disabled mo )
    ? ( model_is_trained mo ) {
        = . mo next_train_at + . mm last_trained ( __an_sched_step mo )
    } {}
    ( store_save_meta . mo store ( string_data . mo mname ) mm )
    ^ ( string_new )
}
