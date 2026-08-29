// metaedit_test.nu — editing a model's metadata from outside (the API the
// dashboard's version editor and its advanced JSON box drive).
//   patch     — a partial version object touches only the fields it names;
//               an unknown key ADDS a version; `replace` drops the rest.
//   clamp     — hand-written nonsense is clamped into a trainable range,
//               and the forest-less `autoencoder` config round-trips as-is.
//   toggle    — disabling a forest version drops its forest and its verdict;
//               re-enabling costs a retrain. The autoencoder is only muted.
//   errors    — the shapes model_apply_meta_patch refuses.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_metaedit_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000
: ~ i g_lcg 1

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

@ near f a f b → b {
    ^ < ( float_abs - a b ) 0.000000001
}

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

@ ingest_temp * Model mo f temp i at → v {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    ?? r {
        T vd → { ( verdict_free vd ) }
        F e → { ( string_free e ) }
    }
}

// A model with 60 points of a tight temp regime, trained.
@ seed * Model mo → v {
    ( model_set_limits mo 20 150000 )
    ( model_set_schedule mo 10 1000 )
    : ~ i k 1
    ~ <= k 60 {
        ( ingest_temp mo + 20.0 * 0.4 ( lcg_u01 ) + T0 * k 60 )
        = k + k 1
    }
    : i _n ( model_force_train_at mo + T0 * 61 60 )
}

// Does the verdict of a probe carry a slice named `vname`?
@ has_version * Model mo s vname → b {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float 20.2 ) )
    : !Verdict String r ( model_detect_only mo j )
    ( json_free j )
    ?? r {
        T vd → {
            : ~ b found F
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        ? == ( nurl_str_eq ( string_data . vv vvname ) vname ) 1 { = found T } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( verdict_free vd )
            ^ found
        }
        F e → { ( string_free e ) ^ F }
    }
}

// Apply a JSON patch written as text; returns the error text (owned).
@ patch_text * Model mo s src → String {
    : !Json JsonError r ( json_parse src )
    ?? r {
        T j → {
            : String err ( model_apply_meta_patch mo j )
            ( json_free j )
            ^ err
        }
        F _ → { ^ ( string_from `unparsable test patch` ) }
    }
}

// ── Scenario 1: partial patches, adds, replace ────────────────────────

@ test_patch Store st → v {
    = g_lcg 1
    : *Model mo ( model_open_at st `patch` T0 )
    ( seed mo )
    : *Meta mm ( model_metadata mo )

    : i before ( vec_len [VerCfg] . mm versions )
    : String e1 ( patch_text mo `{"versions":{"daily":{"decision_margin":0.33}}}` )
    ( check == ( string_len e1 ) 0 `patch: a one-field version object is accepted` )
    ( string_free e1 )
    ( check ( near ( meta_version_margin mm `daily` -1.0 ) 0.33 ) `patch: the named field changed` )
    ( check == ( vec_len [VerCfg] . mm versions ) before `patch: no version was added or lost` )
    ( check == ( meta_version_margin mm `weekly` -1.0 ) 0.06 `patch: other versions are untouched` )

    : i at_daily ( meta_find_version mm `daily` )
    ?? ( vec_get [VerCfg] . mm versions at_daily ) {
        T vc → {
            ( check == . vc window_min 1440 `patch: omitted fields keep their value` )
            ( check == . vc n_estimators 300 `patch: omitted forest size keeps its value` )
            ( check . vc enabled `patch: omitted enabled keeps its value` )
        }
        F _ → { ( check F `patch: daily still present` ) }
    }

    // An unknown key adds a version, defaults filling the gaps.
    : String e2 ( patch_text mo `{"versions":{"hourly":{"window_minutes":60,"n_estimators":150}}}` )
    ( check == ( string_len e2 ) 0 `add: an unknown version name is accepted` )
    ( string_free e2 )
    : i at_h ( meta_find_version mm `hourly` )
    ( check >= at_h 0 `add: the new version is in the metadata` )
    ?? ( vec_get [VerCfg] . mm versions at_h ) {
        T vc → {
            ( check == . vc window_min 60 `add: the given fields are honoured` )
            ( check == . vc n_estimators 150 `add: forest size honoured` )
            ( check == . vc max_samples 256 `add: absent fields take the default` )
            ( check . vc enabled `add: a new version is enabled` )
        }
        F _ → { ( check F `add: hourly readable` ) }
    }

    // It really trains and scores.
    : i _n ( model_force_train_at mo + T0 * 62 60 )
    ( check ( has_version mo `hourly` ) `add: the new version trains and scores` )

    // replace_versions: the list becomes exactly the keys given.
    : String e3 ( patch_text mo
    `{"versions":{"short_term":{},"hourly":{}},"replace_versions":true}` )
    ( check == ( string_len e3 ) 0 `replace: accepted` )
    ( string_free e3 )
    ( check == ( vec_len [VerCfg] . mm versions ) 2 `replace: only the named versions survive` )
    ( check < ( meta_find_version mm `daily` ) 0 `replace: an omitted version is gone` )
    ( check >= ( meta_find_version mm `hourly` ) 0 `replace: a named version stays` )

    // The schedule half of the patch.
    : String e4 ( patch_text mo `{"schedule":{"below_max":25,"at_max":500}}` )
    ( check == ( string_len e4 ) 0 `schedule: accepted` )
    ( string_free e4 )
    ( check == . mm sched_below 25 `schedule: below_max applied` )
    ( check == . mm sched_at_max 500 `schedule: at_max applied` )

    ( model_free mo )

    // Everything survived the round trip through disk.
    : *Model re ( model_open_at st `patch` T0 )
    : *Meta rm ( model_metadata re )
    ( check == ( vec_len [VerCfg] . rm versions ) 2 `persist: the version list reloads` )
    ( check == . rm sched_below 25 `persist: the schedule reloads` )
    ( model_free re )
}

