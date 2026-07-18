// dynamic_test.nu — M4 tests: streaming dynamic model.
//
// Two scenarios:
//   stream    — production limits (min 50, schedule 50/1000), a gaussian-ish
//               deterministic stream: warm-up gating, no false alarms, a
//               step change flagged. The margin 0.17 sits between our
//               deterministic worst normal df (-0.1389) and the outlier df
//               (-0.2080); the forest is seeded, so these never drift.
//               (sklearn on the same data: -0.148 / -0.209 — same story.)
//   mechanics — tiny limits: retrain cadence, ring eviction, lifetime
//               counter, detect_only immutability, reopen-from-disk
//               continuity, bad-value rejection, reset, delete.
//
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_dyn_test).

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

// Deterministic uniform in [0,1): the classic LCG, same on every platform.
@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

// Gaussian-ish jitter (Irwin–Hall of 3 uniforms, centred, std ≈ 0.5).
@ gauss3 → f {
    ^ - + + ( lcg_u01 ) ( lcg_u01 ) ( lcg_u01 ) 1.5
}

: IngestOut {
    b ok
    b ready
    b anomaly
    f score
    i n_versions
}

@ ingest_pt * Model mo f temp f load i idx → IngestOut {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    ( json_obj_set j `load` ( json_float load ) )
    : !Verdict String r ( model_ingest_at mo j + T0 * idx 60 )
    ( json_free j )
    ?? r {
        T vd → {
            : IngestOut out @ IngestOut { T . vd ready . vd anomaly . vd score ( vec_len [VerVerdict] . vd versions ) }
            ( verdict_free vd )
            ^ out
        }
        F e → {
            ( string_free e )
            ^ @ IngestOut { F F F 0.0 0 }
        }
    }
}

@ set_all_margins * Model mo f margin → v {
    : b a ( model_set_margin mo `short_term` margin )
    : b b2 ( model_set_margin mo `daily` margin )
    : b c ( model_set_margin mo `weekly` margin )
    : b d ( model_set_margin mo `seasonal` margin )
    : b e ( model_set_margin mo `timevector` margin )
}

// ── Scenario A: statistical behaviour at production limits ────────────

@ test_stream Store st → v {
    = g_lcg 1
    : *Model mo ( model_open_at st `stream` T0 )
    ( check == ( store_exists st `stream` ) T `stream: created on first use` )
    ( set_all_margins mo 0.17 )

    : ~ b all_warming T
    : ~ b any_false_alarm F
    : ~ b ready_from_50 T
    : ~ i k 1
    ~ <= k 100 {
        : f temp + 20.0 ( gauss3 )
        : f load + 5.0 * ( gauss3 ) 0.5
        : IngestOut o ( ingest_pt mo temp load k )
        ? < k 50 {
            ? & . o ok == . o ready F {} { = all_warming F }
        } {
            ? & . o ok . o ready {} { = ready_from_50 F }
            ? . o anomaly { = any_false_alarm T } {}
        }
        = k + k 1
    }
    ( check all_warming `stream: points 1-49 warming up (ready=false)` )
    ( check ready_from_50 `stream: ready from point 50 (first train)` )
    ( check == any_false_alarm F `stream: no false alarms on 51 normal points` )
    : *Meta mm ( model_metadata mo )
    ( check == . mm last_trained 100 `stream: schedule retrained at 100` )

    // The step change: extreme in both features, flagged immediately.
    : IngestOut o101 ( ingest_pt mo 26.0 8.0 101 )
    ( check . o101 anomaly `stream: step change flagged` )
    ( check <= . o101 score -0.17 `stream: step change crosses the margin` )
    ( check == . o101 n_versions 5 `stream: verdict carries all 5 versions` )

    // detect_only sees the same outlier without touching anything.
    : Json probe ( json_obj_new )
    ( json_obj_set probe `temp` ( json_float 26.0 ) )
    ( json_obj_set probe `load` ( json_float 8.0 ) )
    : !Verdict String dr ( model_detect_only mo probe )
    ( json_free probe )
    ?? dr {
        T vd → {
            ( check . vd anomaly `stream: detect_only flags the outlier` )
            ( verdict_free vd )
        }
        F e → { ( string_free e ) ( check F `stream: detect_only succeeds` ) }
    }
    ( model_free mo )
}

// ── Scenario B: streaming mechanics at tiny limits ────────────────────

