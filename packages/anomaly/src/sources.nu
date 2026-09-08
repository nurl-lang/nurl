// anomaly/sources.nu — data sources: configured once, fetched on a schedule.
//
// A model fed by a producer gets its points pushed. A model fed from a
// public service — a weather office's WFS — has to go and get them, and
// somebody has to say from where, which columns, into which model and
// how often. That somebody is an organisation's administrator, and what
// they say is a SOURCE:
//
//   <root>/orgs/<org>/sources/<id>.json
//
//   { "id", "name", "kind": "wfs" | "http", "url", "query", "params": {…},
//     "mode": "stored" | "type",           WFS: a stored query, or a feature type
//     "method", "headers": {…}, "body", "path",   HTTP: the request, and where the records are
//     "features": ["t2m", "ws_10min"],     the columns kept (empty = all)
//     "categorical": ["lat", "lon"],       columns stored as text → one-hot
//     "time_field": "",                    a feature type's clock ("" = detect)
//     "model", "interval_minutes", "history_hours", "calendar", "enabled",
//     "created_by", "created_at", "updated_at",
//     "first_time", "last_time",           the span of observation time fetched so far
//     "last_run", "last_status", "last_error", "last_rows", "runs", "total_rows" }
//
// A stored query is asked for the window the source has not seen yet —
// (last_time, now], a day per request. A feature type is fetched whole
// each run (at most `count` features): its features carry their own
// clock in a date property, or none — then every run stores a snapshot
// stamped with the fetch time, and the model learns how the snapshots
// drift. Either way the answer is pivoted into points (src/wfs.nu), the
// chosen columns kept — a categorical one written as text, so a
// coordinate or a station name becomes a one-hot identity and anomalies
// are judged per place — and imported with their own timestamps
// (model_import), so a run is the same act as importing a file of
// history and the model learns from it the same way. The first run
// reaches back `history_hours`; a backfill reaches further back, to
// before `first_time`, so no window is fetched twice and no point lands
// twice.
//
// The scheduler is one thread that wakes every few seconds, runs what is
// due, and holds the service lock only while it touches the store: the
// network wait happens with the lock released, so a slow service does
// not stall a single live detection.
//
// Windows are chunked to a day per request — a year of ten-minute
// observations is not one answer, and a service that caps a request's
// span answers a day.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/sort.nu`
$ `src/orgfiles.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/authz.nu`
$ `src/wfs.nu`
$ `src/httpsrc.nu`
$ `src/imptime.nu`

: i SRC_ID_LEN 12
: i SRC_NAME_MAX 80
: i SRC_QUERY_MAX 200
: i SRC_PARAMS_MAX 40
: i SRC_FEATURES_MAX 200
: i SRC_INTERVAL_DEFAULT 10  // minutes
: i SRC_INTERVAL_MAX 10080  // a week
: i SRC_HISTORY_DEFAULT 168  // hours, the first run: a week, so a daily rhythm is seen seven times
: f SRC_FINETUNE_DEFAULT 0.01  // the share of the ring the first train's calibration flags
: i SRC_HISTORY_MAX 8760  // a year
: i SRC_CHUNK_SECS 86400  // one request covers at most a day
: i SRC_TICK_MS 15000  // the scheduler's wake-up
: s SRC_KIND_WFS `wfs`
: s SRC_KIND_HTTP `http`
: i SRC_HEADERS_MAX 20
: i SRC_BODY_MAX 65536
// What the API shows in place of a header's value: a key is an admin's
// secret, and the record is readable by every member. Sent back as a
// value it means "keep what is stored".
: s SRC_MASK `••••••••`
: s SRC_MODE_STORED `stored`
: s SRC_MODE_TYPE `type`
// A feature type's forward window has no upper edge: a forecast's rows
// lie in the future and still belong to this run.
: i SRC_FAR_FUTURE 315360000

// ── Small JSON readers (owned copies, defaults) ───────────────────────

@ __src_jstr Json o s key → String {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {} }
        F _ → {}
    }
    ^ ( string_new )
}

@ _src_jint Json o s key i dflt → i {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } {} }
        F _ → {}
    }
    ^ dflt
}

@ __src_jfloat Json o s key f dflt → f {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ?? ( json_num_as_f v ) { T x → { ^ x } F _ → {} } } {} }
        F _ → {}
    }
    ^ dflt
}

@ __src_jbool Json o s key b dflt → b {
    ?? ( json_obj_get o key ) {
        T v → {
            ? ( json_is_bool v ) { ^ ( json_bool_val v ) } {}
            ? ( json_is_num v ) { ^ != ( json_as_int v ) 0 } {}
        }
        F _ → {}
    }
    ^ dflt
}

@ __src_set_str Json o s key s val → v { ( json_obj_set o key ( json_str_lit val ) ) }

@ __src_set_int Json o s key i val → v { ( json_obj_set o key ( json_int val ) ) }

// ── Names and files ───────────────────────────────────────────────────

// A source id is what rand_hex_str makes: lowercase hex, SRC_ID_LEN long.
@ source_id_ok s id → b {
    : i n ( nurl_str_len id )
    ? != n SRC_ID_LEN { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get id k )
        : b digit & >= c 48 <= c 57
        : b hex & >= c 97 <= c 102
        ? | digit hex {} { ^ F }
        = k + k 1
    }
    ^ T
}

// A model name as the service spells it: letters, digits, underscore.
@ __src_model_ok s name → b {
    : i n ( nurl_str_len name )
    ? | <= n 0 > n 128 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get name k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        ? | | | digit lower upper == c 95 {} { ^ F }
        = k + k 1
    }
    ^ T
}

