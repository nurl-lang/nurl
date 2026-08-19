// pki-server/src/service.nu — HTTP routes & request handlers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/x509.nu`
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
: ~ s g_initial_certs_dir `./certs/initial`
: ~ s g_device_certs_dir `./certs/certificates`
: ~ s g_device_init_key ``
: ~ s g_management_key ``
: ~ s g_ca_cn `Private PKI CA`
: ~ i g_ca_alg 0
: ~ i g_ca_handle 0

@ pki_service_init s ca_cert s ca_key s crl_file s index_file s initial_dir s device_dir s init_key s mgmt_key s ca_cn i alg → b {
    = g_ca_cert_path ca_cert
    = g_ca_key_path ca_key
    = g_crl_file_path crl_file
    = g_index_file_path index_file
    = g_initial_certs_dir initial_dir
    = g_device_certs_dir device_dir
    = g_device_init_key init_key
    = g_management_key mgmt_key
    = g_ca_cn ca_cn

    // Ensure required directory structures exist
    : !v IoErr _d1 ( dir_create_all initial_dir )
    : !v IoErr _d2 ( dir_create_all device_dir )

    // Load or generate CA
    : *PkiCa ca ( pki_load_or_create_ca ca_cert ca_key ca_cn alg )
    = g_ca_handle # i ca
    ? == g_ca_handle 0 { ^ F } {}
    // An existing CA keeps its own algorithm; --algorithm only decides
    // what a *new* CA is minted with, so report back what is actually
    // in force rather than what was asked for.
    = g_ca_alg . ca alg

    // Ensure CRL exists
    : String _crl ( pki_load_crl crl_file ca index_file )
    ( string_free _crl )
    ^ T
}

@ pki_service_alg → i { ^ g_ca_alg }

// ── Helper utilities ──────────────────────────────────────────────────

@ _resp_json i status String json_str → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `application/json; charset=utf-8` )
    ( response_set_header r `X-Content-Type-Options` `nosniff` )
    ( response_set_header r `Cache-Control` `no-store` )
    ( response_set_body_str r ( string_data json_str ) )
    ( string_free json_str )
    ^ r
}

@ _resp_err_json i status s msg → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o `error` ( json_str_lit msg ) )
    : String j ( json_stringify o )
    ( json_free o )
    ^ ( _resp_json status j )
}

// HTML responses carry the policy that makes the escaping in ui.nu a
// belt-and-braces measure rather than the only one: no inline script
// may run, nothing may be loaded cross-origin, and the page may not be
// framed. The UI's one script lives at /js/app.js precisely so
// `script-src 'self'` can hold.
@ _resp_html i status String html → HttpResponse {
    : HttpResponse r ( response_new status )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_header r `Content-Security-Policy` `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'` )
    ( response_set_header r `X-Content-Type-Options` `nosniff` )
    ( response_set_header r `Referrer-Policy` `no-referrer` )
    ( response_set_header r `Cache-Control` `no-store` )
    ( response_set_body_str r ( string_data html ) )
    ( string_free html )
    ^ r
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

// `<dir>/<id>/<id>.<ext>` — the one shape this service builds. `id`
// must already be sanitised.
@ _device_path s dir s id s ext → String {
    : String p ( string_from dir )
    ( string_push_char p 47 )
    ( string_push_str p id )
    ( string_push_char p 47 )
    ( string_push_str p id )
    ( string_push_str p ext )
    ^ p
}

