// anomaly/httpsrc.nu — an HTTP endpoint answering JSON as a source of points.
//
// Most of what a service publishes is not a WFS: it is a URL that
// answers JSON — a REST API polled with a key in a header, a device's
// status page, a queue's metrics. This module fetches one such URL
// (any method, any headers, a body if asked) and turns the answer into
// the same records the WFS pivots make (src/wfs.nu), so everything
// downstream — the chosen columns, the categorical ones, the clock, the
// import — is the same code.
//
//   http_fetch    method + URL + headers + body → the answer's text
//   http_pivot    JSON text + a path + a clock → records
//
// Records are found at `path` (dotted, indexes allowed: `data.items`,
// `stations.0.values`; "" = the whole answer): an array gives one record
// per element, an object gives one record — a snapshot. A record is
// flattened: a nested object's keys are prefixed with the parent's
// (`current_temperature`), numbers and booleans are numbers, short
// strings are text, arrays and nulls are left out. The clock is read as
// for a feature type: a named property, the first that reads as a date,
// or none — then the fetch time.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `deps/http-client/src/http_client.nu`
$ `src/importer.nu`
$ `src/wfs.nu`

: i HTTP_TEXT_MAX 200
: i HTTP_DEPTH_MAX 6

// ── Flattening ────────────────────────────────────────────────────────

