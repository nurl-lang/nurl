// packages/psql/src/pg.nu — PostgreSQL frontend/backend protocol v3 in pure
// NURL. No libpq: the wire protocol, the authentication (trust / cleartext /
// MD5 / SCRAM-SHA-256) and the optional TLS upgrade (PostgreSQL's SSLRequest,
// then the pure-NURL TLS client) are all implemented here, so a secure
// connection works on a host with nothing installed.
//
//   ( pg_connect host port user password database sslmode ) → !*PgConn PgErr
//   ( pg_query conn sql )                                    → !PgResult PgErr
//   ( pg_close conn )                                        → v
//
// sslmode: 0 disable · 1 prefer (TLS if offered, no verify) · 2 require
// (TLS mandatory, no cert check) · 3 verify-full (TLS + chain/hostname).
//
// PgResult is a flat row-major cell table (see the accessors at the bottom):
// nested Vecs are avoided for robustness; NULLs are tracked in a parallel
// flag array.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_md5.nu`
$ `stdlib/std/random.nu`
$ `scram.nu`
$ `deps/tls/src/tls.nu`

// SSLRequest magic (1234 << 16 | 5679) and the protocol-3.0 version word.
: | PgErr {
    PgConnFail  // could not open the TCP socket
    PgTls  // TLS upgrade failed (refused, or handshake/cert error)
    PgProtocol  // malformed/unexpected backend message
    PgAuth  // authentication failed or unsupported method
    PgServerError  // backend ErrorResponse — see . conn lasterr
    PgQuery  // query-time failure — see . conn lasterr
    PgNeedPassword  // server asked for a password but none was supplied
}

@ pg_err_name PgErr e → s {
    ^ ?? e {
        PgConnFail → `PgConnFail`
        PgTls → `PgTls`
        PgProtocol → `PgProtocol`
        PgAuth → `PgAuth`
        PgServerError → `PgServerError`
        PgQuery → `PgQuery`
        PgNeedPassword → `PgNeedPassword`
    }
}

: PgConn {
    i tls  // 0 plaintext, 1 TLS
    i raw  // raw socket handle (plaintext reads; fd the TLS layer took over)
    TcpConn tcp  // plaintext transport (writes via tcp_write_all)
    * TlsConn tc  // TLS transport (when tls = 1)
    ( Vec u ) rxbuf  // backend bytes not yet split into messages
    String lasterr  // last ErrorResponse / failure text
    i be_pid
    i be_key
    String srv_ver  // server_version from ParameterStatus (for the banner)
    String db_name  // connection identity, for the banner and \conninfo
    String user_name
    String host_name
}

: PgMsg {
    i mtype
    ( Vec u ) payload
}

// Row-major result table. cell(r,c) lives at index r*ncols+c.
: PgResult {
    i ncols
    i nrows
    ( Vec String ) colnames
    ( Vec String ) cells  // NULL rendered as empty String; see nulls
    ( Vec u ) nulls  // 1 = SQL NULL
    String tag  // CommandComplete tag (e.g. "SELECT 3")
}

// ── byte helpers ──────────────────────────────────────────────────
@ __bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __rd16 ( Vec u ) v i off → i {
    ^ | << ( __bget v off ) 8 ( __bget v + off 1 )
}

@ __rd32 ( Vec u ) v i off → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 4 { = acc | << acc 8 ( __bget v + off k ) = k + k 1 }
    ^ acc
}

// Signed 32-bit big-endian read. DataRow column lengths use -1
// (0xFFFFFFFF) to mark a SQL NULL, so they must be sign-extended.
@ __rd32s ( Vec u ) v i off → i {
    : i u ( __rd32 v off )
    ? >= u 2147483648 { ^ - u 4294967296 } { ^ u }
}

@ __push16 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ __push32 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 24 255 )
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ __push_raw ( Vec u ) v s raw → v {
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
}

