// anomaly/service.nu — HTTP/JSON service (milestone M6).
//
// Thin: parse JSON → call the library → serialise. The routes and the
// request/response shapes mirror the Python reference service so existing
// dashboards keep working:
//
//   POST   /detect/<model>                    ingest + verdict (202 warming)
//   POST   /detect_only/<model>               score only, no state change
//   GET|POST /force_train/<model>             retrain now
//   POST   /detect_anomalies                  batch-score a CSV file
//   GET    /models/dynamic                    list models + metadata
//   GET    /models/dynamic/<model>/metadata   metadata (+ autoencoder state)
//   PUT    /models/dynamic/<model>/metadata   edit schedule / version configs
//   GET    /models/dynamic/<model>/data       recent points (?limit=N|all)
//   GET    /models/dynamic/<model>/anomalies  scored ring (cached, filtered)
//   GET    /models/dynamic/<model>/calibration  alert rates vs margins
//   POST   /models/dynamic/<model>/import     a CSV/JSON/JSONL file of history
//   POST   /models/dynamic/<model>/reset      drop data+forests, keep name
//   DELETE|GET /delete_model/<model>          delete entirely
//   PUT    /api/dynamic/<model>/schedule      retraining schedule
//   POST   /api/dynamic/<model>/finetune      set margins from a target alert rate
//   POST   /train/autoencoder/<model>         train the autoencoder version
//
// Model names must match ^[a-zA-Z0-9_]+$ (400 otherwise, same message as
// the reference). Divergence from the reference: /detect_anomalies scores
// the CSV with a self-trained stateless forest (the reference's separate
// "static model" family doesn't exist here); passing model_name is a 400.
//
// When a web root is configured (anomaly_service_set_webroot), the router
// also serves the self-contained dashboard pages from disk:
//
//   GET /  |  /modelmanager.html  |  /modeltrainer.html
//       |  /visualize.html        |  /anomalies.html
//       |  /admin.html            |  /oauth/callback  |  /auth.js
//
// With no web root these routes 404 and the service is API-only.
//
// The router is exposed separately from the socket (anomaly_service_router
// + router_handle) so every route is testable without networking.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_server.nu`
$ `deps/http/src/app.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`
$ `src/store.nu`
$ `src/dynamic.nu`
$ `src/csvdata.nu`
$ `src/importer.nu`
$ `src/authz.nu`

// Store root used by every handler; set once before serving.
: ~ s g_an_root `.`

@ anomaly_service_set_root s root → v {
    = g_an_root root
}

// Directory holding the dashboard HTML (modelmanager.html, etc). Empty =
// static serving disabled (API-only). Set once before serving.
: ~ s g_an_webroot ``

@ anomaly_service_set_webroot s root → v {
    = g_an_webroot root
}

// ── Static dashboard serving ──────────────────────────────────────────

// Content-Type for a filename by extension (only the handful the dashboard
// actually ships; everything else is served as octet-stream).
@ __an_content_type s name → s {
    : i n ( nurl_str_len name )
    ? ( __an_ends_with name `.html` ) { ^ `text/html; charset=utf-8` } {}
    ? ( __an_ends_with name `.css` ) { ^ `text/css; charset=utf-8` } {}
    ? ( __an_ends_with name `.js` ) { ^ `application/javascript; charset=utf-8` } {}
    ? ( __an_ends_with name `.json` ) { ^ `application/json; charset=utf-8` } {}
    ? ( __an_ends_with name `.svg` ) { ^ `image/svg+xml` } {}
    ? ( __an_ends_with name `.ico` ) { ^ `image/x-icon` } {}
    ^ `application/octet-stream`
}

@ __an_ends_with s hay s suf → b {
    : i hn ( nurl_str_len hay )
    : i sn ( nurl_str_len suf )
    ? > sn hn { ^ F } {}
    : ~ i k 0
    ~ < k sn {
        ? == ( nurl_str_get hay + - hn sn k ) ( nurl_str_get suf k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

// Serve `<g_an_webroot>/<relfile>`. 404 when the webroot is unset or the
// file is missing. `relfile` is a trusted constant (never request-derived),
// so no path-traversal scrubbing is needed here.
@ __an_serve_file s relfile → HttpResponse {
    ? > ( nurl_str_len g_an_webroot ) 0 {} {
        ^ ( __an_json_err 404 `Dashboard is not available (no web root configured)` )
    }
    : String path ( path_join g_an_webroot relfile )
    : !String IoErr fr ( read_file ( string_data path ) )
    ( string_free path )
    ?? fr {
        T text → {
            : HttpResponse r ( response_new 200 )
            ( response_set_header r `Content-Type` ( __an_content_type relfile ) )
            ( response_set_body_str r ( string_data text ) )
            ( string_free text )
            ^ r
        }
        F _ → {
            : String msg ( string_from `File not found: ` )
            ( string_push_str msg relfile )
            : HttpResponse rr ( __an_json_err 404 ( string_data msg ) )
            ( string_free msg )
            ^ rr
        }
    }
}

// ── Small helpers ─────────────────────────────────────────────────────

@ __an_name_ok s name → b {
    : i n ( nurl_str_len name )
    ? <= n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get name k )
        : ~ b good F
        ? & >= c 48 <= c 57 { = good T } {}
        ? & >= c 65 <= c 90 { = good T } {}
        ? & >= c 97 <= c 122 { = good T } {}
        ? == c 95 { = good T } {}
        ? good {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __an_json_err i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `error` ) )
    ( json_obj_set o `message` ( json_str_lit msg ) )
    : HttpResponse r ( response_json status o )
    ( json_free o )
    ^ r
}

@ __an_str_in ( Vec String ) xs s want → b {
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

@ __an_bad_name → HttpResponse {
    ^ ( __an_json_err 400 `Invalid model name. Use only letters, numbers, and underscores.` )
}

@ __an_404_model s name → HttpResponse {
    : String msg ( string_from `Model ` )
    ( string_push_str msg name )
    ( string_push_str msg ` not found` )
    : HttpResponse r ( __an_json_err 404 ( string_data msg ) )
    ( string_free msg )
    ^ r
}

@ __an_ok_msg s msg → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `message` ( json_str_lit msg ) )
    ^ o
}

// The :model path capture (owned; empty String = missing).
@ __an_param_model Params p → String {
    ?? ( params_get p `model` ) {
        T v → { ^ v }
        F junk → { ^ junk }
    }
}

// Request body as parsed JSON, or None.
@ __an_body_json HttpRequest req → ?Json {
    : String txt ( bytes_to_str . req body )
    : !Json JsonError r ( json_parse ( string_data txt ) )
    ( string_free txt )
    ?? r {
        T j → { ^ @ ?Json { T j } }
        F _ → { ^ @ ?Json { F } }
    }
}

// Integer query parameter (?key=N). `dflt` when missing/garbage; -1 for
// the "everything" spellings (all / max / *).
@ __an_query_int String q s key i dflt → i {
    : String needle ( string_from key )
    ( string_push_char needle 61 )
    : ?i at0 ( string_index_of q ( string_data needle ) )
    : i klen ( string_len needle )
    ( string_free needle )
    ?? at0 {
        T at → {
            : String val ( string_new )
            : i n ( string_len q )
            : ~ i k + at klen
            : ~ b going T
            ~ & going < k n {
                : i c ( string_get q k )
                ? == c 38 { = going F } {
                    ( string_push_char val c )
                    = k + k 1
                }
            }
            : ~ i out dflt
            : s vraw ( string_data val )
            ? || == ( nurl_str_eq vraw `all` ) 1 || == ( nurl_str_eq vraw `max` ) 1 == ( nurl_str_eq vraw `*` ) 1 {
                = out -1
            } {
                ?? ( string_to_int val ) {
                    T x → { ? > x 0 { = out x } {} }
                    F _ → {}
                }
            }
            ( string_free val )
            ^ out
        }
        F _ → { ^ dflt }
    }
}

// ── Authorization ─────────────────────────────────────────────────────
//
// Every handler starts with a gate. The gate resolves the caller (authz.nu)
// and answers one question — may this request proceed — so the handlers
// below never assemble a policy decision out of parts, and a route added
// later cannot forget half of one.
//
// With authentication disabled the resolver hands back a local admin and
// every gate opens, which is what keeps an un-configured deployment
// behaving exactly as it did before authentication existed.

: i AZ_GATE_OK 0
: i AZ_GATE_UNAUTH 401
: i AZ_GATE_FORBID 403

: Gate {
    b allowed
    i status
    Principal who
    b creating  // the named model does not exist yet; this call would make it
}

@ __an_gate_free Gate g → v {
    ( principal_free . g who )
}

// Sanitize a reason before it goes into a header: part of it is copied from
// a token, and a CR LF in there is response splitting, not a diagnostic.
@ __an_safe_reason s raw → String {
    : i n ( nurl_str_len raw )
    : String out ( string_new )
    : ~ i k 0
    ~ & < k n < k 200 {
        : i c ( nurl_str_at raw n k )
        ? | | < c 32 == c 34 == c 92 { ( string_push_char out 32 ) } { ( string_push_char out c ) }
        = k + k 1
    }
    ^ out
}

@ __an_gate_deny Gate g → HttpResponse {
    ? == . g status AZ_GATE_FORBID {
        ^ ( __an_json_err 403 `Forbidden: this model belongs to another user.` )
    } {}
    // A credential was presented and refused: say why. A bare 401 turns a
    // one-line configuration mistake into a sign-in screen that reappears
    // forever with nothing to go on.
    : String why ( __an_safe_reason ( anomaly_authz_last_error ) )
    : ~ HttpResponse r ( __an_json_err 401 `Authentication required.` )
    ? > ( string_len why ) 0 {
        : String msg ( string_from `Token rejected: ` )
        ( string_push_str msg ( string_data why ) )
        ( http_response_free r )
        = r ( __an_json_err 401 ( string_data msg ) )
        : String chal ( string_from `Bearer error="invalid_token", error_description="` )
        ( string_push_str chal ( string_data why ) )
        ( string_push_char chal 34 )
        ( response_set_header r `WWW-Authenticate` ( string_data chal ) )
        ( string_free chal )
        ( string_free msg )
    } {
        ( response_set_header r `WWW-Authenticate` `Bearer` )
    }
    ( string_free why )
    ^ r
}

// Authentication only: is there a caller at all, and (optionally) is it an
// administrator of its organisation?
@ __an_gate_auth HttpRequest req b need_admin → Gate {
    : Principal p ( authz_principal req )
    ? . p authed {} { ^ @ Gate { F AZ_GATE_UNAUTH p F } }
    ? need_admin {
        ? ( principal_is_admin p ) {} { ^ @ Gate { F AZ_GATE_FORBID p F } }
    } {}
    ^ @ Gate { T AZ_GATE_OK p F }
}

// Model access. `allow_create` marks the routes that bring a model into
// existence: a model with no stored directory has no owner yet, and
// refusing it there would mean only administrators could ever create one.
// Ownership is checked exactly when there is something to own.
@ __an_gate_model HttpRequest req s name b allow_create b need_write → Gate {
    : Principal p ( authz_principal req )
    ? . p authed {} { ^ @ Gate { F AZ_GATE_UNAUTH p F } }
    ? ( anomaly_authz_enabled ) {} { ^ @ Gate { T AZ_GATE_OK p F } }

    : Store st ( store_open g_an_root )
    : b exists ( store_exists st name )
    ( store_free st )
    ? exists {} {
        // `allow_create` marks the routes that put DATA in, and a model
        // coming into existence is a side effect of that — the first point
        // for a new sensor defines a new model. So the check is the same one
        // that governs sending points at all: requiring an admin here would
        // mean handing a data producer an administrator's credential to
        // report a reading, which is the opposite of least privilege.
        ? allow_create {
            ? ( principal_may_ingest p ) { ^ @ Gate { T AZ_GATE_OK p T } } {}
            ^ @ Gate { F AZ_GATE_FORBID p F }
        } {}
        // Not a permission problem — the handler's own 404 is the honest
        // answer, and pretending otherwise would tell a caller which model
        // names exist.
        ^ @ Gate { T AZ_GATE_OK p F }
    }
    : ~ b may F
    ?? ( az_db_open ( string_data . p org ) ) {
        F _ → {}
        T db → {
            = may ? need_write ( az_may_write db p name ) ( az_may_see db p name )
        }
    }
    ? may { ^ @ Gate { T AZ_GATE_OK p F } } {}
    ^ @ Gate { F AZ_GATE_FORBID p F }
}

