// timevector_test.nu — the sliding-window version.
//
//   sequence  — timevector catches a SEQUENCE anomaly (a flat run whose
//               every point is individually in range) that the point-based
//               short_term version cannot see; a clean-tail probe stays
//               normal on both.
//   absent    — a window larger than the ring trains no timevector forest
//               and yields NO timevector verdict (absent, never wrong).
//   config    — window_size/step_size round-trip metadata JSON; legacy
//               metadata without the fields gets the timevector defaults
//               (100/1) and plain versions 0/0.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_tv_test).

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

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
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

// detect_only probe → (has timevector verdict, tv anomaly, tv score,
// short_term anomaly, short_term score)
: TvProbe {
    b has_tv
    b tv_hit
    f tv_df
    b st_hit
    f st_df
    i n_versions
}

@ probe * Model mo f temp → TvProbe {
    : Json j ( json_obj_new )
    ( json_obj_set j `temp` ( json_float temp ) )
    : !Verdict String r ( model_detect_only mo j )
    ( json_free j )
    ?? r {
        T vd → {
            : ~ b has_tv F
            : ~ b tv_hit F
            : ~ f tv_df 0.0
            : ~ b st_hit F
            : ~ f st_df 0.0
            : i nv ( vec_len [VerVerdict] . vd versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerVerdict] . vd versions k ) {
                    T vv → {
                        : s vn ( string_data . vv vvname )
                        ? == ( nurl_str_eq vn `timevector` ) 1 {
                            = has_tv T
                            = tv_hit . vv anomaly
                            = tv_df . vv score
                        } {}
                        ? == ( nurl_str_eq vn `short_term` ) 1 {
                            = st_hit . vv anomaly
                            = st_df . vv score
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            : TvProbe out @ TvProbe { has_tv tv_hit tv_df st_hit st_df nv }
            ( verdict_free vd )
            ^ out
        }
        F e → {
            ( string_free e )
            ^ @ TvProbe { F F 0.0 F 0.0 0 }
        }
    }
}

// The clean signal: a sawtooth 20, 21, …, 27, 20, … — every level is
// common on its own; what the window learns is the ORDER.
@ saw f k → f {
    ^ + 20.0 # f % # i k 8
}

@ test_sequence Store st → v {
    : *Model mo ( model_open_at st `tvseq` T0 )
    ( model_set_limits mo 20 150000 )
    ( model_set_schedule mo 1000000 1000000 )  // never auto-train
    : b wset ( model_set_version_window mo `timevector` 8 1 )
    ( check wset `sequence: window set to 8` )

    // 120 clean sawtooth points, one per minute.
    : ~ i k 0
    ~ < k 120 {
        ( ingest_temp mo ( saw # f k ) + T0 * k 60 )
        = k + k 1
    }
    : i used ( model_force_train_at mo + T0 * 121 60 )
    ( check > used 0 `sequence: trained` )

    // The trained timevector forest is 8 points wide (n_cols = 8·nfeat).
    : *Meta mm ( model_metadata mo )
    : i nfeat ( vec_len [String] . mm feats )
    : ~ b wide F
    : i nf ( vec_len [VerModel] . mo forests )
    : ~ i q 0
    ~ < q nf {
        ?? ( vec_get [VerModel] . mo forests q ) {
            T vm → {
                ? == ( nurl_str_eq ( string_data . vm vname ) `timevector` ) 1 {
                    = wide == . vm n_cols * 8 nfeat
                } {}
            }
            F _ → {}
        }
        = q + q 1
    }
    ( check wide `sequence: forest is window-wide (8·nfeat)` )

    // Probe continuing the sawtooth: the window is the clean tail → normal
    // on both versions. The tail ends at k=119 (level 27), next is 20.
    : TvProbe clean ( probe mo 20.0 )
    ( check . clean has_tv `sequence: clean probe has a timevector verdict` )
    ( check ! . clean tv_hit `sequence: clean probe not flagged by timevector` )
    ( check ! . clean st_hit `sequence: clean probe not flagged by short_term` )

    // A REVERSED run: the sawtooth playing backwards — 27, 26, …, 20 —
    // every level individually common, so short_term sees nothing; the
    // descending ORDER is a window pattern the forest never saw (the
    // training windows are the 8 ascending rotations).
    = k 0
    ~ < k 10 {
        ( ingest_temp mo - 27.0 # f % # i k 8 + + T0 * 120 60 * k 60 )
        = k + k 1
    }
    : TvProbe flat ( probe mo - 27.0 # f % 10 8 )
    ( check . flat has_tv `sequence: flat probe has a timevector verdict` )
    ( check < . flat tv_df - . clean tv_df 0.005 `sequence: timevector scores the reversed run WORSE than the clean tail` )
    ( check ! . flat st_hit `sequence: short_term still sees nothing (every point in range)` )
    // The blindness pair: the point-based version thinks the reversed run
    // is MORE normal than the clean probe (its levels sit mid-range) —
    // only the window sees the broken ORDER. This is the property the
    // sliding window exists for.
    ( check > . flat st_df . clean st_df `sequence: short_term is order-blind (reversed scores BETTER pointwise)` )

    ( model_free mo )
}

@ test_absent Store st → v {
    : *Model mo ( model_open_at st `tvabsent` T0 )
    ( model_set_limits mo 20 150000 )
    ( model_set_schedule mo 1000000 1000000 )
    // Window far larger than the ring will ever be here.
    : b _w ( model_set_version_window mo `timevector` 500 1 )
    : ~ i k 0
    ~ < k 60 {
        ( ingest_temp mo ( saw # f k ) + T0 * k 60 )
        = k + k 1
    }
    : i used ( model_force_train_at mo + T0 * 61 60 )
    ( check > used 0 `absent: other versions trained` )
    : TvProbe p ( probe mo 21.0 )
    ( check ! . p has_tv `absent: no timevector verdict when the ring < window` )
    ( check >= . p n_versions 4 `absent: the other versions still answer` )
    ( model_free mo )
}

@ test_config Store st → v {
    // Round-trip: set 8/2, serialise, parse back.
    : *Model mo ( model_open_at st `tvcfg` T0 )
    : b _w ( model_set_version_window mo `timevector` 8 2 )
    : *Meta mm ( model_metadata mo )
    : Json mj ( meta_to_json mm )
    : String ms ( json_stringify mj )
    ( json_free mj )
    ?? ( meta_from_json_str ( string_data ms ) ) {
        T m2 → {
            : ~ i ws 0
            : ~ i ss 0
            : i nv ( vec_len [VerCfg] . m2 versions )
            : ~ i k 0
            ~ < k nv {
                ?? ( vec_get [VerCfg] . m2 versions k ) {
                    T vc → {
                        ? == ( nurl_str_eq ( string_data . vc vname ) `timevector` ) 1 {
                            = ws . vc window_size
                            = ss . vc step_size
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( check == ws 8 `config: window_size round-trips` )
            ( check == ss 2 `config: step_size round-trips` )
            ( meta_free m2 )
        }
        F → { ( check F `config: metadata parses back` ) }
    }
    ( string_free ms )
    ( model_free mo )

    // Legacy metadata (no window fields): timevector gets 100/1, a plain
    // version 0/0 — old on-disk models keep working, upgraded in place.
    : !Json JsonError lr ( json_parse `{"window_minutes":0,"window_points":100,"n_estimators":200,"max_samples":256,"decision_margin":0.1,"enabled":true}` )
    ?? lr {
        T vo → {
            : VerCfg tv ( __an_vercfg_of_json `timevector` vo )
            ( check == . tv window_size 100 `config: legacy timevector defaults to window 100` )
            ( check == . tv step_size 1 `config: legacy timevector defaults to step 1` )
            ( check == . tv window_pts 0 `config: legacy point-cap dropped for the true window` )
            ( _an_vercfg_free tv )
            : VerCfg stv ( __an_vercfg_of_json `short_term` vo )
            ( check == . stv window_size 0 `config: plain versions stay windowless` )
            ( _an_vercfg_free stv )
            ( json_free vo )
        }
        F _ → { ( check F `config: legacy JSON parses` ) }
    }
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_tv_test` )
    : Store st ( store_open ( string_data root ) )
    ( test_sequence st )
    ( test_absent st )
    ( test_config st )
    ( store_free st )
    ( string_free root )
    ( nurl_print `pass ` ) ( nurl_print_int g_pass )
    ( nurl_print ` fail ` ) ( nurl_print_int g_fail ) ( nurl_print `\n` )
    ^ ? > g_fail 0 1 0
}
