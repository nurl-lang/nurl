// anomaly/wfs.nu — an OGC WFS 2.0 service as a source of data points.
//
// A weather service, a hydrology office, a radiation network: what they
// publish is a WFS endpoint with STORED QUERIES — named, parameterised
// requests (`fmi::observations::weather::simple`) that answer with a
// feature collection. The `::simple` family, and anything shaped like
// it, answers in long form: one member per (location, time, parameter,
// value). Pivoting those on (location, time) gives one record per moment
// with a column per parameter — exactly the JSON point the ingest path
// takes, with the observation's own clock on it.
//
// Three operations, none of which touches the network:
//
//   wfs_catalog   DescribeStoredQueries XML → JSON: every stored query
//                 with its title, abstract and parameters, for a person
//                 to pick from. Tolerates ListStoredQueries (ids and
//                 titles only).
//   wfs_pivot     GetFeature XML → records: one JSON object per
//                 (location, time) with `time` (ISO 8601), `timestamp`
//                 (Unix seconds), `lat`, `lon` and a number per
//                 parameter. `NaN` — the service's spelling of "no
//                 reading" — is dropped, not learned.
//   wfs_url_*     the request URLs, every value percent-encoded.
//
// and one that does: `wfs_fetch`, a GET with a deadline and a body cap.
//
// Namespace prefixes are whatever the server chose (`BsWfs:`, `wfs:`,
// none at all), so every tag is matched on its local name.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/xml.nu`
$ `stdlib/ext/http_request.nu`
$ `deps/http-client/src/http_client.nu`

// A fetch that takes longer than this has hung; an answer bigger than
// this is not a time window a source should ask for at once.
: i WFS_TIMEOUT_MS 60000
: i WFS_BODY_MAX 67108864

// ── Tags by local name ────────────────────────────────────────────────

// Does this element's tag, prefix stripped, equal `want`?
@ __wfs_tag_is Xml x s want → b {
    ? != . x kind 1 { ^ F } {}
    : s raw ( string_data . x tag )
    : i c ( nurl_str_find raw `:` )
    ? >= c 0 {
        : s local # s + # i raw + c 1
        ^ == ( nurl_str_eq local want ) 1
    } {}
    ^ == ( nurl_str_eq raw want ) 1
}