// Pull a field out of an application/x-www-form-urlencoded body.
@ _form_get ( Vec QueryPair ) pairs s name → String {
    : ~ String out ( string_new )
    : i n ( vec_len [QueryPair] pairs )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [QueryPair] pairs k ) {
            T pr → {
                ? == 0 ( nurl_str_cmp ( string_data . pr key ) name ) {
                    ( string_free out )
                    = out ( string_clone . pr value )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

@ _json_str_field Json obj s name → String {
    ?? ( json_obj_get obj name ) {
        T v → { ^ ( string_from ( json_as_str v ) ) }
        F _ → { ^ ( string_new ) }
    }
}

// ── Route Handlers ────────────────────────────────────────────────────

// GET /health
@ handle_health HttpRequest req Params p → HttpResponse {
    : i now ( now_seconds )
    : String ts ( pki_iso_timestamp now )
    : Json o ( json_obj_new )
    ( json_obj_set o `status` ( json_str_lit `healthy` ) )
    ( json_obj_set o `timestamp` ( json_str_lit ( string_data ts ) ) )
    ( json_obj_set o `algorithm` ( json_str_lit ( pki_alg_name g_ca_alg ) ) )
    ( json_obj_set o `post_quantum` ( json_bool ( pki_alg_is_pq g_ca_alg ) ) )
    ( string_free ts )
    : String j ( json_stringify o )
    ( json_free o )
    ^ ( _resp_json 200 j )
}

// GET /ca-cert
@ handle_ca_cert HttpRequest req Params p → HttpResponse {
    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : Json obj ( json_obj_new )
        ( json_obj_set obj `ca_certificate` ( json_str_lit ( string_data . ca cert_pem ) ) )
        ( json_obj_set obj `algorithm` ( json_str_lit ( pki_alg_name . ca alg ) ) )
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
        ^ ( _resp_err_json 401 `Invalid or missing API key` )
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : String crl_pem ( pki_load_crl g_crl_file_path ca g_index_file_path )
        : HttpResponse r ( response_new 200 )
        ( response_set_header r `Content-Type` `application/pkix-crl` )
        ( response_set_header r `Content-Disposition` `attachment; filename=ca.crl` )
        ( response_set_header r `X-Content-Type-Options` `nosniff` )
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
            : String dev_id ( _json_str_field jobj `device_id` )
            : String key_val ( _json_str_field jobj `key` )
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

            : String clean_dev_id ( pki_sanitize_id ( string_data dev_id ) )
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

            : !v IoErr _cd ( dir_create_all ( string_data dev_dir ) )
            ( string_free dev_dir )

            ? != g_ca_handle 0 {
                : *PkiCa ca # *PkiCa g_ca_handle
                : PkiCert cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) 365 )

                : String crt_path ( _device_path g_initial_certs_dir ( string_data clean_dev_id ) `.crt` )
                : String key_path ( _device_path g_initial_certs_dir ( string_data clean_dev_id ) `.key` )
                : !v IoErr _w1 ( write_file ( string_data crt_path ) ( string_data . cert cert_pem ) )
                : !v IoErr _w2 ( write_file ( string_data key_path ) ( string_data . cert key_pem ) )
                : !v IoErr _cm ( set_permissions ( string_data key_path ) 384 )

                ( string_free crt_path )
                ( string_free key_path )
                ( string_free clean_dev_id )

                : Json res ( json_obj_new )
                ( json_obj_set res `certificate` ( json_str_lit ( string_data . cert cert_pem ) ) )
                ( json_obj_set res `private_key` ( json_str_lit ( string_data . cert key_pem ) ) )
                ( json_obj_set res `serial` ( json_str_lit ( string_data . cert serial_hex ) ) )
                : String jout ( json_stringify res )
                ( json_free res )
                ( pki_cert_free cert )

                ^ ( _resp_json 200 jout )
            } {
                ( string_free clean_dev_id )
                ^ ( _resp_err_json 500 `CA not available` )
            }
        }
        F _ → {
            ^ ( _resp_err_json 400 `Malformed JSON body` )
        }
    }
}

// Compare a submitted PEM with the enrollment certificate on disk. Both
// are normalised to DER first, so re-wrapped armor or line endings do
// not change the answer.
@ _initial_cert_matches s stored_path s submitted_pem → b {
    : !String IoErr stored_r ( read_file stored_path )
    : ~ b ok F
    ?? stored_r {
        T stored → {
            // Both results are unwrapped to a (possibly empty) Vec of
            // their own before either is examined. Nesting the second
            // match inside the first arm leaks the stored DER on every
            // request whose submitted PEM does not parse — which is
            // every attacker probe.
            : !( Vec u ) ParseErr sub_r ( pem_to_der submitted_pem )
            : !( Vec u ) ParseErr sto_r ( pem_to_der ( string_data stored ) )
            : ( Vec u ) sub ?? sub_r { T v → v F _ → ( vec_new [u] ) }
            : ( Vec u ) sto ?? sto_r { T v → v F _ → ( vec_new [u] ) }
            ? & > ( vec_len [u] sub ) 0 ( bytes_eq sub sto ) { = ok T } {}
            ( vec_free [u] sub )
            ( vec_free [u] sto )
            ( string_free stored )
        }
        F _ → {}
    }
    ^ ok
}

