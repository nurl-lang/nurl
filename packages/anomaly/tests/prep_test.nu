// prep_test.nu — M1 unit tests: preprocessing, projection, scaler,
// metadata JSON round-trip. Prints one `ok`/`FAIL` line per check and
// exits non-zero if anything failed. Run via tests/anomaly_test.sh.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( pline label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( pline label )
        = g_fail + g_fail 1
    }
}

@ feq f a f b → b {
    ^ < ( float_abs - a b ) 0.000000001
}

// Value of feature `name` in an encoded point, or NaN-ish sentinel.
@ enc_val EncPoint p s name → f {
    : i at ( enc_find p name )
    ? < at 0 { ^ -999999.0 } {}
    ?? ( vec_get [f] . p vals at ) { T x → { ^ x } F _ → { ^ -999999.0 } }
}

// Name of feature k in a ( Vec String ), as borrowed data (test-only).
@ feat_eq ( Vec String ) fs i k s want → b {
    ?? ( vec_get [String] fs k ) {
        T x → { ^ == ( nurl_str_eq ( string_data x ) want ) 1 }
        F _ → { ^ F }
    }
}

// ── 1. Golden mixed-type record ───────────────────────────────────────

@ test_golden → v {
    : *Meta m ( meta_new `t1` `2026-07-03T00:00:00Z` )
    : !Json JsonError r ( json_parse `{"temp": 21.5, "status": "ok", "when": "2026-07-03T12:34:56Z", "timestamp": "2026-07-03T12:00:00Z"}` )
    ?? r {
        T j → {
            : !EncPoint String er ( anomaly_preprocess m j )
            ?? er {
                T p → {
                    ( check == ( vec_len [f] . p vals ) 8 `golden: 8 features (timestamp key skipped)` )
                    ( check ( feq ( enc_val p `temp` ) 21.5 ) `golden: numeric passthrough` )
                    ( check ( feq ( enc_val p `status_ok` ) 1.0 ) `golden: one-hot fires` )
                    // 12:34 → hour 12 of 24: sin(π) ≈ 0, cos(π) = -1.
                    ( check ( feq ( enc_val p `when_hour_sin` ) 0.0 ) `golden: hour sin` )
                    ( check ( feq ( enc_val p `when_hour_cos` ) -1.0 ) `golden: hour cos` )
                    // Friday = 4 of 7 (Monday = 0, Python convention).
                    ( check ( feq ( enc_val p `when_weekday_sin` ) ( float_sin / * 8.0 PI 7.0 ) ) `golden: weekday sin (Fri=4)` )
                    ( check ( feq ( enc_val p `when_weekday_cos` ) ( float_cos / * 8.0 PI 7.0 ) ) `golden: weekday cos` )
                    // July = position 6 of 12: sin(π) ≈ 0, cos(π) = -1.
                    ( check ( feq ( enc_val p `when_month_sin` ) 0.0 ) `golden: month sin` )
                    ( check ( feq ( enc_val p `when_month_cos` ) -1.0 ) `golden: month cos` )
                    ( enc_free p )
                }
                F e → {
                    ( nurl_eprint `preprocess error: ` )
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    ( check F `golden: preprocess succeeds` )
                }
            }
            // Derived feature order: cols first-seen, canonical expansion.
            : ( Vec String ) fs ( meta_derived_feats m )
            ( check == ( vec_len [String] fs ) 8 `golden: derived feature count` )
            ( check ( feat_eq fs 0 `temp` ) `golden: feat[0] temp` )
            ( check ( feat_eq fs 1 `status_ok` ) `golden: feat[1] status_ok` )
            ( check ( feat_eq fs 2 `when_hour_sin` ) `golden: feat[2] when_hour_sin` )
            ( vec_free_with [String] fs \ String x → v { ( string_free x ) } )
            ( json_free j )
        }
        F _ → { ( check F `golden: test json parses` ) }
    }
    ( meta_free m )
}

// ── 1b. Calendar features read the clock the stamp was written in ─────

// The hour_sin/hour_cos pair of `stamp`'s encoding, as (sin, cos) of the
// hour it names; -999999 when the stamp is rejected.
@ hour_of * Meta m s stamp → f {
    : String src ( string_from `{"when": "` )
    ( string_push_str src stamp )
    ( string_push_str src `"}` )
    : ~ f got -999999.0
    ?? ( json_parse ( string_data src ) ) {
        T j → {
            ?? ( anomaly_preprocess m j ) {
                T p → {
                    // atan2 of the pair gives the angle back; 24·angle/2π is the hour.
                    : f ang ( float_atan2 ( enc_val p `when_hour_sin` ) ( enc_val p `when_hour_cos` ) )
                    : ~ f h / * 24.0 ang * 2.0 PI
                    ? < h -0.5 { = h + h 24.0 } {}
                    = got h
                    ( enc_free p )
                }
                F e → { ( string_free e ) }
            }
            ( json_free j )
        }
        F _ → {}
    }
    ( string_free src )
    ^ got
}

