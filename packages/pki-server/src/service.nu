// pki-server/src/service.nu — HTTP routes & request handlers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `deps/http/src/http.nu`
$ `pki.nu`
$ `auth.nu`
$ `ui.nu`

// ── Service state ─────────────────────────────────────────────────────

: ~ s g_ca_cert_path `./certs/ca.crt`
: ~ s g_ca_key_path `./certs/ca.key`
: ~ s g_crl_file_path `./certs/ca.crl`
: ~ s g_index_file_path `./certs/index.txt`
: ~ s g_serial_file_path `./certs/serial`
: ~ s g_initial_certs_dir `./certs/initial`
: ~ s g_device_certs_dir `./certs/certificates`
: ~ s g_device_init_key `your-device-init-key`
: ~ s g_management_key `your-management-key-here`
: ~ s g_ca_cn `Private PKI CA`
: ~ i g_ca_handle 0

@ pki_service_init s ca_cert s ca_key s crl_file s index_file s serial_file s initial_dir s device_dir s init_key s mgmt_key s ca_cn → b {
    = g_ca_cert_path ca_cert
    = g_ca_key_path ca_key
    = g_crl_file_path crl_file
    = g_index_file_path index_file
    = g_serial_file_path serial_file
    = g_initial_certs_dir initial_dir
    = g_device_certs_dir device_dir
    = g_device_init_key init_key
    = g_management_key mgmt_key
    = g_ca_cn ca_cn

    // Ensure required directory structures exist
    : !v IoErr _d1 ( dir_create_all initial_dir )
    : !v IoErr _d2 ( dir_create_all device_dir )

    // Load or generate CA
    : *PkiCa ca ( pki_load_or_create_ca ca_cert ca_key ca_cn )
    = g_ca_handle # i ca
    ? == g_ca_handle 0 { ^ F } {}

    // Ensure CRL exists
    : String _crl ( pki_load_crl crl_file ca index_file )
    ( string_free _crl )
    ^ T
}

// ── Helper utilities ──────────────────────────────────────────────────

@ _resp_json i status String json_str → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( response_set_body_str r ( string_data json_str ) )
    ( string_free json_str )
    ^ r
}

@ _resp_err_json i status s msg → HttpResponse {
    : String j ( string_from `{"error":"` )
    ( string_push_str j msg )
    ( string_push_str j `"}` )
    ^ ( _resp_json status j )
}

@ _resp_html i status String html → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_body_str r ( string_data html ) )
    ( string_free html )
    ^ r
}

// Sanitize device ID to [a-zA-Z0-9-._] and prevent directory traversal
@ _sanitize_device_id s raw → String {
    : String s ( string_new )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        : b ok | | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122 | | == c 45 == c 95 == c 46
        ? ok { ( string_push_char s c ) } {}
        = k + k 1
    }
    // Prevent '.' or '..'
    ? | ( string_eq s ( string_from `.` ) ) ( string_eq s ( string_from `..` ) ) {
        ( string_clear s )
    } {}
    ^ s
}

// Check if request prefers JSON (via header or content-type)
@ _wants_json HttpRequest req → b {
    : ?String ct ( header_get . req headers `content-type` )
    ?? ct {
        T s_ct → {
            : b is_j ( string_contains s_ct `application/json` )
            ( string_free s_ct )
            ? is_j { ^ T } {}
        }
        F _ → {}
    }
    : ?String acc ( header_get . req headers `accept` )
    ?? acc {
        T s_acc → {
            : b is_j ( string_contains s_acc `application/json` )
            ( string_free s_acc )
            ? is_j { ^ T } {}
        }
        F _ → {}
    }
    ^ F
}

// ── Route Handlers ────────────────────────────────────────────────────

// GET /health
@ handle_health HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : String ts ( pki_iso_timestamp now )
    : String j ( string_from `{"status":"healthy","timestamp":"` )
    ( string_push_str j ( string_data ts ) )
    ( string_push_str j `"}` )
    ( string_free ts )
    ^ ( _resp_json 200 j )
}

// GET /ca-cert
@ handle_ca_cert HttpRequest req Params p → HttpResponse {
    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : Json obj ( json_obj_new )
        ( json_obj_set obj `ca_certificate` ( json_str_lit ( string_data . ca cert_pem ) ) )
        : String j ( json_stringify obj )
        ( json_free obj )
        ^ ( _resp_json 200 j )
    } {
        ^ ( _resp_err_json 500 `Failed to read CA certificate` )
    }
}

