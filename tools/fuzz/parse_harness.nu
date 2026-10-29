// tools/fuzz/parse_harness.nu — a single dispatch harness for fuzzing the
// untrusted-input parsers. Usage: `parse_harness <which> <file>...`.
//
// It reads each `file` in turn (raw bytes for binary formats, a C-string
// for text formats), feeds it to the selected parser, and drops whatever
// came back. The ONLY acceptable outcomes are a parsed value or a graceful
// parse error — never a crash, out-of-bounds access, UB, or a hang. Built
// with ASan+UBSan and driven over mutated inputs by fuzz_parsers.sh, any
// sanitizer report or non-zero exit is a real parser bug. Several files
// per run amortise process start-up (and, for the socket targets, the
// listener and the TLS identity) over a batch; fuzz_parsers.py re-runs a
// failing batch one file at a time to name the input.
//
// Pure (bytes in, value out):
//   x509 cbor msgpack json yaml xml toml
//   hpack     HPACK header blocks against one dynamic table (RFC 7541)
//   h2frame   HTTP/2 frame split + DATA padding strip (RFC 9113 §4, §6.1)
//   qpack     QPACK field sections + encoder/decoder stream (RFC 9204)
//   h3frame   HTTP/3 frame walk, SETTINGS, HEADERS → QPACK (RFC 9114 §7)
//   multipart multipart/form-data; the first line is the boundary
//   urlish    one text through url_parse, the query / form / percent
//             decoders, cookie_parse, the permessage-deflate offer and
//             the SSE frame parser
//   tlscert   a TLS Certificate message (what a server sends a client):
//             byte 0 bit 0 picks the TLS 1.2 layout; the chain walk,
//             x509 parse, name / validity / CA checks and signatures
//   csr       a DER PKCS#10 request: csr_parse + csr_verify
//   pem       PEM text: pem_to_der → x509_parse, csr_from_pem → csr_parse
//
// Over a loopback socket (the input is everything the peer sends, then
// the peer half-closes and drains whatever comes back):
//   http1     the HTTP/1.1 server connection loop (request line, headers,
//             Content-Length / chunked bodies, pipelining) — the input is
//             the client's byte stream
//   h2        the same server on the HTTP/2 prior-knowledge path
//             (preface sniff, frames, HPACK, CONTINUATION, flow control)
//   tls       a pure-TLS listener's accept + the HTTP server behind it:
//             TLS record framing, ClientHello and its extensions
//   tlscli    the pure-TLS client handshake — the input is the server's
//             byte stream (ServerHello, records)
//   ws        WebSocket frame + message reader, server side; input byte 0
//             bit 0 selects permessage-deflate inflation, bit 1 the
//             client-side (unmasked) reader
//   http1resp the HTTP/1.1 client: status line, headers, chunked /
//             Content-Length / to-EOF bodies — the input is the response
//   mqtt      the MQTT client's packet reader + PUBLISH / property
//             decoder — the input is the broker's byte stream

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/yaml.nu`
$ `stdlib/ext/xml.nu`
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/cbor.nu`
$ `stdlib/ext/msgpack.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/tls_verify.nu`
$ `stdlib/std/csr.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_multipart.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_hpack.nu`
$ `stdlib/ext/http3_frame.nu`
$ `stdlib/ext/http3_qpack.nu`
$ `stdlib/ext/cookies.nu`
$ `stdlib/ext/websocket.nu`
$ `stdlib/ext/mqtt.nu`

& `libc` @ nurl_tcp_connect s host i port → i

& `c` @ shutdown i32 fd i32 how → i32

& `c` @ getpid → i32