@ test_calendar_clock → v {
    : *Meta m ( meta_new `t1b` `2026-07-03T00:00:00Z` )
    // Midnight in +03:00 is midnight to the sender, not 21:00 UTC.
    ( check ( feq ( hour_of m `2026-08-01T00:00:00+03:00` ) 0.0 ) `calendar: +03:00 midnight is hour 0` )
    ( check ( feq ( hour_of m `2026-08-01T00:00:00-05:30` ) 0.0 ) `calendar: -05:30 midnight is hour 0` )
    ( check ( feq ( hour_of m `2026-08-01T23:00:00Z` ) 23.0 ) `calendar: Z is UTC` )
    ( check ( feq ( hour_of m `2026-08-01T07:15:00` ) 7.0 ) `calendar: no designator = as written` )
    ( check ( feq ( hour_of m `2026-08-01T07:15:00.250+02:00` ) 7.0 ) `calendar: fraction before the offset` )
    ( check == ( __an_iso_offset `2026-08-01T00:00:00+0300` ) 10800 `calendar: offset without colon` )
    ( check == ( __an_iso_offset `2026-08-01T00:00:00-05:30` ) -19800 `calendar: negative offset` )
    ( check == ( __an_iso_offset `2026-08-01T00:00:00Z` ) 0 `calendar: Z offset 0` )
    ( check ! ( meta_retrain_required m ) `calendar: a current model needs no retrain` )

    // A model stored under encoding 1 still encodes its points the old
    // way (its frozen feature order names them) and says so.
    = . m feat_enc 1
    ( meta_refresh_feats m )
    ( check ( meta_retrain_required m ) `calendar: encoding-1 model needs a retrain` )
    ?? ( json_parse `{"when": "2026-08-01T00:00:00+03:00"}` ) {
        T j → {
            ?? ( anomaly_preprocess m j ) {
                T p → {
                    ( check ( feq ( enc_val p `when_hour` ) 21.0 ) `calendar: encoding 1 keeps its UTC hour` )
                    ( check ( feq ( enc_val p `when_day` ) 31.0 ) `calendar: encoding 1 keeps day-of-month` )
                    ( enc_free p )
                }
                F e → { ( string_free e ) }
            }
            ( json_free j )
        }
        F _ → {}
    }
    : ( Vec String ) fs ( meta_derived_feats m )
    ( check ( feat_eq fs 0 `when_hour` ) `calendar: encoding 1 keeps its feature names` )
    ( vec_free_with [String] fs \ String x → v { ( string_free x ) } )
    ( meta_free m )
}

// ── 2. Category growth is deterministic and sorted ────────────────────

@ test_categories → v {
    : *Meta m ( meta_new `t2` `2026-07-03T00:00:00Z` )
    : !Json JsonError r1 ( json_parse `{"status": "warn"}` )
    : !Json JsonError r2 ( json_parse `{"status": "alert"}` )
    ?? r1 {
        T j1 → {
            : !EncPoint String e1 ( anomaly_preprocess m j1 )
            ?? e1 { T p → { ( enc_free p ) } F e → { ( string_free e ) } }
            ( json_free j1 )
        }
        F _ → {}
    }
    ?? r2 {
        T j2 → {
            : !EncPoint String e2 ( anomaly_preprocess m j2 )
            ?? e2 {
                T p → {
                    // Both categories known now; "alert" is hot.
                    ( check ( feq ( enc_val p `status_alert` ) 1.0 ) `cats: new category hot` )
                    ( check ( feq ( enc_val p `status_warn` ) 0.0 ) `cats: old category cold` )
                    ( enc_free p )
                }
                F e → { ( string_free e ) ( check F `cats: preprocess succeeds` ) }
            }
            ( json_free j2 )
        }
        F _ → {}
    }
    // Sorted order: alert before warn regardless of arrival order.
    : ( Vec String ) fs ( meta_derived_feats m )
    ( check ( feat_eq fs 0 `status_alert` ) `cats: sorted feat[0] status_alert` )
    ( check ( feat_eq fs 1 `status_warn` ) `cats: sorted feat[1] status_warn` )
    ( vec_free_with [String] fs \ String x → v { ( string_free x ) } )
    ( meta_free m )
}