// Ingest. The producers feeding these models are deployed devices and
// flows that cannot do an interactive sign-in, so while ANOMALY_OPEN_INGEST
// is set these two routes stay reachable without credentials — the
// migration window in which keys are handed out. It is a window, not a
// design: with it closed they behave like every other model route.
@ __an_gate_ingest HttpRequest req s name → Gate {
    // Simple mode: no credentials anywhere, and everything collected
    // belongs to the shared public organisation.
    ? ( anomaly_authz_enabled ) {} {
        ^ @ Gate { T AZ_GATE_OK ( principal_public_admin ) F }
    }
    // Signed in, a point needs a credential that names an ORGANISATION.
    // Without one there is nothing the point could belong to, and a model
    // created from it would be exactly the ownerless model this design
    // refuses to make. `open_ingest` is the migration escape hatch, and
    // even then the points land in the public organisation rather than
    // conjuring an unowned model.
    ? ( anomaly_authz_open_ingest ) {
        : Principal p ( authz_principal req )
        : b have . p authed
        ( principal_free p )
        ? have {} { ^ @ Gate { T AZ_GATE_OK ( principal_public_admin ) T } }
    } {}
    // Putting data in — a streamed point, or a file of history; the
    // transport differs and the act does not. It is not viewing, so it is
    // not a viewer's; it does not change or destroy a model, so it need not
    // be an admin's. It belongs to the credential issued to do it: an
    // `ingest` key, which may feed the organisation's models and bring a
    // new one into being by feeding it, and may do nothing else.
    : Gate g ( __an_gate_model req name T F )
    ? . g allowed {} { ^ g }
    : Principal ip . g who
    ? ( principal_may_ingest ip ) {} { ^ @ Gate { F AZ_GATE_FORBID . g who F } }
    ^ g
}

// Record who created a model, so the next request can be told whether it
// may touch it. Called only after the store actually holds one.
@ __an_gate_claim Gate g s name → v {
    ? ( anomaly_authz_enabled ) {} { ^ }
    ? . g creating {} { ^ }
    : Principal gp . g who
    ? . gp authed {} { ^ }
    ?? ( az_db_open ( string_data . gp org ) ) {
        F _ → {}
        T db → { : b _c ( az_model_claim db name ( string_data . gp sub ) ( now_seconds ) F ) }
    }
}

// A deleted model must not leave its ownership row behind: the next model
// to reuse the name would inherit an owner nobody chose.
@ __an_forget_model Principal p s name → v {
    ? ( anomaly_authz_enabled ) {} { ^ }
    ?? ( az_db_open ( string_data . p org ) ) {
        F _ → {}
        T db → { ( az_model_forget db name ) }
    }
}

// ── Verdict → JSON ────────────────────────────────────────────────────

@ __an_verdict_resp * Model mo s mname Json body Verdict vd → HttpResponse {
    ? . vd ready {} {
        : *Meta mm ( model_metadata mo )
        : i n ( model_n_points mo )
        : String msg ( string_from `Collecting data (` )
        ( string_push_int msg n )
        ( string_push_char msg 47 )
        ( string_push_int msg . mo min_points )
        ( string_push_str msg ` points).` )
        : Json o ( json_obj_new )
        ( json_obj_set o `status` ( json_str_lit `collecting` ) )
        ( json_obj_set o `message` ( json_str_lit ( string_data msg ) ) )
        ( json_obj_set o `data_points` ( json_int n ) )
        ( json_obj_set o `min_data_points` ( json_int . mo min_points ) )
        ( json_obj_set o `model_name` ( json_str_lit mname ) )
        ( string_free msg )
        : HttpResponse r ( response_json 202 o )
        ( json_free o )
        ^ r
    }

    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model` ( json_str_lit mname ) )
    ( json_obj_set o `anomaly` ( json_bool . vd anomaly ) )
    ( json_obj_set o `score` ( json_float . vd score ) )
    ( json_obj_set o `data_points` ( json_int ( model_n_points mo ) ) )

    // `severity` is the one number that means the same thing in every
    // version: -score / margin, so 1.0 is exactly the alert line, 2.0 is
    // twice as far past it, and a negative value is a comfortably normal
    // point. `score` and `margin` stay in each version's own units.
    : Json vers ( json_obj_new )
    : i nv ( vec_len [VerVerdict] . vd versions )
    : ~ f top_sev 0.0
    : ~ b first T
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [VerVerdict] . vd versions k ) {
            T vv → {
                : Json vo ( json_obj_new )
                ( json_obj_set vo `anomaly` ( json_bool . vv anomaly ) )
                ( json_obj_set vo `score` ( json_float . vv score ) )
                : ~ f sev 0.0
                ? > . vv margin 0.0 { = sev / - 0.0 . vv score . vv margin } {
                    = sev ? <= . vv score 0.0 1.0 0.0
                }
                ( json_obj_set vo `severity` ( json_float sev ) )
                ? || first > sev top_sev { = top_sev sev } {}
                = first F
                : Json ti ( json_obj_new )
                ( json_obj_set ti `margin` ( json_float . vv margin ) )
                ( json_obj_set vo `threshold_info` ti )
                ( json_obj_set vers ( string_data . vv vvname ) vo )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `severity` ( json_float top_sev ) )
    ( json_obj_set o `versions` vers )
    ( json_obj_set o `data_point` ( json_clone body ) )

    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// ── Route handlers ────────────────────────────────────────────────────

@ __an_h_detect HttpRequest req Params p b ingest → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    // /detect puts a point in; /detect_only only scores one and changes
    // nothing, which makes it a read a viewer may do.
    : ~ Gate gate ( __an_gate_ingest req ( string_data mname ) )
    ? ingest {} {
        ( __an_gate_free gate )
        = gate ( __an_gate_model req ( string_data mname ) F F )
    }
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            ? ( json_is_obj body ) {} {
                ( json_free body )
                ( __an_gate_free gate )
                ( string_free mname )
                ^ ( __an_json_err 400 `No parameters provided. Need at least one numeric parameter.` )
            }
            : Store st ( store_open g_an_root )
            ? ingest {} {
                ? ( store_exists st ( string_data mname ) ) {} {
                    : HttpResponse r404 ( __an_404_model ( string_data mname ) )
                    ( store_free st )
                    ( json_free body )
                    ( __an_gate_free gate )
                    ( string_free mname )
                    ^ r404
                }
            }
            : *Model mo ( model_open st ( string_data mname ) )
            ? ingest {} {
                ? ( model_is_trained mo ) {} {
                    : String msg ( string_from `Model ` )
                    ( string_push_str msg ( string_data mname ) )
                    ( string_push_str msg ` exists but is not trained yet.` )
                    : HttpResponse rr ( __an_json_err 400 ( string_data msg ) )
                    ( string_free msg )
                    ( model_free mo )
                    ( store_free st )
                    ( json_free body )
                    ( __an_gate_free gate )
                    ( string_free mname )
                    ^ rr
                }
            }
            : ~ HttpResponse resp ( response_status_only 500 )
            ? ingest {
                : !Verdict String vr ( model_ingest mo body )
                ?? vr {
                    T vd → {
                        ( http_response_free resp )
                        = resp ( __an_verdict_resp mo ( string_data mname ) body vd )
                        ( verdict_free vd )
                    }
                    F e → {
                        ( http_response_free resp )
                        = resp ( __an_json_err 400 ( string_data e ) )
                        ( string_free e )
                    }
                }
            } {
                : !Verdict String vr ( model_detect_only mo body )
                ?? vr {
                    T vd → {
                        ( http_response_free resp )
                        = resp ( __an_verdict_resp mo ( string_data mname ) body vd )
                        ( verdict_free vd )
                    }
                    F e → {
                        ( http_response_free resp )
                        = resp ( __an_json_err 400 ( string_data e ) )
                        ( string_free e )
                    }
                }
            }
            ( model_free mo )
            ( store_free st )
            ( json_free body )
            // The model exists now if it did not before, so whoever brought
            // it into being becomes its owner. Doing this after the ingest
            // means a rejected point never claims a model.
            ( __an_gate_claim gate ( string_data mname ) )
            ( __an_gate_free gate )
            ( string_free mname )
            ^ resp
        }
        F _ → {
            ( __an_gate_free gate )
            ( string_free mname )
            ^ ( __an_json_err 400 `No parameters provided. Need at least one numeric parameter.` )
        }
    }
}

@ __an_h_force_train HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    : i used ( model_force_train mo )
    : ~ HttpResponse resp ( response_status_only 500 )
    ? > used 0 {
        : String msg ( string_from `Model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` trained` )
        : Json o ( __an_ok_msg ( string_data msg ) )
        ( json_obj_set o `points_used` ( json_int used ) )
        ( http_response_free resp )
        = resp ( response_json 200 o )
        ( json_free o )
        ( string_free msg )
    } {
        ( http_response_free resp )
        = resp ( __an_json_err 400 `Not enough data to train` )
    }
    ( model_free mo )
    ( store_free st )
    ( string_free mname )
    ^ resp
}