// ── Scenario 2: clamping ──────────────────────────────────────────────

@ test_clamp Store st → v {
    = g_lcg 7
    : *Model mo ( model_open_at st `clamp` T0 )
    ( seed mo )
    : *Meta mm ( model_metadata mo )

    : String e ( patch_text mo
    `{"versions":{"daily":{"n_estimators":-5,"max_samples":0,"window_minutes":-60,"window_size":8,"step_size":0,"decision_margin":-1.0,"contamination":0.9}}}` )
    ( check == ( string_len e ) 0 `clamp: a nonsense config is accepted, not rejected` )
    ( string_free e )
    : i at ( meta_find_version mm `daily` )
    ?? ( vec_get [VerCfg] . mm versions at ) {
        T vc → {
            ( check == . vc n_estimators 1 `clamp: a forest has at least one tree` )
            ( check == . vc max_samples 1 `clamp: max_samples floors at 1` )
            ( check == . vc window_min 0 `clamp: a negative window becomes "all"` )
            ( check == . vc step_size 1 `clamp: a sliding window steps at least 1` )
            ( check ( near . vc decision_margin 0.0 ) `clamp: a negative margin becomes 0` )
            ( check ( near . vc contamination 0.5 ) `clamp: contamination caps at 0.5` )
        }
        F _ → { ( check F `clamp: daily readable` ) }
    }

    // 0 contamination means "auto" (-1), the same as the string spelling.
    : String e2 ( patch_text mo `{"versions":{"weekly":{"contamination":0}}}` )
    ( string_free e2 )
    : i atw ( meta_find_version mm `weekly` )
    ?? ( vec_get [VerCfg] . mm versions atw ) {
        T vc → { ( check < . vc contamination 0.0 `clamp: contamination 0 means auto` ) }
        F _ → { ( check F `clamp: weekly readable` ) }
    }

    // The autoencoder has no forest: its zeroed tree counts round-trip.
    : ( Vec i ) hidden ( vec_new [i] )
    : String aerr ( model_train_autoencoder mo hidden -1.0 )
    ( vec_free [i] hidden )
    ( check == ( string_len aerr ) 0 `clamp: the autoencoder trains` )
    ( string_free aerr )
    : String e3 ( patch_text mo `{"versions":{"autoencoder":{"decision_margin":0.07}}}` )
    ( string_free e3 )
    : i ata ( meta_find_version mm `autoencoder` )
    ?? ( vec_get [VerCfg] . mm versions ata ) {
        T vc → {
            ( check == . vc n_estimators 0 `clamp: the autoencoder keeps 0 trees` )
            ( check == . vc max_samples 0 `clamp: the autoencoder keeps 0 samples` )
            ( check ( near . vc decision_margin 0.07 ) `clamp: its margin is still editable` )
        }
        F _ → { ( check F `clamp: autoencoder readable` ) }
    }
    ( model_free mo )
}