unsafe @ __fz_byte ( Vec u ) b i k → i { ^ # i . ( vec_data [u] b ) k }

// A plain loopback connection to `port`, or None.
unsafe @ __fz_connect i port → ?TcpConn {
    : i raw ( nurl_tcp_connect `127.0.0.1` port )
    ? != 0 ( nurl_tcp_err_kind raw ) {
        ( nurl_tcp_close raw )
        ^ @ ?TcpConn { F }
    } {}
    ^ @ ?TcpConn { T ( tcp_conn_adopt raw ) }
}

unsafe @ __fz_shutdown_wr TcpConn conn → v { : i32 _s ( shutdown # i32 ( __fz_fd conn ) # i32 1 ) }

unsafe @ __fz_pid → i { ^ # i ( getpid ) }

@ __fuzz_bytes s path → ( Vec u ) {
    : !( Vec u ) IoErr rb ( read_file_bytes path )
    ^ ?? rb { T b → b F _ → ( vec_new [u] ) }
}

// ── pure targets ─────────────────────────────────────────────────────

// Byte 0 picks the dynamic table's size limit (0 .. 8064, so eviction
// runs); the rest is decoded twice against the SAME table, the second
// pass resolving indices the first one inserted.
@ __fz_hpack ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    ? == n 0 { ^ v } {}
    : i cap * & ( __fz_byte b 0 ) 63 128
    : ( Vec u ) blk ( bytes_slice b 1 n )
    : ~ HpackDynTable dyn ( hpack_dyn_new cap )
    ?? ( hpack_decode_block blk dyn ) { T _ → {} F _ → {} }
    ?? ( hpack_decode_block blk dyn ) { T _ → {} F _ → {} }
}

@ __fz_h2frame ( Vec u ) b → v {
    : ~ i off 0
    : ~ b go T
    ~ go {
        ?? ( h2_parse_frame b off ) {
            T pf → {
                = off + off . pf consumed
                : H2Frame f . pf frame
                ? | == . f frame_type ( h2_type_data ) == . f frame_type ( h2_type_headers ) {
                    ?? ( h2_data_strip_padding f ) { T _ → {} F _ → {} }
                } {}
            }
            F _ → { = go F }
        }
    }
}

@ __fz_qpack ( Vec u ) b → v {
    ?? ( qpack_decode_section b ) { T _ → {} F _ → {} }
    : ~ i off 0
    : ~ b go T
    ~ go {
        : i r ( qpack_encoder_instruction b off )
        ? > r 0 { = off + off r } { = go F }
    }
    = off 0
    = go T
    ~ go {
        : i r ( qpack_decoder_instruction b off )
        ? > r 0 { = off + off r } { = go F }
    }
}

@ __fz_h3frame ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    : ~ i off 0
    : ~ b go T
    ~ go {
        : H3FrameHead fh ( h3_frame_peek b off )
        ? | < . fh ftype 0 > . fh length - - n off . fh head_len { = go F } {
            : i lo + off . fh head_len
            : ( Vec u ) payload ( bytes_slice b lo + lo . fh length )
            ? == . fh ftype ( h3_ft_settings ) {
                : i _e ( h3_settings_parse payload )
                : i _v ( h3_settings_get payload ( h3_setting_max_field_section_size ) )
            } {}
            ? == . fh ftype ( h3_ft_headers ) {
                ?? ( qpack_decode_section payload ) { T _ → {} F _ → {} }
            } {}
            = off + lo . fh length
        }
    }
}

@ __fz_multipart ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    : ~ i nl 0
    ~ & < nl n != ( __fz_byte b nl ) 10 { = nl + nl 1 }
    : String boundary ( string_new )
    : ~ i k 0
    ~ < k nl {
        : i c ( __fz_byte b k )
        ? != c 0 { ( string_push_char boundary c ) } {}
        = k + k 1
    }
    : ( Vec u ) body ( bytes_slice b ? < nl n + nl 1 n n )
    : ( Vec MultipartPart ) parts ( parse_multipart_form body ( string_data boundary ) )
    : i _c ( multipart_count parts )
    : i _f ( multipart_find_first parts `file` )
}

@ __fz_tlscert ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    ? == n 0 { ^ v } {}
    : i is12 & ( __fz_byte b 0 ) 1
    : ( Vec u ) msg ( bytes_slice b 1 n )
    : i _rc ( tls_chain_verify msg is12 `localhost` )
    : X509 _leaf ( tls_leaf_cert msg is12 )
}

@ __fz_csr ( Vec u ) b → v {
    : Csr c ( csr_parse b )
    : b _ok ( csr_verify c )
}

@ __fz_pem s src → v {
    ?? ( pem_to_der src ) {
        T der → {
            : X509 _c ( x509_parse der )
            ( __fz_csr der )
        }
        F _ → {}
    }
    ?? ( csr_from_pem src ) { T der → ( __fz_csr der ) F _ → {} }
}