// Has this device's current enrollment certificate been revoked? The
// serial is read back out of the stored certificate and checked against
// index.txt, so revoking by serial alone — with no CN to invalidate a
// file by — still locks the device out.
@ _initial_cert_revoked s stored_path → b {
    : !String IoErr r ( read_file stored_path )
    : ~ b revoked F
    ?? r {
        T stored → {
            : PkiCertInfo info ( pki_extract_cert_info ( string_data stored ) )
            ? . info ok {
                = revoked ( pki_is_revoked g_index_file_path ( string_data . info serial_hex ) )
            } {}
            ( pki_cert_info_free info )
            ( string_free stored )
        }
        F _ → {}
    }
    ^ revoked
}

// POST /renew_initial_cert
@ handle_renew_initial_cert HttpRequest req Params p → HttpResponse {
    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )
    ( string_free body_str )

    ?? jr {
        T jobj → {
            : String dev_id ( _json_str_field jobj `device_id` )
            : String key_val ( _json_str_field jobj `key` )
            : String submitted_cert ( _json_str_field jobj `initial_cert` )
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

            : String clean_dev_id ( pki_sanitize_id ( string_data dev_id ) )
            ( string_free dev_id )
            ? == ( string_len clean_dev_id ) 0 {
                ( string_free clean_dev_id ) ( string_free submitted_cert )
                ^ ( _resp_err_json 400 `Invalid device_id` )
            } {}

            : String crt_path ( _device_path g_initial_certs_dir ( string_data clean_dev_id ) `.crt` )
            ? ! ( file_exists ( string_data crt_path ) ) {
                ( string_free crt_path ) ( string_free clean_dev_id ) ( string_free submitted_cert )
                ^ ( _resp_err_json 404 `Device is not initialized` )
            } {}

            ? ( _initial_cert_revoked ( string_data crt_path ) ) {
                ( string_free crt_path ) ( string_free clean_dev_id ) ( string_free submitted_cert )
                ^ ( _resp_err_json 403 `Enrollment certificate has been revoked` )
            } {}

            : b matched ( _initial_cert_matches ( string_data crt_path ) ( string_data submitted_cert ) )
            ( string_free submitted_cert )
            ? ! matched {
                ( string_free crt_path ) ( string_free clean_dev_id )
                ^ ( _resp_err_json 401 `Invalid initial certificate` )
            } {}

            ? != g_ca_handle 0 {
                : *PkiCa ca # *PkiCa g_ca_handle
                : PkiCert cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) 365 )

                : String key_path ( _device_path g_initial_certs_dir ( string_data clean_dev_id ) `.key` )
                : !v IoErr _w1 ( write_file ( string_data crt_path ) ( string_data . cert cert_pem ) )
                : !v IoErr _w2 ( write_file ( string_data key_path ) ( string_data . cert key_pem ) )
                : !v IoErr _cm ( set_permissions ( string_data key_path ) 384 )

                ( string_free crt_path )
                ( string_free key_path )
                ( string_free clean_dev_id )

                : Json res ( json_obj_new )
                ( json_obj_set res `certificate` ( json_str_lit ( string_data . cert cert_pem ) ) )
                ( json_obj_set res `private_key` ( json_str_lit ( string_data . cert key_pem ) ) )
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

@ _cert_error b is_json i status s msg → HttpResponse {
    ? is_json { ^ ( _resp_err_json status msg ) } {}
    ^ ( _resp_html status ( ui_render_request_cert msg ) )
}

// POST /request-cert
@ handle_request_cert_post HttpRequest req Params p → HttpResponse {
    : b is_json ( _wants_json req )

    : ~ String dev_id ( string_new )
    : ~ String initial_cert ( string_new )
    : ~ i validity_days 365

    : String body_str ( bytes_to_str . req body )
    : !Json JsonError jr ( json_parse ( string_data body_str ) )

    ?? jr {
        T jobj → {
            ( string_free dev_id )
            = dev_id ( _json_str_field jobj `device_id` )
            ( string_free initial_cert )
            = initial_cert ( _json_str_field jobj `initial_cert` )
            ?? ( json_obj_get jobj `validity_days` ) {
                T vj → { : i v ( json_as_int vj ) ? > v 0 { = validity_days v } {} }
                F _ → {}
            }
            ( json_free jobj )
        }
        F _ → {
            : ( Vec QueryPair ) qpairs ( parse_query ( string_data body_str ) )
            ( string_free dev_id )
            = dev_id ( _form_get qpairs `device_id` )
            ( string_free initial_cert )
            = initial_cert ( _form_get qpairs `initial_cert` )
            : String vd ( _form_get qpairs `validity_days` )
            ?? ( string_to_int vd ) {
                T v → { ? > v 0 { = validity_days v } {} }
                F _ → {}
            }
            ( string_free vd )
            ( query_pairs_free qpairs )
        }
    }
    ( string_free body_str )

    // A certificate outliving its CA, or issued for a century, is a
    // liability rather than a convenience.
    ? > validity_days 3650 { = validity_days 3650 } {}

    ? | == ( string_len dev_id ) 0 == ( string_len initial_cert ) 0 {
        ( string_free dev_id ) ( string_free initial_cert )
        ^ ( _cert_error is_json 400 `Missing device_id or initial_cert` )
    } {}

    : String clean_dev_id ( pki_sanitize_id ( string_data dev_id ) )
    ( string_free dev_id )
    ? == ( string_len clean_dev_id ) 0 {
        ( string_free clean_dev_id ) ( string_free initial_cert )
        ^ ( _cert_error is_json 400 `Invalid device ID` )
    } {}

    : String initial_crt_path ( _device_path g_initial_certs_dir ( string_data clean_dev_id ) `.crt` )
    ? ! ( file_exists ( string_data initial_crt_path ) ) {
        ( string_free initial_crt_path ) ( string_free clean_dev_id ) ( string_free initial_cert )
        ^ ( _cert_error is_json 401 `Device not initialized` )
    } {}

    // Revocation is checked against index.txt, not merely inferred from
    // the on-disk enrollment file having been scribbled over.
    ? ( _initial_cert_revoked ( string_data initial_crt_path ) ) {
        ( string_free initial_crt_path ) ( string_free clean_dev_id ) ( string_free initial_cert )
        ^ ( _cert_error is_json 403 `Enrollment certificate has been revoked` )
    } {}

    : b matched ( _initial_cert_matches ( string_data initial_crt_path ) ( string_data initial_cert ) )
    ( string_free initial_crt_path )
    ? ! matched {
        ( string_free clean_dev_id ) ( string_free initial_cert )
        ^ ( _cert_error is_json 401 `Initial certificate does not match stored certificate` )
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : b cert_valid ( pki_verify_cert ca ( string_data initial_cert ) ( string_data clean_dev_id ) )
        ( string_free initial_cert )

        ? ! cert_valid {
            ( string_free clean_dev_id )
            ^ ( _cert_error is_json 401 `Invalid initial certificate` )
        } {}

        : PkiCert op_cert ( pki_issue_device_cert ca ( string_data clean_dev_id ) validity_days )

        : String dev_out_dir ( string_from g_device_certs_dir )
        ( string_push_char dev_out_dir 47 )
        ( string_push_str dev_out_dir ( string_data clean_dev_id ) )
        : !v IoErr _md ( dir_create_all ( string_data dev_out_dir ) )
        ( string_free dev_out_dir )

        : String crt_file ( _device_path g_device_certs_dir ( string_data clean_dev_id ) `.crt` )
        : String key_file ( _device_path g_device_certs_dir ( string_data clean_dev_id ) `.key` )
        : !v IoErr _w1 ( write_file ( string_data crt_file ) ( string_data . op_cert cert_pem ) )
        : !v IoErr _w2 ( write_file ( string_data key_file ) ( string_data . op_cert key_pem ) )
        : !v IoErr _cm ( set_permissions ( string_data key_file ) 384 )
        ( string_free crt_file )
        ( string_free key_file )

        ? is_json {
            : Json res ( json_obj_new )
            ( json_obj_set res `device_id` ( json_str_lit ( string_data clean_dev_id ) ) )
            ( json_obj_set res `certificate` ( json_str_lit ( string_data . op_cert cert_pem ) ) )
            ( json_obj_set res `private_key` ( json_str_lit ( string_data . op_cert key_pem ) ) )
            ( json_obj_set res `ca_certificate` ( json_str_lit ( string_data . ca cert_pem ) ) )
            ( json_obj_set res `serial` ( json_str_lit ( string_data . op_cert serial_hex ) ) )
            ( json_obj_set res `algorithm` ( json_str_lit ( pki_alg_name . ca alg ) ) )
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

// POST /request-csr — Issue certificate from a client-provided PKCS#10 CSR.
// Client private key never crosses the wire (Zero Trust PKI).
@ handle_request_csr_post HttpRequest req Params p → HttpResponse {
    ? ! ( auth_check_api_key req g_management_key ) {
        ^ ( _resp_err_json 401 `Unauthorized: valid management API key required` )
    } {}

    : String body_str ( bytes_to_str . req body )
    : ~ String csr_input ( string_new )
    : ~ i validity_days 365

    : !Json JsonError jr ( json_parse ( string_data body_str ) )
    ?? jr {
        T root → {
            ( string_free csr_input )
            = csr_input ( _json_str_field root `csr` )
            ?? ( json_obj_get root `validity_days` ) {
                T v → {
                    ?? ( json_num_as_i v ) {
                        T val → { ? > val 0 { = validity_days val } {} }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            ( json_free root )
        }
        F _ → {
            // Raw PEM posted as the body.
            ? > ( nurl_str_find ( string_data body_str ) `-----BEGIN` ) -1 {
                ( string_free csr_input )
                = csr_input ( string_clone body_str )
            } {}
        }
    }
    ( string_free body_str )

    ? > validity_days 3650 { = validity_days 3650 } {}

    ? == ( string_len csr_input ) 0 {
        ( string_free csr_input )
        ^ ( _resp_err_json 400 `Missing CSR PEM in request body` )
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle
        : !PkiCert String res ( pki_issue_cert_from_csr ca ( string_data csr_input ) validity_days )
        ( string_free csr_input )
        ?? res {
            T cert → {
                : Json out ( json_obj_new )
                ( json_obj_set out `status` ( json_str_lit `success` ) )
                ( json_obj_set out `certificate` ( json_str_lit ( string_data . cert cert_pem ) ) )
                ( json_obj_set out `ca_certificate` ( json_str_lit ( string_data . ca cert_pem ) ) )
                ( json_obj_set out `serial` ( json_str_lit ( string_data . cert serial_hex ) ) )
                ( json_obj_set out `algorithm` ( json_str_lit ( pki_alg_name . ca alg ) ) )
                ( json_obj_set out `expires` ( json_str_lit ( string_data . cert expires_iso ) ) )

                ( pki_cert_free cert )
                : String jout ( json_stringify out )
                ( json_free out )
                ^ ( _resp_json 200 jout )
            }
            F err → {
                : HttpResponse r ( _resp_err_json 400 ( string_data err ) )
                ( string_free err )
                ^ r
            }
        }
    } {
        ( string_free csr_input )
        ^ ( _resp_err_json 500 `CA not initialized` )
    }
}

// GET /revoke
@ handle_revoke_get HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_revoke_cert `` ) )
}

@ _revoke_error b is_json i status s msg → HttpResponse {
    ? is_json { ^ ( _resp_err_json status msg ) } {}
    ^ ( _resp_html status ( ui_render_revoke_cert msg ) )
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
            ( string_free serial_input )
            = serial_input ( _json_str_field jobj `serial` )
            ( string_free cert_input )
            = cert_input ( _json_str_field jobj `certificate` )
            ( string_free form_api_key )
            = form_api_key ( _json_str_field jobj `api_key` )
            ( json_free jobj )
        }
        F _ → {
            : ( Vec QueryPair ) qpairs ( parse_query ( string_data body_str ) )
            ( string_free serial_input )
            = serial_input ( _form_get qpairs `serial` )
            ( string_free cert_input )
            = cert_input ( _form_get qpairs `certificate` )
            ( string_free form_api_key )
            = form_api_key ( _form_get qpairs `api_key` )
            ( query_pairs_free qpairs )
        }
    }
    ( string_free body_str )

    : ~ b auth_ok ( auth_check_api_key req g_management_key )
    ? ! auth_ok {
        ? ( auth_check_api_key_value ( string_data form_api_key ) g_management_key ) { = auth_ok T } {}
    } {}
    ( string_free form_api_key )

    ? ! auth_ok {
        ( string_free serial_input ) ( string_free cert_input )
        ^ ( _revoke_error is_json 401 `Invalid or missing Management API key` )
    } {}

    ? & == ( string_len serial_input ) 0 == ( string_len cert_input ) 0 {
        ( string_free serial_input ) ( string_free cert_input )
        ^ ( _revoke_error is_json 400 `Missing serial or certificate` )
    } {}

    : ~ String final_serial ( string_new )
    : ~ String final_cn ( string_new )

    ? > ( string_len cert_input ) 0 {
        ? == g_ca_handle 0 {
            ( string_free serial_input ) ( string_free cert_input )
            ( string_free final_serial ) ( string_free final_cn )
            ^ ( _revoke_error is_json 500 `CA not available` )
        } {}
        : *PkiCa vca # *PkiCa g_ca_handle
        // Revoking by PEM used to trust whatever the body claimed: the
        // CN was lifted straight out of an unverified certificate and
        // then used to name a file. Only a certificate this CA actually
        // issued gets that far now. The expiry window is deliberately
        // NOT part of the check — an expired certificate is still a
        // legitimate thing to place on a CRL — so the signature is
        // verified directly rather than through pki_verify_cert.
        : b issued_here ( _cert_issued_by_ca vca ( string_data cert_input ) )
        ? ! issued_here {
            ( string_free serial_input ) ( string_free cert_input )
            ( string_free final_serial ) ( string_free final_cn )
            ^ ( _revoke_error is_json 400 `Certificate was not issued by this CA` )
        } {}
        : PkiCertInfo cinfo ( pki_extract_cert_info ( string_data cert_input ) )
        ? . cinfo ok {
            ( string_free final_serial )
            = final_serial ( pki_normalise_serial ( string_data . cinfo serial_hex ) )
            ( string_free final_cn )
            = final_cn ( string_clone . cinfo cn )
        } {}
        ( pki_cert_info_free cinfo )
    } {}
    ( string_free cert_input )

    ? & == ( string_len final_serial ) 0 > ( string_len serial_input ) 0 {
        ( string_free final_serial )
        = final_serial ( pki_normalise_serial ( string_data serial_input ) )
    } {}
    ( string_free serial_input )

    ? == ( string_len final_serial ) 0 {
        ( string_free final_serial ) ( string_free final_cn )
        ^ ( _revoke_error is_json 400 `Serial must be an even-length hex string of at most 40 bytes` )
    } {}

    ? != g_ca_handle 0 {
        : *PkiCa ca # *PkiCa g_ca_handle

        ? > ( string_len final_cn ) 0 {
            : b _inv ( pki_invalidate_initial_cert g_initial_certs_dir ( string_data final_cn ) )
        } {}

        : String updated_crl ( pki_record_revocation g_index_file_path g_crl_file_path ca ( string_data final_serial ) ( string_data final_cn ) )
        ( string_free final_cn )

        : String now_iso ( pki_iso_timestamp ( now_seconds ) )
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

// Signature-only check: was this certificate signed by our CA key? No
// validity-window test, because revoking an already-expired certificate
// is legitimate.
@ _cert_issued_by_ca * PkiCa ca s cert_pem → b {
    : !( Vec u ) ParseErr dr ( pem_to_der cert_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 { ( vec_free [u] der ) ^ F } {}
    : X509 x ( x509_parse der )
    : ~ b ok F
    ? . x ok {
        = ok ( _pki_verify_sig . ca alg ( pki_ca_public ca ) . x tbs . x sig )
    } {}
    ( x509_free x )
    ( vec_free [u] der )
    ^ ok
}

// GET /
@ handle_index HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_index ) )
}

// GET /api
@ handle_api_docs HttpRequest req Params p → HttpResponse {
    ^ ( _resp_html 200 ( ui_render_api_docs ( pki_alg_display g_ca_alg ) ) )
}

// GET /css/style.css
@ handle_style_css HttpRequest req Params p → HttpResponse {
    : ~ String css ( string_new )
    ? ( file_exists `./static/css/style.css` ) {
        : !String IoErr r ( read_file `./static/css/style.css` )
        ?? r {
            T content → { ( string_free css ) = css content }
            F _ → {}
        }
    } {}
    ? == ( string_len css ) 0 {
        ( string_free css )
        = css ( ui_default_css )
    } {}
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `text/css; charset=utf-8` )
    ( response_set_header resp `X-Content-Type-Options` `nosniff` )
    ( response_set_body_str resp ( string_data css ) )
    ( string_free css )
    ^ resp
}

// GET /js/app.js
@ handle_app_js HttpRequest req Params p → HttpResponse {
    : HttpResponse resp ( response_new 200 )
    ( response_set_header resp `Content-Type` `text/javascript; charset=utf-8` )
    ( response_set_header resp `X-Content-Type-Options` `nosniff` )
    : String js ( ui_app_js )
    ( response_set_body_str resp ( string_data js ) )
    ( string_free js )
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
    ( http_app_logging a )

    ( http_app_get a `/health` \ HttpRequest req Params p → HttpResponse { ^ ( handle_health req p ) } )
    ( http_app_get a `/ca-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_ca_cert req p ) } )
    ( http_app_get a `/crl` \ HttpRequest req Params p → HttpResponse { ^ ( handle_crl req p ) } )

    ( http_app_post a `/init` \ HttpRequest req Params p → HttpResponse { ^ ( handle_init req p ) } )
    ( http_app_post a `/renew_initial_cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_renew_initial_cert req p ) } )

    ( http_app_get a `/request-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_request_cert_get req p ) } )
    ( http_app_post a `/request-cert` \ HttpRequest req Params p → HttpResponse { ^ ( handle_request_cert_post req p ) } )
    ( http_app_post a `/request-csr` \ HttpRequest req Params p → HttpResponse { ^ ( handle_request_csr_post req p ) } )

    ( http_app_get a `/revoke` \ HttpRequest req Params p → HttpResponse { ^ ( handle_revoke_get req p ) } )
    ( http_app_post a `/revoke` \ HttpRequest req Params p → HttpResponse { ^ ( handle_revoke_post req p ) } )

    ( http_app_get a `/` \ HttpRequest req Params p → HttpResponse { ^ ( handle_index req p ) } )
    ( http_app_get a `/api` \ HttpRequest req Params p → HttpResponse { ^ ( handle_api_docs req p ) } )
    ( http_app_get a `/css/style.css` \ HttpRequest req Params p → HttpResponse { ^ ( handle_style_css req p ) } )
    ( http_app_get a `/js/app.js` \ HttpRequest req Params p → HttpResponse { ^ ( handle_app_js req p ) } )
    ( http_app_get a `/favicon.ico` \ HttpRequest req Params p → HttpResponse { ^ ( handle_favicon req p ) } )

    // Unmatched GETs fall through to ./static. http_static.nu rejects
    // any `..` segment, so the webroot is the boundary it claims to be.
    ( http_app_static_dir a `./static` )

    ^ a
}