// The listing is where "you see only your own models" is actually visible,
// so it filters rather than 403s: a viewer's listing simply does not
// mention what belongs to someone else.
@ __an_h_models HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal lp . gate who
    // With authentication off there is one implicit organisation and the
    // whole store is it. With it on, the store is FLAT — one directory of
    // models shared by every organisation — so an admin's world is the set
    // its organisation has CLAIMED, never the directory listing. Showing
    // the latter would show one tenant another tenant's models.
    : b see_all ! ( anomaly_authz_enabled )
    // One database open for the whole listing: asking per model would
    // reopen it once per row.
    : ~ ( Vec String ) owned ( vec_new [String] )
    ? see_all {} {
        ?? ( az_db_open ( string_data . lp org ) ) {
            F _ → {}
            T db → {
                ( vec_free [String] owned )
                ? ( principal_is_admin lp ) {
                    = owned ( az_org_model_names db )
                } {
                    = owned ( az_owned_names db ( string_data . lp sub ) )
                }
            }
        }
    }
    : Store st ( store_open g_an_root )
    : Json models ( json_obj_new )
    : ( Vec String ) names ( store_list st )
    : i n ( vec_len [String] names )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] names k ) {
            T nm → {
                : ~ b visible see_all
                ? visible {} { = visible ( __an_str_in owned ( string_data nm ) ) }
                ? visible {
                    : ?*Meta mload ( store_load_meta st ( string_data nm ) )
                    ?? mload {
                        T mm → {
                            : Json mj ( meta_to_json mm )
                            ( json_obj_set mj `editable_fields` ( meta_editable_fields ) )
                            ( json_obj_set models ( string_data nm ) mj )
                            ( meta_free mm )
                        }
                        F _ → {}
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
    ( vec_free_with [String] owned \ String x → v { ( string_free x ) } )
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `models` models )
    ( json_obj_set o `min_data_points` ( json_int ANOM_MIN_POINTS ) )
    ( json_obj_set o `max_data_points` ( json_int ANOM_MAX_POINTS ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( store_free st )
    ( __an_gate_free gate )
    ^ r
}

// The autoencoder version's own state, which lives outside the metadata
// (autoencoder.json, not meta.json) and so has no place in meta_to_json.
// `enabled` is read back from the metadata: disabling the version mutes
// the verdict but keeps the trained net.
@ __an_ae_json Store st s name * Meta mm → Json {
    : Json o ( json_obj_new )
    ?? ( store_load_ae st name ) {
        T ae → {
            ( json_obj_set o `trained` ( json_bool . ae trained ) )
            ( json_obj_set o `enabled` ( json_bool ( meta_version_enabled mm `autoencoder` F ) ) )
            ( json_obj_set o `reconstruction_threshold` ( json_float . ae threshold ) )
            ( json_obj_set o `training_data_points` ( json_int . ae trained_on ) )
            ( json_obj_set o `filtered_anomalies` ( json_int . ae filtered ) )
            ( json_obj_set o `prefilter_contamination` ( json_float . ae prefilter ) )
            ( json_obj_set o `trained_at` ( json_int . ae trained_at ) )
            ( json_obj_set o `retrain_with_forests` ( json_bool . mm sched_ae ) )
            ( json_obj_set o `decision_margin` ( json_float ( meta_version_margin mm `autoencoder` 0.05 ) ) )
            ( json_obj_set o `feature_names` ( _an_jarr_of_strs . ae feats ) )
            : Json layers ( json_arr_new )
            : Mlp net . ae net
            : i nl ( vec_len [i] . net sizes )
            : ~ i k 0
            ~ < k nl {
                ?? ( vec_get [i] . net sizes k ) {
                    T sz → { ( json_arr_push layers ( json_int sz ) ) }
                    F _ → {}
                }
                = k + k 1
            }
            ( json_obj_set o `layer_sizes` layers )
            ( ae_free ae )
        }
        F → {
            ( json_obj_set o `trained` ( json_bool F ) )
            ( json_obj_set o `enabled` ( json_bool ( meta_version_enabled mm `autoencoder` F ) ) )
        }
    }
    ^ o
}

@ __an_h_metadata HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    // The owner is not part of the stored metadata — it belongs to the
    // organisation's database, not to the model — but a client asking who
    // owns a model has this response in its hand already.
    : Principal mp . gate who
    : ~ String owner ( string_new )
    ? ( anomaly_authz_enabled ) {
        ?? ( az_db_open ( string_data . mp org ) ) {
            F _ → {}
            T db → {
                ( string_free owner )
                = owner ( az_model_owner db ( string_data mname ) )
            }
        }
    } {}
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    : ?*Meta mload ( store_load_meta st ( string_data mname ) )
    : ~ HttpResponse resp ( response_status_only 500 )
    ?? mload {
        T mm → {
            : Json o ( meta_to_json mm )
            ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
            ( json_obj_set o `owner` ( json_str_lit ( string_data owner ) ) )
            ( json_obj_set o `editable_fields` ( meta_editable_fields ) )
            ( json_obj_set o `autoencoder` ( __an_ae_json st ( string_data mname ) mm ) )
            ( http_response_free resp )
            = resp ( response_json 200 o )
            ( json_free o )
            ( meta_free mm )
        }
        F _ → {
            ( http_response_free resp )
            = resp ( __an_404_model ( string_data mname ) )
        }
    }
    ( store_free st )
    ( string_free owner )
    ( string_free mname )
    ^ resp
}

@ __an_h_data HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : i limit ( __an_query_int . req query `limit` 100 )
    : ( Vec String ) pts ( store_load_points st ( string_data mname ) )
    : i total ( vec_len [String] pts )
    : ~ i from 0
    ? > limit 0 {
        ? > total limit { = from - total limit } {}
    } {}
    : Json arr ( json_arr_new )
    : ~ i k from
    ~ < k total {
        ?? ( vec_get [String] pts k ) {
            T l → {
                : !Json JsonError jr ( json_parse ( string_data l ) )
                ?? jr {
                    T j → { ( json_arr_push arr j ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] pts \ String x → v { ( string_free x ) } )
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
    ( json_obj_set o `data_points_count` ( json_int total ) )
    ( json_obj_set o `data` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( store_free st )
    ( string_free mname )
    ^ r
}

// String query parameter (?key=value). Empty String when missing. Values
// are taken verbatim up to the next '&' — no percent-decoding, because
// every parameter this route accepts is a name from our own metadata.
@ __an_query_str String q s key → String {
    : String needle ( string_from key )
    ( string_push_char needle 61 )
    : ?i at0 ( string_index_of q ( string_data needle ) )
    : i klen ( string_len needle )
    ( string_free needle )
    ?? at0 {
        T at → {
            : String val ( string_new )
            : i n ( string_len q )
            : ~ i k + at klen
            : ~ b going T
            ~ & going < k n {
                : i c ( string_get q k )
                ? == c 38 { = going F } {
                    ( string_push_char val c )
                    = k + k 1
                }
            }
            ^ val
        }
        F _ → { ^ ( string_new ) }
    }
}

// Is `name` listed in a comma-separated filter? An empty filter matches
// everything, which is what makes "no filter" and "all filters" the same
// request.
@ __an_csv_has String csv s name → b {
    ? == ( string_len csv ) 0 { ^ T } {}
    : ( Vec String ) parts ( string_split csv `,` )
    : i n ( vec_len [String] parts )
    : ~ b found F
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] parts k ) {
            T x → { ? == ( nurl_str_eq ( string_data x ) name ) 1 { = found T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] parts \ String x → v { ( string_free x ) } )
    ^ found
}

// GET /models/dynamic/<m>/anomalies
//
// The dashboard's scan, server-side. One model load, one pass over the
// requested slice of the ring, verdicts served from the epoch-stamped
// cache when the model has not changed since they were computed.
//
//   ?from=<unix>&to=<unix>     time window (either bound may be omitted)
//   &last=<seconds>            shorthand: the last N seconds up to `to`/now
//   &limit=N                   newest N rows of the window (default 2000)
//   &only=anomalies            omit the rows nothing flagged
//   &versions=a,b              keep only rows flagged by one of these
//   &fields=x,y                include these numeric fields per row
//   &contrib=N                 top-N autoencoder contributors per flagged row
//   &refresh=1                 recompute even when the cache is warm
//
// `total`/`considered`/`anomalies` describe the whole window; `points` is
// what survived `limit`, `only` and `versions`, so a filtered response
// still says how much it filtered.
@ __an_h_anomalies HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }

    : i limit ( __an_query_int . req query `limit` 2000 )
    : i q_from ( __an_query_int . req query `from` 0 )
    : i q_to ( __an_query_int . req query `to` 0 )
    : i q_last ( __an_query_int . req query `last` 0 )
    // Read via the string form: __an_query_int treats a non-positive value
    // as "absent", and `contrib=0` (chart-only fetches that want no
    // attribution) has to be distinguishable from not asking at all.
    : String ctopk ( __an_query_str . req query `contrib` )
    : ~ i topk 3
    ? > ( string_len ctopk ) 0 {
        ?? ( string_to_int ctopk ) { T x → { = topk x } F _ → {} }
    } {}
    ( string_free ctopk )
    : i refresh ( __an_query_int . req query `refresh` 0 )
    : String only ( __an_query_str . req query `only` )
    : String vfilter ( __an_query_str . req query `versions` )
    : String ffilter ( __an_query_str . req query `fields` )
    : b only_anom == ( nurl_str_eq ( string_data only ) `anomalies` ) 1

    : *Model mo ( model_open st ( string_data mname ) )

    // `last` is relative to the window's upper bound, or to the newest
    // stored point when there is none — never to the server's clock, so a
    // model that stopped receiving data still answers "the last 24 h of it".
    : ~ i from_ts q_from
    : ~ i to_ts q_to
    : i q_span ( __an_last_span mo q_last )
    ? > q_span 0 {
        : ~ i anchor to_ts
        ? > anchor 0 {} {
            : i np ( model_n_points mo )
            ? > np 0 {
                ?? ( vec_get [i] . mo times - np 1 ) { T x → { = anchor x } F _ → {} }
            } {}
        }
        ? > anchor 0 { = from_ts - anchor q_span } {}
    } {}

    : ScanOut so ( model_scan_at mo from_ts to_ts limit > refresh 0 )

    : Json vers ( json_arr_new )
    : i nvn ( vec_len [String] . so vnames )
    : ~ i k 0
    ~ < k nvn {
        ?? ( vec_get [String] . so vnames k ) {
            T nm → { ( json_arr_push vers ( json_str_lit ( string_data nm ) ) ) }
            F _ → {}
        }
        = k + k 1
    }

    : ( Vec String ) fields ( string_split ffilter `,` )
    : b want_fields > ( string_len ffilter ) 0

    : Json arr ( json_arr_new )
    : i np ( vec_len [ScoredPt] . so pts )
    : ~ i shown 0
    = k 0
    ~ < k np {
        ?? ( vec_get [ScoredPt] . so pts k ) {
            T r → {
                // Version names this row's bitmasks decode to.
                : Json flagged ( json_arr_new )
                : ~ b keep T
                : ~ b matched F
                : ~ i b 0
                ~ < b nvn {
                    ? != & >> . r sp_flagged b 1 0 {
                        ?? ( vec_get [String] . so vnames b ) {
                            T nm → {
                                ( json_arr_push flagged ( json_str_lit ( string_data nm ) ) )
                                ? ( __an_csv_has vfilter ( string_data nm ) ) { = matched T } {}
                            }
                            F _ → {}
                        }
                    } {}
                    = b + b 1
                }
                ? only_anom { ? . r sp_anomaly {} { = keep F } } {}
                ? > ( string_len vfilter ) 0 { ? matched {} { = keep F } } {}

                ? keep {
                    : Json o ( json_obj_new )
                    ( json_obj_set o `index` ( json_int . r sp_idx ) )
                    ( json_obj_set o `timestamp` ( json_int . r sp_ts ) )
                    ( json_obj_set o `score` ( json_float . r sp_score ) )
                    ( json_obj_set o `anomaly` ( json_bool . r sp_anomaly ) )
                    ( json_obj_set o `versions` flagged )
                    ? || want_fields . r sp_anomaly {
                        ?? ( model_point_json mo . r sp_idx ) {
                            T rec → {
                                ? want_fields {
                                    : Json vals ( json_obj_new )
                                    : i nf ( vec_len [String] fields )
                                    : ~ i fi 0
                                    ~ < fi nf {
                                        ?? ( vec_get [String] fields fi ) {
                                            T fname → {
                                                ?? ( json_obj_get rec ( string_data fname ) ) {
                                                    T fv → { ( json_obj_set vals ( string_data fname ) ( json_clone fv ) ) }
                                                    F _ → {}
                                                }
                                            }
                                            F _ → {}
                                        }
                                        = fi + fi 1
                                    }
                                    ( json_obj_set o `values` vals )
                                } {}
                                // Attribution costs one autoencoder forward
                                // pass, so it is computed only for the rows
                                // actually being returned as anomalies.
                                ? & . r sp_anomaly > topk 0 {
                                    : ( Vec AeContrib ) cs ( model_ae_contrib mo rec topk )
                                    : i nc ( vec_len [AeContrib] cs )
                                    ? > nc 0 {
                                        : Json ca ( json_arr_new )
                                        : ~ i ci 0
                                        ~ < ci nc {
                                            ?? ( vec_get [AeContrib] cs ci ) {
                                                T c → {
                                                    : Json co ( json_obj_new )
                                                    ( json_obj_set co `feature` ( json_str_lit ( string_data . c ac_name ) ) )
                                                    ( json_obj_set co `error` ( json_float . c ac_err ) )
                                                    ( json_obj_set co `share` ( json_float . c ac_share ) )
                                                    ( json_arr_push ca co )
                                                }
                                                F _ → {}
                                            }
                                            = ci + ci 1
                                        }
                                        ( json_obj_set o `contributions` ca )
                                    } {}
                                    ( ae_contrib_free cs )
                                } {}
                                ( json_free rec )
                            }
                            F → {}
                        }
                    } {}
                    ( json_arr_push arr o )
                    = shown + shown 1
                } { ( json_free flagged ) }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] fields \ String x → v { ( string_free x ) } )

    : Json cache ( json_obj_new )
    ( json_obj_set cache `hits` ( json_int . so hits ) )
    ( json_obj_set cache `misses` ( json_int . so misses ) )
    ( json_obj_set cache `epoch` ( json_int . so epoch ) )

    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
    ( json_obj_set o `data_points_count` ( json_int . so total ) )
    ( json_obj_set o `considered` ( json_int . so considered ) )
    ( json_obj_set o `anomalies` ( json_int . so anomalies ) )
    ( json_obj_set o `returned` ( json_int shown ) )
    ( json_obj_set o `model_versions` vers )
    ( json_obj_set o `cache` cache )
    ( json_obj_set o `points` arr )

    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( scan_free so )
    ( model_free mo )
    ( store_free st )
    ( string_free only )
    ( string_free vfilter )
    ( string_free ffilter )
    ( string_free mname )
    ^ r
}

@ __an_h_reset HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    ( model_reset mo )
    ( model_free mo )
    : String msg ( string_from `Model ` )
    ( string_push_str msg ( string_data mname ) )
    ( string_push_str msg ` reset` )
    : Json o ( __an_ok_msg ( string_data msg ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_delete HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ r404
    }
    : b okd ( store_delete st ( string_data mname ) )
    // The stored model is gone; its ownership row must go with it, or the
    // next model to take the name inherits an owner nobody chose.
    : Principal dp . gate who
    ( __an_forget_model dp ( string_data mname ) )
    ( __an_gate_free gate )
    : String msg ( string_from `Model ` )
    ( string_push_str msg ( string_data mname ) )
    ( string_push_str msg ` deleted successfully` )
    : Json o ( __an_ok_msg ( string_data msg ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( store_free st )
    ( string_free mname )
    ^ r
}

@ __an_h_schedule HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            : i below ( _an_jint body `below_max_retrain_frequency` 0 )
            : i atmax ( _an_jint body `at_max_retrain_frequency` 0 )
            ( json_free body )
            ? || > below 0 > atmax 0 {} {
                ( store_free st )
                ( string_free mname )
                ^ ( __an_json_err 400 `No training schedule parameters provided` )
            }
            : *Model mo ( model_open st ( string_data mname ) )
            ( model_set_schedule mo below atmax )
            : *Meta mm ( model_metadata mo )
            : String msg ( string_from `Training schedule updated for model ` )
            ( string_push_str msg ( string_data mname ) )
            : Json o ( __an_ok_msg ( string_data msg ) )
            : Json sched ( json_obj_new )
            ( json_obj_set sched `below_max` ( json_int . mm sched_below ) )
            ( json_obj_set sched `at_max` ( json_int . mm sched_at_max ) )
            ( json_obj_set sched `autoencoder` ( json_bool . mm sched_ae ) )
            ( json_obj_set o `training_schedule` sched )
            : HttpResponse r ( response_json 200 o )
            ( json_free o )
            ( string_free msg )
            ( model_free mo )
            ( store_free st )
            ( string_free mname )
            ^ r
        }
        F _ → {
            ( store_free st )
            ( string_free mname )
            ^ ( __an_json_err 400 `No data provided` )
        }
    }
}

@ __an_h_meta_update HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            : *Model mo ( model_open st ( string_data mname ) )
            : String err ( model_apply_meta_patch mo body )
            ( json_free body )
            ? == ( string_len err ) 0 {} {
                : HttpResponse rbad ( __an_json_err 400 ( string_data err ) )
                ( string_free err )
                ( model_free mo )
                ( store_free st )
                ( string_free mname )
                ^ rbad
            }
            ( string_free err )
            : *Meta mm ( model_metadata mo )
            : String msg ( string_from `Metadata updated for model ` )
            ( string_push_str msg ( string_data mname ) )
            : Json o ( __an_ok_msg ( string_data msg ) )
            ( string_free msg )
            : Json meta ( meta_to_json mm )
            ( json_obj_set meta `model_name` ( json_str_lit ( string_data mname ) ) )
            ( json_obj_set meta `editable_fields` ( meta_editable_fields ) )
            ( json_obj_set meta `autoencoder` ( __an_ae_json st ( string_data mname ) mm ) )
            ( json_obj_set o `metadata` meta )
            : HttpResponse r ( response_json 200 o )
            ( json_free o )
            ( model_free mo )
            ( store_free st )
            ( string_free mname )
            ^ r
        }
        F _ → {
            ( store_free st )
            ( string_free mname )
            ^ ( __an_json_err 400 `No data provided` )
        }
    }
}

@ __an_h_train_ae HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : *Model mo ( model_open st ( string_data mname ) )
    // Optional body: {"hidden": [64, 32, 64], "contamination": 0.1}.
    // Absent (or empty / unparsable) → the 64-32-64 default and the
    // pre-filter's own "auto" contamination.
    : ( Vec i ) hidden ( vec_new [i] )
    : ~ f contam -1.0
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `hidden` ) {
                T ha → {
                    ? ( json_is_arr ha ) {
                        : i nh ( json_arr_len ha )
                        : ~ i k 0
                        ~ < k nh {
                            ?? ( json_arr_get ha k ) {
                                T e → {
                                    : ?i hv ( json_num_as_i e )
                                    ?? hv { T x → { ? > x 0 { ( vec_push [i] hidden x ) } {} } F _ → {} }
                                }
                                F _ → {}
                            }
                            = k + k 1
                        }
                    } {}
                }
                F _ → {}
            }
            ?? ( json_obj_get body `contamination` ) {
                T cj → {
                    ? ( json_is_num cj ) {
                        : ?f cf ( json_num_as_f cj )
                        ?? cf { T x → { ? > x 0.0 { = contam x } {} } F _ → {} }
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F _ → {}
    }
    : String err ( model_train_autoencoder mo hidden contam )
    ( vec_free [i] hidden )
    ? == ( string_len err ) 0 {
        : AeModel tae . mo ae
        : String msg ( string_from `Autoencoder trained successfully for model ` )
        ( string_push_str msg ( string_data mname ) )
        : Json o ( __an_ok_msg ( string_data msg ) )
        ( string_free msg )
        ( json_obj_set o `training_data_points` ( json_int . tae trained_on ) )
        ( json_obj_set o `filtered_anomalies` ( json_int . tae filtered ) )
        ( json_obj_set o `reconstruction_threshold` ( json_float . tae threshold ) )
        : HttpResponse rr ( response_json 200 o )
        ( string_free err )
        ( model_free mo )
        ( store_free st )
        ( string_free mname )
        ^ rr
    } {
        : HttpResponse rr ( __an_json_err 400 ( string_data err ) )
        ( string_free err )
        ( model_free mo )
        ( store_free st )
        ( string_free mname )
        ^ rr
    }
}

// The rate ladder a calibration answers "margin for" without being asked:
// what a person can type in one breath.
@ __an_cal_rates → ( Vec f ) {
    : ( Vec f ) r ( vec_new [f] )
    ( vec_push [f] r 0.001 ) ( vec_push [f] r 0.005 ) ( vec_push [f] r 0.01 )
    ( vec_push [f] r 0.02 ) ( vec_push [f] r 0.05 ) ( vec_push [f] r 0.1 )
    ^ r
}

// The (rate, margin) curve the dashboard interpolates for "how many
// would THIS margin flag": every 0.1 % up to 1 %, then every 1 % — the
// resolution a slider needs where the decision values are dense.
@ __an_cal_curve CalVer cv → Json {
    : Json a ( json_arr_new )
    : ~ i k 0
    ~ <= k 109 {
        : ~ f rate 0.0
        ? < k 10 { = rate * # f k 0.001 } { = rate * # f - k 9 0.01 }
        : f m ( cal_margin_for_rate cv rate )
        : Json pt ( json_arr_new )
        ( json_arr_push pt ( json_float rate ) )
        ( json_arr_push pt ( json_float m ) )
        ( json_arr_push a pt )
        = k + k 1
    }
    ^ a
}

@ __an_rate_key f rate → String {
    // "0.01" → key "1%", "0.001" → "0.1%", "0.1" → "10%"
    : f pct * rate 100.0
    : String key ( string_new )
    : f r3 ( round_sig pct 3 )
    ? == r3 ( float_floor r3 ) {
        ( string_push_int key # i r3 )
    } {
        : s t ( float_to_string r3 )
        ( string_push_str key t )
    }
    ( string_push_char key 37 )
    ^ key
}

// One version's calibration block.
@ __an_cal_ver_json CalVer cv b with_curve → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `margin` ( json_float . cv cur_margin ) )
    ( json_obj_set o `n` ( json_int . cv n ) )
    ( json_obj_set o `flagged` ( json_int . cv flagged ) )
    : ~ f rate 0.0
    ? > . cv n 0 { = rate / # f . cv flagged # f . cv n } {}
    ( json_obj_set o `rate` ( json_float rate ) )
    ( json_obj_set o `worst` ( json_float . cv worst ) )
    ( json_obj_set o `median` ( json_float . cv median ) )
    : Json mfr ( json_obj_new )
    : ( Vec f ) rates ( __an_cal_rates )
    : i nr ( vec_len [f] rates )
    : ~ i k 0
    ~ < k nr {
        : f r ( _mlp_fget rates k )
        : f m ( cal_margin_for_rate cv r )
        : Json e ( json_obj_new )
        ( json_obj_set e `margin` ( json_float m ) )
        ( json_obj_set e `flagged` ( json_int ( cal_flagged_at cv m ) ) )
        : String key ( __an_rate_key r )
        ( json_obj_set mfr ( string_data key ) e )
        ( string_free key )
        = k + k 1
    }
    ( vec_free [f] rates )
    ( json_obj_set o `margin_for_rate` mfr )
    ? with_curve { ( json_obj_set o `curve` ( __an_cal_curve cv ) ) } {}
    ^ o
}

// `last` as a span of stamps: seconds on the wall clock; on the count
// clock the caller counts POINTS, and a point is one tick.
@ __an_last_span * Model mo i q_last → i {
    ^ ( model_last_span mo q_last )
}

// The window shared by calibration and fine-tune: ?from / ?to / ?last
// (query) or the same keys in a JSON body; `last` defaults to 24 h when
// nothing bounds the window.
@ __an_cal_window * Model mo i q_from i q_to i q_last → ( Vec i ) {
    : ~ i from_ts q_from
    : ~ i to_ts q_to
    : ~ i last ( __an_last_span mo q_last )
    ? & & <= from_ts 0 <= to_ts 0 == last 0 { = last ( model_last_span mo ( model_default_last mo ) ) } {}
    ? > last 0 {
        : i f2 ( model_window_from_last mo to_ts last )
        ? > f2 0 { = from_ts f2 } {}
    } {}
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w from_ts )
    ( vec_push [i] w to_ts )
    ^ w
}

// GET /models/dynamic/<m>/calibration
//
//   ?from=<unix>&to=<unix>&last=<seconds>   window (default: last 24 h;
//                                           last=all for the whole ring)
//   &curve=0                                omit the (rate, margin) curves
//
// Per enabled, trained version: the current margin and what it flags in
// the window, the margin for each standard alert rate, and the curve.
// Read-only — nothing is written.
@ __an_h_calibration HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Gate gate ( __an_gate_model req ( string_data mname ) F F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }
    : i q_from ( __an_query_int . req query `from` 0 )
    : i q_to ( __an_query_int . req query `to` 0 )
    : i q_last ( __an_query_int . req query `last` 0 )
    : String qcurve ( __an_query_str . req query `curve` )
    : b with_curve ! == ( nurl_str_eq ( string_data qcurve ) `0` ) 1
    ( string_free qcurve )

    : *Model mo ( model_open st ( string_data mname ) )
    ? ( model_is_trained mo ) {} {
        : String msg ( string_from `Model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` exists but is not trained yet.` )
        : HttpResponse rr ( __an_json_err 400 ( string_data msg ) )
        ( string_free msg )
        ( model_free mo )
        ( store_free st )
        ( string_free mname )
        ^ rr
    }
    : ( Vec i ) win ( __an_cal_window mo q_from q_to q_last )
    : i from_ts ( _mlp_iget win 0 )
    : i to_ts ( _mlp_iget win 1 )
    ( vec_free [i] win )
    : CalReport cal ( model_calibrate mo from_ts to_ts )

    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `model` ( json_str_lit ( string_data mname ) ) )
    : Json wj ( json_obj_new )
    ( json_obj_set wj `from` ( json_int from_ts ) )
    ( json_obj_set wj `to` ( json_int to_ts ) )
    ( json_obj_set wj `rows` ( json_int . cal n_rows ) )
    ( json_obj_set wj `total` ( json_int ( model_n_points mo ) ) )
    ( json_obj_set o `window` wj )
    : Json agg ( json_obj_new )
    ( json_obj_set agg `flagged` ( json_int . cal agg_flagged ) )
    : ~ f arate 0.0
    ? > . cal n_rows 0 { = arate / # f . cal agg_flagged # f . cal n_rows } {}
    ( json_obj_set agg `rate` ( json_float arate ) )
    ( json_obj_set o `aggregate` agg )
    : Json vers ( json_obj_new )
    : i ni ( vec_len [CalVer] . cal items )
    : ~ i k 0
    ~ < k ni {
        ?? ( vec_get [CalVer] . cal items k ) {
            T cv → { ( json_obj_set vers ( string_data . cv cvname ) ( __an_cal_ver_json cv with_curve ) ) }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set o `versions` vers )
    ( cal_free cal )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( model_free mo )
    ( store_free st )
    ( string_free mname )
    ^ r
}

// POST /models/dynamic/<m>/finetune
//
// Body (all optional): {"rate": 0.01, "last": 86400 | "all", "from": N, "to": N,
// "dry_run": false, "versions": ["short_term", ...]}. Sets every enabled,
// trained version's margin so that `rate` of the window is flagged
// (rounded to the fewest significant digits that keep the count);
// `dry_run` reports without writing.
// The response keeps the legacy `adjusted_margins` map (the new margins,
// whether or not they were applied) beside the per-version detail.
@ __an_h_finetune HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }

    // Authorization first: a caller who may not touch this model must not
    // learn from a 404 whether it exists.
    : Gate gate ( __an_gate_model req ( string_data mname ) F T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    ( __an_gate_free gate )
    : Store st ( store_open g_an_root )
    ? ( store_exists st ( string_data mname ) ) {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( store_free st )
        ( string_free mname )
        ^ r404
    }

    : ~ f rate ANOM_FT_RATE
    : ~ i q_from ( __an_query_int . req query `from` 0 )
    : ~ i q_to ( __an_query_int . req query `to` 0 )
    : ~ i q_last ( __an_query_int . req query `last` 0 )
    : ~ b dry F
    : ~ b own F
    : ( Vec String ) only ( vec_new [String] )
    : ~ b bad_rate F
    : String qlast ( __an_query_str . req query `last` )
    ? == ( nurl_str_eq ( string_data qlast ) `own` ) 1 { = own T } {}
    ( string_free qlast )
    ?? ( __an_body_json req ) {
        T body → {
            ? ( json_is_obj body ) {
                ?? ( json_obj_get body `rate` ) {
                    T rj → {
                        : ~ b okr F
                        ? ( json_is_num rj ) {
                            ?? ( json_num_as_f rj ) {
                                T x → { ? & >= x 0.0 <= x 1.0 { = rate x = okr T } {} }
                                F _ → {}
                            }
                        } {}
                        ? okr {} { = bad_rate T }
                    }
                    F _ → {}
                }
                = q_from ( _an_jint body `from` q_from )
                = q_to ( _an_jint body `to` q_to )
                = q_last ( _an_jint body `last` q_last )
                // "last": "all" (or -1) means the whole ring, as in the query;
                // "own" tunes each version over the window it trains on.
                ?? ( json_obj_get body `last` ) {
                    T lj → {
                        ? ( json_is_str lj ) {
                            ? == ( nurl_str_eq ( json_str_data lj ) `all` ) 1 { = q_last -1 } {}
                            ? == ( nurl_str_eq ( json_str_data lj ) `own` ) 1 { = own T } {}
                        } {}
                    }
                    F _ → {}
                }
                ?? ( json_obj_get body `dry_run` ) { T dj → { = dry ( json_as_bool dj ) } F _ → {} }
                ?? ( json_obj_get body `versions` ) {
                    T va → {
                        ? ( json_is_arr va ) {
                            : i nv ( json_arr_len va )
                            : ~ i k 0
                            ~ < k nv {
                                ?? ( json_arr_get va k ) {
                                    T e → { ? ( json_is_str e ) { ( vec_push [String] only ( string_from ( json_str_data e ) ) ) } {} }
                                    F _ → {}
                                }
                                = k + k 1
                            }
                        } {}
                    }
                    F _ → {}
                }
            } {}
            ( json_free body )
        }
        F _ → {}
    }
    ? bad_rate {
        ( vec_free_with [String] only \ String x → v { ( string_free x ) } )
        : HttpResponse rb ( __an_json_err 400 `rate must be a number between 0 and 1 (the fraction of the window to flag)` )
        ( store_free st )
        ( string_free mname )
        ^ rb
    } {}

    : *Model mo ( model_open st ( string_data mname ) )
    ? ( model_is_trained mo ) {} {
        ( vec_free_with [String] only \ String x → v { ( string_free x ) } )
        : String msg ( string_from `Model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` exists but is not trained yet.` )
        : HttpResponse rr ( __an_json_err 400 ( string_data msg ) )
        ( string_free msg )
        ( model_free mo )
        ( store_free st )
        ( string_free mname )
        ^ rr
    }
    : ~ i from_ts 0
    : ~ i to_ts 0
    ? own {} {
        : ( Vec i ) win ( __an_cal_window mo q_from q_to q_last )
        = from_ts ( _mlp_iget win 0 )
        = to_ts ( _mlp_iget win 1 )
        ( vec_free [i] win )
    }
    : FineTuneReport rep ? own ( model_finetune_own mo rate ! dry only ) ( model_finetune_at mo rate from_ts to_ts ! dry only )
    ? own { = from_ts . rep from_ts } {}
    ( vec_free_with [String] only \ String x → v { ( string_free x ) } )

    : Json margins ( json_obj_new )
    : Json scores ( json_obj_new )
    : Json vers ( json_obj_new )
    : i ni ( vec_len [FtVer] . rep items )
    : ~ i k 0
    ~ < k ni {
        ?? ( vec_get [FtVer] . rep items k ) {
            T ft → {
                ( json_obj_set margins ( string_data . ft ftname ) ( json_float . ft new_margin ) )
                ( json_obj_set scores ( string_data . ft ftname ) ( json_float . ft worst ) )
                : Json v ( json_obj_new )
                ( json_obj_set v `old_margin` ( json_float . ft old_margin ) )
                ( json_obj_set v `new_margin` ( json_float . ft new_margin ) )
                ( json_obj_set v `n` ( json_int . ft n ) )
                ( json_obj_set v `flagged_before` ( json_int . ft before ) )
                ( json_obj_set v `flagged_after` ( json_int . ft after ) )
                : ~ f rb 0.0
                : ~ f ra 0.0
                ? > . ft n 0 {
                    = rb / # f . ft before # f . ft n
                    = ra / # f . ft after # f . ft n
                } {}
                ( json_obj_set v `rate_before` ( json_float rb ) )
                ( json_obj_set v `rate_after` ( json_float ra ) )
                ( json_obj_set v `worst` ( json_float . ft worst ) )
                ( json_obj_set v `applied` ( json_bool . ft applied ) )
                ( json_obj_set v `from` ( json_int . ft ft_from ) )
                ( json_obj_set v `rows` ( json_int . ft ft_n_rows ) )
                ( json_obj_set vers ( string_data . ft ftname ) v )
            }
            F _ → {}
        }
        = k + k 1
    }
    : String msg ( string_new )
    ? dry {
        ( string_push_str msg `Dry run: margins for model ` )
        ( string_push_str msg ( string_data mname ) )
        ( string_push_str msg ` were not changed` )
    } {
        ( string_push_str msg `Successfully fine-tuned model ` )
        ( string_push_str msg ( string_data mname ) )
    }
    : Json o ( __an_ok_msg ( string_data msg ) )
    ( json_obj_set o `rate` ( json_float rate ) )
    ( json_obj_set o `dry_run` ( json_bool dry ) )
    : Json wj ( json_obj_new )
    ( json_obj_set wj `from` ( json_int from_ts ) )
    ( json_obj_set wj `to` ( json_int to_ts ) )
    ( json_obj_set wj `rows` ( json_int . rep n_rows ) )
    ( json_obj_set wj `own` ( json_bool own ) )
    ( json_obj_set o `window` wj )
    ( json_obj_set o `versions` vers )
    ( json_obj_set o `adjusted_margins` margins )
    ( json_obj_set o `max_anomaly_scores` scores )
    ( finetune_free rep )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free msg )
    ( model_free mo )
    ( store_free st )
    ( string_free mname )
    ^ r
}