@ __fz_urlish s src → v {
    ?? ( url_parse src ) {
        T u → { : String _t ( url_request_target u ) }
        F → {}
    }
    : ( Vec UrlParam ) up ( url_query_decode src )
    : String pd ( url_percent_decode src )
    : String pe ( url_percent_encode src )
    : UrlSplit us ( parse_url src )
    : ( Vec QueryPair ) qp ( parse_query src )
    : String pd2 ( percent_decode src )
    : ( Vec u ) raw ( vec_new [u] )
    ( bytes_extend_str raw src )
    : ( Vec QueryPair ) fp ( parse_form_urlencoded raw )
    ?? ( cookie_parse src `example.com` `/a/b` 1700000000 ) { T _ → {} F → {} }
    ?? ( ws_deflate_parse_extensions src ) { T _ → {} F → {} }
    : i sl ( nurl_str_len src )
    : i fe ( sse_frame_end src sl )
    : SseEvent _ev ( sse_parse_frame src ? >= fe 0 fe sl )
}

// ── loopback plumbing ────────────────────────────────────────────────

@ __fz_port TcpListener l → i {
    : String a ( tcp_local_addr l )
    : i n ( string_len a )
    : ~ i k - n 1
    ~ & > k 0 != ( string_get a k ) 58 { = k - k 1 }
    : ~ i port 0
    : ~ i j + k 1
    ~ < j n {
        = port + * port 10 - ( string_get a j ) 48
        = j + j 1
    }
    ^ port
}

// Read and drop what the far side sends on socket `fd` until it closes,
// fails, or stays quiet for 20 s. The drain gets the fd number, not the
// connection: a share of the TcpConn would leave its other owner on the
// writing thread, which the crossing check refuses (docs/MEMORY.md 6.5),
// and the runtime record's read state is the writer's alone. The fd may
// be non-blocking (the runtime's choice), so poll before each read; a
// read that finds nothing after poll said ready is an error, and ends it.
unsafe @ __fz_drain_fd i fd → v {
    : *u pfd # *u ( nurl_alloc ( posix_pollfd_size ) )
    : *u buf # *u ( nurl_alloc 65536 )
    : ~ b go T
    ~ go {
        ( posix_pollfd_set pfd 0 fd 1 )
        ? <= # i ( poll pfd 1 # i32 20000 ) 0 { = go F } {
            ? <= ( read # i32 fd buf 65536 ) 0 { = go F } {}
        }
    }
    ( nurl_free # s buf )
    ( nurl_free # s pfd )
}

unsafe @ __fz_fd TcpConn conn → i { ^ ( nurl_tcp_get_fd ( tcp_conn_fd conn ) ) }

// Write `path`'s bytes to `conn`, half-close it, then read until the far
// side closes. The drain runs on its own thread so a big input never
// deadlocks against a peer whose replies filled the socket buffer; the
// connection outlives it (closed by the caller after the join).
@ __fz_feed TcpConn conn s path → v {
    : i fd ( __fz_fd conn )
    : ( @ v ) drain \ → v { ( __fz_drain_fd fd ) }
    : !Thread ThreadErr dt ( thread_spawn drain )
    : ( Vec u ) data ( __fuzz_bytes path )
    ?? ( tcp_write_all conn data ) { T _ → {} F _ → {} }
    ( __fz_shutdown_wr conn )
    : i _j ?? dt { T th → ( thread_join th ) F _ → 0 }
}

// The peer as a client: connect to `port` and feed it `path`.
@ __fz_client_feed i port s path → v {
    ?? ( __fz_connect port ) {
        T conn → {
            ( __fz_feed conn path )
            ( tcp_close_conn conn )
        }
        F → {}
    }
}

// The peer as a server: accept one connection on `l` and feed it `path`.
@ __fz_server_feed TcpListener l s path → v {
    ?? ( tcp_accept l ) {
        T conn → {
            ( __fz_feed conn path )
            ( tcp_close_conn conn )
        }
        F _ → {}
    }
}

@ __fz_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `ok` )
}

// One server connection per input: the client feeder runs on a thread
// while the server under test accepts and serves on this one.
@ __fz_serve_one HttpServer srv i port s path → v {
    : ( @ v ) feeder \ → v { ( __fz_client_feed port path ) }
    : !Thread ThreadErr ft ( thread_spawn feeder )
    ?? ( server_run_once srv ) { T _ → {} F _ → {} }
    : i _j ?? ft { T th → ( thread_join th ) F _ → 0 }
}