// GET /crl
@ handle_crl HttpRequest req Params p → HttpResponse {
    ? ! ( auth_check_api_key req g_management_key ) {
        : String j ( string_from `{"status":"error","message":"Invalid or missing API key"}` )
        ^ ( _resp_json 401 j )
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : String crl_pem ( pki_load_crl g_crl_file_path ca g_index_file_path )
        : HttpResponse r ( response_new 200 )
        ( response_set_header r `Content-Type` `application/pkix-crl` )
        ( response_set_header r `Content-Disposition` `attachment; filename=ca.crl` )
        ( response_set_body_str r ( string_data crl_pem ) )
        ( string_free crl_pem )
        ^ r
    } {
        ^ ( _resp_err_json 500 `Failed to load CRL` )
    }
}

// POST /init
@ handle_init HttpRequest req Params p → HttpResponse {
    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )
    ( string_free body_str )

    ?? jr {
        T jobj → {
            : ?Json dev_j ( json_obj_get jobj `device_id` )
            : ?Json key_j ( json_obj_get jobj `key` )

            : ~ String dev_id ( string_new )
            : ~ String key_val ( string_new )

            ?? dev_j { T dj → { = dev_id ( string_from ( json_as_str dj ) ) } F _ → {} }
            ?? key_j { T kj → { = key_val ( string_from ( json_as_str kj ) ) } F _ → {} }

            ( json_free jobj )

            ? | == ( string_len dev_id ) 0 == ( string_len key_val ) 0 {
                ( string_free dev_id ) ( string_free key_val )
                ^ ( _resp_err_json 400 `Missing device_id or key` )
            } {}

            ? ! ( auth_check_device_key ( string_data key_val ) g_device_init_key ) {
                ( string_free dev_id ) ( string_free key_val )
                ^ ( _resp_err_json 401 `Invalid initialization key` )
            } {}
            ( string_free key_val )

            : String clean_dev_id ( _sanitize_device_id ( string_data dev_id ) )
            ( string_free dev_id )
            ? == ( string_len clean_dev_id ) 0 {
                ( string_free clean_dev_id )
                ^ ( _resp_err_json 400 `Invalid device_id` )
            } {}

            // Check if already initialized
            : String dev_dir ( string_from g_initial_certs_dir )
            ( string_push_char dev_dir 47 )
            ( string_push_str dev_dir ( string_data clean_dev_id ) )
            ? ( file_exists ( string_data dev_dir ) ) {
                ( string_free clean_dev_id ) ( string_free dev_dir )
                ^ ( _resp_err_json 403 `Device is already initialized` )
            } {}

            // Create device directory
            : !v IoErr _cd ( dir_create_all ( string_data dev_dir ) )

            ? != g_ca_handle 0 {
                : *PkiCa ca # *PkiCa g_ca_handle
                : PkiCert cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) 365 )

                // Save certificate & key
                : String crt_path ( string_clone dev_dir )
                ( string_push_char crt_path 47 )
                ( string_push_str crt_path ( string_data clean_dev_id ) )
                ( string_push_str crt_path `.crt` )

                : String key_path ( string_clone dev_dir )
                ( string_push_char key_path 47 )
                ( string_push_str key_path ( string_data clean_dev_id ) )
                ( string_push_str key_path `.key` )

                : !v IoErr _w1 ( write_file ( string_data crt_path ) ( string_data . cert cert_pem ) )
                : !v IoErr _w2 ( write_file ( string_data key_path ) ( string_data . cert key_pem ) )

                ( string_free crt_path )
                ( string_free key_path )
                ( string_free dev_dir )
                ( string_free clean_dev_id )

                : Json res ( json_obj_new )
                ( json_obj_set res `certificate` ( json_str_lit ( string_data . cert cert_pem ) ) )
                : String jout ( json_stringify res )
                ( json_free res )
                ( pki_cert_free cert )

                ^ ( _resp_json 200 jout )
            } {
                ( string_free dev_dir ) ( string_free clean_dev_id )
                ^ ( _resp_err_json 500 `CA not available` )
            }
        }
        F _ → {
            ^ ( _resp_err_json 400 `Malformed JSON body` )
        }
    }
}