// Batch scoring names a path on the SERVER's filesystem, so it is the one
// route where the caller picks what the process reads. Administrators only:
// there is no per-model ownership to check, only whether this caller is
// trusted with the machine's files at all.
@ __an_h_batch HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    ( __an_gate_free gate )
    : ?Json bodyo ( __an_body_json req )
    ?? bodyo {
        T body → {
            ? ( json_obj_has body `model_name` ) {
                ( json_free body )
                ^ ( __an_json_err 400 `model_name is not supported: batch scoring trains a stateless forest on the file itself` )
            } {}
            : ~ String fpath ( string_new )
            : ~ b have_path F
            ?? ( json_obj_get body `file_path` ) {
                T fp → {
                    ? ( json_is_str fp ) {
                        ( string_free fpath )
                        = fpath ( string_from ( json_str_data fp ) )
                        = have_path T
                    } {}
                }
                F _ → {}
            }
            : ~ b header T
            ?? ( json_obj_get body `has_header` ) {
                T hh → { = header ( json_as_bool hh ) }
                F _ → {}
            }
            ( json_free body )
            ? have_path {} {
                ( string_free fpath )
                ^ ( __an_json_err 400 `file_path is required` )
            }
            : !String IoErr fr ( read_file ( string_data fpath ) )
            ?? fr {
                T text → {
                    : AnomCsv ds ( anom_parse_csv ( string_data text ) `,` header )
                    ( string_free text )
                    ? || <= . ds rows 0 <= . ds cols 0 {
                        ( anom_csv_free ds )
                        ( string_free fpath )
                        ^ ( __an_json_err 400 `No numeric rows found in file` )
                    } {}
                    : VerCfg cfg @ VerCfg { ( string_from `batch` ) 0 0 0 0 100 256 -1.0 0.0 T }
                    : BatchReport rep ( anomaly_batch . ds data . ds rows . ds cols cfg )
                    ( _an_vercfg_free cfg )

                    : Json res ( json_obj_new )
                    ( json_obj_set res `file_path` ( json_str_lit ( string_data fpath ) ) )
                    ( json_obj_set res `model_used` ( json_str_lit `batch:iforest` ) )
                    ( json_obj_set res `total_rows` ( json_int . rep total_rows ) )
                    ( json_obj_set res `anomaly_count` ( json_int . rep anomaly_count ) )
                    ( json_obj_set res `anomaly_percentage` ( json_float . rep anomaly_percentage ) )
                    ( json_obj_set res `has_anomalies` ( json_bool . rep has_anomalies ) )
                    : Json idxs ( json_arr_new )
                    : i nh ( vec_len [i] . rep anomaly_indices )
                    : ~ i k 0
                    ~ < k nh {
                        ?? ( vec_get [i] . rep anomaly_indices k ) {
                            T idx → { ( json_arr_push idxs ( json_int idx ) ) }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ( json_obj_set res `anomaly_indices` idxs )
                    // First 100 anomalies with their scores (and named
                    // column values when the CSV had a header row).
                    : Json details ( json_arr_new )
                    : ~ i d 0
                    ~ & < d nh < d 100 {
                        ?? ( vec_get [i] . rep anomaly_indices d ) {
                            T idx → {
                                : Json det ( json_obj_new )
                                ( json_obj_set det `index` ( json_int idx ) )
                                ?? ( vec_get [f] . rep scores idx ) {
                                    T sc → { ( json_obj_set det `anomaly_score` ( json_float sc ) ) }
                                    F _ → {}
                                }
                                : i nhead ( vec_len [String] . ds headers )
                                : ~ i c 0
                                ~ & < c nhead < c . ds cols {
                                    ?? ( vec_get [String] . ds headers c ) {
                                        T hname → {
                                            ?? ( vec_get [f] . ds data + * idx . ds cols c ) {
                                                T val → { ( json_obj_set det ( string_data hname ) ( json_float val ) ) }
                                                F _ → {}
                                            }
                                        }
                                        F _ → {}
                                    }
                                    = c + c 1
                                }
                                ( json_arr_push details det )
                            }
                            F _ → {}
                        }
                        = d + d 1
                    }
                    ( json_obj_set res `anomaly_details` details )
                    ( anomaly_report_free rep )
                    ( anom_csv_free ds )
                    ( string_free fpath )

                    : Json o ( __an_ok_msg `Anomaly detection completed` )
                    ( json_obj_set o `result` res )
                    : HttpResponse r ( response_json 200 o )
                    ( json_free o )
                    ^ r
                }
                F _ → {
                    : String msg ( string_from `File not found: ` )
                    ( string_push_str msg ( string_data fpath ) )
                    : HttpResponse rr ( __an_json_err 404 ( string_data msg ) )
                    ( string_free msg )
                    ( string_free fpath )
                    ^ rr
                }
            }
        }
        F _ → { ^ ( __an_json_err 400 `file_path is required` ) }
    }
}

// ── Identity and organisation routes ──────────────────────────────────

// GET /api/auth/config — what a browser needs to start a sign-in.
//
// Public by necessity: the page that has not signed in yet is the one
// asking. Everything here is public by nature — a client id and an issuer
// URL are in the redirect the user's browser makes anyway — and publishing
// them is what stops the dashboard from carrying a second, drifting copy
// of the deployment's identity configuration.
@ __an_h_auth_config HttpRequest req Params p → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `enabled` ( json_bool ( anomaly_authz_enabled ) ) )
    ( json_obj_set o `mode` ( json_str_lit ? ( anomaly_authz_enabled ) `oidc` `simple` ) )
    ( json_obj_set o `issuer` ( json_str_lit ( anomaly_authz_issuer ) ) )
    ( json_obj_set o `client_id` ( json_str_lit ( anomaly_authz_client_id ) ) )
    ( json_obj_set o `audience` ( json_str_lit ( anomaly_authz_audience ) ) )
    ( json_obj_set o `redirect_path` ( json_str_lit `/oauth/callback` ) )
    ( json_obj_set o `open_ingest` ( json_bool ( anomaly_authz_open_ingest ) ) )
    : String scope ( string_from `openid profile email ` )
    ( string_push_str scope ( anomaly_authz_audience ) )
    ( string_push_str scope `/access_as_user` )
    ( json_obj_set o `scope` ( json_str_lit ( string_data scope ) ) )
    ( string_free scope )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ^ r
}