@ __fz_ws_one TcpListener l i port s path → v {
    : ( Vec u ) data ( __fuzz_bytes path )
    : i mode ? > ( vec_len [u] data ) 0 ( __fz_byte data 0 ) 0
    : ( @ v ) feeder \ → v { ( __fz_client_feed port path ) }
    : !Thread ThreadErr ft ( thread_spawn feeder )
    ?? ( tcp_accept l ) {
        T conn → {
            ( tcp_set_timeout conn 20000 )
            // Skip the mode byte so frames start where the reader expects.
            ?? ( tcp_read_chunk conn 1 ) { T _ → {} F _ → {} }
            : WsLimits lim @ WsLimits { 1048576 4194304 20000 128 }
            : ~ b go T
            ? != & mode 1 0 {
                ?? ( ws_deflate_make ( ws_deflate_default_config ) T ) {
                    T d → {
                        ~ go {
                            ?? ( ws_read_message_deflate d conn lim ) { T _ → {} F _ → { = go F } }
                        }
                    }
                    F _ → {}
                }
            } {
                : b client != & mode 2 0
                ~ go {
                    : !WsMessage WsErr mr ? client ( ws_client_read_message conn lim ) ( ws_read_message conn lim )
                    ?? mr { T _ → {} F _ → { = go F } }
                }
            }
            ( tcp_close_conn conn )
        }
        F _ → {}
    }
    : i _j ?? ft { T th → ( thread_join th ) F _ → 0 }
}

// The client under test connects to a feeder that plays the server.
@ __fz_tlscli_one TcpListener l i port s path → v {
    : ( @ v ) feeder \ → v { ( __fz_server_feed l path ) }
    : !Thread ThreadErr ft ( thread_spawn feeder )
    ?? ( tcp_connect_tls `127.0.0.1` port `localhost` 0 ) {
        T c → {
            ( tcp_set_timeout c 20000 )
            ?? ( tcp_read_chunk c 4096 ) { T _ → {} F _ → {} }
            ( tcp_close_conn c )
        }
        F _ → {}
    }
    : i _j ?? ft { T th → ( thread_join th ) F _ → 0 }
}

@ __fz_http1resp_one TcpListener l i port s path → v {
    : ( @ v ) feeder \ → v { ( __fz_server_feed l path ) }
    : !Thread ThreadErr ft ( thread_spawn feeder )
    : String url ( string_from `http://127.0.0.1:` )
    ( string_push_str url ( nurl_str_int port ) )
    ( string_push_str url `/x` )
    : HttpOptions opt @ HttpOptions { 20000 5000 0 0 0 `` }
    ?? ( http_get_opts ( string_data url ) opt ) { T _ → {} F _ → {} }
    : i _j ?? ft { T th → ( thread_join th ) F _ → 0 }
}

@ __fz_mqtt_one TcpListener l i port s path → v {
    : ( @ v ) feeder \ → v { ( __fz_server_feed l path ) }
    : !Thread ThreadErr ft ( thread_spawn feeder )
    ?? ( __fz_connect port ) {
        T conn → {
            ( tcp_set_timeout conn 20000 )
            // A connected client (CONNACK already behind it): keep-alive off,
            // so no PINGREQ timer fires mid-read.
            // ctl = [keep-alive deadline, next packet id] (mqtt.nu's MQTT_CTL_*).
            : ( Vec i ) ctl ( vec_new [i] )
            ( vec_push [i] ctl 0 )
            ( vec_push [i] ctl 1 )
            : MqttClient cl @ MqttClient { conn ( vec_new [u] ) ctl 0 ( vec_new [i] ) F }
            : ~ b go T
            ~ go {
                ?? ( mqtt_receive cl ) { T _ → {} F _ → { = go F } }
            }
            ( tcp_close_conn . cl conn )
        }
        F → {}
    }
    : i _j ?? ft { T th → ( thread_join th ) F _ → 0 }
}

// ── dispatch ─────────────────────────────────────────────────────────