// POST /renew_initial_cert
@ handle_renew_initial_cert HttpRequest req Params p → HttpResponse {
    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )
    ( string_free body_str )

    ?? jr {
        T jobj → {
            : ?Json dev_j ( json_obj_get jobj `device_id` )
            : ?Json key_j ( json_obj_get jobj `key` )
            : ?Json cert_j ( json_obj_get jobj `initial_cert` )

            : ~ String dev_id ( string_new )
            : ~ String key_val ( string_new )
            : ~ String submitted_cert ( string_new )

            ?? dev_j { T dj → { = dev_id ( string_from ( json_as_str dj ) ) } F _ → {} }
            ?? key_j { T kj → { = key_val ( string_from ( json_as_str kj ) ) } F _ → {} }
            ?? cert_j { T cj → { = submitted_cert ( string_from ( json_as_str cj ) ) } F _ → {} }

            ( json_free jobj )

            ? | | == ( string_len dev_id ) 0 == ( string_len key_val ) 0 == ( string_len submitted_cert ) 0 {
                ( string_free dev_id ) ( string_free key_val ) ( string_free submitted_cert )
                ^ ( _resp_err_json 400 `Missing device_id, key or initial_cert` )
            } {}

            ? ! ( auth_check_device_key ( string_data key_val ) g_device_init_key ) {
                ( string_free dev_id ) ( string_free key_val ) ( string_free submitted_cert )
                ^ ( _resp_err_json 401 `Invalid initialization key` )
            } {}
            ( string_free key_val )

            : String clean_dev_id ( _sanitize_device_id ( string_data dev_id ) )
            ( string_free dev_id )
            ? == ( string_len clean_dev_id ) 0 {
                ( string_free clean_dev_id ) ( string_free submitted_cert )
                ^ ( _resp_err_json 400 `Invalid device_id` )
            } {}

            // Check if device initialized
            : String crt_path ( string_from g_initial_certs_dir )
            ( string_push_char crt_path 47 )
            ( string_push_str crt_path ( string_data clean_dev_id ) )
            ( string_push_char crt_path 47 )
            ( string_push_str crt_path ( string_data clean_dev_id ) )
            ( string_push_str crt_path `.crt` )

            ? ! ( file_exists ( string_data crt_path ) ) {
                ( string_free crt_path ) ( string_free clean_dev_id ) ( string_free submitted_cert )
                ^ ( _resp_err_json 404 `Device is not initialized` )
            } {}

            // Read stored certificate
            : !String IoErr stored_r ( read_file ( string_data crt_path ) )
            : ~ String stored_cert ( string_new )
            ?? stored_r {
                T s → { = stored_cert s }
                F _ → {
                    ( string_free crt_path ) ( string_free clean_dev_id ) ( string_free submitted_cert )
                    ^ ( _resp_err_json 404 `Initial certificate not found` )
                }
            }

            // Compare certificates
            : !( Vec u ) ParseErr sub_der_r ( pem_to_der ( string_data submitted_cert ) )
            : !( Vec u ) ParseErr sto_der_r ( pem_to_der ( string_data stored_cert ) )
            ( string_free stored_cert )
            ( string_free submitted_cert )

            : ~ b der_match F
            ?? sub_der_r {
                T sub_der → {
                    ?? sto_der_r {
                        T sto_der → {
                            ? == 0 ( nurl_memcmp_lex # s ( vec_data [u] sub_der ) ( vec_len [u] sub_der ) # s ( vec_data [u] sto_der ) ( vec_len [u] sto_der ) ) {
                                = der_match T
                            } {}
                            ( vec_free [u] sto_der )
                        }
                        F _ → {}
                    }
                    ( vec_free [u] sub_der )
                }
                F _ → {}
            }

            ? ! der_match {
                ( string_free crt_path ) ( string_free clean_dev_id )
                ^ ( _resp_err_json 401 `Invalid initial certificate` )
            } {}

            // Generate renewed certificate
            ? != g_ca_handle 0 {
                : *PkiCa ca # *PkiCa g_ca_handle
                : PkiCert cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) 365 )

                : String key_path ( string_from g_initial_certs_dir )
                ( string_push_char key_path 47 )
                ( string_push_str key_path ( string_data clean_dev_id ) )
                ( string_push_char key_path 47 )
                ( string_push_str key_path ( string_data clean_dev_id ) )
                ( string_push_str key_path `.key` )

                : !v IoErr _w1 ( write_file ( string_data crt_path ) ( string_data . cert cert_pem ) )
                : !v IoErr _w2 ( write_file ( string_data key_path ) ( string_data . cert key_pem ) )

                ( string_free crt_path )
                ( string_free key_path )
                ( string_free clean_dev_id )

                : Json res ( json_obj_new )
                ( json_obj_set res `certificate` ( json_str_lit ( string_data . cert cert_pem ) ) )
                : String jout ( json_stringify res )
                ( json_free res )
                ( pki_cert_free cert )

                ^ ( _resp_json 200 jout )
            } {
                ( string_free crt_path ) ( string_free clean_dev_id )
                ^ ( _resp_err_json 500 `CA not available` )
            }
        }
        F _ → {
            ^ ( _resp_err_json 400 `Malformed JSON body` )
        }
    }
}