// Every scalar below `node` into `row` under `parent_key` names; `cols`
// learns the names.
@ __hs_flatten Json node Json row ( Vec String ) cols s parent i depth → v {
    ? > depth HTTP_DEPTH_MAX { ^ } {}
    : ( Vec String ) keys ( json_obj_keys node )
    : i n ( vec_len [String] keys )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] keys k ) {
            T key → {
                : ~ String name ( string_new )
                ? > ( nurl_str_len parent ) 0 {
                    ( string_push_str name parent )
                    ( string_push_char name 95 )
                } {}
                ( string_push_str name ( string_data key ) )
                ?? ( json_obj_get node ( string_data key ) ) {
                    T v → {
                        ? ( json_is_obj v ) {
                            ( __hs_flatten v row cols ( string_data name ) + depth 1 )
                        } {
                            ? ( json_obj_has row ( string_data name ) ) {} {
                                ? ( json_is_num v ) {
                                    ( json_obj_set row ( string_data name ) ( json_clone v ) )
                                    ( _wfs_col_add cols ( string_data name ) )
                                } {}
                                ? ( json_is_bool v ) {
                                    ( json_obj_set row ( string_data name ) ( json_int ? ( json_bool_val v ) 1 0 ) )
                                    ( _wfs_col_add cols ( string_data name ) )
                                } {}
                                ? ( json_is_str v ) {
                                    : s txt ( json_str_data v )
                                    : i tl ( nurl_str_len txt )
                                    ? & > tl 0 <= tl HTTP_TEXT_MAX {
                                        ( json_obj_set row ( string_data name ) ( json_str_lit txt ) )
                                        ( _wfs_col_add cols ( string_data name ) )
                                    } {}
                                } {}
                            }
                        }
                    }
                    F _ → {}
                }
                ( string_free name )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
}

// One JSON object → one record with its clock, into `rows`.
@ __hs_record Json obj ( Vec Json ) rows ( Vec String ) cols s time_field i now → b {
    : Json row ( json_obj_new )
    ( __hs_flatten obj row cols `` 0 )
    : ( Vec String ) got ( json_obj_keys row )
    : i ngot ( vec_len [String] got )
    ( vec_free_with [String] got \ String s → v { ( string_free s ) } )
    ? == ngot 0 { ( json_free row ) ^ F } {}
    ? ( _wfs_wide_clock row time_field ) {} { ( json_obj_set row `timestamp` ( json_int now ) ) }
    ( vec_push [Json] rows row )
    ^ T
}

// JSON text → records at `path`. `err` says what was wrong when nothing
// could be read.
@ http_pivot s text s path s time_field i now → WfsPivot {
    ?? ( json_parse text ) {
        T body → {
            : ( Vec Json ) rows ( vec_new [Json] )
            : ( Vec String ) cols ( vec_new [String] )
            : ~ i members 0
            : ~ i missing 0
            : ~ String err ( string_new )
            ?? ( json_get body path ) {
                T node → {
                    ? ( json_is_arr node ) {
                        : i n ( json_arr_len node )
                        : ~ i k 0
                        ~ < k n {
                            ?? ( json_arr_get node k ) {
                                T el → {
                                    ? ( json_is_obj el ) {
                                        ? ( __hs_record el rows cols time_field now ) { = members + members 1 } { = missing + missing 1 }
                                    } { = missing + missing 1 }
                                }
                                F _ → {}
                            }
                            = k + k 1
                        }
                        ? & == members 0 > n 0 {
                            ( string_free err )
                            = err ( string_from `the array at the path holds no objects with numbers or text in them` )
                        } {}
                    } {
                        ? ( json_is_obj node ) {
                            ? ( __hs_record node rows cols time_field now ) { = members 1 } {
                                ( string_free err )
                                = err ( string_from `the object at the path holds no numbers or text` )
                            }
                        } {
                            ( string_free err )
                            = err ( string_from `the path must lead to an array of objects or to an object` )
                        }
                    }
                }
                F _ → {
                    ( string_free err )
                    = err ( string_from `nothing at the path ` )
                    ( string_push_str err path )
                    ( string_push_str err ` in the answer` )
                }
            }
            ( json_free body )
            ^ @ WfsPivot { rows cols members missing err }
        }
        F e → {
            : String msg ( string_from `the answer is not JSON (` )
            : String why ( json_format_error e )
            ( string_push_str msg ( string_data why ) )
            ( string_free why )
            ( string_push_char msg 41 )
            : WfsPivot pe ( _wfs_pivot_err ( string_data msg ) )
            ( string_free msg )
            ^ pe
        }
    }
}

// CSV text → records. A feed that answers with a file rather than with an
// API — the USGS earthquake summaries, a station's export, anything a
// spreadsheet would open — is a data source like any other, and it needs
// no parser of its own: `import_parse` is the one the import route and
// `analyze_data` already use, so a file that imports cleanly as history
// fetches cleanly as a feed, with the same delimiter sniffing, the same
// missing-value rules and the same cell typing.
//
// The clock is a column, named or detected, exactly as in the JSON and
// WFS pivots; a row with no readable stamp is stamped `now`, which makes
// an undated file a snapshot of the moment it was fetched.
@ csv_pivot s text s time_field i now → WfsPivot {
    : ImportParse ip ( import_parse text `csv` )
    ? > ( string_len . ip err ) 0 {
        : String msg ( string_from `the answer is not readable as CSV (` )
        ( string_push_str msg ( string_data . ip err ) )
        ( string_push_char msg 41 )
        ( import_parse_free ip )
        : WfsPivot pe ( _wfs_pivot_err ( string_data msg ) )
        ( string_free msg )
        ^ pe
    } {}
    : ( Vec Json ) rows ( vec_new [Json] )
    : ( Vec String ) cols ( vec_new [String] )
    : ~ i members 0
    : ~ i missing . ip skipped
    : i n ( vec_len [Json] . ip rows )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Json] . ip rows k ) {
            T srcrow → {
                : Json row ( json_clone srcrow )
                : ( Vec String ) keys ( json_obj_keys row )
                : i nk ( vec_len [String] keys )
                : ~ i q 0
                ~ < q nk {
                    ?? ( vec_get [String] keys q ) {
                        T kn → { ( _wfs_col_add cols ( string_data kn ) ) }
                        F _ → {}
                    }
                    = q + q 1
                }
                ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
                ? == nk 0 {
                    ( json_free row )
                    = missing + missing 1
                } {
                    ? ( _wfs_wide_clock row time_field ) {} { ( json_obj_set row `timestamp` ( json_int now ) ) }
                    ( vec_push [Json] rows row )
                    = members + members 1
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( import_parse_free ip )
    : ~ String err ( string_new )
    ? == members 0 {
        ( string_free err )
        = err ( string_from `the answer parsed as CSV but held no rows with values in them` )
    } {}
    ^ @ WfsPivot { rows cols members missing err }
}

// ── The network ───────────────────────────────────────────────────────

// One request; Ok(body text) on a 2xx, Err(why) otherwise — the status
// and the first line of the body, or the transport's word.
@ http_fetch s method s url Json headers s body → !String String {
    : *HttpClient hc ( http_client_new )
    ( http_client_set_timeout hc WFS_TIMEOUT_MS )
    ( http_client_set_body_max hc WFS_BODY_MAX )
    ( http_client_set_user_agent hc `anomaly-http/1.0` )
    : ( Vec Header ) hs ( vec_new [Header] )
    : ~ b has_accept F
    : ~ b has_ctype F
    ? ( json_is_obj headers ) {
        : ( Vec String ) keys ( json_obj_keys headers )
        : i n ( vec_len [String] keys )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [String] keys k ) {
                T key → {
                    ?? ( json_obj_get headers ( string_data key ) ) {
                        T v → {
                            ? ( json_is_str v ) {
                                ( vec_push [Header] hs ( header_new ( string_data key ) ( json_str_data v ) ) )
                                // `string_eq` takes two Strings, so the
                                // literals must be built and freed: made
                                // inline they were two allocations per
                                // header of every fetch, forever.
                                : String lower ( string_to_lower key )
                                : s low ( string_data lower )
                                ? == ( nurl_str_eq low `accept` ) 1 { = has_accept T } {}
                                ? == ( nurl_str_eq low `content-type` ) 1 { = has_ctype T } {}
                                ( string_free lower )
                            } {}
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = k + k 1
        }
        ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
    } {}
    ? has_accept {} { ( vec_push [Header] hs ( header_new `accept` `application/json` ) ) }
    : i blen ( nurl_str_len body )
    ? & > blen 0 ! has_ctype { ( vec_push [Header] hs ( header_new `content-type` `application/json` ) ) } {}
    : ( Vec u ) bb ( bytes_from_str body )
    : ~ b ok F
    : ~ String text ( string_new )
    ?? ( http_client_request hc method url hs bb ) {
        T r → {
            : String rb ( bytes_to_str . r body )
            ? & >= . r status 200 < . r status 300 {
                ( string_free text )
                = text rb
                = ok T
            } {
                ( string_push_str text `HTTP ` )
                ( string_push_int text . r status )
                ( string_push_str text ` from the service` )
                : i bl ( string_len rb )
                ? > bl 0 {
                    ( string_push_str text `: ` )
                    : ~ i k 0
                    ~ & < k bl < k 300 {
                        : i c ( string_get rb k )
                        ? | == c 10 == c 13 { ( string_push_char text 32 ) } { ( string_push_char text c ) }
                        = k + k 1
                    }
                } {}
                ( string_free rb )
            }
            ( http_response_free r )
        }
        F e → {
            ( string_push_str text `could not fetch: ` )
            ( string_push_str text ( http_client_err_name e ) )
        }
    }
    ( vec_free [u] bb )
    ( http_client_free hc )
    ? ok { ^ @ !String String { T text } } {}
    ^ @ !String String { F text }
}