// Text with no control characters and a bounded length: a name, a query
// id, a parameter value — things that go into a URL or a page.
@ __src_text_ok s t i max → b {
    : i n ( nurl_str_len t )
    ? > n max { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c & 255 ( nurl_str_get t k )
        ? < c 32 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ source_path s org s id → String {
    : String p ( orgfiles_sources_dir org )
    ( string_push_char p 47 )
    ( string_push_str p id )
    ( string_push_str p `.json` )
    ^ p
}

@ source_load s org s id → ?Json {
    ? ( source_id_ok id ) {} { ^ @ ?Json { F } }
    : String p ( source_path org id )
    : ~ ? Json out @ ?Json { F }
    ?? ( read_file ( string_data p ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T j → { ? ( json_is_obj j ) { = out @ ?Json { T j } } { ( json_free j ) } }
                F _ → {}
            }
            ( string_free txt )
        }
        F _ → {}
    }
    ( string_free p )
    ^ out
}

// Written whole to a temp name and renamed over the old: a crash
// mid-write leaves the previous record, not half of the new one.
@ source_save s org Json src → b {
    : String id ( __src_jstr src `id` )
    ? ( source_id_ok ( string_data id ) ) {} { ( string_free id ) ^ F }
    : String p ( source_path org ( string_data id ) )
    : String tmp ( string_clone p )
    ( string_push_str tmp `.tmp` )
    : String txt ( json_pretty src )
    : ~ b ok F
    ?? ( write_file ( string_data tmp ) ( string_data txt ) ) {
        T _ → {
            ?? ( fs_rename ( string_data tmp ) ( string_data p ) ) {
                T _ → { = ok T }
                F _ → {}
            }
        }
        F _ → {}
    }
    ( string_free txt )
    ( string_free tmp )
    ( string_free p )
    ( string_free id )
    ^ ok
}

@ source_delete s org s id → b {
    ? ( source_id_ok id ) {} { ^ F }
    : String p ( source_path org id )
    : ~ b ok F
    ? ( file_exists ( string_data p ) ) {
        ?? ( file_delete ( string_data p ) ) { T _ → { = ok T } F _ → {} }
    } {}
    ( string_free p )
    ^ ok
}

// Every source of the organisation, oldest first.
@ sources_list s org → ( Vec Json ) {
    : String d ( orgfiles_sources_dir org )
    : ( Vec Json ) out ( vec_new [Json] )
    ?? ( dir_list ( string_data d ) ) {
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? & == ( string_len nm ) + SRC_ID_LEN 5 ( string_ends_with nm `.json` ) {
                            : String id ( string_substr nm 0 SRC_ID_LEN )
                            ?? ( source_load org ( string_data id ) ) {
                                T j → { ( vec_push [Json] out j ) }
                                F _ → {}
                            }
                            ( string_free id )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _ → {}
    }
    ( string_free d )
    // Insertion sort on created_at: a folder holds a handful of sources.
    : i m ( vec_len [Json] out )
    : ~ i a 1
    ~ < a m {
        : ~ i b a
        : ~ b going T
        ~ & going > b 0 {
            : i ca ?? ( vec_get [Json] out b ) { T x → ( _src_jint x `created_at` 0 ) F _ → 0 }
            : i cb ?? ( vec_get [Json] out - b 1 ) { T x → ( _src_jint x `created_at` 0 ) F _ → 0 }
            ? < ca cb { ( vec_swap [Json] out b - b 1 ) = b - b 1 } { = going F }
        }
        = a + a 1
    }
    ^ out
}

@ sources_free ( Vec Json ) xs → v {
    ( vec_free_with [Json] xs \ Json j → v { ( json_free j ) } )
}

// ── Validation ────────────────────────────────────────────────────────

// Apply `body` (what a caller sent) to `src` (a record, fresh or loaded),
// field by field, refusing the first thing that is wrong. Fields the
// body leaves out keep what the record has. Returns "" when it is good.
@ source_apply Json src Json body → String {
    ? ( json_is_obj body ) {} { ^ ( string_from `the body must be a JSON object` ) }

    ? ( json_obj_has body `kind` ) {
        : String kind ( __src_jstr body `kind` )
        : b ok | == ( nurl_str_eq ( string_data kind ) SRC_KIND_WFS ) 1 == ( nurl_str_eq ( string_data kind ) SRC_KIND_HTTP ) 1
        ? ok { ( __src_set_str src `kind` ( string_data kind ) ) } {}
        ( string_free kind )
        ? ok {} { ^ ( string_from `kind must be "wfs" or "http"` ) }
    } {}
    : b is_http ( source_is_http src )

    ? ( json_obj_has body `url` ) {
        : String url0 ( __src_jstr body `url` )
        : String url ( string_trim url0 )
        ( string_free url0 )
        : b ok & ( wfs_url_ok ( string_data url ) ) ( __src_text_ok ( string_data url ) 2048 )
        ? ok {
            // A WFS is named by its endpoint, the requests built on it; an
            // HTTP source is the URL exactly as given, query string and all.
            ? is_http { ( __src_set_str src `url` ( string_data url ) ) } {
                : String base ( wfs_base_url ( string_data url ) )
                ( __src_set_str src `url` ( string_data base ) )
                ( string_free base )
            }
        } {}
        ( string_free url )
        ? ok {} { ^ ( string_from ? is_http `url must be an http(s) URL` `url must be an http(s) WFS endpoint` ) }
    } {}

    ? ( json_obj_has body `method` ) {
        : String m0 ( __src_jstr body `method` )
        : String m ( string_to_upper m0 )
        ( string_free m0 )
        : b ok | | == ( nurl_str_eq ( string_data m ) `GET` ) 1 == ( nurl_str_eq ( string_data m ) `POST` ) 1 == ( nurl_str_eq ( string_data m ) `PUT` ) 1
        ? ok { ( __src_set_str src `method` ( string_data m ) ) } {}
        ( string_free m )
        ? ok {} { ^ ( string_from `method must be GET, POST or PUT` ) }
    } {}

    ? ( json_obj_has body `headers` ) {
        ?? ( json_obj_get body `headers` ) {
            T hv → {
                ? ( json_is_obj hv ) {} { ^ ( string_from `headers must be an object of header values` ) }
                : ( Vec String ) keys ( json_obj_keys hv )
                : i nk ( vec_len [String] keys )
                : ~ String bad ( string_new )
                : Json merged ( json_obj_new )
                : ~ i k 0
                ~ & < k nk == ( string_len bad ) 0 {
                    ?? ( vec_get [String] keys k ) {
                        T key → {
                            ? ( __src_header_name_ok ( string_data key ) ) {} { ( string_free bad ) = bad ( string_from `a header name may hold letters, digits and dashes only` ) }
                            ?? ( json_obj_get hv ( string_data key ) ) {
                                T v → {
                                    ? ( json_is_str v ) {
                                        ? ( __src_text_ok ( json_str_data v ) 1024 ) {} { ( string_free bad ) = bad ( string_from `a header value is not printable text` ) }
                                        // The mask sent back: keep the stored value.
                                        ? == ( nurl_str_eq ( json_str_data v ) SRC_MASK ) 1 {
                                            ?? ( json_obj_get src `headers` ) {
                                                T oh → { ?? ( json_obj_get oh ( string_data key ) ) { T ov → { ( json_obj_set merged ( string_data key ) ( json_clone ov ) ) } F _ → {} } }
                                                F _ → {}
                                            }
                                        } { ( json_obj_set merged ( string_data key ) ( json_clone v ) ) }
                                    } { ( string_free bad ) = bad ( string_from `header values must be strings` ) }
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
                ? > nk SRC_HEADERS_MAX { ( string_free bad ) = bad ( string_from `too many headers` ) } {}
                ? > ( string_len bad ) 0 { ( json_free merged ) ^ bad } {}
                ( string_free bad )
                ( json_obj_set src `headers` merged )
            }
            F _ → {}
        }
    } {}

    ? ( json_obj_has body `body` ) {
        : String b ( __src_jstr body `body` )
        : b ok <= ( string_len b ) SRC_BODY_MAX
        ? ok { ( __src_set_str src `body` ( string_data b ) ) } {}
        ( string_free b )
        ? ok {} { ^ ( string_from `body is too long` ) }
    } {}

    ? ( json_obj_has body `path` ) {
        : String p0 ( __src_jstr body `path` )
        : String p ( string_trim p0 )
        ( string_free p0 )
        : b ok ( __src_text_ok ( string_data p ) 200 )
        ? ok { ( __src_set_str src `path` ( string_data p ) ) } {}
        ( string_free p )
        ? ok {} { ^ ( string_from `path must be a dotted path into the answer (data.items)` ) }
    } {}

    ? ( json_obj_has body `query` ) {
        : String q ( __src_jstr body `query` )
        : b ok & > ( string_len q ) 0 ( __src_text_ok ( string_data q ) SRC_QUERY_MAX )
        ? ok { ( __src_set_str src `query` ( string_data q ) ) } {}
        ( string_free q )
        ? ok {} { ^ ( string_from `query must name a stored query (fmi::observations::weather::simple)` ) }
    } {}

    ? ( json_obj_has body `params` ) {
        ?? ( json_obj_get body `params` ) {
            T pv → {
                ? ( json_is_obj pv ) {} { ^ ( string_from `params must be an object of parameter values` ) }
                : ( Vec String ) keys ( json_obj_keys pv )
                : i nk ( vec_len [String] keys )
                : ~ String bad ( string_new )
                : ~ i k 0
                ~ & < k nk == ( string_len bad ) 0 {
                    ?? ( vec_get [String] keys k ) {
                        T key → {
                            ? ( __src_text_ok ( string_data key ) 64 ) {} { = bad ( string_from `a parameter name is not printable text` ) }
                            ?? ( json_obj_get pv ( string_data key ) ) {
                                T v → {
                                    ? | | ( json_is_str v ) ( json_is_num v ) ( json_is_bool v ) {
                                        ? ( json_is_str v ) {
                                            ? ( __src_text_ok ( json_str_data v ) 512 ) {} {
                                                ( string_free bad )
                                                = bad ( string_from `a parameter value is not printable text` )
                                            }
                                        } {}
                                    } {
                                        ( string_free bad )
                                        = bad ( string_from `parameter values must be strings or numbers` )
                                    }
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
                ? > nk SRC_PARAMS_MAX { ( string_free bad ) = bad ( string_from `too many parameters` ) } {}
                ? > ( string_len bad ) 0 { ^ bad } {}
                ( string_free bad )
                ( json_obj_set src `params` ( json_clone pv ) )
            }
            F _ → {}
        }
    } {}

    ? ( json_obj_has body `mode` ) {
        : String mode ( __src_jstr body `mode` )
        : b ok | == ( nurl_str_eq ( string_data mode ) SRC_MODE_STORED ) 1 == ( nurl_str_eq ( string_data mode ) SRC_MODE_TYPE ) 1
        ? ok { ( __src_set_str src `mode` ( string_data mode ) ) } {}
        ( string_free mode )
        ? ok {} { ^ ( string_from `mode must be "stored" (a stored query) or "type" (a feature type)` ) }
    } {}

    ? ( json_obj_has body `time_field` ) {
        : String tf ( __src_jstr body `time_field` )
        : b ok ( __src_text_ok ( string_data tf ) 64 )
        ? ok { ( __src_set_str src `time_field` ( string_data tf ) ) } {}
        ( string_free tf )
        ? ok {} { ^ ( string_from `time_field must be a column name` ) }
    } {}

    ? ( json_obj_has body `categorical` ) {
        ?? ( json_obj_get body `categorical` ) {
            T cv → {
                ? ( json_is_arr cv ) {} { ^ ( string_from `categorical must be an array of column names` ) }
                : i ncv ( json_arr_len cv )
                ? > ncv SRC_FEATURES_MAX { ^ ( string_from `too many categorical columns` ) } {}
                : ~ i k 0
                ~ < k ncv {
                    ?? ( json_arr_get cv k ) {
                        T f → {
                            ? & ( json_is_str f ) & > ( nurl_str_len ( json_str_data f ) ) 0 ( __src_text_ok ( json_str_data f ) 64 ) {} {
                                ^ ( string_from `every categorical entry must be a column name` )
                            }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( json_obj_set src `categorical` ( json_clone cv ) )
            }
            F _ → {}
        }
    } {}

    ? ( json_obj_has body `features` ) {
        ?? ( json_obj_get body `features` ) {
            T fv → {
                ? ( json_is_arr fv ) {} { ^ ( string_from `features must be an array of column names` ) }
                : i nf ( json_arr_len fv )
                ? > nf SRC_FEATURES_MAX { ^ ( string_from `too many features` ) } {}
                : ~ i k 0
                ~ < k nf {
                    ?? ( json_arr_get fv k ) {
                        T f → {
                            ? & ( json_is_str f ) & > ( nurl_str_len ( json_str_data f ) ) 0 ( __src_text_ok ( json_str_data f ) 64 ) {} {
                                ^ ( string_from `every feature must be a column name` )
                            }
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( json_obj_set src `features` ( json_clone fv ) )
            }
            F _ → {}
        }
    } {}

    ? ( json_obj_has body `model` ) {
        : String m ( __src_jstr body `model` )
        : b ok ( __src_model_ok ( string_data m ) )
        ? ok { ( __src_set_str src `model` ( string_data m ) ) } {}
        ( string_free m )
        ? ok {} { ^ ( string_from `model must be a model name: letters, numbers and underscores` ) }
    } {}

    ? ( json_obj_has body `interval_minutes` ) {
        : i iv ( _src_jint body `interval_minutes` 0 )
        ? | < iv 1 > iv SRC_INTERVAL_MAX { ^ ( string_from `interval_minutes must be between 1 and 10080` ) } {}
        ( __src_set_int src `interval_minutes` iv )
    } {}

    ? ( json_obj_has body `history_hours` ) {
        : i hh ( _src_jint body `history_hours` 0 )
        ? | < hh 1 > hh SRC_HISTORY_MAX { ^ ( string_from `history_hours must be between 1 and 8760` ) } {}
        ( __src_set_int src `history_hours` hh )
    } {}

    ? ( json_obj_has body `calendar` ) { ( json_obj_set src `calendar` ( json_bool ( __src_jbool body `calendar` T ) ) ) } {}
    ? ( json_obj_has body `allow_future` ) { ( json_obj_set src `allow_future` ( json_bool ( __src_jbool body `allow_future` F ) ) ) } {}
    ? ( json_obj_has body `finetune_rate` ) {
        : f fr ( __src_jfloat body `finetune_rate` -1.0 )
        ? | < fr 0.0 > fr 0.5 { ^ ( string_from `finetune_rate must be between 0 (no calibration) and 0.5` ) } {}
        ( json_obj_set src `finetune_rate` ( json_float fr ) )
    } {}
    ? ( json_obj_has body `enabled` ) { ( json_obj_set src `enabled` ( json_bool ( __src_jbool body `enabled` T ) ) ) } {}

    ? ( json_obj_has body `name` ) {
        : String nm0 ( __src_jstr body `name` )
        : String nm ( string_trim nm0 )
        ( string_free nm0 )
        : b ok ( __src_text_ok ( string_data nm ) SRC_NAME_MAX )
        ? ok { ( __src_set_str src `name` ( string_data nm ) ) } {}
        ( string_free nm )
        ? ok {} { ^ ( string_from `name must be printable text of at most 80 characters` ) }
    } {}

    // What a complete record must have.
    : String url ( __src_jstr src `url` )
    : String q ( __src_jstr src `query` )
    : String m ( __src_jstr src `model` )
    : b have & & > ( string_len url ) 0 | is_http > ( string_len q ) 0 > ( string_len m ) 0
    ( string_free m )
    ? have {} { ( string_free url ) ( string_free q ) ^ ( string_from ? is_http `a source needs url and model` `a source needs url, query and model` ) }
    // A nameless source is called after its query, or its URL.
    : String nm ( __src_jstr src `name` )
    ? == ( string_len nm ) 0 { ( __src_set_str src `name` ? is_http ( string_data url ) ( string_data q ) ) } {}
    ( string_free nm )
    ( string_free url )
    ( string_free q )
    ^ ( string_new )
}

// A header name: RFC 7230 tokens, in practice letters, digits and dashes.
@ __src_header_name_ok s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n 64 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get name k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        ? | | | digit lower upper | == c 45 == c 95 {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ source_is_http Json src → b {
    : String kind ( __src_jstr src `kind` )
    : b h == ( nurl_str_eq ( string_data kind ) SRC_KIND_HTTP ) 1
    ( string_free kind )
    ^ h
}

// A record with every field present, so a reader never has to default.
@ __src_blank s id s by i now → Json {
    : Json o ( json_obj_new )
    ( __src_set_str o `id` id )
    ( __src_set_str o `name` `` )
    ( __src_set_str o `kind` SRC_KIND_WFS )
    ( __src_set_str o `url` `` )
    ( __src_set_str o `query` `` )
    ( json_obj_set o `params` ( json_obj_new ) )
    ( __src_set_str o `mode` SRC_MODE_STORED )
    ( __src_set_str o `method` `GET` )
    ( json_obj_set o `headers` ( json_obj_new ) )
    ( __src_set_str o `body` `` )
    ( __src_set_str o `path` `` )
    ( json_obj_set o `features` ( json_arr_new ) )
    ( json_obj_set o `categorical` ( json_arr_new ) )
    ( __src_set_str o `time_field` `` )
    ( __src_set_str o `model` `` )
    ( __src_set_int o `interval_minutes` SRC_INTERVAL_DEFAULT )
    ( __src_set_int o `history_hours` SRC_HISTORY_DEFAULT )
    ( json_obj_set o `calendar` ( json_bool T ) )
    ( json_obj_set o `allow_future` ( json_bool F ) )
    ( json_obj_set o `finetune_rate` ( json_float SRC_FINETUNE_DEFAULT ) )
    ( json_obj_set o `enabled` ( json_bool T ) )
    ( __src_set_str o `created_by` by )
    ( __src_set_int o `created_at` now )
    ( __src_set_int o `updated_at` now )
    ( __src_set_int o `first_time` 0 )
    ( __src_set_int o `last_time` 0 )
    ( __src_set_int o `last_run` 0 )
    ( __src_set_str o `last_status` `` )
    ( __src_set_str o `last_error` `` )
    ( __src_set_int o `last_rows` 0 )
    ( __src_set_int o `runs` 0 )
    ( __src_set_int o `total_rows` 0 )
    ^ o
}

// Create a source from `body`; Ok(the saved record) or Err(why).
@ source_create s org Json body s by i now → !Json String {
    // rand_hex_str takes a byte count and writes two digits per byte.
    : String id ( rand_hex_str / SRC_ID_LEN 2 )
    : Json src ( __src_blank ( string_data id ) by now )
    ( string_free id )
    : String err ( source_apply src body )
    ? > ( string_len err ) 0 { ( json_free src ) ^ @ !Json String { F err } } {}
    ( string_free err )
    ? ( source_save org src ) {} {
        ( json_free src )
        ^ @ !Json String { F ( string_from `the source could not be written to the organisation's folder` ) }
    }
    ^ @ !Json String { T src }
}

// Change a source. A changed query, url or parameters make the fetched
// span meaningless — the next run starts over from `history_hours` back.
@ source_update s org s id Json body i now → !Json String {
    ?? ( source_load org id ) {
        T src → {
            : String u0 ( __src_jstr src `url` )
            : String q0 ( __src_jstr src `query` )
            : String p0 ?? ( json_obj_get src `params` ) { T p → ( json_stringify p ) F _ → ( string_new ) }
            ( string_push_str p0 ( string_data ( __src_jstr src `mode` ) ) )
            ( string_push_str p0 ( string_data ( __src_jstr src `time_field` ) ) )
            ( string_push_str p0 ( string_data ( __src_jstr src `method` ) ) )
            ( string_push_str p0 ( string_data ( __src_jstr src `body` ) ) )
            ( string_push_str p0 ( string_data ( __src_jstr src `path` ) ) )
            ?? ( json_obj_get src `headers` ) { T h → { : String ht ( json_stringify h ) ( string_push_str p0 ( string_data ht ) ) ( string_free ht ) } F _ → {} }
            : String err ( source_apply src body )
            ? > ( string_len err ) 0 {
                ( string_free u0 ) ( string_free q0 ) ( string_free p0 )
                ( json_free src )
                ^ @ !Json String { F err }
            } {}
            ( string_free err )
            : String u1 ( __src_jstr src `url` )
            : String q1 ( __src_jstr src `query` )
            : String p1 ?? ( json_obj_get src `params` ) { T p → ( json_stringify p ) F _ → ( string_new ) }
            ( string_push_str p1 ( string_data ( __src_jstr src `mode` ) ) )
            ( string_push_str p1 ( string_data ( __src_jstr src `time_field` ) ) )
            ( string_push_str p1 ( string_data ( __src_jstr src `method` ) ) )
            ( string_push_str p1 ( string_data ( __src_jstr src `body` ) ) )
            ( string_push_str p1 ( string_data ( __src_jstr src `path` ) ) )
            ?? ( json_obj_get src `headers` ) { T h → { : String ht ( json_stringify h ) ( string_push_str p1 ( string_data ht ) ) ( string_free ht ) } F _ → {} }
            : b same & & ( string_eq u0 u1 ) ( string_eq q0 q1 ) ( string_eq p0 p1 )
            ( string_free u0 ) ( string_free q0 ) ( string_free p0 )
            ( string_free u1 ) ( string_free q1 ) ( string_free p1 )
            ? same {} {
                ( __src_set_int src `first_time` 0 )
                ( __src_set_int src `last_time` 0 )
            }
            ( __src_set_int src `updated_at` now )
            ? ( source_save org src ) {} {
                ( json_free src )
                ^ @ !Json String { F ( string_from `the source could not be written to the organisation's folder` ) }
            }
            ^ @ !Json String { T src }
        }
        F _ → { ^ @ !Json String { F ( string_from `no such source` ) } }
    }
}

// ── Windows ───────────────────────────────────────────────────────────

: SrcWindow { i start i end }

// The span a run fetches. Forward: from just after the newest observation
// seen to now, or `history_hours` back on the first run. Backfill: from
// `hours` back to just before the oldest observation seen — never over
// ground already covered. An empty window has end < start.
// Fetched whole on every run, its clock in the records: a feature type,
// and an HTTP source alike.
@ source_is_type Json src → b {
    ? ( source_is_http src ) { ^ T } {}
    : String mode ( __src_jstr src `mode` )
    : b t == ( nurl_str_eq ( string_data mode ) SRC_MODE_TYPE ) 1
    ( string_free mode )
    ^ t
}

@ source_window Json src i now b backfill i hours → SrcWindow {
    : i first ( _src_jint src `first_time` 0 )
    : i last ( _src_jint src `last_time` 0 )
    : i hist ( _src_jint src `history_hours` SRC_HISTORY_DEFAULT )
    // Nothing dated past the fetch is taken unless the source says so
    // (`allow_future`: a price list published ahead): a record from
    // tomorrow would put the span, the calendar features and the
    // forecast ahead of the clock.
    : i cap ? ( __src_jbool src `allow_future` F ) + now SRC_FAR_FUTURE now
    ? backfill {
        : i start - now * hours 3600
        : i end ? > first 0 - first 1 now
        ^ @ SrcWindow { start end }
    } {}
    // A feature type or an http answer is fetched whole; the window says
    // which of its records land: newer than what was seen, and on the
    // first run no older than history_hours.
    : i start ? > last 0 + last 1 - now * hist 3600
    ^ @ SrcWindow { start ? ( source_is_type src ) cap now }
}

// ── Rows → points ─────────────────────────────────────────────────────

: SrcProject {
    ( Vec Json ) points
    i outside  // rows whose timestamp fell outside the window
    i empty  // rows with none of the chosen features
    i unstamped  // rows whose time could not be read
    i oldest
    i newest
}

@ __src_project_free SrcProject sp → v {
    ( vec_free_with [Json] . sp points \ Json j → v { ( json_free j ) } )
}

// Keep, from every pivoted row inside [lo, hi], the chosen features (all
// parameters when none are chosen), the timestamp, and — when the source
// says so — the ISO time for the calendar features.
@ __src_project Json src ( Vec Json ) rows i lo i hi → SrcProject {
    : ( Vec Json ) pts ( vec_new [Json] )
    : ~ i outside 0
    : ~ i empty 0
    : ~ i unstamped 0
    : ~ i oldest 0
    : ~ i newest 0
    : b calendar ( __src_jbool src `calendar` T )
    : ( Vec String ) cats ?? ( json_obj_get src `categorical` ) {
        T cv → {
            : ( Vec String ) cs ( vec_new [String] )
            : i ncs ( json_arr_len cv )
            : ~ i k 0
            ~ < k ncs {
                ?? ( json_arr_get cv k ) {
                    T f → { ? ( json_is_str f ) { ( vec_push [String] cs ( string_from ( json_str_data f ) ) ) } {} }
                    F _ → {}
                }
                = k + k 1
            }
            cs
        }
        F _ → ( vec_new [String] )
    }
    : ( Vec String ) feats ?? ( json_obj_get src `features` ) {
        T fv → {
            : ( Vec String ) fs ( vec_new [String] )
            : i nf ( json_arr_len fv )
            : ~ i k 0
            ~ < k nf {
                ?? ( json_arr_get fv k ) {
                    T f → { ? ( json_is_str f ) { ( vec_push [String] fs ( string_from ( json_str_data f ) ) ) } {} }
                    F _ → {}
                }
                = k + k 1
            }
            fs
        }
        F _ → ( vec_new [String] )
    }
    : i nfeat ( vec_len [String] feats )
    : i n ( vec_len [Json] rows )
    : ~ i r 0
    ~ < r n {
        ?? ( vec_get [Json] rows r ) {
            T row → {
                : i ts ( _src_jint row `timestamp` 0 )
                ? <= ts 0 { = unstamped + unstamped 1 } {
                    ? | < ts lo > ts hi { = outside + outside 1 } {
                        : Json pt ( json_obj_new )
                        ( __src_set_int pt `timestamp` ts )
                        ? calendar {
                            : String t ( __src_jstr row `time` )
                            ? > ( string_len t ) 0 { ( __src_set_str pt `time` ( string_data t ) ) } {}
                            ( string_free t )
                        } {}
                        : ~ i got 0
                        ? > nfeat 0 {
                            : ~ i k 0
                            ~ < k nfeat {
                                ?? ( vec_get [String] feats k ) {
                                    T f → {
                                        ?? ( json_obj_get row ( string_data f ) ) {
                                            T v → { ( json_obj_set pt ( string_data f ) ( __src_as_feature v ( __src_str_in cats ( string_data f ) ) ) ) = got + got 1 }
                                            F _ → {}
                                        }
                                    }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                        } {
                            : ( Vec String ) keys ( json_obj_keys row )
                            : i nk ( vec_len [String] keys )
                            : ~ i k 0
                            ~ < k nk {
                                ?? ( vec_get [String] keys k ) {
                                    T key → {
                                        : s ks ( string_data key )
                                        // The clock is not a feature; nor, unasked, is a
                                        // feature's identity — one-hot per feature is no model.
                                        : b clock | | == ( nurl_str_eq ks `time` ) 1 == ( nurl_str_eq ks `timestamp` ) 1 == ( nurl_str_eq ks `gml_id` ) 1
                                        ? clock {} {
                                            ?? ( json_obj_get row ks ) {
                                                T v → {
                                                    // A second date column (an interval's end, a
                                                    // publication time) is not a reading: as text
                                                    // it would be a category per row. Name it in
                                                    // `features` to take it anyway.
                                                    : ~ b date F
                                                    ? & ( json_is_str v ) ! ( __src_str_in cats ks ) {
                                                        : ImpStamp st ( imp_stamp_of_text ( json_str_data v ) )
                                                        ? | == . st kind STAMP_DATETIME == . st kind STAMP_DATE { = date T } {}
                                                    } {}
                                                    ? date {} { ( json_obj_set pt ks ( __src_as_feature v ( __src_str_in cats ks ) ) ) = got + got 1 }
                                                }
                                                F _ → {}
                                            }
                                        }
                                    }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                            ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
                        }
                        ? > got 0 {
                            ( vec_push [Json] pts pt )
                            ? | == oldest 0 < ts oldest { = oldest ts } {}
                            ? > ts newest { = newest ts } {}
                        } {
                            ( json_free pt )
                            = empty + empty 1
                        }
                    }
                }
            }
            F _ → {}
        }
        = r + r 1
    }
    ( vec_free_with [String] feats \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] cats \ String s → v { ( string_free s ) } )
    ^ @ SrcProject { pts outside empty unstamped oldest newest }
}

@ __src_str_in ( Vec String ) xs s want → b {
    : i n ( vec_len [String] xs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] xs k ) {
            T x → { ? == ( nurl_str_eq ( string_data x ) want ) 1 { ^ T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// A column value as the model should see it: as it came, or — for a
// categorical column — as text, so the preprocessing makes a one-hot
// identity of it whatever it was (a coordinate, a station code).
@ __src_as_feature Json v b categorical → Json {
    ? categorical {} { ^ ( json_clone v ) }
    ? ( json_is_str v ) { ^ ( json_clone v ) } {}
    : String txt ( json_stringify v )
    : Json out ( json_str_lit ( string_data txt ) )
    ( string_free txt )
    ^ out
}

// ── Fetching ──────────────────────────────────────────────────────────

// GET the window in day-sized chunks; every chunk's rows into one list.
// Err(why) on the first failed chunk — a partial answer is not imported,
// because the source's span would then claim ground it does not hold.
@ source_fetch Json src i start i end → !( Vec Json ) String {
    : String url ( __src_jstr src `url` )
    : String q ( __src_jstr src `query` )
    : Json params ?? ( json_obj_get src `params` ) { T p → ( json_clone p ) F _ → ( json_obj_new ) }
    : ( Vec Json ) rows ( vec_new [Json] )
    : ~ String err ( string_new )
    // A feature type, or an HTTP endpoint: one request, the whole
    // answer, no window.
    ? ( source_is_type src ) {
        : String tf ( __src_jstr src `time_field` )
        : b is_http ( source_is_http src )
        : ~ String u ( string_new )
        ? is_http { ( string_push_str u ( string_data url ) ) } {
            ( string_free u )
            = u ( wfs_url_type ( string_data url ) ( string_data q ) params )
        }
        : ~ String method ( __src_jstr src `method` )
        // A record built for a preview may carry no method: GET it is.
        ? == ( string_len method ) 0 { ( string_free method ) = method ( string_from `GET` ) } {}
        : String hbody ( __src_jstr src `body` )
        : String path ( __src_jstr src `path` )
        : Json headers ?? ( json_obj_get src `headers` ) { T h → ( json_clone h ) F _ → ( json_obj_new ) }
        : !String String fr ? is_http ( http_fetch ( string_data method ) ( string_data u ) headers ( string_data hbody ) ) ( wfs_fetch ( string_data u ) )
        ( json_free headers )
        ?? fr {
            T body → {
                : WfsPivot pv ? is_http ( http_pivot ( string_data body ) ( string_data path ) ( string_data tf ) ( now_seconds ) ) ( wfs_pivot_wide ( string_data body ) ( string_data tf ) ( now_seconds ) )
                ? > ( string_len . pv err ) 0 {
                    ? & == . pv members 0 ( string_starts_with . pv err `the feature collection holds no` ) {} {
                        ( string_free err )
                        = err ( string_clone . pv err )
                    }
                } {}
                : i nr ( vec_len [Json] . pv rows )
                : ~ i k 0
                ~ < k nr {
                    ?? ( vec_get [Json] . pv rows k ) {
                        T r → { ( vec_push [Json] rows ( json_clone r ) ) }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( wfs_pivot_free pv )
                ( string_free body )
            }
            F why → { ( string_free err ) = err why }
        }
        ( string_free path )
        ( string_free hbody )
        ( string_free method )
        ( string_free u )
        ( string_free tf )
        ( json_free params )
        ( string_free q )
        ( string_free url )
        ? > ( string_len err ) 0 {
            ( vec_free_with [Json] rows \ Json j → v { ( json_free j ) } )
            ^ @ !( Vec Json ) String { F err }
        } {}
        ^ @ !( Vec Json ) String { T rows }
    } {}
    : ~ i a start
    ~ & <= a end == ( string_len err ) 0 {
        : ~ i b + a - SRC_CHUNK_SECS 1
        ? > b end { = b end } {}
        : String u ( wfs_url_feature ( string_data url ) ( string_data q ) params a b )
        ?? ( wfs_fetch ( string_data u ) ) {
            T body → {
                : WfsPivot pv ( wfs_pivot ( string_data body ) )
                ? > ( string_len . pv err ) 0 {
                    // A window with nothing in it is not an error — a
                    // station that reported nothing that day, a
                    // forecast that starts later. Only a service that
                    // refused, or spoke another language, is.
                    ? & == . pv members 0 ( string_starts_with . pv err `the feature collection holds no` ) {} {
                        ( string_free err )
                        = err ( string_clone . pv err )
                    }
                } {}
                : i nr ( vec_len [Json] . pv rows )
                : ~ i k 0
                ~ < k nr {
                    ?? ( vec_get [Json] . pv rows k ) {
                        T r → { ( vec_push [Json] rows ( json_clone r ) ) }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( wfs_pivot_free pv )
                ( string_free body )
            }
            F why → { ( string_free err ) = err why }
        }
        ( string_free u )
        = a + b 1
    }
    ( json_free params )
    ( string_free q )
    ( string_free url )
    ? > ( string_len err ) 0 {
        ( vec_free_with [Json] rows \ Json j → v { ( json_free j ) } )
        ^ @ !( Vec Json ) String { F err }
    } {}
    ^ @ !( Vec Json ) String { T rows }
}

// ── Running ───────────────────────────────────────────────────────────

// Sources mid-run, as "<org>/<id>", so a manual run and the scheduler
// never fetch the same source at once. Touched only under the service
// lock.
: ~ i g_src_running 0

@ __src_running → ( Vec String ) {
    ? != g_src_running 0 { ^ # ( Vec String ) g_src_running } {}
    : ( Vec String ) v ( vec_new [String] )
    = g_src_running # i v
    ^ v
}

@ __src_run_key s org s id → String {
    : String k ( string_from org )
    ( string_push_char k 47 )
    ( string_push_str k id )
    ^ k
}

@ source_is_running s org s id → b {
    : String key ( __src_run_key org id )
    : ( Vec String ) v ( __src_running )
    : i n ( vec_len [String] v )
    : ~ i k 0
    : ~ b found F
    ~ & < k n ! found {
        ?? ( vec_get [String] v k ) {
            T x → { ? ( string_eq x key ) { = found T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( string_free key )
    ^ found
}

@ __src_mark_running s org s id b on → v {
    : ( Vec String ) v ( __src_running )
    ? on {
        ( vec_push [String] v ( __src_run_key org id ) )
    } {
        : String key ( __src_run_key org id )
        : i n ( vec_len [String] v )
        : ~ i k 0
        : ~ i hit -1
        ~ & < k n < hit 0 {
            ?? ( vec_get [String] v k ) {
                T x → { ? ( string_eq x key ) { = hit k } {} }
                F _ → {}
            }
            = k + k 1
        }
        ? >= hit 0 {
            ?? ( vec_remove [String] v hit ) { T gone → { ( string_free gone ) } F _ → {} }
        } {}
        ( string_free key )
    }
}

// Import projected points into the source's model, claiming a model the
// run brings into being for the organisation. Returns "" or why not.
// The caller holds the service lock.
@ __src_ingest s org Json src SrcProject sp i now b trained_out → String {
    : String model ( __src_jstr src `model` )
    : Store st ( store_open ( orgfiles_root ) )
    : b existed ( store_exists st ( string_data model ) )
    : ~ String err ( string_new )
    ? & existed ( anomaly_authz_enabled ) {
        ?? ( az_db_open org ) {
            T db → {
                ? ( az_model_in_org db ( string_data model ) ) {} {
                    ( string_free err )
                    = err ( string_from `model ` )
                    ( string_push_str err ( string_data model ) )
                    ( string_push_str err ` is not this organisation's: pick another name, or have an administrator assign it` )
                }
            }
            F _ → {
                ( string_free err )
                = err ( string_from `the organisation's database could not be opened` )
            }
        }
    } {}
    ? > ( string_len err ) 0 {
        ( store_free st )
        ( string_free model )
        ^ err
    } {}
    : *Model mo ( model_open st ( string_data model ) )
    // A categorical column is declared before the first point arrives,
    // or a coordinate would be judged a number by its first value. On a
    // model that already knows the column the kind is settled and the
    // declaration is a no-op.
    ?? ( json_obj_get src `categorical` ) {
        T cv → {
            : *Meta mm . mo meta
            : i ncv ( json_arr_len cv )
            : ~ i k 0
            ~ < k ncv {
                ?? ( json_arr_get cv k ) {
                    T f → { ? ( json_is_str f ) { : b _d ( meta_declare_column mm ( json_str_data f ) COL_CATEGORICAL ) } {} }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
    : ImportReport rep ( model_import_at mo . sp points now )
    ? > ( string_len . rep err ) 0 {
        ( string_free err )
        = err ( string_clone . rep err )
    } {
        ? & ! existed ( anomaly_authz_enabled ) {
            ?? ( az_db_open org ) {
                T db → {
                    : String by ( __src_jstr src `created_by` )
                    : b _c ( az_model_claim db ( string_data model ) ( string_data by ) now F )
                    ( string_free by )
                }
                F _ → {}
            }
        } {}
    }
    ( __src_set_int src `last_rows` . rep accepted )
    ( __src_set_int src `total_rows` + ( _src_jint src `total_rows` 0 ) . rep accepted )
    ( json_obj_set src `last_trained` ( json_bool . rep trained ) )
    ? . rep trained { ( json_obj_set src `last_tuned` ( json_bool ( __src_first_train mo src . sp points now ) ) ) } {}
    ( import_report_free rep )
    ( model_free mo )
    ( store_free st )
    ( string_free model )
    ^ err
}

// The step of a run's points: the median gap between their timestamps
// in seconds, 0 when there are too few to say.
@ source_step_of ( Vec Json ) points → i {
    : i n ( vec_len [Json] points )
    ? < n 3 { ^ 0 } {}
    : ( Vec i ) ts ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Json] points k ) { T p → { ( vec_push [i] ts ( _src_jint p `timestamp` 0 ) ) } F _ → {} }
        = k + k 1
    }
    ( sort_by [i] ts \ i a i b → i { ? < a b { ^ -1 } {} ? > a b { ^ 1 } {} ^ 0 } )
    : ( Vec i ) gaps ( vec_new [i] )
    = k 1
    ~ < k ( vec_len [i] ts ) {
        : i g - ( _src_geti ts k ) ( _src_geti ts - k 1 )
        ? > g 0 { ( vec_push [i] gaps g ) } {}
        = k + k 1
    }
    ( vec_free [i] ts )
    : i ng ( vec_len [i] gaps )
    ? < ng 2 { ( vec_free [i] gaps ) ^ 0 } {}
    ( sort_by [i] gaps \ i a i b → i { ? < a b { ^ -1 } {} ? > a b { ^ 1 } {} ^ 0 } )
    : i med ( _src_geti gaps / ng 2 )
    ( vec_free [i] gaps )
    ^ med
}

@ _src_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } }
}

// The seasonal period, in rows, a step implies: the day for a step up to
// twelve hours (144 rows at ten minutes, 24 at an hour), the week for a
// daily step, none otherwise.
@ source_season_of i step → i {
    ^ ( anomaly_season_of step )
}

// What a run's first train settles once: the margins, calibrated to
// `finetune_rate` of the ring (model_autotune_at), and the forecast
// version's season from the points' step — so that switching the
// version on fits the daily rhythm the feed has, not a plain ARIMA. A
// model tuned before, by hand or by an earlier run, is left as it is.
// Returns whether the margins were calibrated now.
@ __src_first_train * Model mo Json src ( Vec Json ) points i now → b {
    : *Meta mm ( model_metadata mo )
    ? == . mm tuned_at 0 {} { ^ F }
    : i season ( source_season_of ( source_step_of points ) )
    ? > season 0 {
        : i at ( meta_find_version mm ANOM_FC_NAME )
        : ~ b unset T
        ? >= at 0 { ?? ( vec_get [VerCfg] . mm versions at ) { T vc → { ? > . vc window_size 0 { = unset F } {} } F _ → {} } } {}
        ? unset { : b _w ( model_set_version_window mo ANOM_FC_NAME season 0 ) } {}
    } {}
    ^ ( model_autotune_at mo ( __src_jfloat src `finetune_rate` SRC_FINETUNE_DEFAULT ) now )
}

// What a run does once the answer is in hand: the record re-read (it may
// have been edited while the fetch ran), the rows projected onto the
// window and the chosen features, the points imported, the span and the
// statistics updated, the record saved. Public so a body obtained some
// other way — a test's fixture, a file — takes the same path. `rows` are
// consumed. The caller holds the service lock.
@ source_run_rows s org s id ! ( Vec Json ) String fr SrcWindow w b backfill i now → Json {
    : Json out ( json_obj_new )
    ( __src_set_str out `id` id )
    ( __src_set_int out `window_start` . w start )
    ( __src_set_int out `window_end` . w end )
    ?? ( source_load org id ) {
        T cur → {
            ( __src_set_int cur `last_run` now )
            ( __src_set_int cur `runs` + ( _src_jint cur `runs` 0 ) 1 )
            ?? fr {
                T rows → {
                    : SrcProject sp ( __src_project cur rows . w start . w end )
                    ( vec_free_with [Json] rows \ Json j → v { ( json_free j ) } )
                    ( __src_set_int out `fetched` + + + ( vec_len [Json] . sp points ) . sp outside . sp empty . sp unstamped )
                    ( __src_set_int out `skipped_outside` . sp outside )
                    ( __src_set_int out `skipped_empty` . sp empty )
                    ( __src_set_int out `skipped_unstamped` . sp unstamped )
                    : ~ String err ( string_new )
                    ? > ( vec_len [Json] . sp points ) 0 {
                        ( string_free err )
                        = err ( __src_ingest org cur sp now F )
                    } {
                        ( __src_set_int cur `last_rows` 0 )
                    }
                    ? > ( string_len err ) 0 {
                        ( __src_set_str out `status` `error` )
                        ( __src_set_str out `message` ( string_data err ) )
                        ( __src_set_int out `ingested` 0 )
                        ( __src_set_str cur `last_status` `error` )
                        ( __src_set_str cur `last_error` ( string_data err ) )
                    } {
                        ( __src_set_str out `status` `success` )
                        ( __src_set_int out `ingested` ( vec_len [Json] . sp points ) )
                        ( __src_set_str cur `last_status` `ok` )
                        ( __src_set_str cur `last_error` `` )
                        // The span grows over the window asked for, not
                        // only the points found: an empty day fetched is
                        // a day fetched. A feature type has no window of
                        // its own: its span is the features' clocks, or
                        // the fetch time of a snapshot.
                        : i first ( _src_jint cur `first_time` 0 )
                        : i last ( _src_jint cur `last_time` 0 )
                        // A feature type's span moves only with the clocks
                        // of the features that landed: a run that found
                        // nothing new leaves it, so a reading published
                        // late is not skipped as older than "now".
                        : b typed ( source_is_type cur )
                        : i lo ? typed ? > . sp oldest 0 . sp oldest first . w start
                        : i hi ? typed ? > . sp newest 0 . sp newest last . w end
                        ? backfill {
                            ? | == first 0 < lo first { ( __src_set_int cur `first_time` lo ) } {}
                            ? == last 0 { ( __src_set_int cur `last_time` hi ) } {}
                        } {
                            ? == first 0 { ( __src_set_int cur `first_time` lo ) } {}
                            ? > hi last { ( __src_set_int cur `last_time` hi ) } {}
                        }
                        ? > . sp newest 0 { ( __src_set_int out `newest` . sp newest ) } {}
                        ? > . sp oldest 0 { ( __src_set_int out `oldest` . sp oldest ) } {}
                    }
                    ( string_free err )
                    ( __src_project_free sp )
                }
                F why → {
                    ( __src_set_str out `status` `error` )
                    ( __src_set_str out `message` ( string_data why ) )
                    ( __src_set_int out `fetched` 0 )
                    ( __src_set_int out `ingested` 0 )
                    ( __src_set_str cur `last_status` `error` )
                    ( __src_set_str cur `last_error` ( string_data why ) )
                    ( string_free why )
                }
            }
            : b _s ( source_save org cur )
            ( json_free cur )
        }
        F _ → {
            ?? fr {
                T rows → { ( vec_free_with [Json] rows \ Json j → v { ( json_free j ) } ) }
                F why → { ( string_free why ) }
            }
            ( __src_set_str out `status` `error` )
            ( __src_set_str out `message` `the source was deleted while it was being fetched` )
        }
    }
    ^ out
}

// One run of one source: the window, the fetch with the service lock
// released, then source_run_rows with it held. The answer is what the API
// returns and what the log line says.
//
// `backfill` with `hours` reaches back before the oldest observation the
// source has seen; otherwise the run is forward.
@ source_run s org s id b backfill i hours i now ( @ v ) unlock ( @ v ) lock → Json {
    ? ( source_is_running org id ) {
        : Json busy ( json_obj_new )
        ( __src_set_str busy `id` id )
        ( __src_set_str busy `status` `busy` )
        ( __src_set_str busy `message` `this source is being fetched right now` )
        ^ busy
    } {}
    ?? ( source_load org id ) {
        T src → {
            : SrcWindow w ( source_window src now backfill hours )
            ? > . w start . w end {
                : Json none ( json_obj_new )
                ( __src_set_str none `id` id )
                ( __src_set_str none `status` `success` )
                ( __src_set_str none `message` ? ( source_is_type src ) `nothing to fetch: a feature type has no history to reach back to` `nothing to fetch: the window is already covered` )
                ( __src_set_int none `window_start` . w start )
                ( __src_set_int none `window_end` . w end )
                ( __src_set_int none `fetched` 0 )
                ( __src_set_int none `ingested` 0 )
                ( json_free src )
                ^ none
            } {}
            ( __src_mark_running org id T )
            ( unlock )
            : !( Vec Json ) String fr ( source_fetch src . w start . w end )
            ( lock )
            ( __src_mark_running org id F )
            ( json_free src )
            ^ ( source_run_rows org id fr w backfill now )
        }
        F _ → {
            : Json none ( json_obj_new )
            ( __src_set_str none `id` id )
            ( __src_set_str none `status` `error` )
            ( __src_set_str none `message` `no such source` )
            ^ none
        }
    }
}

// ── The scheduler ─────────────────────────────────────────────────────

: SrcRef { String org String id }

// Every enabled source whose interval has passed since its last run.
@ sources_due i now → ( Vec SrcRef ) {
    : ( Vec SrcRef ) out ( vec_new [SrcRef] )
    : ( Vec String ) orgs ( orgfiles_orgs )
    : i no ( vec_len [String] orgs )
    : ~ i o 0
    ~ < o no {
        ?? ( vec_get [String] orgs o ) {
            T org → {
                : ( Vec Json ) srcs ( sources_list ( string_data org ) )
                : i ns ( vec_len [Json] srcs )
                : ~ i k 0
                ~ < k ns {
                    ?? ( vec_get [Json] srcs k ) {
                        T src → {
                            ? ( __src_jbool src `enabled` T ) {
                                : i last ( _src_jint src `last_run` 0 )
                                : i iv ( _src_jint src `interval_minutes` SRC_INTERVAL_DEFAULT )
                                ? <= + last * iv 60 now {
                                    ( vec_push [SrcRef] out @ SrcRef { ( string_clone org ) ( __src_jstr src `id` ) } )
                                } {}
                            } {}
                        }
                        F _ → {}
                    }
                    = k + k 1
                }
                ( sources_free srcs )
            }
            F _ → {}
        }
        = o + o 1
    }
    ( vec_free_with [String] orgs \ String s → v { ( string_free s ) } )
    ^ out
}

@ __src_refs_free ( Vec SrcRef ) xs → v {
    ( vec_free_with [SrcRef] xs \ SrcRef r → v { ( string_free . r org ) ( string_free . r id ) } )
}

// Run everything due. Called with the service lock held; the lock is let
// go for each fetch. Returns how many sources ran.
@ sources_tick i now ( @ v ) unlock ( @ v ) lock → i {
    : ( Vec SrcRef ) due ( sources_due now )
    : i n ( vec_len [SrcRef] due )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [SrcRef] due k ) {
            T r → {
                : Json rep ( source_run ( string_data . r org ) ( string_data . r id ) F 0 now unlock lock )
                : String status ( __src_jstr rep `status` )
                ? == ( nurl_str_eq ( string_data status ) `error` ) 1 {
                    : String msg ( __src_jstr rep `message` )
                    ( nurl_eprint `anomaly: source ` )
                    ( nurl_eprint ( string_data . r org ) )
                    ( nurl_eprint `/` )
                    ( nurl_eprint ( string_data . r id ) )
                    ( nurl_eprint `: ` )
                    ( nurl_eprintln ( string_data msg ) )
                    ( string_free msg )
                } {}
                ( string_free status )
                ( json_free rep )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( __src_refs_free due )
    ^ n
}

// The scheduler thread: wake, take the lock, run what is due, let go.
// Detached; it lives as long as the service.
@ sources_start_scheduler ( @ v ) unlock ( @ v ) lock → b {
    : ( @ v ) body \ → v {
        ~ T {
            ( sleep_ms SRC_TICK_MS )
            ( lock )
            : i _n ( sources_tick ( now_seconds ) unlock lock )
            ( unlock )
        }
    }
    ?? ( thread_spawn_owned body ) {
        T t → { ( thread_detach t ) ^ T }
        F _ → { ^ F }
    }
}