// First element child with local name `want`. BORROW into the tree.
@ __wfs_child Xml x s want → ?Xml {
    : i n ( vec_len [Xml] . x children )
    : ~ i k 0
    : ~ i hit -1
    ~ & < k n < hit 0 {
        ?? ( vec_get [Xml] . x children k ) {
            T c → { ? ( __wfs_tag_is c want ) { = hit k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ? < hit 0 { ^ @ ?Xml { F # Xml 0 } } {}
    ^ ( vec_get [Xml] . x children hit )
}

// The trimmed text under the first child named `want`, or "".
@ __wfs_child_text Xml x s want → String {
    ?? ( __wfs_child x want ) {
        T c → {
            : String raw ( xml_inner_text c )
            : String out ( string_trim raw )
            ( string_free raw )
            ^ out
        }
        F _ → { ^ ( string_new ) }
    }
}

// The first element child of any name. BORROW.
@ __wfs_first_elem Xml x → ?Xml {
    : i n ( vec_len [Xml] . x children )
    : ~ i k 0
    : ~ i hit -1
    ~ & < k n < hit 0 {
        ?? ( vec_get [Xml] . x children k ) {
            T c → { ? == . c kind 1 { = hit k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ? < hit 0 { ^ @ ?Xml { F # Xml 0 } } {}
    ^ ( vec_get [Xml] . x children hit )
}

// ── URLs ──────────────────────────────────────────────────────────────

// The endpoint without its query string: what a person pastes is often
// the GetCapabilities link, and the base is what every request builds on.
@ wfs_base_url s url → String {
    : String t0 ( string_from url )
    : String t ( string_trim t0 )
    ( string_free t0 )
    : i q ( nurl_str_find ( string_data t ) `?` )
    ? >= q 0 {
        : String base ( string_substr t 0 q )
        ( string_free t )
        ^ base
    } {}
    ^ t
}

// http or https, nothing else: the service fetches this URL on a
// schedule, and a scheme it does not speak is a mistake worth refusing
// at configuration time rather than at three in the morning.
@ wfs_url_ok s url → b {
    : String b ( wfs_base_url url )
    : b ok | ( string_starts_with b `https://` ) ( string_starts_with b `http://` )
    : b long > ( string_len b ) 10
    ( string_free b )
    ^ & ok long
}

@ __wfs_url_start s base s request → String {
    : String u ( wfs_base_url base )
    ( string_push_str u `?service=WFS&version=2.0.0&request=` )
    ( string_push_str u request )
    ^ u
}

@ wfs_url_catalog s base → String {
    ^ ( __wfs_url_start base `DescribeStoredQueries` )
}

@ __wfs_push_param String u s key s val → v {
    ( string_push_char u 38 )
    : String ek ( percent_encode key )
    ( string_push_str u ( string_data ek ) )
    ( string_free ek )
    ( string_push_char u 61 )
    : String ev ( percent_encode val )
    ( string_push_str u ( string_data ev ) )
    ( string_free ev )
}

// A stored-query value as text: strings as they are, numbers printed.
@ __wfs_param_text Json v → String {
    ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
    ? ( json_is_num v ) {
        ?? ( json_num_as_f v ) {
            T x → {
                : i xi # i x
                : String out ( string_new )
                ? == # f xi x { ( string_push_int out xi ) } { ( string_push_float out x ) }
                ^ out
            }
            F _ → {}
        }
    } {}
    ? ( json_is_bool v ) { ^ ( string_from ? ( json_bool_val v ) `true` `false` ) } {}
    ^ ( string_new )
}

// GetFeature for one stored query over [start, end] (Unix seconds). The
// caller's parameters go in as given, except the two the window owns —
// a saved `starttime` would pin every fetch to the same hour.
@ wfs_url_feature s base s query Json params i start i end → String {
    : String u ( __wfs_url_start base `GetFeature` )
    ( __wfs_push_param u `storedquery_id` query )
    ? ( json_is_obj params ) {
        ( json_obj_each params \ s key Json v → v {
            ? | == ( nurl_str_eq key `starttime` ) 1 == ( nurl_str_eq key `endtime` ) 1 {} {
                : String txt ( __wfs_param_text v )
                ? > ( string_len txt ) 0 { ( __wfs_push_param u key ( string_data txt ) ) } {}
                ( string_free txt )
            }
        } )
    } {}
    : String s0 ( time_format_iso ( time_from_unix start ) )
    : String s1 ( time_format_iso ( time_from_unix end ) )
    ( __wfs_push_param u `starttime` ( string_data s0 ) )
    ( __wfs_push_param u `endtime` ( string_data s1 ) )
    ( string_free s0 )
    ( string_free s1 )
    ^ u
}

// ── The catalogue ─────────────────────────────────────────────────────

@ __wfs_param_json Xml p → Json {
    : Json o ( json_obj_new )
    ?? ( xml_attr p `name` ) {
        T nm → { ( json_obj_set o `name` ( json_str_lit ( string_data nm ) ) ) ( string_free nm ) }
        F _ → { ( json_obj_set o `name` ( json_str_lit `` ) ) }
    }
    ?? ( xml_attr p `type` ) {
        T ty → { ( json_obj_set o `type` ( json_str_lit ( string_data ty ) ) ) ( string_free ty ) }
        F _ → { ( json_obj_set o `type` ( json_str_lit `` ) ) }
    }
    : String title ( __wfs_child_text p `Title` )
    ( json_obj_set o `title` ( json_str_lit ( string_data title ) ) )
    ( string_free title )
    : String abs ( __wfs_child_text p `Abstract` )
    ( json_obj_set o `abstract` ( json_str_lit ( string_data abs ) ) )
    ( string_free abs )
    ^ o
}

@ __wfs_query_json Xml q → Json {
    : Json o ( json_obj_new )
    ?? ( xml_attr q `id` ) {
        T id → { ( json_obj_set o `id` ( json_str_lit ( string_data id ) ) ) ( string_free id ) }
        F _ → { ( json_obj_set o `id` ( json_str_lit `` ) ) }
    }
    : String title ( __wfs_child_text q `Title` )
    ( json_obj_set o `title` ( json_str_lit ( string_data title ) ) )
    ( string_free title )
    : String abs ( __wfs_child_text q `Abstract` )
    ( json_obj_set o `abstract` ( json_str_lit ( string_data abs ) ) )
    ( string_free abs )
    : Json ps ( json_arr_new )
    : i n ( vec_len [Xml] . q children )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Xml] . q children k ) {
            T c → { ? ( __wfs_tag_is c `Parameter` ) { ( json_arr_push ps ( __wfs_param_json c ) ) } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `parameters` ps )
    ^ o
}

// DescribeStoredQueries (or ListStoredQueries) → `{queries: [...]}`;
// `{error: ...}` when the document is not one of those.
@ wfs_catalog s xml → Json {
    : Json out ( json_obj_new )
    ?? ( xml_parse xml ) {
        T root → {
            : Json qs ( json_arr_new )
            : i n ( vec_len [Xml] . root children )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [Xml] . root children k ) {
                    T c → {
                        ? | ( __wfs_tag_is c `StoredQueryDescription` ) ( __wfs_tag_is c `StoredQuery` ) {
                            ( json_arr_push qs ( __wfs_query_json c ) )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ? == ( json_arr_len qs ) 0 {
                ( json_free qs )
                ? ( __wfs_tag_is root `ExceptionReport` ) {
                    : String why ( xml_inner_text root )
                    : String tw ( string_trim why )
                    : String msg ( string_from `the service answered with an exception: ` )
                    ( string_push_str msg ( string_data tw ) )
                    ( json_obj_set out `error` ( json_str_lit ( string_data msg ) ) )
                    ( string_free msg )
                    ( string_free tw )
                    ( string_free why )
                } {
                    ( json_obj_set out `error` ( json_str_lit `no stored queries in the answer: is this a WFS 2.0 endpoint?` ) )
                }
            } {
                ( json_obj_set out `queries` qs )
            }
            ( xml_free root )
        }
        F e → {
            : String msg ( string_from `the answer is not XML (` )
            ( string_push_str msg ( xml_err_name e ) )
            ( string_push_char msg 41 )
            ( json_obj_set out `error` ( json_str_lit ( string_data msg ) ) )
            ( string_free msg )
        }
    }
    ^ out
}

// ── The pivot ─────────────────────────────────────────────────────────

: WfsPivot {
    ( Vec Json ) rows  // one object per (location, time), in order of first appearance
    ( Vec String ) columns  // lat, lon, then every parameter in order of first appearance
    i members  // feature members read
    i missing  // values that were NaN or empty, left out of their row
    String err  // non-empty ⇒ nothing was read
}

@ wfs_pivot_free WfsPivot p → v {
    ( vec_free_with [Json] . p rows \ Json j → v { ( json_free j ) } )
    ( vec_free_with [String] . p columns \ String s → v { ( string_free s ) } )
    ( string_free . p err )
}

@ __wfs_pivot_err s msg → WfsPivot {
    ^ @ WfsPivot { ( vec_new [Json] ) ( vec_new [String] ) 0 0 ( string_from msg ) }
}

@ __wfs_col_add ( Vec String ) cols s name → v {
    : i n ( vec_len [String] cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] cols k ) {
            T c → { ? == ( nurl_str_eq ( string_data c ) name ) 1 { ^ } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_push [String] cols ( string_from name ) )
}

// Index of the row keyed `key`, or -1. Members of one (location, time)
// arrive together, so the newest row is checked first and the scan is
// the exception.
@ __wfs_row_find ( Vec String ) keys s key → i {
    : i n ( vec_len [String] keys )
    ? == n 0 { ^ -1 } {}
    ?? ( vec_get [String] keys - n 1 ) {
        T last → { ? == ( nurl_str_eq ( string_data last ) key ) 1 { ^ - n 1 } {} }
        F _ → {}
    }
    : ~ i k - n 2
    ~ >= k 0 {
        ?? ( vec_get [String] keys k ) {
            T c → { ? == ( nurl_str_eq ( string_data c ) key ) 1 { ^ k } {} }
            F _ → {}
        }
        = k - k 1
    }
    ^ -1
}

// "60.17523 24.94459" → (lat, lon); F when it is not two numbers.
: __WfsPos { b ok f lat f lon }

@ __wfs_parse_pos String pos → __WfsPos {
    : ( Vec String ) parts ( string_split pos ` ` )
    : ~ __WfsPos out @ __WfsPos { F 0.0 0.0 }
    : ~ i got 0
    : i n ( vec_len [String] parts )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] parts k ) {
            T p → {
                ? > ( string_len p ) 0 {
                    ?? ( string_to_float p ) {
                        T x → {
                            ? == got 0 { = . out lat x } {}
                            ? == got 1 { = . out lon x } {}
                            = got + got 1
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
    = . out ok >= got 2
    ^ out
}

// One member element into the pivot: 0 when it is not a (location, time,
// name, value) element at all, 1 when its value landed in a row, 2 when
// the value was missing (NaN, empty, not a number).
@ __wfs_pivot_member ( Vec Json ) rows ( Vec String ) cols ( Vec String ) keys Xml el → i {
    : String name ( __wfs_child_text el `ParameterName` )
    : String tstr ( __wfs_child_text el `Time` )
    ? & > ( string_len name ) 0 > ( string_len tstr ) 0 {} {
        ( string_free name )
        ( string_free tstr )
        ^ 0
    }
    : ~ String pos ( string_new )
    ?? ( __wfs_child el `Location` ) {
        T loc → {
            ?? ( __wfs_child loc `Point` ) {
                T pt → {
                    ( string_free pos )
                    = pos ( __wfs_child_text pt `pos` )
                }
                F _ → {}
            }
        }
        F _ → {}
    }
    : String key ( string_clone pos )
    ( string_push_char key 124 )
    ( string_push_str key ( string_data tstr ) )
    : ~ i at ( __wfs_row_find keys ( string_data key ) )
    ? < at 0 {
        : Json row ( json_obj_new )
        ( json_obj_set row `time` ( json_str_lit ( string_data tstr ) ) )
        ?? ( time_parse_iso ( string_data tstr ) ) {
            T secs → { ( json_obj_set row `timestamp` ( json_int secs ) ) }
            F _ → {}
        }
        : __WfsPos wp ( __wfs_parse_pos pos )
        ? . wp ok {
            ( json_obj_set row `lat` ( json_float . wp lat ) )
            ( json_obj_set row `lon` ( json_float . wp lon ) )
            ( __wfs_col_add cols `lat` )
            ( __wfs_col_add cols `lon` )
        } {}
        ( vec_push [Json] rows row )
        ( vec_push [String] keys key )
        = at - ( vec_len [Json] rows ) 1
    } { ( string_free key ) }
    ( string_free pos )
    ( string_free tstr )

    : String vstr ( __wfs_child_text el `ParameterValue` )
    : ~ i rc 2
    ? & > ( string_len vstr ) 0 != ( nurl_str_eq ( string_data vstr ) `NaN` ) 1 {
        ?? ( string_to_float vstr ) {
            T x → {
                ?? ( vec_get [Json] rows at ) {
                    T row → {
                        ( json_obj_set row ( string_data name ) ( json_float x ) )
                        ( __wfs_col_add cols ( string_data name ) )
                        = rc 1
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
    } {}
    ( string_free vstr )
    ( string_free name )
    ^ rc
}

// A GetFeature answer, pivoted. `err` names what went wrong when nothing
// could be read: a service exception, a document of another shape.
@ wfs_pivot s xml → WfsPivot {
    ?? ( xml_parse xml ) {
        T root → {
            ? ( __wfs_tag_is root `ExceptionReport` ) {
                : String why ( xml_inner_text root )
                : String tw ( string_trim why )
                : String msg ( string_from `the service answered with an exception: ` )
                ( string_push_str msg ( string_data tw ) )
                : WfsPivot pe ( __wfs_pivot_err ( string_data msg ) )
                ( string_free msg )
                ( string_free tw )
                ( string_free why )
                ( xml_free root )
                ^ pe
            } {}
            : b is_fc ( __wfs_tag_is root `FeatureCollection` )
            : ( Vec Json ) rows ( vec_new [Json] )
            : ( Vec String ) cols ( vec_new [String] )
            : ( Vec String ) keys ( vec_new [String] )
            : ~ i members 0
            : ~ i missing 0
            : i n ( vec_len [Xml] . root children )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [Xml] . root children k ) {
                    T c → {
                        : ~ i rc 0
                        ? ( __wfs_tag_is c `member` ) {
                            ?? ( __wfs_first_elem c ) {
                                T el → { = rc ( __wfs_pivot_member rows cols keys el ) }
                                F _ → {}
                            }
                        } {
                            ? == . c kind 1 { = rc ( __wfs_pivot_member rows cols keys c ) } {}
                        }
                        ? > rc 0 { = members + members 1 } {}
                        ? == rc 2 { = missing + missing 1 } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] keys \ String s → v { ( string_free s ) } )
            ( xml_free root )
            : ~ String err ( string_new )
            ? == members 0 {
                ( string_free err )
                ? is_fc {
                    = err ( string_from `the feature collection holds no (location, time, parameter, value) members: pick a "simple" stored query` )
                } {
                    = err ( string_from `not a WFS feature collection` )
                }
            } {}
            ^ @ WfsPivot { rows cols members missing err }
        }
        F e → {
            : String msg ( string_from `the answer is not XML (` )
            ( string_push_str msg ( xml_err_name e ) )
            ( string_push_char msg 41 )
            : WfsPivot pe ( __wfs_pivot_err ( string_data msg ) )
            ( string_free msg )
            ^ pe
        }
    }
}

// ── The network ───────────────────────────────────────────────────────

// GET `url`; Ok(body) on a 2xx, Err(why) otherwise — the status and the
// first line of the body, which is where a WFS puts its exception text.
@ wfs_fetch s url → !String String {
    : *HttpClient hc ( http_client_new )
    ( http_client_set_timeout hc WFS_TIMEOUT_MS )
    ( http_client_set_body_max hc WFS_BODY_MAX )
    ( http_client_set_user_agent hc `anomaly-wfs/1.0` )
    : ~ b ok F
    : ~ String text ( string_new )
    ?? ( http_client_get hc url ) {
        T r → {
            : String body ( bytes_to_str . r body )
            ? & >= . r status 200 < . r status 300 {
                ( string_free text )
                = text body
                = ok T
            } {
                ( string_push_str text `HTTP ` )
                ( string_push_int text . r status )
                ( string_push_str text ` from the service` )
                : i bl ( string_len body )
                ? > bl 0 {
                    ( string_push_str text `: ` )
                    : ~ i k 0
                    ~ & < k bl < k 300 {
                        : i c ( string_get body k )
                        ? | == c 10 == c 13 { ( string_push_char text 32 ) } { ( string_push_char text c ) }
                        = k + k 1
                    }
                } {}
                ( string_free body )
            }
            ( http_response_free r )
        }
        F e → {
            ( string_push_str text `could not fetch: ` )
            ( string_push_str text ( http_client_err_name e ) )
        }
    }
    ( http_client_free hc )
    ? ok { ^ @ !String String { T text } } {}
    ^ @ !String String { F text }
}