// ── 3. Frozen projection: stability rule ──────────────────────────────

@ test_projection → v {
    : *Meta m ( meta_new `t3` `2026-07-03T00:00:00Z` )
    : !Json JsonError r1 ( json_parse `{"a": 1, "status": "ok"}` )
    ?? r1 {
        T j1 → {
            : !EncPoint String e1 ( anomaly_preprocess m j1 )
            ?? e1 { T p → { ( enc_free p ) } F e → { ( string_free e ) } }
            ( json_free j1 )
        }
        F _ → {}
    }
    ( meta_refresh_feats m )
    ( check ( meta_is_frozen m ) `proj: frozen after refresh` )
    : i nfroz ( vec_len [String] . m feats )
    ( check == nfroz 2 `proj: frozen order has 2 features` )

    // A later point brings a new column and a new category: the projected
    // vector must keep exactly the frozen shape (extras dropped, missing 0).
    : !Json JsonError r2 ( json_parse `{"status": "zzz", "extra": 9.0}` )
    ?? r2 {
        T j2 → {
            : !EncPoint String e2 ( anomaly_preprocess m j2 )
            ?? e2 {
                T p → {
                    : ( Vec f ) x ( anomaly_project p . m feats )
                    ( check == ( vec_len [f] x ) 2 `proj: projected length = frozen length` )
                    ?? ( vec_get [f] x 0 ) { T v0 → { ( check ( feq v0 0.0 ) `proj: missing numeric = 0` ) } F _ → {} }
                    ?? ( vec_get [f] x 1 ) { T v1 → { ( check ( feq v1 0.0 ) `proj: unseen category = all-zero one-hot` ) } F _ → {} }
                    ( vec_free [f] x )
                    ( enc_free p )
                }
                F e → { ( string_free e ) ( check F `proj: preprocess succeeds` ) }
            }
            ( json_free j2 )
        }
        F _ → {}
    }
    // Metadata itself kept learning (new col + category recorded for the
    // next retrain), even though the frozen order didn't move.
    : ( Vec String ) fs ( meta_derived_feats m )
    ( check == ( vec_len [String] fs ) 4 `proj: metadata still learns (4 derived feats)` )
    ( vec_free_with [String] fs \ String x → v { ( string_free x ) } )
    ( meta_free m )
}

// ── 4. Numeric parse failure is a hard error ──────────────────────────

@ test_numeric_error → v {
    : *Meta m ( meta_new `t4` `2026-07-03T00:00:00Z` )
    : !Json JsonError r1 ( json_parse `{"temp": 1.0}` )
    ?? r1 {
        T j1 → {
            : !EncPoint String e1 ( anomaly_preprocess m j1 )
            ?? e1 { T p → { ( enc_free p ) } F e → { ( string_free e ) } }
            ( json_free j1 )
        }
        F _ → {}
    }
    : !Json JsonError r2 ( json_parse `{"temp": "abc"}` )
    ?? r2 {
        T j2 → {
            : !EncPoint String e2 ( anomaly_preprocess m j2 )
            ?? e2 {
                T p → { ( enc_free p ) ( check F `numerr: bad value rejected` ) }
                F e → {
                    : ?i at ( string_index_of e `must be a numeric value` )
                    ?? at { T _ → { ( check T `numerr: bad value rejected` ) } F _ → { ( check F `numerr: message names the rule` ) } }
                    ( string_free e )
                }
            }
            ( json_free j2 )
        }
        F _ → {}
    }
    ( meta_free m )
}

// ── 5. Scaler: fit / apply / inverse / zero-variance ──────────────────