@ __fz_pure s which s path → i {
    // ── binary formats (raw bytes) ──────────────────────────────────
    ? != 0 ( nurl_str_eq which `x509` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : X509 c ( x509_parse b )
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `cbor` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : !Json CborErr r ( cbor_decode b )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `msgpack` ) {
        : ( Vec u ) b ( __fuzz_bytes path )
        : !Json MsgpackErr r ( msgpack_decode b )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `hpack` ) { ( __fz_hpack ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `h2frame` ) { ( __fz_h2frame ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `qpack` ) { ( __fz_qpack ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `h3frame` ) { ( __fz_h3frame ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `multipart` ) { ( __fz_multipart ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `tlscert` ) { ( __fz_tlscert ( __fuzz_bytes path ) ) ^ 0 } {}
    ? != 0 ( nurl_str_eq which `csr` ) { ( __fz_csr ( __fuzz_bytes path ) ) ^ 0 } {}

    // ── text formats (C-string; embedded NUL truncates, by contract) ─
    ? != 0 ( nurl_str_eq which `json` ) {
        : s src ( nurl_read_file path )
        : !Json JsonError r ( json_parse src )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `yaml` ) {
        : s src ( nurl_read_file path )
        : !Json YamlErr r ( yaml_parse src )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `xml` ) {
        : s src ( nurl_read_file path )
        : !Xml XmlErr r ( xml_parse src )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `toml` ) {
        : s src ( nurl_read_file path )
        : !TomlValue TomlErr r ( toml_parse src )
        ?? r { T _ → {} F _ → {} }
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `urlish` ) {
        : s src ( nurl_read_file path )
        ( __fz_urlish src )
        ^ 0
    } {}
    ? != 0 ( nurl_str_eq which `pem` ) {
        : s src ( nurl_read_file path )
        ( __fz_pem src )
        ^ 0
    } {}
    ^ 2
}

@ __fz_is_socket s which → b {
    ^ != 0 | | | ( nurl_str_eq which `http1` ) ( nurl_str_eq which `h2` )
    | ( nurl_str_eq which `tls` ) ( nurl_str_eq which `tlscli` )
    | | ( nurl_str_eq which `ws` ) ( nurl_str_eq which `http1resp` ) ( nurl_str_eq which `mqtt` )
}

// The self-signed identity the TLS targets serve, minted once per run.
@ __fz_tls_identity s cp s kp → b {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : b ok1 ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → T F _ → F }
    : b ok2 ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → T F _ → F }
    ^ & ok1 ok2
}

@ __fz_socket s which i first → i {
    : b tls_srv != 0 ( nurl_str_eq which `tls` )
    : b tls_cli != 0 ( nurl_str_eq which `tlscli` )
    : String dir ( string_from ( nurl_argv first ) )
    ( string_push_str dir `.` )
    ( string_push_str dir ( nurl_str_int ( __fz_pid ) ) )
    : String cp ( string_from ( string_data dir ) )
    ( string_push_str cp `.crt` )
    : String kp ( string_from ( string_data dir ) )
    ( string_push_str kp `.key` )
    ? tls_srv {
        ? ( __fz_tls_identity ( string_data cp ) ( string_data kp ) ) {} {
            ( nurl_eprintln `parse_harness: cannot write the TLS identity` )
            ^ 2
        }
    } {}
    : !TcpListener NetErr lr ? tls_srv
    ( tcp_listen_tls `127.0.0.1` 0 ( string_data cp ) ( string_data kp ) )
    ( tcp_listen `127.0.0.1` 0 )
    ?? ( file_delete ( string_data cp ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( string_data kp ) ) { T _ → {} F _ → {} }
    ?? lr {
        T l → {
            : i port ( __fz_port l )
            : HttpServer srv ( server_new_with_timeout l \ HttpRequest req → HttpResponse { ^ ( __fz_handler req ) } 20000 )
            : ~ i k first
            ~ < k ( nurl_argc ) {
                : s path ( nurl_argv k )
                ? | tls_srv != 0 | ( nurl_str_eq which `http1` ) ( nurl_str_eq which `h2` ) {
                    ( __fz_serve_one srv port path )
                } {}
                ? != 0 ( nurl_str_eq which `ws` ) { ( __fz_ws_one l port path ) } {}
                ? tls_cli { ( __fz_tlscli_one l port path ) } {}
                ? != 0 ( nurl_str_eq which `http1resp` ) { ( __fz_http1resp_one l port path ) } {}
                ? != 0 ( nurl_str_eq which `mqtt` ) { ( __fz_mqtt_one l port path ) } {}
                = k + k 1
            }
            ^ 0
        }
        F e → {
            ( nurl_eprintln ( nurl_str_cat `parse_harness: listen failed: ` ( net_err_name e ) ) )
            ^ 2
        }
    }
}

@ main → i {
    ? < ( nurl_argc ) 3 {
        ( nurl_eprintln `usage: parse_harness <target> <file>...` )
        ^ 2
    } {}
    : s which ( nurl_argv 1 )
    ? ( __fz_is_socket which ) { ^ ( __fz_socket which 2 ) } {}
    : ~ i k 2
    ~ < k ( nurl_argc ) {
        ? != 0 ( __fz_pure which ( nurl_argv k ) ) {
            ( nurl_eprintln ( nurl_str_cat `unknown parser: ` which ) )
            ^ 2
        } {}
        = k + k 1
    }
    ^ 0
}