// GET /api/me — who the server thinks is calling.
@ __an_h_me HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : Json o ( principal_json me )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `auth_enabled` ( json_bool ( anomaly_authz_enabled ) ) )
    ( json_obj_set o `is_admin` ( json_bool ( principal_is_admin me ) ) )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( __an_gate_free gate )
    ^ r
}

// GET /api/org/users — the organisation's roster. Administrators only:
// it names every person who has ever signed in.
@ __an_h_org_users HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ Json arr ( json_arr_new )
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            ( json_free arr )
            = arr ( az_users_json db )
        }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `organization` ( json_str_lit ( string_data . me org ) ) )
    ( json_obj_set o `users` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( __an_gate_free gate )
    ^ r
}

// PUT /api/org/users/<sub>/role  { "role": "admin" | "viewer" }
@ __an_h_org_role HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ String target ( string_new )
    ?? ( params_get p `sub` ) {
        T v → { ( string_free target ) = target v }
        F junk → { ( string_free target ) = target junk }
    }
    : ~ String role ( string_new )
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `role` ) {
                T rv → {
                    ? ( json_is_str rv ) {
                        ( string_free role )
                        = role ( string_from ( json_str_data rv ) )
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F → {}
    }
    ? > ( string_len role ) 0 {} {
        ( string_free role ) ( string_free target ) ( __an_gate_free gate )
        ^ ( __an_json_err 400 `role must be "admin" or "viewer"` )
    }
    : ~ b ok F
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → { = ok ( az_user_set_role db ( string_data target ) ( string_data role ) ) }
    }
    : ~ HttpResponse r ( response_status_only 500 )
    ? ok {
        : String msg ( string_from `Role updated` )
        : Json o ( __an_ok_msg ( string_data msg ) )
        ( json_obj_set o `subject` ( json_str_lit ( string_data target ) ) )
        ( json_obj_set o `role` ( json_str_lit ( string_data role ) ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
        ( string_free msg )
    } {
        ( http_response_free r )
        // The one refusal worth naming: an organisation that demotes its
        // last administrator can never appoint another.
        = r ( __an_json_err 400 `Refused: unknown user, unknown role, or this is the organisation's last administrator.` )
    }
    ( string_free role )
    ( string_free target )
    ( __an_gate_free gate )
    ^ r
}

// GET /api/org/keys — the caller's keys, or the organisation's for an admin.
@ __an_h_keys_list HttpRequest req Params p → HttpResponse {
    // Administrators only. A key is a credential that reaches the whole
    // organisation; a viewer reads what the models have collected and
    // decided, and has no business knowing one exists.
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ Json arr ( json_arr_new )
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            ( json_free arr )
            = arr ( az_keys_json db )
        }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `keys` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( __an_gate_free gate )
    ^ r
}

// POST /api/org/keys  { "label": "node-red" }
//
// The response carries the only copy of the secret there will ever be: the
// database holds a SHA-256 of it, so a lost key is reissued, never
// recovered.
@ __an_h_keys_create HttpRequest req Params p → HttpResponse {
    // Administrators only. A key is a credential that reaches the whole
    // organisation; a viewer reads what the models have collected and
    // decided, and has no business knowing one exists.
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ String label ( string_new )
    : ~ b want_admin F
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `label` ) {
                T lv → {
                    ? ( json_is_str lv ) {
                        ( string_free label )
                        = label ( string_from ( json_str_data lv ) )
                    } {}
                }
                F _ → {}
            }
            ?? ( json_obj_get body `role` ) {
                T rv → {
                    ? ( json_is_str rv ) {
                        = want_admin == ( nurl_str_eq ( json_str_data rv ) AZ_ROLE_ADMIN ) 1
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F → {}
    }
    : ~ HttpResponse r ( __an_json_err 500 `could not open the organisation database` )
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            // A key carries a capability of its own, so it keeps working
            // when the person who made it is forgotten. `ingest` is the
            // default and the one a producer wants: it can send points to
            // the organisation's models and cannot delete them.
            : ~ s krole AZ_ROLE_INGEST
            ? want_admin { = krole AZ_ROLE_ADMIN } {}
            : KeyIssue k ( az_key_create db ( string_data . me sub ) ( string_data label ) krole ( now_seconds ) )
            : Json o ( json_obj_new )
            ( json_obj_set o `status` ( json_str_lit `success` ) )
            ( json_obj_set o `id` ( json_str_lit ( string_data . k key_id ) ) )
            ( json_obj_set o `label` ( json_str_lit ( string_data label ) ) )
            ( json_obj_set o `role` ( json_str_lit krole ) )
            ( json_obj_set o `key` ( json_str_lit ( string_data . k secret ) ) )
            ( json_obj_set o `message` ( json_str_lit `Copy this key now: it is stored hashed and cannot be shown again.` ) )
            ( http_response_free r )
            = r ( response_json 201 o )
            ( json_free o )
            ( key_issue_free k )
        }
    }
    ( string_free label )
    ( __an_gate_free gate )
    ^ r
}