@ test_scaler → v {
    // 3 rows × 2 cols; col0 = 1,2,3 (varies), col1 = 5,5,5 (constant).
    : ( Vec f ) data ( vec_new [f] )
    ( vec_push [f] data 1.0 ) ( vec_push [f] data 5.0 )
    ( vec_push [f] data 2.0 ) ( vec_push [f] data 5.0 )
    ( vec_push [f] data 3.0 ) ( vec_push [f] data 5.0 )
    : Scaler sc ( scaler_fit data 3 2 )

    ?? ( vec_get [f] . sc mean 0 ) { T mu → { ( check ( feq mu 2.0 ) `scaler: mean` ) } F _ → {} }
    ?? ( vec_get [f] . sc inv_std 1 ) { T iv → { ( check ( feq iv 1.0 ) `scaler: zero-variance inv_std = 1` ) } F _ → {} }

    : ( Vec f ) pt ( vec_new [f] )
    ( vec_push [f] pt 3.0 ) ( vec_push [f] pt 5.0 )
    ( scaler_apply sc pt )
    // population std of {1,2,3} = sqrt(2/3); (3-2)/sqrt(2/3) = sqrt(1.5)
    ?? ( vec_get [f] pt 0 ) { T y0 → { ( check ( feq y0 ( float_sqrt 1.5 ) ) `scaler: standardises` ) } F _ → {} }
    ?? ( vec_get [f] pt 1 ) { T y1 → { ( check ( feq y1 0.0 ) `scaler: constant col centres to 0` ) } F _ → {} }

    // Inverse identity: x = y/inv + mean.
    ?? ( vec_get [f] pt 0 ) {
        T y0 → {
            ?? ( vec_get [f] . sc inv_std 0 ) {
                T iv0 → {
                    ?? ( vec_get [f] . sc mean 0 ) {
                        T mu0 → { ( check ( feq + / y0 iv0 mu0 3.0 ) `scaler: inverse identity` ) }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( vec_free [f] pt )
    ( vec_free [f] data )

    // Round-trip through metadata (mean/std persisted, rebuilt as inv_std).
    : *Meta m ( meta_new `t5` `2026-07-03T00:00:00Z` )
    ( meta_set_scaler m sc )
    : Scaler sc2 ( meta_scaler m )
    ?? ( vec_get [f] . sc inv_std 0 ) {
        T a0 → {
            ?? ( vec_get [f] . sc2 inv_std 0 ) {
                T b0 → { ( check ( feq a0 b0 ) `scaler: survives metadata round-trip` ) }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( scaler_free sc2 )
    ( scaler_free sc )
    ( meta_free m )
}

// ── 6. Metadata JSON round-trip is byte-stable ────────────────────────

@ test_meta_roundtrip → v {
    : *Meta m ( meta_new `t6` `2026-07-03T00:00:00Z` )
    : !Json JsonError r1 ( json_parse `{"temp": 21.5, "status": "ok", "when": "2026-07-03T12:34:56Z"}` )
    ?? r1 {
        T j1 → {
            : !EncPoint String e1 ( anomaly_preprocess m j1 )
            ?? e1 { T p → { ( enc_free p ) } F e → { ( string_free e ) } }
            ( json_free j1 )
        }
        F _ → {}
    }
    ( meta_refresh_feats m )
    : ( Vec f ) data ( vec_new [f] )
    ( vec_push [f] data 1.0 ) ( vec_push [f] data 2.0 )
    ( vec_push [f] data 3.0 ) ( vec_push [f] data 4.0 )
    : Scaler sc ( scaler_fit data 2 2 )
    ( meta_set_scaler m sc )
    ( scaler_free sc )
    ( vec_free [f] data )
    = . m n_seen 123
    = . m last_trained 100

    : String s1 ( meta_to_json_str m )
    : ?*Meta m2o ( meta_from_json_str ( string_data s1 ) )
    ?? m2o {
        T m2 → {
            : String s2 ( meta_to_json_str m2 )
            ( check ( string_eq s1 s2 ) `meta: JSON round-trip byte-stable` )
            ( check == . m2 n_seen 123 `meta: n_points_seen survives` )
            ( check == . m2 sched_below 50 `meta: schedule default survives` )
            ( check == ( vec_len [VerCfg] . m2 versions ) 5 `meta: 5 default versions survive` )
            ( check == ( vec_len [String] . m2 feats ) 8 `meta: feature order survives` )
            ( check == . m2 feat_enc ANOM_FEAT_ENC `meta: feature encoding survives` )
            ( string_free s2 )
            ( meta_free m2 )
        }
        F _ → { ( check F `meta: JSON parses back` ) }
    }
    ( string_free s1 )

    // Corrupt / partial input is rejected cleanly, never UB.
    : ?*Meta bad1 ( meta_from_json_str `{"name": 7}` )
    ?? bad1 { T mb → { ( meta_free mb ) ( check F `meta: mistyped name rejected` ) } F _ → { ( check T `meta: mistyped name rejected` ) } }
    : ?*Meta bad2 ( meta_from_json_str `not json at all` )
    ?? bad2 { T mb → { ( meta_free mb ) ( check F `meta: garbage rejected` ) } F _ → { ( check T `meta: garbage rejected` ) } }
    ( meta_free m )
}

@ main → i {
    ( test_golden )
    ( test_calendar_clock )
    ( test_categories )
    ( test_projection )
    ( test_numeric_error )
    ( test_scaler )
    ( test_meta_roundtrip )
    : String summary ( string_from `prep_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
