// http3_client_server.nu — HTTP/3 with NURL on both ends:
// `ext/http3_client.nu` (client) against `ext/http3_server.nu` (the
// server the HTTP stack puts beside every TLS listener), no other
// implementation involved.
//
// Asserted: the QUIC handshake completes on ALPN "h3" with an
// X25519MLKEM768 key exchange; a GET gets its status, a header and its
// body back; a POST body reaches the handler and comes back; the
// response's `content-type` arrives lower-cased as HTTP/3 wants; a
// second request rides the same connection; a 404 is a normal response,
// not an error; the connection closes cleanly (the server's event 3).
//
// Server on an OS thread (http3_server_run blocks), client on the main
// thread, like tls_pq_hybrid.nu.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http3_server.nu`
$ `stdlib/ext/http3_client.nu`

: ~ i g_requests 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ label_int s k i v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` )
}

@ handler HttpRequest req → HttpResponse {
    = g_requests + g_requests 1
    : s path ( string_data . req path )
    ? != 0 ( nurl_str_eq path `/` ) {
        : HttpResponse r ( response_new 200 )
        ( response_set_header r `Content-Type` `text/plain` )
        ( response_set_header r `X-Served-By` `nurl-h3` )
        : ( Vec u ) b ( bytes_from_str `hello over h3` )
        ( bytes_extend_bytes . r body b )
        ( vec_free [u] b )
        ^ r
    } {}
    ? != 0 ( nurl_str_eq path `/echo` ) {
        : HttpResponse r ( response_new 200 )
        ( bytes_extend_bytes . r body . req body )
        ^ r
    } {}
    ^ ( response_new 404 )
}

@ header_of HttpResponse r s name → String {
    : i n ( vec_len [Header] . r headers )
    : *Header d ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k n {
        : Header h . d k
        ? != 0 ( nurl_str_eq ( string_data . h name ) name ) { ^ ( string_from ( string_data . h value ) ) } {}
        = k + k 1
    }
    ^ ( string_new )
}

@ client_round → v {
    : *H3Client cl ( h3_client_connect `127.0.0.1` 18963 `localhost` 0 5000 )
    ? == # i cl 0 { ( label `connect` `NO-SOCKET` ) ^ } {}
    ( label `connect` ? ( h3_client_connected cl ) `OK` `FAIL` )
    ? ! ( h3_client_connected cl ) { ( label_int `close_code` ( h3_client_close_code cl ) ) ( h3_client_free cl ) ^ } {}
    ( label `pq` ? ( h3_client_is_pq cl ) `T` `F` )
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Accept` `text/plain` ) )
    : ( Vec u ) nobody ( vec_new [u] )
    ?? ( h3_client_request cl `GET` `https` `localhost` `/` hs nobody 5000 ) {
        T r → {
            ( label_int `get_status` . r status )
            : String ct ( header_of r `content-type` )
            ( label `get_content_type` ( string_data ct ) )
            ( string_free ct )
            : String by ( header_of r `x-served-by` )
            ( label `get_served_by` ( string_data by ) )
            ( string_free by )
            : String body ( string_from_bytes ( vec_data [u] . r body ) ( vec_len [u] . r body ) )
            ( label `get_body` ( string_data body ) )
            ( string_free body )
            ( http_response_free r )
        }
        F e → { ( label `get` ( h3_client_err_name e ) ) ( label_int `get_refusal` ( h3_client_last_refusal cl ) ) }
    }
    : ( Vec u ) payload ( bytes_from_str `posted bytes` )
    ?? ( h3_client_request cl `POST` `https` `localhost` `/echo` hs payload 5000 ) {
        T r → {
            ( label_int `post_status` . r status )
            ( label `post_echo` ? ( bytes_eq . r body payload ) `T` `F` )
            ( http_response_free r )
        }
        F e → { ( label `post` ( h3_client_err_name e ) ) }
    }
    ?? ( h3_client_request cl `GET` `https` `localhost` `/missing` hs nobody 5000 ) {
        T r → {
            ( label_int `missing_status` . r status )
            ( http_response_free r )
        }
        F e → { ( label `missing` ( h3_client_err_name e ) ) }
    }
    ( label `alive_after_three` ? ( h3_client_alive cl ) `T` `F` )
    ( vec_free [u] payload )
    ( vec_free [u] nobody )
    ( vec_free_with [Header] hs \ Header hh → v { ( header_free hh ) } )
    ( h3_client_close cl )
    ( h3_client_free cl )
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_http3_client_server.crt`
    : s kp `/tmp/nurl_http3_client_server.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )
    : *QuicCreds creds ( http3_creds_load cp kp )
    ? == # i creds 0 { ( label `creds` `FAIL` ) ^ } {}
    : !UdpSocket NetErr sr ( udp_bind `127.0.0.1` 18963 )
    ?? sr {
        T sock → {
            : ( Vec u ) prefs ( tls_alpn_pack `h3` )
            : *QuicTp stp ( http3_default_tp )
            : ( @ HttpResponse HttpRequest ) hf \ HttpRequest req → HttpResponse { ^ ( handler req ) }
            : *H3Server srv ( http3_server_new sock creds prefs stp hf 1048576 )
            : ( @ v ) server \ → v { ( http3_server_run srv ) }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 100 )
                    ( client_round )
                    ( sleep_ms 100 )
                    ( http3_server_stop srv )
                    ( thread_join t )
                    : *u server_env # *u server 1
                    ( nurl_free # s server_env )
                }
                F _ → { ( label `spawn` `FAIL` ) }
            }
            ( label_int `server_requests` g_requests )
            ( label_int `server_accepted` ( http3_server_accepted srv ) )
            ( http3_server_free srv )
            : *u hf_env # *u hf 1
            ( nurl_free # s hf_env )
            ( quic_tp_free stp )
            ( vec_free [u] prefs )
            ( udp_close sock )
        }
        F _ → { ( label `udp_bind` `FAIL` ) }
    }
    ( quic_creds_free creds )
}

@ main → i {
    ( run )
    ^ 0
}