// DELETE /api/org/keys/<id>
@ __an_h_keys_revoke HttpRequest req Params p → HttpResponse {
    // Administrators only. A key is a credential that reaches the whole
    // organisation; a viewer reads what the models have collected and
    // decided, and has no business knowing one exists.
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ String kid ( string_new )
    ?? ( params_get p `id` ) {
        T v → { ( string_free kid ) = kid v }
        F junk → { ( string_free kid ) = kid junk }
    }
    : ~ b ok F
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            = ok ( az_key_revoke db ( string_data kid ) ( now_seconds ) )
        }
    }
    : ~ HttpResponse r ( __an_json_err 404 `No such key, or it is already revoked.` )
    ? ok {
        : Json o ( __an_ok_msg `Key revoked` )
        ( json_obj_set o `id` ( json_str_lit ( string_data kid ) ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( string_free kid )
    ( __an_gate_free gate )
    ^ r
}

// POST /models/dynamic/<m>/claim  { "owner": "<sub>" }
//
// How the models that predate authentication get an owner, and how an
// administrator hands one over. Unowned by default means an admin has to
// decide — a model does not silently become the property of whoever
// happened to sign in first.
@ __an_h_claim HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Gate gate ( __an_gate_auth req T )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }
    : Principal me . gate who
    : Store st ( store_open g_an_root )
    : b exists ( store_exists st ( string_data mname ) )
    ( store_free st )
    ? exists {} {
        : HttpResponse r404 ( __an_404_model ( string_data mname ) )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ r404
    }
    : ~ String owner ( string_from ( string_data . me sub ) )
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `owner` ) {
                T ov → {
                    ? ( json_is_str ov ) {
                        ( string_free owner )
                        = owner ( string_from ( json_str_data ov ) )
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F → {}
    }
    : ~ b ok F
    : ~ b refused_home F
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            : b claimed ( az_model_in_org db ( string_data mname ) )
            // Reassigning WITHIN an organisation is ordinary administration.
            // Adopting one no organisation has claimed is not: nothing in an
            // unowned model says whose it is, so letting any admin take one
            // would let a stranger who signed in from their own tenant adopt
            // the operator's data. Only the home organisation — the first
            // this store created, which is the one that set the service up —
            // may do that.
            //
            // A model held by `public` counts as unowned for this purpose.
            // It got there because a point arrived without a credential
            // naming an owner, which is the same condition adoption exists
            // for; `public` is where such data waits, not an organisation
            // with a claim on it.
            : b home ( az_is_home_org ( string_data . me org ) )
            ? | claimed home {
                ? & home ! claimed {
                    : b _rel ( az_model_release_public ( string_data mname ) )
                } {}
                = ok ( az_model_claim db ( string_data mname ) ( string_data owner ) ( now_seconds ) T )
            } { = refused_home T }
        }
    }
    : ~ HttpResponse r ( __an_json_err 500 `could not record the owner` )
    ? refused_home {
        ( http_response_free r )
        = r ( __an_json_err 403 `This model belongs to no organization, and only the home organization may adopt one.` )
    } {}
    ? ok {
        : Json o ( __an_ok_msg `Owner set` )
        ( json_obj_set o `model` ( json_str_lit ( string_data mname ) ) )
        ( json_obj_set o `owner` ( json_str_lit ( string_data owner ) ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( string_free owner )
    ( __an_gate_free gate )
    ( string_free mname )
    ^ r
}

// POST /models/dynamic/<m>/import?format=csv|json|jsonl|auto
//     &inspect=1            describe the file and propose its clock; import nothing
//     &time=<json>          the time plan (percent-encoded JSON):
//                             {"mode":"auto"}                       — the proposal (default)
//                             {"mode":"column","column":"ts"}       — one column
//                             {"mode":"parts","parts":{"year":..,"month":..,"day":..,
//                                "clock":.. | "hour":..,"minute":..,"second":..}}
//                             {"mode":"none"}                       — read no time
//     &tz=local|utc|+03:00  the zone naive stamps are read in (default local)
//     &calendar=1           keep an ISO `time` column for calendar features
//     &clock=time|count     the clock a NEW model runs on; without it, a
//                           model born from stamped rows runs on time, one
//                           born from unstamped rows on its point count
//
// The body is the file, verbatim — no multipart, no base64. A file is
// bytes and this is the shortest path from a browser's FileReader to the
// ring; wrapping it in a form encoding would only mean decoding it again.
//
// The clock of a file is read before a row lands: `inspect=1` returns the
// columns, what their values look like, and a proposal — the column, or
// the year/month/day/clock parts, the time is in — with a confidence, so
// the dashboard can show the guess and let the person confirm or change
// it. The import call then takes the same plan back, stamps every row
// from it, and drops the columns it consumed so a year never becomes a
// feature.
//
// This is the same act as sending points, done in one call instead of ten
// thousand, so it is gated the same way: an `ingest` credential may do it,
// including bringing the model into being. And what it creates belongs to
// the ORGANISATION exactly like one grown from a stream — there is no third
// kind of model here.
@ __an_h_import HttpRequest req Params p → HttpResponse {
    : String mname ( __an_param_model p )
    ? ( __an_name_ok ( string_data mname ) ) {} {
        ( string_free mname )
        ^ ( __an_bad_name )
    }
    : Gate gate ( __an_gate_ingest req ( string_data mname ) )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rd
    }

    : String fmt ( __an_query_str . req query `format` )
    : String body ( bytes_to_str . req body )
    : ImportParse ip ( import_parse ( string_data body ) ( string_data fmt ) )
    ( string_free body )
    ( string_free fmt )

    ? > ( string_len . ip err ) 0 {
        : HttpResponse rr ( __an_json_err 400 ( string_data . ip err ) )
        ( import_parse_free ip )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rr
    } {}

    // The time spec: `time=` JSON, with `tz=` layered over it.
    : ~ Json spec ( json_obj_new )
    : String tq ( __an_query_str . req query `time` )
    ? > ( string_len tq ) 0 {
        : String tdec ( percent_decode ( string_data tq ) )
        : !Json JsonError tj ( json_parse ( string_data tdec ) )
        ( string_free tdec )
        ?? tj {
            T j → { ? ( json_is_obj j ) { ( json_free spec ) = spec j } { ( json_free j ) } }
            F _ → {}
        }
    } {}
    ( string_free tq )
    : String tzq ( __an_query_str . req query `tz` )
    ? > ( string_len tzq ) 0 { ( json_obj_set spec `tz` ( json_str_lit ( string_data tzq ) ) ) } {}
    ( string_free tzq )
    : i tz ( imp_tz_of spec )
    : b calendar > ( __an_query_int . req query `calendar` 0 ) 0
    : String clockq ( __an_query_str . req query `clock` )

    : Store st ( store_open g_an_root )
    : b existed ( store_exists st ( string_data mname ) )
    : Json insp ( import_inspect . ip rows spec tz )
    ( json_free spec )

    // inspect=1: the description, and where the model stands, nothing
    // more — a model that does not exist is not brought into being by a
    // look at a file.
    ? > ( __an_query_int . req query `inspect` 0 ) 0 {
        ( json_obj_set insp `format` ( json_str_lit ( string_data . ip format ) ) )
        ( json_obj_set insp `rows` ( json_int ( vec_len [Json] . ip rows ) ) )
        ( json_obj_set insp `skipped` ( json_int . ip skipped ) )
        : Json mj ( json_obj_new )
        ( json_obj_set mj `exists` ( json_bool existed ) )
        : ~ i npts 0
        : ~ b count F
        ? existed {
            : *Model mo0 ( model_open st ( string_data mname ) )
            : *Meta mm0 . mo0 meta
            = npts ( model_n_points mo0 )
            = count . mm0 count_clock
            ( model_free mo0 )
        } {}
        ( json_obj_set mj `data_points` ( json_int npts ) )
        ( json_obj_set mj `clock` ( json_str_lit ? count `count` `time` ) )
        ( json_obj_set insp `model` mj )
        : HttpResponse ri ( response_json 200 insp )
        ( json_free insp )
        ( string_free clockq )
        ( import_parse_free ip )
        ( store_free st )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ ri
    } {}
    : *Model mo ( model_open st ( string_data mname ) )
    : *Meta mm . mo meta

    // The plan, applied: every row stamped from it, or a 400 naming what
    // the plan asked for and the file does not have.
    : Json plan ?? ( json_obj_get insp `time` ) { T tp → ( json_clone tp ) F _ → ( json_obj_new ) }
    ( json_free insp )
    ? ( json_obj_has plan `error` ) {
        : s perr ?? ( json_obj_get plan `error` ) { T e → ( json_str_data e ) F _ → `bad time plan` }
        : HttpResponse rp ( __an_json_err 400 perr )
        ( json_free plan )
        ( string_free clockq )
        ( import_parse_free ip )
        ( model_free mo )
        ( store_free st )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rp
    } {}
    : ImpTimeResult tr ( import_time_apply . ip rows plan calendar tz )

    // Which clock. A model that already holds points keeps its clock; a
    // fresh one takes `clock=`, or the one its first rows imply.
    : ~ String cerr ( string_new )
    ? == ( model_n_points mo ) 0 {
        : ~ b want . mm count_clock
        ? > ( string_len clockq ) 0 {
            ? == ( nurl_str_eq ( string_data clockq ) `count` ) 1 { = want T } {
                ? == ( nurl_str_eq ( string_data clockq ) `time` ) 1 { = want F } {
                    ( string_free cerr )
                    = cerr ( string_from `clock must be "time" or "count"` )
                }
            }
        } { = want == . tr stamped 0 }
        = . mm count_clock want
    } {
        ? & > ( string_len clockq ) 0 != == ( nurl_str_eq ( string_data clockq ) `count` ) 1 . mm count_clock {
            ( string_free cerr )
            = cerr ( string_from `clock can only change on a model with no stored points (reset it first)` )
        } {}
    }
    ( string_free clockq )
    ? > ( string_len cerr ) 0 {
        : HttpResponse rc ( __an_json_err 400 ( string_data cerr ) )
        ( string_free cerr )
        ( imp_time_result_free tr )
        ( json_free plan )
        ( import_parse_free ip )
        ( model_free mo )
        ( store_free st )
        ( __an_gate_free gate )
        ( string_free mname )
        ^ rc
    } {}
    ( string_free cerr )

    : ImportReport rep ( model_import mo . ip rows )

    : ~ HttpResponse r ( response_status_only 500 )
    ? > ( string_len . rep err ) 0 {
        ( http_response_free r )
        = r ( __an_json_err 400 ( string_data . rep err ) )
    } {
        // The model exists now if it did not before, so the organisation
        // that imported it owns it — the same rule a streamed model follows.
        ( __an_gate_claim gate ( string_data mname ) )
        : Json o ( json_obj_new )
        ( json_obj_set o `status` ( json_str_lit `success` ) )
        ( json_obj_set o `model_name` ( json_str_lit ( string_data mname ) ) )
        ( json_obj_set o `format` ( json_str_lit ( string_data . ip format ) ) )
        ( json_obj_set o `imported` ( json_int . rep accepted ) )
        // Rows the FILE could not give up, plus rows the model could not
        // take. Two different failures, and a caller fixing a file wants
        // both counted.
        ( json_obj_set o `skipped` ( json_int + . ip skipped . rep rejected ) )
        ( json_obj_set o `data_points` ( json_int . rep stored ) )
        ( json_obj_set o `trained` ( json_bool . rep trained ) )
        ( json_obj_set o `clock` ( json_str_lit ? . mm count_clock `count` `time` ) )
        : Json tj ( json_clone plan )
        ( json_obj_set tj `stamped` ( json_int . tr stamped ) )
        ( json_obj_set tj `failed` ( json_int . tr failed ) )
        ? > ( string_len . tr first_fail ) 0 { ( json_obj_set tj `first_failure` ( json_str_lit ( string_data . tr first_fail ) ) ) } {}
        ( json_obj_set o `time` tj )
        : Json notes ( json_arr_new )
        : i pn ( vec_len [String] . ip notes )
        : ~ i k 0
        ~ < k pn {
            ?? ( vec_get [String] . ip notes k ) {
                T m → { ( json_arr_push notes ( json_str_lit ( string_data m ) ) ) }
                F _ → {}
            }
            = k + k 1
        }
        // The clock of a model with points is settled: stamps landing on
        // a count clock become ticks, unstamped rows on a time clock take
        // the clock time. Neither is an error, but both are worth a note.
        ? & . mm count_clock > . tr stamped 0 {
            ( json_arr_push notes ( json_str_lit `the model counts points: the rows' timestamps were read but not kept; every row took the next tick` ) )
        } {}
        ? & ! . mm count_clock & == . tr stamped 0 > . rep accepted 0 {
            ( json_arr_push notes ( json_str_lit `the model runs on time and the rows carry no timestamp: they were stamped with the current time` ) )
        } {}
        : i rn ( vec_len [String] . rep notes )
        = k 0
        ~ < k rn {
            ?? ( vec_get [String] . rep notes k ) {
                T m → { ( json_arr_push notes ( json_str_lit ( string_data m ) ) ) }
                F _ → {}
            }
            = k + k 1
        }
        ( json_obj_set o `notes` notes )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    }
    ( import_report_free rep )
    ( imp_time_result_free tr )
    ( json_free plan )
    ( import_parse_free ip )
    ( model_free mo )
    ( store_free st )
    ( __an_gate_free gate )
    ( string_free mname )
    ^ r
}

// ── The owner tenant's console ────────────────────────────────────────
//
// One organisation administers the service itself: which other
// organisations may use it, and — when an organisation has locked itself
// out by losing its last admin — that organisation's users. It is named in
// the configuration file and nowhere else; a tenant that could grant itself
// this from the dashboard would not be an anchor.

@ __an_gate_owner HttpRequest req → Gate {
    : Gate g ( __an_gate_auth req T )
    ? . g allowed {} { ^ g }
    : Principal me . g who
    ? ( principal_is_owner_admin me ) {} {
        ^ @ Gate { F AZ_GATE_FORBID . g who F }
    }
    ^ g
}

// GET /api/tenants — every organisation this service has ever seen, and
// what was decided about it.
@ __an_h_tenants HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : ~ Json arr ( json_arr_new )
    ?? ( az_root_open ) {
        F _ → {}
        T db → { ( json_free arr ) = arr ( az_tenants_json db ) }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `owner_tenant` ( json_str_lit ( anomaly_authz_owner_tenant ) ) )
    ( json_obj_set o `tenants` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( __an_gate_free gate )
    ^ r
}

// PUT /api/tenants/<tid>  { "state": "allowed" | "pending" | "blocked" }
@ __an_h_tenant_state HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    : ~ String tid ( string_new )
    ?? ( params_get p `tid` ) {
        T v → { ( string_free tid ) = tid v }
        F junk → { ( string_free tid ) = tid junk }
    }
    : ~ String state ( string_new )
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `state` ) {
                T sv → {
                    ? ( json_is_str sv ) {
                        ( string_free state )
                        = state ( string_from ( json_str_data sv ) )
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F → {}
    }
    : ~ b ok F
    ?? ( az_root_open ) {
        F _ → {}
        T db → {
            = ok ( az_tenant_set_state db ( string_data tid ) ( string_data state )
            ( string_data . me sub ) ( now_seconds ) )
        }
    }
    : ~ HttpResponse r ( __an_json_err 400 `state must be "allowed", "pending" or "blocked"` )
    ? ok {
        : Json o ( __an_ok_msg `Tenant updated` )
        ( json_obj_set o `tenant` ( json_str_lit ( string_data tid ) ) )
        ( json_obj_set o `state` ( json_str_lit ( string_data state ) ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( string_free state )
    ( string_free tid )
    ( __an_gate_free gate )
    ^ r
}

// GET /api/orgs — every organisation with a database, and how many members
// and models it has. The view an owner-tenant admin needs to spot one that
// has locked itself out.
@ __an_h_orgs HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Json arr ( json_arr_new )
    : ( Vec String ) orgs ( __az_org_ids )
    : i n ( vec_len [String] orgs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] orgs k ) {
            T org → {
                ?? ( az_db_open ( string_data org ) ) {
                    F _ → {}
                    T db → {
                        : ( Vec String ) ms ( az_org_model_names db )
                        : Json o ( json_obj_new )
                        ( json_obj_set o `organization` ( json_str_lit ( string_data org ) ) )
                        ( json_obj_set o `users` ( json_int ( az_user_count db ) ) )
                        ( json_obj_set o `admins` ( json_int ( az_admin_count db ) ) )
                        ( json_obj_set o `models` ( json_int ( vec_len [String] ms ) ) )
                        ( json_obj_set o `is_home` ( json_bool ( az_is_home_org ( string_data org ) ) ) )
                        ( json_arr_push arr o )
                        ( vec_free_with [String] ms \ String x → v { ( string_free x ) } )
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] orgs \ String x → v { ( string_free x ) } )
    : Json out ( json_obj_new )
    ( json_obj_set out `status` ( json_str_lit `success` ) )
    ( json_obj_set out `organizations` arr )
    : HttpResponse r ( response_json 200 out )
    ( json_free out )
    ( __an_gate_free gate )
    ^ r
}

// GET /api/orgs/<org>/users
@ __an_h_org_roster HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : ~ String org ( string_new )
    ?? ( params_get p `org` ) {
        T v → { ( string_free org ) = org v }
        F junk → { ( string_free org ) = org junk }
    }
    : ~ Json arr ( json_arr_new )
    ?? ( az_db_open ( string_data org ) ) {
        F _ → {}
        T db → { ( json_free arr ) = arr ( az_users_json db ) }
    }
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `success` ) )
    ( json_obj_set o `organization` ( json_str_lit ( string_data org ) ) )
    ( json_obj_set o `users` arr )
    : HttpResponse r ( response_json 200 o )
    ( json_free o )
    ( string_free org )
    ( __an_gate_free gate )
    ^ r
}

// PUT /api/orgs/<org>/users/<sub>/role  { "role": … }
//
// The repair for an organisation that has lost its last admin — the case
// its own members cannot fix, because promoting somebody is an admin's act
// and there is no admin left.
@ __an_h_org_promote HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : ~ String org ( string_new )
    ?? ( params_get p `org` ) {
        T v → { ( string_free org ) = org v }
        F junk → { ( string_free org ) = org junk }
    }
    : ~ String sub ( string_new )
    ?? ( params_get p `sub` ) {
        T v → { ( string_free sub ) = sub v }
        F junk → { ( string_free sub ) = sub junk }
    }
    : ~ String role ( string_new )
    ?? ( __an_body_json req ) {
        T body → {
            ?? ( json_obj_get body `role` ) {
                T rv → {
                    ? ( json_is_str rv ) {
                        ( string_free role )
                        = role ( string_from ( json_str_data rv ) )
                    } {}
                }
                F _ → {}
            }
            ( json_free body )
        }
        F → {}
    }
    : ~ b ok F
    ?? ( az_db_open ( string_data org ) ) {
        F _ → {}
        T db → { = ok ( az_user_set_role db ( string_data sub ) ( string_data role ) ) }
    }
    : ~ HttpResponse r ( __an_json_err 400 `Refused: unknown user, unknown role, or that organization's last administrator.` )
    ? ok {
        : Json o ( __an_ok_msg `Role updated` )
        ( json_obj_set o `organization` ( json_str_lit ( string_data org ) ) )
        ( json_obj_set o `subject` ( json_str_lit ( string_data sub ) ) )
        ( json_obj_set o `role` ( json_str_lit ( string_data role ) ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( string_free role )
    ( string_free sub )
    ( string_free org )
    ( __an_gate_free gate )
    ^ r
}

// ── Leaving ───────────────────────────────────────────────────────────

// Remove an organisation entirely: its models from the shared store, then
// the database that said they were its. In that order — a crash between the
// two leaves models nobody claims, which the next admin can adopt, while
// the reverse leaves a database pointing at models that are gone.
@ __an_drop_org s org → i {
    : ~ i removed 0
    ?? ( az_db_open org ) {
        F _ → {}
        T db → {
            : ( Vec String ) ms ( az_org_model_names db )
            : Store st ( store_open g_an_root )
            : i n ( vec_len [String] ms )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] ms k ) {
                    T nm → {
                        ? ( store_delete st ( string_data nm ) ) { = removed + removed 1 } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( store_free st )
            ( vec_free_with [String] ms \ String x → v { ( string_free x ) } )
        }
    }
    : b _d ( az_org_drop org )
    ^ removed
}

// DELETE /api/me — the right to be forgotten.
//
// The person's row goes, and with it the personal identifier attached to
// anything they made. What the organisation keeps is what belongs to the
// ORGANISATION: its models, and the keys that feed them. A colleague
// leaving must not stop the data arriving.
//
// Unless they were the last one. An organisation with no members has
// nobody it could belong to, so it goes — database, models and keys.
@ __an_h_forget_me HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_auth req F )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : Principal me . gate who
    // A key is the organisation's credential, not a person: it cannot ask
    // to be forgotten on that person's behalf.
    ? . me via_key {
        ( __an_gate_free gate )
        ^ ( __an_json_err 403 `An API key cannot delete the account that made it. Sign in first.` )
    } {}
    ? ( anomaly_authz_enabled ) {} {
        ( __an_gate_free gate )
        ^ ( __an_json_err 400 `There is no account to delete: this service is running without sign-in.` )
    }

    : ~ b ok F
    : ~ b org_gone F
    : ~ i models_gone 0
    ?? ( az_db_open ( string_data . me org ) ) {
        F _ → {}
        T db → {
            = ok ( az_user_delete db ( string_data . me sub ) )
            ? ok { = org_gone == ( az_user_count db ) 0 } {}
        }
    }
    // The database has to be closed before it can be deleted, which is why
    // the drop happens out here rather than inside the arm above.
    ? & ok org_gone { = models_gone ( __an_drop_org ( string_data . me org ) ) } {}

    : ~ HttpResponse r ( __an_json_err 404 `No such account.` )
    ? ok {
        : Json o ( __an_ok_msg ? org_gone
        `Account deleted. You were the last member, so the organization and its models went with it.`
        `Account deleted.` )
        ( json_obj_set o `organization_deleted` ( json_bool org_gone ) )
        ( json_obj_set o `models_deleted` ( json_int models_gone ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( __an_gate_free gate )
    ^ r
}

// DELETE /api/orgs/<org>/users/<sub> — the same, done for somebody else by
// an owner-tenant admin. The account that has to go when its person is
// gone and cannot ask.
@ __an_h_org_forget HttpRequest req Params p → HttpResponse {
    : Gate gate ( __an_gate_owner req )
    ? . gate allowed {} {
        : HttpResponse rd ( __an_gate_deny gate )
        ( __an_gate_free gate )
        ^ rd
    }
    : ~ String org ( string_new )
    ?? ( params_get p `org` ) {
        T v → { ( string_free org ) = org v }
        F junk → { ( string_free org ) = org junk }
    }
    : ~ String sub ( string_new )
    ?? ( params_get p `sub` ) {
        T v → { ( string_free sub ) = sub v }
        F junk → { ( string_free sub ) = sub junk }
    }
    : ~ b ok F
    : ~ b org_gone F
    : ~ i models_gone 0
    ?? ( az_db_open ( string_data org ) ) {
        F _ → {}
        T db → {
            = ok ( az_user_delete db ( string_data sub ) )
            ? ok { = org_gone == ( az_user_count db ) 0 } {}
        }
    }
    ? & ok org_gone { = models_gone ( __an_drop_org ( string_data org ) ) } {}
    : ~ HttpResponse r ( __an_json_err 404 `No such user in that organization.` )
    ? ok {
        : Json o ( __an_ok_msg `User deleted` )
        ( json_obj_set o `organization` ( json_str_lit ( string_data org ) ) )
        ( json_obj_set o `subject` ( json_str_lit ( string_data sub ) ) )
        ( json_obj_set o `organization_deleted` ( json_bool org_gone ) )
        ( json_obj_set o `models_deleted` ( json_int models_gone ) )
        ( http_response_free r )
        = r ( response_json 200 o )
        ( json_free o )
    } {}
    ( string_free sub )
    ( string_free org )
    ( __an_gate_free gate )
    ^ r
}

// ── Router assembly / server ──────────────────────────────────────────

@ anomaly_service_router → Router {
    : Router r ( router_new )
    // Dashboard pages (served from g_an_webroot; 404 when unset).
    ( router_get r `/` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `modelmanager.html` ) } )
    ( router_get r `/modelmanager.html` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `modelmanager.html` ) } )
    ( router_get r `/anomalies.html` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `anomalies.html` ) } )
    ( router_get r `/oauth/callback` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `oauth-callback.html` ) } )
    ( router_get r `/auth.js` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `auth.js` ) } )
    ( router_get r `/admin.html` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `admin.html` ) } )
    ( router_get r `/modeltrainer.html` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `modeltrainer.html` ) } )
    ( router_get r `/visualize.html` \ HttpRequest req Params p → HttpResponse { ^ ( __an_serve_file `visualize.html` ) } )
    ( router_post r `/detect/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_detect req p T ) } )
    ( router_post r `/detect_only/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_detect req p F ) } )
    ( router_post r `/force_train/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_force_train req p ) } )
    ( router_get r `/force_train/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_force_train req p ) } )
    ( router_post r `/detect_anomalies` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_batch req p ) } )
    ( router_get r `/models/dynamic` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_models req p ) } )
    ( router_get r `/models/dynamic/:model/metadata` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_metadata req p ) } )
    ( router_put r `/models/dynamic/:model/metadata` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_meta_update req p ) } )
    ( router_get r `/models/dynamic/:model/data` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_data req p ) } )
    ( router_get r `/models/dynamic/:model/anomalies` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_anomalies req p ) } )
    ( router_post r `/models/dynamic/:model/reset` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_reset req p ) } )
    ( router_delete r `/delete_model/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_delete req p ) } )
    ( router_get r `/delete_model/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_delete req p ) } )
    ( router_put r `/api/dynamic/:model/schedule` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_schedule req p ) } )
    ( router_post r `/api/dynamic/:model/finetune` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_finetune req p ) } )
    ( router_get r `/models/dynamic/:model/calibration` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_calibration req p ) } )
    ( router_post r `/train/autoencoder/:model` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_train_ae req p ) } )
    ( router_post r `/models/dynamic/:model/claim` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_claim req p ) } )
    ( router_post r `/models/dynamic/:model/import` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_import req p ) } )
    ( router_get r `/api/auth/config` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_auth_config req p ) } )
    ( router_get r `/api/me` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_me req p ) } )
    ( router_get r `/api/org/users` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_org_users req p ) } )
    ( router_put r `/api/org/users/:sub/role` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_org_role req p ) } )
    ( router_get r `/api/org/keys` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_keys_list req p ) } )
    ( router_post r `/api/org/keys` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_keys_create req p ) } )
    ( router_delete r `/api/org/keys/:id` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_keys_revoke req p ) } )
    ( router_delete r `/api/me` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_forget_me req p ) } )
    ( router_get r `/api/tenants` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_tenants req p ) } )
    ( router_put r `/api/tenants/:tid` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_tenant_state req p ) } )
    ( router_get r `/api/orgs` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_orgs req p ) } )
    ( router_get r `/api/orgs/:org/users` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_org_roster req p ) } )
    ( router_put r `/api/orgs/:org/users/:sub/role` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_org_promote req p ) } )
    ( router_delete r `/api/orgs/:org/users/:sub` \ HttpRequest req Params p → HttpResponse { ^ ( __an_h_org_forget req p ) } )
    ^ r
}

// Serve until the listener errors. Returns a process exit code.
// Serve the routes over the `http` package's App facade: it owns the
// bind + keep-alive loop, a graceful SIGINT/SIGTERM shutdown, and turns a
// handler panic into a 500 (rather than dropping the connection). The
// router itself is still built by anomaly_service_router, so every route
// stays drivable without a socket in the test suite.
@ anomaly_serve s host i port → i {
    : *HttpApp app ( http_app_new )
    ( http_app_use_router app ( anomaly_service_router ) )
    : i rc ( http_app_listen app host port )
    ( http_app_free app )
    ^ rc
}
