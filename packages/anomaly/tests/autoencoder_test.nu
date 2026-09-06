// autoencoder_test.nu — the autoencoder version.
//
//   detect   — trained on a ring of correlated 2-feature points (with a
//              few injected anomalies the iforest pre-filter must drop),
//              the AE flags an off-manifold probe whose every value is
//              in range, and passes an on-manifold probe — the AE sees
//              CORRELATION the marginals hide. (Whether a forest also
//              catches it depends on partitioning luck; not asserted.)
//   persist  — reopening the model loads the trained AE and scores the
//              same probe bit-identically; the metadata carries the
//              autoencoder version config.
//   errors   — too few points → an error text, model untouched.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_ae_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/autoenc.nu`
$ `src/store.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000
: ~ i g_lcg 1

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

@ ingest2 * Model mo f a f b2 i at → v {
    : Json j ( json_obj_new )
    ( json_obj_set j `pres` ( json_float a ) )
    ( json_obj_set j `flow` ( json_float b2 ) )
    : !Verdict String r ( model_ingest_at mo j at )
    ( json_free j )
    ?? r {
        T vd → { ( verdict_free vd ) }
        F e → { ( string_free e ) }
    }
}

// detect_only → (ae verdict present, ae hit, ae df)
: AeProbe {
    b has_ae
    b ae_hit
    f ae_df
    i hits_other
}

@ probe2 * Model mo f a f b2 → AeProbe {
    : Json j ( json_obj_new )
    ( json_obj_set j `pres` ( json_float a ) )
    ( json_obj_set j `flow` ( json_float b2 ) )
    : !Verdict String r ( model_detect_only mo j )
    ( json_free j )
    ?? r {
        T vd → {
            : ~ b has_ae F
            : ~ b ae_hit F
            : ~ f ae_df 0.0
            : ~ i others 0
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        ? == ( nurl_str_eq ( string_data . vv vvname ) `autoencoder` ) 1 {
                            = has_ae T
                            = ae_hit . vv anomaly
                            = ae_df . vv score
                        } {
                            ? . vv anomaly { = others + others 1 } {}
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            : AeProbe out @ AeProbe { has_ae ae_hit ae_df others }
            ( verdict_free vd )
            ^ out
        }
        F e → {
            ( string_free e )
            ^ @ AeProbe { F F 0.0 0 }
        }
    }
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_ae_test` )
    : Store st ( store_open ( string_data root ) )

    // ── training data: flow ≈ 2·pres (a 1-D manifold in 2-D), pres in
    // [1, 2]; 12 injected anomalies break the correlation — the
    // pre-filter must drop them so the AE learns only the line.
    : *Model mo ( model_open_at st `aemodel` T0 )
    ( model_set_limits mo 30 150000 )
    ( model_set_schedule mo 1000000 1000000 )
    = g_lcg 7
    : ~ i k 0
    ~ < k 240 {
        : f pres + 1.0 ( lcg_u01 )
        : ~ f flow * 2.0 pres
        ? == % k 20 19 { = flow + 1.0 * 3.0 ( lcg_u01 ) }  // broken correlation
        ( ingest2 mo pres flow + T0 * k 60 )
        = k + k 1
    }
    ( check > ( model_force_train_at mo + T0 * 241 60 ) 0 `forests trained` )

    // Before AE training: no autoencoder verdict.
    : AeProbe pre ( probe2 mo 1.5 3.0 )
    ( check ! . pre has_ae `no AE verdict before training` )

    // ── train the autoencoder ──
    : ( Vec i ) hidden ( vec_new [i] )
    : String err ( model_train_autoencoder mo hidden -1.0 )
    ( check == ( string_len err ) 0 `AE trains ("" error)` )
    ( string_free err )
    : AeModel tae . mo ae
    ( check . tae trained `AE marked trained` )
    ( check > . tae filtered 0 `pre-filter dropped injected anomalies` )
    ( check > . tae threshold 0.0 `threshold positive` )

    // ── detection ──
    // On-manifold probe: pres 1.5, flow 3.0 — clean.
    : AeProbe onp ( probe2 mo 1.5 3.0 )
    ( check . onp has_ae `AE verdict present after training` )
    ( check ! . onp ae_hit `on-manifold probe passes` )
    // Off-manifold probe: pres 1.2 (common), flow 3.8 (common for pres
    // 1.9 — but NOT for 1.2). Marginals fine, correlation broken.
    : AeProbe offp ( probe2 mo 1.2 3.8 )
    ( check . offp ae_hit `off-manifold probe flagged by the AE` )
    ( check < . offp ae_df . onp ae_df `off-manifold scores worse than on-manifold` )

    // ── persistence ──
    : f df_before . offp ae_df
    ( model_free mo )
    : *Model mo2 ( model_open_at st `aemodel` + T0 * 300 60 )
    : AeModel lae . mo2 ae
    ( check . lae trained `reopened model has the AE` )
    : AeProbe offp2 ( probe2 mo2 1.2 3.8 )
    ( check == ( f64_to_bits . offp2 ae_df ) ( f64_to_bits df_before ) `reload scores bit-identically` )
    // metadata carries the version config (margin tunable)
    : *Meta mm2 ( model_metadata mo2 )
    : ~ b have_cfg F
    : i nv ( vec_len [VerCfg] . mm2 versions )
    = k 0
    ~ < k nv {
        ?? ( vec_get [VerCfg] . mm2 versions k ) {
            T vc → {
                ? == ( nurl_str_eq ( string_data . vc vname ) `autoencoder` ) 1 { = have_cfg T } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check have_cfg `metadata carries the autoencoder version config` )

    // ── a stale net ──
    // A net whose frozen feature order names a feature the model no
    // longer encodes (the calendar features changed shape once; a cycle
    // the span has not seen twice is left out) would reconstruct 0 where
    // it learned a value and flag every point by thousands of margins.
    // It must fall silent instead, and the next forest retrain replaces
    // it even with the schedule's autoencoder switch off.
    ( check ! . mo2 ae_stale `a net over the model's own features is not stale` )
    ( vec_push [String] . . mo2 ae feats ( string_from `when_month_sin` ) )
    ( check ( an_ae_stale mm2 . mo2 ae ) `a net naming a feature the model does not encode is stale` )
    = . mo2 ae_stale T
    : AeProbe stp ( probe2 mo2 1.2 3.8 )
    ( check ! . stp has_ae `a stale net gives no verdict` )
    ( check ! . mm2 sched_ae `(the schedule does not retrain the net on its own)` )
    ( check > ( model_force_train_at mo2 + T0 * 301 60 ) 0 `forests retrain` )
    ( check ! . mo2 ae_stale `the retrain replaced the stale net` )
    : AeProbe fresh ( probe2 mo2 1.2 3.8 )
    ( check & . fresh has_ae . fresh ae_hit `the fresh net scores, and still flags the off-manifold point` )

    // ── an empty layout is the trained one, not the default ──
    // The dashboard's Retrain button sends no layout unless the box is
    // filled in; a net trained 8-4-8 must come back 8-4-8, not 64-32-64.
    : ( Vec i ) h848 ( vec_new [i] )
    ( vec_push [i] h848 8 ) ( vec_push [i] h848 4 ) ( vec_push [i] h848 8 )
    : String err848 ( model_train_autoencoder_at mo2 h848 -1.0 + T0 * 302 60 )
    ( check == ( string_len err848 ) 0 `AE retrains with an 8-4-8 layout` )
    ( string_free err848 )
    : ( Vec i ) hnone ( vec_new [i] )
    : String errk ( model_train_autoencoder_at mo2 hnone -1.0 + T0 * 303 60 )
    ( check == ( string_len errk ) 0 `AE retrains with no layout given` )
    ( string_free errk )
    : AeModel kae . mo2 ae
    : ( Vec i ) kept ( ae_hidden kae )
    ( check & == ( vec_len [i] kept ) 3 & == ( _mlp_iget kept 0 ) 8 == ( _mlp_iget kept 1 ) 4
    `an empty layout keeps the trained 8-4-8, not the 64-32-64 default` )
    ( vec_free [i] kept )
    ( vec_free [i] hnone )
    ( vec_free [i] h848 )
    ( model_free mo2 )

    // ── errors ──
    : *Model tiny ( model_open_at st `aetiny` T0 )
    ( model_set_limits tiny 30 150000 )
    ( model_set_schedule tiny 1000000 1000000 )
    ( ingest2 tiny 1.0 2.0 T0 )
    : ( Vec i ) h2 ( vec_new [i] )
    : String err2 ( model_train_autoencoder tiny h2 -1.0 )
    ( check > ( string_len err2 ) 0 `too few points → error text` )
    : AeModel tae2 . tiny ae
    ( check ! . tae2 trained `failed train leaves the model untouched` )
    ( string_free err2 )
    ( vec_free [i] h2 )
    ( vec_free [i] hidden )
    ( model_free tiny )

    ( store_free st )
    ( string_free root )
    ( nurl_print `autoencoder_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