// GET /request-cert
@ handle_request_cert_get HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_request_cert `` ) )
}

// POST /request-cert
@ handle_request_cert_post HttpRequest req Params p → HttpResponse {
    : b is_json ( _wants_json req )

    : ~ String dev_id ( string_new )
    : ~ String initial_cert ( string_new )
    : ~ i validity_days 365

    // Try parsing as JSON first
    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )

    ?? jr {
        T jobj → {
            : ?Json dev_j ( json_obj_get jobj `device_id` )
            : ?Json cert_j ( json_obj_get jobj `initial_cert` )
            : ?Json val_j ( json_obj_get jobj `validity_days` )

            ?? dev_j { T dj → { = dev_id ( string_from ( json_as_str dj ) ) } F _ → {} }
            ?? cert_j { T cj → { = initial_cert ( string_from ( json_as_str cj ) ) } F _ → {} }
            ?? val_j { T vj → { : i v ( json_as_int vj ) ? > v 0 { = validity_days v } {} } F _ → {} }
            ( json_free jobj )
        }
        F _ → {
            // Try url-encoded form body
            : ( Vec QueryPair ) qpairs ( parse_query ( string_data body_str ) )
            : i nq ( vec_len [QueryPair] qpairs )
            : ~ i k 0
            ~ < k nq {
                : ?QueryPair po ( vec_get [QueryPair] qpairs k )
                ?? po {
                    T pr → {
                        ? ( string_eq . pr key ( string_from `device_id` ) ) {
                            = dev_id ( string_clone . pr value )
                        } {}
                        ? ( string_eq . pr key ( string_from `initial_cert` ) ) {
                            = initial_cert ( string_clone . pr value )
                        } {}
                        ? ( string_eq . pr key ( string_from `validity_days` ) ) {
                            ?? ( string_to_int . pr value ) {
                                T v → { ? > v 0 { = validity_days v } {} }
                                F _ → {}
                            }
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( query_pairs_free qpairs )
        }
    }
    ( string_free body_str )

    ? | == ( string_len dev_id ) 0 == ( string_len initial_cert ) 0 {
        ( string_free dev_id ) ( string_free initial_cert )
        ? is_json {
            ^ ( _resp_err_json 400 `Missing device_id or initial_cert` )
        } {
            ^ ( _resp_html 400 ( ui_render_request_cert `Missing device_id or initial_cert` ) )
        }
    } {}

    : String clean_dev_id ( _sanitize_device_id ( string_data dev_id ) )
    ( string_free dev_id )
    ? == ( string_len clean_dev_id ) 0 {
        ( string_free clean_dev_id ) ( string_free initial_cert )
        ? is_json {
            ^ ( _resp_err_json 400 `Invalid device ID` )
        } {
            ^ ( _resp_html 400 ( ui_render_request_cert `Invalid device ID` ) )
        }
    } {}

    // Check if device is initialized
    : String initial_crt_path ( string_from g_initial_certs_dir )
    ( string_push_char initial_crt_path 47 )
    ( string_push_str initial_crt_path ( string_data clean_dev_id ) )
    ( string_push_char initial_crt_path 47 )
    ( string_push_str initial_crt_path ( string_data clean_dev_id ) )
    ( string_push_str initial_crt_path `.crt` )

    ? ! ( file_exists ( string_data initial_crt_path ) ) {
        ( string_free initial_crt_path ) ( string_free clean_dev_id ) ( string_free initial_cert )
        ? is_json {
            ^ ( _resp_err_json 401 `Device not initialized` )
        } {
            ^ ( _resp_html 401 ( ui_render_request_cert `Device not initialized` ) )
        }
    } {}

    // Read stored initial cert
    : !String IoErr stored_r ( read_file ( string_data initial_crt_path ) )
    : ~ String stored_cert ( string_new )
    ?? stored_r {
        T s → { = stored_cert s }
        F _ → {
            ( string_free initial_crt_path ) ( string_free clean_dev_id ) ( string_free initial_cert )
            ? is_json {
                ^ ( _resp_err_json 500 `Error reading stored initial certificate` )
            } {
                ^ ( _resp_html 500 ( ui_render_request_cert `Error reading stored initial certificate` ) )
            }
        }
    }
    ( string_free initial_crt_path )

    // Check stored cert vs submitted cert DER
    : !( Vec u ) ParseErr sub_der_r ( pem_to_der ( string_data initial_cert ) )
    : !( Vec u ) ParseErr sto_der_r ( pem_to_der ( string_data stored_cert ) )
    ( string_free stored_cert )

    : ~ b der_match F
    ?? sub_der_r {
        T sub_der → {
            ?? sto_der_r {
                T sto_der → {
                    ? == 0 ( nurl_memcmp_lex # s ( vec_data [u] sub_der ) ( vec_len [u] sub_der ) # s ( vec_data [u] sto_der ) ( vec_len [u] sto_der ) ) {
                        = der_match T
                    } {}
                    ( vec_free [u] sto_der )
                }
                F _ → {}
            }
            ( vec_free [u] sub_der )
        }
        F _ → {}
    }

    ? ! der_match {
        ( string_free clean_dev_id ) ( string_free initial_cert )
        ? is_json {
            ^ ( _resp_err_json 401 `Initial certificate does not match stored certificate` )
        } {
            ^ ( _resp_html 401 ( ui_render_request_cert `Initial certificate does not match stored certificate` ) )
        }
    } {}

    // Cryptographically validate initial cert against CA
    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : b cert_valid ( pki_verify_cert . ca pubkey ( string_data initial_cert ) ( string_data clean_dev_id ) )
        ( string_free initial_cert )

        ? ! cert_valid {
            ( string_free clean_dev_id )
            ? is_json {
                ^ ( _resp_err_json 401 `Invalid initial certificate` )
            } {
                ^ ( _resp_html 401 ( ui_render_request_cert `Invalid initial certificate` ) )
            }
        } {}

        // Issue operational certificate
        : PkiCert op_cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) validity_days )

        // Save to device cert directory
        : String dev_out_dir ( string_from g_device_certs_dir )
        ( string_push_char dev_out_dir 47 )
        ( string_push_str dev_out_dir ( string_data clean_dev_id ) )
        : !v IoErr _md ( dir_create_all ( string_data dev_out_dir ) )

        : String crt_file ( string_clone dev_out_dir )
        ( string_push_char crt_file 47 )
        ( string_push_str crt_file ( string_data clean_dev_id ) )
        ( string_push_str crt_file `.crt` )

        : String key_file ( string_clone dev_out_dir )
        ( string_push_char key_file 47 )
        ( string_push_str key_file ( string_data clean_dev_id ) )
        ( string_push_str key_file `.key` )

        : !v IoErr _w1 ( write_file ( string_data crt_file ) ( string_data . op_cert cert_pem ) )
        : !v IoErr _w2 ( write_file ( string_data key_file ) ( string_data . op_cert key_pem ) )

        ( string_free dev_out_dir )
        ( string_free crt_file )
        ( string_free key_file )

        ? is_json {
            : Json res ( json_obj_new )
            ( json_obj_set res `device_id` ( json_str_lit ( string_data clean_dev_id ) ) )
            ( json_obj_set res `certificate` ( json_str_lit ( string_data . op_cert cert_pem ) ) )
            ( json_obj_set res `private_key` ( json_str_lit ( string_data . op_cert key_pem ) ) )
            ( json_obj_set res `ca_certificate` ( json_str_lit ( string_data . ca cert_pem ) ) )
            ( json_obj_set res `expires` ( json_str_lit ( string_data . op_cert expires_iso ) ) )

            ( string_free clean_dev_id )
            : String jout ( json_stringify res )
            ( json_free res )
            ( pki_cert_free op_cert )

            ^ ( _resp_json 200 jout )
        } {
            : String html ( ui_render_cert_result ( string_data clean_dev_id ) ( string_data . op_cert cert_pem ) ( string_data . op_cert key_pem ) ( string_data . ca cert_pem ) ( string_data . op_cert expires_iso ) )
            ( string_free clean_dev_id )
            ( pki_cert_free op_cert )
            ^ ( _resp_html 200 html )
        }
    } {
        ( string_free clean_dev_id ) ( string_free initial_cert )
        ^ ( _resp_err_json 500 `CA not available` )
    }
}