@ __push_cstr ( Vec u ) v s raw → v {
    ( __push_raw v raw )
    ( vec_push [u] v # u 0 )
}

@ __push_strv ( Vec u ) v String s → v {
    ( __push_raw v ( string_data s ) )
}

// Bytes [from,to) of a Vec u as a heap String.
@ __slice_str ( Vec u ) v i from i to → String {
    : String out ( string_with_cap ? > - to from 0 - to from 1 )
    : ~ i k from
    ~ < k to { ( string_push_char out ( __bget v k ) ) = k + k 1 }
    ^ out
}

// ── transport ─────────────────────────────────────────────────────
@ __pg_write * PgConn c ( Vec u ) bytes → i {
    ? == . c tls 1 {
        ?? ( tls_write . c tc bytes ) { T _ → ^ 1 F _ → ^ 0 }
    } {
        ?? ( tcp_write_all . c tcp bytes ) { T _ → ^ 1 F _ → ^ 0 }
    }
}

// Read one chunk into rxbuf. Returns 1 on progress, 0 on EOF/error.
@ __pg_fill * PgConn c → i {
    ? == . c tls 1 {
        ?? ( tls_read . c tc 16384 ) {
            T v → {
                ? == ( vec_len [u] v ) 0 { ( vec_free [u] v ) ^ 0 } {}
                ( __cat . c rxbuf v )
                ( vec_free [u] v )
                ^ 1
            }
            F _ → ^ 0
        }
    } {
        : ( Vec u ) tmp ( vec_with_cap [u] 16384 )
        : i got ( nurl_tcp_read . c raw # s ( vec_data [u] tmp ) 16384 )
        ? <= got 0 { ( vec_free [u] tmp ) ^ 0 } {}
        : b _ok ( vec_set_len [u] tmp got )
        ( __cat . c rxbuf tmp )
        ( vec_free [u] tmp )
        ^ 1
    }
}

@ __pg_ensure * PgConn c i n → i {
    ~ < ( vec_len [u] . c rxbuf ) n {
        ? == ( __pg_fill c ) 0 { ^ 0 } {}
    }
    ^ 1
}

// Pull the next backend message (type byte + length-framed payload).
@ __pg_next * PgConn c → !PgMsg PgErr {
    ? == ( __pg_ensure c 5 ) 0 { ^ @ !PgMsg PgErr { F # PgErr PgProtocol } } {}
    : i mtype ( __bget . c rxbuf 0 )
    : i len ( __rd32 . c rxbuf 1 )
    : i total + 1 len
    ? == ( __pg_ensure c total ) 0 { ^ @ !PgMsg PgErr { F # PgErr PgProtocol } } {}
    : ( Vec u ) payload ( bytes_slice . c rxbuf 5 total )
    : i have ( vec_len [u] . c rxbuf )
    : ( Vec u ) rest ( bytes_slice . c rxbuf total have )
    ( vec_free [u] . c rxbuf )
    = . c rxbuf rest
    ^ @ !PgMsg PgErr { T @ PgMsg { mtype payload } }
}

// Frame and send a typed frontend message.
@ __pg_send_typed * PgConn c i mtype ( Vec u ) payload → i {
    : ( Vec u ) msg ( vec_with_cap [u] + ( vec_len [u] payload ) 5 )
    ( vec_push [u] msg # u mtype )
    ( __push32 msg + 4 ( vec_len [u] payload ) )
    ( __cat msg payload )
    : i ok ( __pg_write c msg )
    ( vec_free [u] msg )
    ^ ok
}

// ── ErrorResponse / NoticeResponse parsing ────────────────────────
// Fields: 1-byte code, NUL-terminated value, terminated by a 0 code.
// We surface the human-readable "M" (message) and "C" (SQLSTATE).
@ __pg_error_text ( Vec u ) payload → String {
    : i n ( vec_len [u] payload )
    : ~ String msg ( string_with_cap 64 )
    : ~ String code ( string_with_cap 8 )
    : ~ i k 0
    ~ < k n {
        : i field ( __bget payload k )
        ? == field 0 { = k n } {
            = k + k 1
            : ~ i start k
            ~ & < k n != ( __bget payload k ) 0 { = k + k 1 }
            : String val ( __slice_str payload start k )
            ? == field 77 { = msg val } {}
            ? == field 67 { = code val } {}
            = k + k 1
        }
    }
    : String out ( string_with_cap + 16 ( string_len msg ) )
    ( string_push_str out `[` )
    ( string_push_str out ( string_data code ) )
    ( string_push_str out `] ` )
    ( string_push_str out ( string_data msg ) )
    ^ out
}

// ── authentication ────────────────────────────────────────────────
// MD5: "md5" + md5_hex( md5_hex(password ++ user) ++ salt )
@ __pg_md5_auth * PgConn c s user s password ( Vec u ) salt → i {
    : ( Vec u ) inner ( vec_new [u] )
    ( __push_raw inner password )
    ( __push_raw inner user )
    : ( Vec u ) inner_d ( md5_pure inner )
    : String inner_hex ( bytes_to_hex inner_d )

    : ( Vec u ) outer ( vec_new [u] )
    ( __push_strv outer inner_hex )
    ( __cat outer salt )
    : ( Vec u ) outer_d ( md5_pure outer )
    : String outer_hex ( bytes_to_hex outer_d )

    : ( Vec u ) payload ( vec_new [u] )
    ( __push_raw payload `md5` )
    ( __push_strv payload outer_hex )
    ( vec_push [u] payload # u 0 )
    : i ok ( __pg_send_typed c 112 payload )

    ( vec_free [u] inner ) ( vec_free [u] inner_d ) ( vec_free [u] outer )
    ( vec_free [u] outer_d ) ( vec_free [u] payload )
    ^ ok
}

// SCRAM-SHA-256 exchange. Returns 1 on the messages being sent OK; the
// final server-signature check happens when SASLFinal arrives.
@ __pg_scram_init * PgConn c String cfb → i {
    : String full ( string_with_cap + 8 ( string_len cfb ) )
    ( string_push_str full `n,,` )
    ( string_push_str full ( string_data cfb ) )
    : ( Vec u ) payload ( vec_new [u] )
    ( __push_cstr payload `SCRAM-SHA-256` )
    ( __push32 payload ( string_len full ) )
    ( __push_strv payload full )
    : i ok ( __pg_send_typed c 112 payload )
    ( vec_free [u] payload )
    ( string_free full )
    ^ ok
}

// Run the whole startup→auth→ReadyForQuery sequence.
@ __pg_authenticate * PgConn c s user s password → !v PgErr {
    : ( Vec u ) pwbytes ( vec_new [u] )
    ( __push_raw pwbytes password )

    : String scram_nonce ( rand_hex_str 18 )
    : String scram_cfb ( scram_client_first_bare ( string_data scram_nonce ) )
    : ~ String scram_expect ( string_with_cap 0 )

    : ~ i done 0
    : ~ i rc 0
    ~ == done 0 {
        : !PgMsg PgErr mr ( __pg_next c )
        : PgMsg m ?? mr { T x → x F _ → { = done 1 = rc 1 @ PgMsg { 0 ( vec_new [u] ) } } }
        ? == done 1 {} {
            : i t . m mtype
            : ( Vec u ) pl . m payload
            ? == t 82 {
                // AuthenticationRequest
                : i sub ( __rd32 pl 0 )
                ? == sub 0 {} {}  // AuthenticationOk: keep reading until Z
                ? == sub 3 {
                    ? == ( nurl_str_len password ) 0 { = done 1 = rc 4 } {
                        : ( Vec u ) pw ( vec_new [u] )
                        ( __push_cstr pw password )
                        : i _o ( __pg_send_typed c 112 pw )
                        ( vec_free [u] pw )
                    }
                } {}
                ? == sub 5 {
                    ? == ( nurl_str_len password ) 0 { = done 1 = rc 4 } {
                        : ( Vec u ) salt ( bytes_slice pl 4 ( vec_len [u] pl ) )
                        : i _o ( __pg_md5_auth c user password salt )
                        ( vec_free [u] salt )
                    }
                } {}
                ? == sub 10 {
                    ? == ( nurl_str_len password ) 0 { = done 1 = rc 4 } {
                        : i _o ( __pg_scram_init c scram_cfb )
                    }
                } {}
                ? == sub 11 {
                    // SASLContinue: payload is the server-first message
                    : String sf ( __slice_str pl 4 ( vec_len [u] pl ) )
                    : ScramResult sres ( scram_compute pwbytes scram_cfb sf )
                    ( string_free sf )
                    ? == . sres ok 0 {
                        ( string_free . sres client_final ) ( string_free . sres server_sig )
                        = done 1 = rc 2
                    } {
                        : ( Vec u ) cf ( vec_new [u] )
                        ( __push_strv cf . sres client_final )
                        : i _o ( __pg_send_typed c 112 cf )
                        ( vec_free [u] cf )
                        ( string_free . sres client_final )
                        ( string_free scram_expect )
                        = scram_expect . sres server_sig
                    }
                } {}
                ? == sub 12 {
                    // SASLFinal: payload "v=<base64 server signature>"
                    : String got ( __slice_str pl 6 ( vec_len [u] pl ) )
                    ? ( string_eq got scram_expect ) {} { = done 1 = rc 2 }
                    ( string_free got )
                } {}
                ? & & & & != sub 0 != sub 3 != sub 5 != sub 10 & != sub 11 != sub 12 {
                    = done 1 = rc 2
                } {}
            } {
                ? == t 69 {
                    = . c lasterr ( __pg_error_text pl )
                    = done 1 = rc 3
                } {
                    ? == t 83 {
                        // ParameterStatus: key\0 value\0 — keep server_version.
                        : i pn ( vec_len [u] pl )
                        : ~ i e 0
                        ~ & < e pn != ( __bget pl e ) 0 { = e + e 1 }
                        : String key ( __slice_str pl 0 e )
                        ? ( nurl_str_eq ( string_data key ) `server_version` ) {
                            : i vs + e 1
                            : ~ i ve vs
                            ~ & < ve pn != ( __bget pl ve ) 0 { = ve + ve 1 }
                            ( string_free . c srv_ver )
                            = . c srv_ver ( __slice_str pl vs ve )
                        } {}
                        ( string_free key )
                    } {}
                    ? == t 75 {
                        = . c be_pid ( __rd32 pl 0 )
                        = . c be_key ( __rd32 pl 4 )
                    } {}
                    ? == t 78 {} {}  // NoticeResponse
                    ? == t 90 { = done 1 = rc 0 } {}  // ReadyForQuery
                }
            }
            ( vec_free [u] pl )
        }
    }
    ( vec_free [u] pwbytes )
    ( string_free scram_nonce ) ( string_free scram_cfb ) ( string_free scram_expect )
    ? == rc 0 { ^ @ !v PgErr { T 0 } } {
        ? == rc 4 { ^ @ !v PgErr { F # PgErr PgNeedPassword } } {
            ? == rc 3 { ^ @ !v PgErr { F # PgErr PgServerError } } {
                ? == rc 1 { ^ @ !v PgErr { F # PgErr PgProtocol } } { ^ @ !v PgErr { F # PgErr PgAuth } }
            }
        }
    }
}

// ── connection ────────────────────────────────────────────────────
// Try the SSLRequest negotiation on the raw socket. Returns 'S'(83) if
// the server agrees to TLS, 'N'(78) if not, <0 on I/O failure.
@ __pg_ssl_request i raw → i {
    : ( Vec u ) req ( vec_new [u] )
    ( __push32 req 8 )
    ( __push32 req 80877103 )
    : TcpConn t @ TcpConn { # s raw }
    ?? ( tcp_write_all t req ) { T _ → {} F _ → { ( vec_free [u] req ) ^ -1 } }
    ( vec_free [u] req )
    : ( Vec u ) one ( vec_with_cap [u] 1 )
    : i got ( nurl_tcp_read raw # s ( vec_data [u] one ) 1 )
    ? <= got 0 { ( vec_free [u] one ) ^ -1 } {}
    : b _ok ( vec_set_len [u] one got )
    : i r ( __bget one 0 )
    ( vec_free [u] one )
    ^ r
}

@ pg_connect s host i port s user s password s database i sslmode → !*PgConn PgErr {
    : i rawfd ( nurl_tcp_connect host port )
    ? != ( nurl_tcp_err_kind rawfd ) 0 { ^ @ !*PgConn PgErr { F # PgErr PgConnFail } } {}

    : *PgConn c # *PgConn ( nurl_alloc Z PgConn )
    = . c tls 0
    = . c raw rawfd
    = . c tcp @ TcpConn { # s rawfd }
    = . c tc # *TlsConn 0
    = . c rxbuf ( vec_new [u] )
    = . c lasterr ( string_with_cap 0 )
    = . c be_pid 0
    = . c be_key 0
    = . c srv_ver ( string_with_cap 0 )
    = . c db_name ( string_from database )
    = . c user_name ( string_from user )
    = . c host_name ( string_from host )

    // ── optional TLS upgrade (SSLRequest → pure-NURL TLS) ──
    ? > sslmode 0 {
        : i resp ( __pg_ssl_request rawfd )
        ? == resp 83 {
            : !*TlsConn TlsErr tr ? >= sslmode 3 ( tls_attach_verify rawfd host ) ( tls_attach rawfd host )
            ?? tr {
                T tc → { = . c tls 1 = . c tc tc }
                F _ → {
                    ( nurl_tcp_close rawfd )
                    ( vec_free [u] . c rxbuf ) ( string_free . c lasterr )
                ( string_free . c srv_ver ) ( string_free . c db_name )
                ( string_free . c user_name ) ( string_free . c host_name )
                ( nurl_free # s c )
                    ^ @ !*PgConn PgErr { F # PgErr PgTls }
                }
            }
        } {
            // server declined TLS
            ? >= sslmode 2 {
                ( nurl_tcp_close rawfd )
                ( vec_free [u] . c rxbuf ) ( string_free . c lasterr )
                ( string_free . c srv_ver ) ( string_free . c db_name )
                ( string_free . c user_name ) ( string_free . c host_name )
                ( nurl_free # s c )
                ^ @ !*PgConn PgErr { F # PgErr PgTls }
            } {}
        }
    } {}

    // ── StartupMessage ──
    : ( Vec u ) startup ( vec_new [u] )
    ( __push32 startup 196608 )  // protocol 3.0
    ( __push_cstr startup `user` )
    ( __push_cstr startup user )
    ? > ( nurl_str_len database ) 0 {
        ( __push_cstr startup `database` )
        ( __push_cstr startup database )
    } {}
    ( __push_cstr startup `client_encoding` )
    ( __push_cstr startup `UTF8` )
    ( vec_push [u] startup # u 0 )  // trailing terminator

    : ( Vec u ) frame ( vec_new [u] )
    ( __push32 frame + 4 ( vec_len [u] startup ) )
    ( __cat frame startup )
    : i wok ( __pg_write c frame )
    ( vec_free [u] startup ) ( vec_free [u] frame )
    ? == wok 0 { ( pg_close c ) ^ @ !*PgConn PgErr { F # PgErr PgConnFail } } {}

    : !v PgErr ar ( __pg_authenticate c user password )
    ?? ar {
        T _ → { ^ @ !*PgConn PgErr { T c } }
        F e → {
            // Authentication failed — close the socket and free the conn
            // (the caller only inspects the PgErr, never c, on failure).
            ( pg_close c )
            ^ @ !*PgConn PgErr { F e }
        }
    }
}

// ── simple query ──────────────────────────────────────────────────
@ pg_query * PgConn c s sql → !PgResult PgErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( __push_cstr payload sql )
    : i wok ( __pg_send_typed c 81 payload )
    ( vec_free [u] payload )
    ? == wok 0 { ^ @ !PgResult PgErr { F # PgErr PgQuery } } {}

    : ~ i ncols 0
    : ~ ( Vec String ) colnames ( vec_new [String] )
    : ~ ( Vec String ) cells ( vec_new [String] )
    : ~ ( Vec u ) nulls ( vec_new [u] )
    : ~ i nrows 0
    : ~ String tag ( string_with_cap 0 )

    : ~ i done 0
    : ~ i rc 0
    ~ == done 0 {
        : !PgMsg PgErr mr ( __pg_next c )
        : PgMsg m ?? mr { T x → x F _ → { = done 1 = rc 1 @ PgMsg { 0 ( vec_new [u] ) } } }
        ? == done 1 {} {
            : i t . m mtype
            : ( Vec u ) pl . m payload
            ? == t 84 {
                // RowDescription
                = ncols ( __rd16 pl 0 )
                ( vec_free_with [String] colnames \ String s → v { ( string_free s ) } )
                = colnames ( vec_new [String] )
                : ~ i off 2
                : ~ i fi 0
                ~ < fi ncols {
                    : ~ i e off
                    ~ != ( __bget pl e ) 0 { = e + e 1 }
                    ( vec_push [String] colnames ( __slice_str pl off e ) )
                    = off + e 1
                    = off + off 18  // tableoid(4) colno(2) typeoid(4) typelen(2) typmod(4) format(2)
                    = fi + fi 1
                }
            } {
                ? == t 68 {
                    // DataRow
                    : i nf ( __rd16 pl 0 )
                    : ~ i off 2
                    : ~ i ci 0
                    ~ < ci nf {
                        : i flen ( __rd32s pl off )
                        = off + off 4
                        ? == flen -1 {
                            ( vec_push [String] cells ( string_with_cap 0 ) )
                            ( vec_push [u] nulls # u 1 )
                        } {
                            ( vec_push [String] cells ( __slice_str pl off + off flen ) )
                            ( vec_push [u] nulls # u 0 )
                            = off + off flen
                        }
                        = ci + ci 1
                    }
                    = nrows + nrows 1
                } {
                    ? == t 67 {
                        // CommandComplete
                        : ~ i e 0
                        ~ != ( __bget pl e ) 0 { = e + e 1 }
                        ( string_free tag )
                        = tag ( __slice_str pl 0 e )
                    } {
                        ? == t 69 {
                            = . c lasterr ( __pg_error_text pl )
                            = done 1 = rc 3
                        } {
                            ? == t 90 { = done 1 } {}  // ReadyForQuery
                            // 'I' EmptyQuery, 'N' Notice, 'S' ParameterStatus → ignore
                        }
                    }
                }
            }
            ( vec_free [u] pl )
        }
    }

    ? == rc 0 {
        ^ @ !PgResult PgErr { T @ PgResult { ncols nrows colnames cells nulls tag } }
    } {
        ( vec_free_with [String] colnames \ String s → v { ( string_free s ) } )
        ( vec_free_with [String] cells \ String s → v { ( string_free s ) } )
        ( vec_free [u] nulls )
        ? == rc 3 { ^ @ !PgResult PgErr { F # PgErr PgServerError } } { ^ @ !PgResult PgErr { F # PgErr PgQuery } }
    }
}

// ── result accessors ──────────────────────────────────────────────
@ pg_result_col PgResult r i idx → String {
    ?? ( vec_get [String] . r colnames idx ) { T s → ^ s F _ → ^ ( string_with_cap 0 ) }
}

@ pg_result_is_null PgResult r i row i col → b {
    : i idx + * row . r ncols col
    ^ == ( __bget . r nulls idx ) 1
}

@ pg_result_cell PgResult r i row i col → String {
    : i idx + * row . r ncols col
    ?? ( vec_get [String] . r cells idx ) { T s → ^ s F _ → ^ ( string_with_cap 0 ) }
}

@ pg_result_free PgResult r → v {
    ( vec_free_with [String] . r colnames \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] . r cells \ String s → v { ( string_free s ) } )
    ( vec_free [u] . r nulls )
    ( string_free . r tag )
}

// ── teardown ──────────────────────────────────────────────────────
@ pg_close * PgConn c → v {
    // Best-effort Terminate ('X') then close the transport.
    : ( Vec u ) term ( vec_new [u] )
    : i _o ( __pg_send_typed c 88 term )
    ( vec_free [u] term )
    ? == . c tls 1 { ( tls_close . c tc ) } { ( nurl_tcp_close . c raw ) }
    ( vec_free [u] . c rxbuf )
    ( string_free . c lasterr )
    ( string_free . c srv_ver )
    ( string_free . c db_name )
    ( string_free . c user_name )
    ( string_free . c host_name )
    ( nurl_free # s c )
}