@ test_mechanics Store st → v {
    : *Model mo ( model_open_at st `mech` T0 )
    ( model_set_limits mo 10 30 )
    ( model_set_schedule mo 10 20 )
    ( check ( model_set_margin mo `weekly` 0.5 ) `mech: margin update accepted` )
    ( check == ( model_set_margin mo `nosuch` 0.5 ) F `mech: unknown version margin rejected` )
    ( set_all_margins mo 0.5 )
    ( check == ( model_is_trained mo ) F `mech: starts untrained` )

    : ~ b all_warming T
    : ~ i k 1
    ~ <= k 9 {
        : IngestOut o ( ingest_pt mo + 20.0 ( gauss3 ) + 5.0 ( gauss3 ) k )
        ? & . o ok == . o ready F {} { = all_warming F }
        = k + k 1
    }
    ( check all_warming `mech: points 1-9 warming up` )

    : IngestOut o10 ( ingest_pt mo + 20.0 ( gauss3 ) + 5.0 ( gauss3 ) 10 )
    ( check . o10 ready `mech: point 10 trains and is ready` )
    ( check ( model_is_trained mo ) `mech: trained after warm-up` )
    : *Meta mm ( model_metadata mo )
    ( check == . mm last_trained 10 `mech: last_trained = 10` )

    = k 11
    ~ <= k 25 {
        : IngestOut o ( ingest_pt mo + 20.0 ( gauss3 ) + 5.0 ( gauss3 ) k )
        = k + k 1
    }
    ( check == . mm last_trained 20 `mech: schedule retrained at 20` )

    // detect_only mutates nothing: not metadata, not the ring, not disk.
    : String meta_before ( meta_to_json_str mm )
    : i pts_before ( model_n_points mo )
    : Json probe ( json_obj_new )
    ( json_obj_set probe `temp` ( json_float 1000.0 ) )
    ( json_obj_set probe `newcol` ( json_float 5.0 ) )
    ( json_obj_set probe `status` ( json_str_lit `newcat` ) )
    : !Verdict String dr ( model_detect_only mo probe )
    ( json_free probe )
    ?? dr {
        T vd → { ( verdict_free vd ) ( check T `mech: detect_only succeeds` ) }
        F e → { ( string_free e ) ( check F `mech: detect_only succeeds` ) }
    }
    : String meta_after ( meta_to_json_str mm )
    ( check ( string_eq meta_before meta_after ) `mech: detect_only leaves metadata untouched` )
    ( check == ( model_n_points mo ) pts_before `mech: detect_only leaves the ring untouched` )
    : ( Vec String ) disk_pts ( store_load_points st `mech` )
    ( check == ( vec_len [String] disk_pts ) pts_before `mech: detect_only leaves disk untouched` )
    ( vec_free_with [String] disk_pts \ String x → v { ( string_free x ) } )
    ( string_free meta_before )
    ( string_free meta_after )

    // Ring eviction: cap is 30, lifetime counter keeps going.
    = k 26
    ~ <= k 40 {
        : IngestOut o ( ingest_pt mo + 20.0 ( gauss3 ) + 5.0 ( gauss3 ) k )
        = k + k 1
    }
    ( check == ( model_n_points mo ) 30 `mech: ring capped at 30` )
    ( check == . mm n_seen 40 `mech: n_seen counts past the cap` )
    ?? ( vec_get [i] . mo times 0 ) {
        T t0 → { ( check > t0 T0 `mech: oldest point evicted` ) }
        F _ → {}
    }
    : ( Vec String ) disk2 ( store_load_points st `mech` )
    ( check == ( vec_len [String] disk2 ) 30 `mech: eviction persisted` )
    ( vec_free_with [String] disk2 \ String x → v { ( string_free x ) } )

    // Reopen from disk: trained state, counters, schedule survive.
    ( model_free mo )
    : *Model mo2 ( model_open_at st `mech` + T0 * 41 60 )
    ( model_set_limits mo2 10 30 )
    ( check ( model_is_trained mo2 ) `mech: reopened model is trained` )
    ( check == ( model_n_points mo2 ) 30 `mech: reopened ring intact` )
    : *Meta mm2 ( model_metadata mo2 )
    ( check == . mm2 n_seen 40 `mech: reopened n_seen intact` )
    ( check == . mm2 sched_below 10 `mech: reopened schedule intact` )

    // Bad values are hard errors and leave no trace.
    : i seen_before . mm2 n_seen
    : Json badj ( json_obj_new )
    ( json_obj_set badj `temp` ( json_str_lit `not-a-number` ) )
    : !Verdict String br ( model_ingest_at mo2 badj + T0 * 42 60 )
    ( json_free badj )
    ?? br {
        T vd → { ( verdict_free vd ) ( check F `mech: bad numeric rejected` ) }
        F e → { ( string_free e ) ( check T `mech: bad numeric rejected` ) }
    }
    ( check == . mm2 n_seen seen_before `mech: rejected point not counted` )

    // Reset: data and forests gone, identity/schedule kept.
    ( model_reset mo2 )
    ( check == ( model_n_points mo2 ) 0 `mech: reset drops the ring` )
    ( check == ( model_is_trained mo2 ) F `mech: reset drops the forests` )
    ( check == . ( model_metadata mo2 ) sched_below 10 `mech: reset keeps the schedule` )
    ( check ( store_exists st `mech` ) `mech: reset keeps the model` )

    // Delete: everything gone.
    ( model_free mo2 )
    ( check ( model_delete st `mech` ) `mech: delete` )
    ( check == ( store_exists st `mech` ) F `mech: deleted model gone` )
}

@ main → i {
    : ~ String root ( string_from `./anomaly_dyn_test` )
    ?? ( env_get `ANOMALY_TEST_DIR` ) {
        T d → { ( string_free root ) = root d }
        F _ → {}
    }
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    ( test_stream st )
    ( test_mechanics st )

    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )

    : String summary ( string_from `dynamic_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