// GET /revoke
@ handle_revoke_get HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_revoke_cert `` ) )
}

// POST /revoke
@ handle_revoke_post HttpRequest req Params p → HttpResponse {
    : b is_json ( _wants_json req )

    : ~ String serial_input ( string_new )
    : ~ String cert_input ( string_new )
    : ~ String form_api_key ( string_new )

    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )

    ?? jr {
        T jobj → {
            : ?Json ser_j ( json_obj_get jobj `serial` )
            : ?Json crt_j ( json_obj_get jobj `certificate` )
            : ?Json key_j ( json_obj_get jobj `api_key` )

            ?? ser_j { T sj → { = serial_input ( string_from ( json_as_str sj ) ) } F _ → {} }
            ?? crt_j { T cj → { = cert_input ( string_from ( json_as_str cj ) ) } F _ → {} }
            ?? key_j { T kj → { = form_api_key ( string_from ( json_as_str kj ) ) } F _ → {} }
            ( json_free jobj )
        }
        F _ → {
            : ( Vec QueryPair ) qpairs ( parse_query ( string_data body_str ) )
            : i nq ( vec_len [QueryPair] qpairs )
            : ~ i k 0
            ~ < k nq {
                : ?QueryPair po ( vec_get [QueryPair] qpairs k )
                ?? po {
                    T pr → {
                        ? ( string_eq . pr key ( string_from `serial` ) ) {
                            = serial_input ( string_clone . pr value )
                        } {}
                        ? ( string_eq . pr key ( string_from `certificate` ) ) {
                            = cert_input ( string_clone . pr value )
                        } {}
                        ? ( string_eq . pr key ( string_from `api_key` ) ) {
                            = form_api_key ( string_clone . pr value )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( query_pairs_free qpairs )
        }
    }
    ( string_free body_str )

    // Authentication check
    : ~ b auth_ok ( auth_check_api_key req g_management_key )
    ? & ! auth_ok > ( string_len form_api_key ) 0 {
        ? ( string_eq form_api_key ( string_from g_management_key ) ) {
            = auth_ok T
        } {}
    } {}
    ( string_free form_api_key )

    ? ! auth_ok {
        ( string_free serial_input ) ( string_free cert_input )
        ? is_json {
            : String j ( string_from `{"status":"error","message":"Invalid or missing API key"}` )
            ^ ( _resp_json 401 j )
        } {
            ^ ( _resp_html 401 ( ui_render_revoke_cert `Invalid or missing Management API key` ) )
        }
    } {}

    ? & == ( string_len serial_input ) 0 == ( string_len cert_input ) 0 {
        ( string_free serial_input ) ( string_free cert_input )
        ? is_json {
            ^ ( _resp_err_json 400 `Missing serial or certificate` )
        } {
            ^ ( _resp_html 400 ( ui_render_revoke_cert `Missing serial or certificate` ) )
        }
    } {}

    : ~ String final_serial ( string_new )
    : ~ String final_cn ( string_new )

    ? > ( string_len cert_input ) 0 {
        : PkiCertInfo cinfo ( pki_extract_cert_info ( string_data cert_input ) )
        ? . cinfo ok {
            = final_serial ( string_clone . cinfo serial_hex )
            = final_cn ( string_clone . cinfo cn )
        } {}
        ( pki_cert_info_free cinfo )
    } {}
    ( string_free cert_input )

    ? & == ( string_len final_serial ) 0 > ( string_len serial_input ) 0 {
        = final_serial ( string_clone serial_input )
    } {}
    ( string_free serial_input )

    ? == ( string_len final_serial ) 0 {
        ( string_free final_serial ) ( string_free final_cn )
        ? is_json {
            ^ ( _resp_err_json 400 `Could not extract serial from certificate` )
        } {
            ^ ( _resp_html 400 ( ui_render_revoke_cert `Could not extract serial from certificate` ) )
        }
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle

        // Invalidate initial cert if CN is known
        ? > ( string_len final_cn ) 0 {
            : b _inv ( pki_invalidate_initial_cert g_initial_certs_dir ( string_data final_cn ) )
        } {}

        // Record revocation & generate new CRL
        : String updated_crl ( pki_record_revocation g_index_file_path g_crl_file_path ca ( string_data final_serial ) ( string_data final_cn ) )
        ( string_free final_cn )

        : i now ( now_seconds )
        : String now_iso ( pki_iso_timestamp now )
        : String msg ( string_from `Certificate with serial ` )
        ( string_push_str msg ( string_data final_serial ) )
        ( string_push_str msg ` has been revoked` )

        ? is_json {
            : Json res ( json_obj_new )
            ( json_obj_set res `status` ( json_str_lit `success` ) )
            ( json_obj_set res `message` ( json_str_lit ( string_data msg ) ) )
            ( json_obj_set res `serial` ( json_str_lit ( string_data final_serial ) ) )
            ( json_obj_set res `revocation_time` ( json_str_lit ( string_data now_iso ) ) )
            ( json_obj_set res `crl` ( json_str_lit ( string_data updated_crl ) ) )

            ( string_free msg )
            ( string_free now_iso )
            ( string_free final_serial )
            ( string_free updated_crl )

            : String jout ( json_stringify res )
            ( json_free res )
            ^ ( _resp_json 200 jout )
        } {
            : String html ( ui_render_revoke_result ( string_data msg ) ( string_data final_serial ) ( string_data now_iso ) ( string_data updated_crl ) )
            ( string_free msg )
            ( string_free now_iso )
            ( string_free final_serial )
            ( string_free updated_crl )
            ^ ( _resp_html 200 html )
        }
    } {
        ( string_free final_serial ) ( string_free final_cn )
        ^ ( _resp_err_json 500 `CA not available` )
    }
}

// GET /
@ handle_index HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_index ) )
}