// ── Scenario 3: enable / disable ──────────────────────────────────────

@ test_toggle Store st → v {
    = g_lcg 3
    : *Model mo ( model_open_at st `toggle` T0 )
    ( seed mo )
    ( check ( has_version mo `weekly` ) `toggle: weekly scores while enabled` )

    ( check ( model_set_version_enabled mo `weekly` F ) `toggle: disabling a known version` )
    ( check == ( model_set_version_enabled mo `nosuch` F ) F `toggle: an unknown version is refused` )
    ( check == ( has_version mo `weekly` ) F `toggle: a disabled version stops scoring at once` )
    : ~ b blob_gone T
    ?? ( store_load_forest . mo store `toggle` `weekly` ) {
        T vm → { = blob_gone F ( anom_vermodel_free vm ) }
        F _ → {}
    }
    ( check blob_gone `toggle: the disabled version's forest blob is gone` )
    ( model_free mo )

    // Re-enabling does not resurrect a stale forest: it waits for a retrain.
    : *Model re ( model_open_at st `toggle` T0 )
    ( check ( model_set_version_enabled re `weekly` T ) `toggle: re-enabling a known version` )
    ( check == ( has_version re `weekly` ) F `toggle: re-enabled but not yet retrained = no verdict` )
    : i _n ( model_force_train_at re + T0 * 62 60 )
    ( check ( has_version re `weekly` ) `toggle: the retrain brings the verdict back` )

    // The autoencoder is muted, not thrown away.
    : ( Vec i ) hidden ( vec_new [i] )
    : String aerr ( model_train_autoencoder re hidden -1.0 )
    ( vec_free [i] hidden )
    ( check == ( string_len aerr ) 0 `toggle: the autoencoder trains` )
    ( string_free aerr )
    ( check ( has_version re `autoencoder` ) `toggle: the autoencoder scores once trained` )
    ( check ( model_set_version_enabled re `autoencoder` F ) `toggle: the autoencoder version toggles` )
    ( check == ( has_version re `autoencoder` ) F `toggle: a disabled autoencoder is silent` )
    ( check ( model_set_version_enabled re `autoencoder` T ) `toggle: re-enabling the autoencoder` )
    ( check ( has_version re `autoencoder` ) `toggle: its net was kept — no retrain needed` )
    ( model_free re )
}

// ── Scenario 4: refused shapes ────────────────────────────────────────

@ test_errors Store st → v {
    = g_lcg 5
    : *Model mo ( model_open_at st `errs` T0 )
    ( seed mo )

    : String e1 ( patch_text mo `{}` )
    ( check > ( string_len e1 ) 0 `error: an empty patch is refused` )
    ( string_free e1 )
    : String e2 ( patch_text mo `{"versions":[1,2]}` )
    ( check > ( string_len e2 ) 0 `error: versions must be an object` )
    ( string_free e2 )
    : String e3 ( patch_text mo `{"schedule":7}` )
    ( check > ( string_len e3 ) 0 `error: schedule must be an object` )
    ( string_free e3 )
    : String e4 ( patch_text mo `{"schedule":{"below_max":0,"at_max":0}}` )
    ( check > ( string_len e4 ) 0 `error: a non-positive schedule is refused` )
    ( string_free e4 )
    : String e5 ( patch_text mo `[1,2,3]` )
    ( check > ( string_len e5 ) 0 `error: the patch itself must be an object` )
    ( string_free e5 )

    // A refused patch changes nothing.
    : *Meta mm ( model_metadata mo )
    ( check == . mm sched_below 10 `error: a refused patch leaves the schedule alone` )
    ( model_free mo )
}

@ main → i {
    : ~ String root ( string_from `./anomaly_metaedit_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    ( test_patch st )
    ( test_clamp st )
    ( test_toggle st )
    ( test_errors st )

    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `metaedit_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