// GET /api
@ handle_api_docs HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_api_docs ) )
}

// GET /css/style.css
@ handle_style_css HttpRequest req Params p → HttpResponse {
    : String css_path ( string_from `./static/css/style.css` )
    ? ( file_exists ( string_data css_path ) ) {
        : !String IoErr r ( read_file ( string_data css_path ) )
        ( string_free css_path )
        ?? r {
            T content → {
                : HttpResponse resp ( response_new 200 )
                ( response_set_header resp `Content-Type` `text/css; charset=utf-8` )
                ( response_set_body_str resp ( string_data content ) )
                ( string_free content )
                ^ resp
            }
            F _ → {}
        }
    } {
        ( string_free css_path )
    }
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `text/css; charset=utf-8` )
    : String def_css ( ui_default_css )
    ( response_set_body_str resp ( string_data def_css ) )
    ( string_free def_css )
    ^ resp
}

// GET /favicon.ico
@ handle_favicon HttpRequest req Params p → HttpResponse {
    : HttpResponse resp ( response_new 204 )
    ^ resp
}

// ── App Setup ─────────────────────────────────────────────────────────

@ pki_build_app → *HttpApp {
    : *HttpApp a ( http_app_new )
    ( http_app_workers a 8 )
    ( http_app_cors a )
    ( http_app_logging a )

    ( http_app_get a `/health` \ HttpRequest req Params p → HttpResponse { ^ ( handle_health req p ) } )
    ( http_app_get a `/ca-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_ca_cert req p ) } )
    ( http_app_get a `/crl` \ HttpRequest req Params p → HttpResponse { ^ ( handle_crl req p ) } )

    ( http_app_post a `/init` \ HttpRequest req Params p → HttpResponse { ^ ( handle_init req p ) } )
    ( http_app_post a `/renew_initial_cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_renew_initial_cert req p ) } )

    ( http_app_get a `/request-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_request_cert_get req p ) } )
    ( http_app_post a `/request-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_request_cert_post req p ) } )

    ( http_app_get a `/revoke` \ HttpRequest req Params p → HttpResponse { ^ ( handle_revoke_get req p ) } )
    ( http_app_post a `/revoke` \ HttpRequest req Params p → HttpResponse { ^ ( handle_revoke_post req p ) } )

    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse { ^ ( handle_index req p ) } )
    ( http_app_get a `/api` \ HttpRequest req Params p → HttpResponse { ^ ( handle_api_docs req p ) } )
    ( http_app_get a `/css/style.css` \ HttpRequest req Params p → HttpResponse { ^ ( handle_style_css req p ) } )
    ( http_app_get a `/favicon.ico` \ HttpRequest req Params p → HttpResponse { ^ ( handle_favicon req p ) } )

    ( http_app_static_dir a `./static` )

    ^ a
}
