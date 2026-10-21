// packages/psql/src/pg.nu — a PostgreSQL client in pure NURL. No libpq:
// the wire protocol (pgwire.nu), the authentication (trust / cleartext /
// MD5 / SCRAM-SHA-256) and the optional TLS upgrade (PostgreSQL's
// SSLRequest, then the pure-NURL TLS client) are all implemented here, so
// a secure connection works on a host with nothing installed.
//
//   ( pg_connect host port user password database sslmode ) → !PgConn PgErr
//   ( pg_query conn sql )                     → !PgResult PgErr  simple protocol:
//                                                any number of statements, text cells
//   ( pg_query_params conn sql params )       → !PgResult PgErr  extended protocol:
//                                                `$1 … $n` bound to typed PgVal
//                                                parameters, binary cells where exact,
//                                                the statement prepared once per
//                                                connection (the statement cache)
//   ( pg_pool_new host port user password database sslmode cfg ) → ( Pool PgConn PgErr )
//   ( pg_pool_get pool )                      → !( Pooled PgConn PgErr ) PgErr
//   ( pg_close conn )                         → v   early release (optional)
//
// A PgConn is a handle: every copy is the same connection, and the last
// owner closes it (Terminate, then the TLS session or the socket). A
// request checks the connection's state out of its Locked for the round
// trip, so copies on several threads or fibers take turns. PgResult is a
// plain value (pgwire.nu: its typed accessors pg_row_i / pg_row_f /
// pg_row_b / pg_row_s / pg_row_bytes / pg_row_ts / pg_row_date). Nothing
// here is released by hand.
//
// sslmode: 0 disable · 1 prefer (TLS if the server offers it, no
// certificate check; should it decline, a password is sent only through
// SCRAM — a server asking for it in the clear or as MD5 is refused with
// PgInsecureAuth, since anyone in the path can ask) · 2 require (TLS
// mandatory, no certificate check) · 3 verify-full (TLS, the chain checked
// against the system trust store and the host name against the
// certificate — what a connection over a network wants).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_md5.nu`
$ `stdlib/std/random.nu`
$ `scram.nu`
$ `pgwire.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/pool.nu`
$ `stdlib/core/slice.nu`

: | PgErr {
    PgConnFail  // could not open the TCP socket, or the connection broke
    PgTls  // TLS upgrade failed (refused, or handshake/cert error)
    PgProtocol  // malformed/unexpected backend message
    PgAuth  // authentication failed or unsupported method
    PgServerError  // backend ErrorResponse — see ( pg_conn_lasterr conn )
    PgQuery  // query-time failure — see ( pg_conn_lasterr conn )
    PgNeedPassword  // server asked for a password but none was supplied
    PgInsecureAuth  // sslmode=prefer fell back to plaintext and the server asked for the password in the clear or as MD5
    PgPoolTimeout  // pg_pool_get waited its wait_ms and no connection came back
    PgPoolClosed  // the pool was closed
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
        PgInsecureAuth → `PgInsecureAuth`
        PgPoolTimeout → `PgPoolTimeout`
        PgPoolClosed → `PgPoolClosed`
    }
}

// A statement the connection prepared: what Describe said of it, and the
// formats its results are asked in.
: PgStmt {
    String sql
    i hash  // of sql, compared before the text
    String name
    ( Vec i ) param_oids
    ( Vec PgCol ) cols  // fmt = the format asked for (pgw_result_fmt)
    ( Vec i ) rfmts  // Bind's result-format codes for cols
    i used  // the connection's clock when last executed (LRU)
}

// How many prepared statements a connection keeps by default.
: i PG_STMT_CACHE 64

: PgConnImpl {
    TcpConn conn  // the transport: plaintext, or TLS once tcp_starttls ran
    i tls  // 0 plaintext, 1 TLS
    ( Vec u ) rxbuf  // backend bytes; messages from rpos on are not read yet
    i rpos
    ( Vec u ) txbuf  // the frontend messages of the request being sent
    String lasterr  // last ErrorResponse (`[SQLSTATE] message`) / failure text
    PgNotice err  // …in full
    i be_pid
    i be_key
    String srv_ver  // server_version from ParameterStatus (for the banner)
    String db_name  // connection identity, for the banner and \conninfo
    String user_name
    String host_name
    i started  // 1 once the StartupMessage went out: say Terminate on close
    b broken  // an I/O or protocol failure: the stream is lost
    i txn  // the last ReadyForQuery status: 73 idle, 84 in a transaction, 69 failed one
    ( Vec PgStmt ) stmts  // the statement cache
    i stmt_cap
    i stmt_seq  // names the next statement
    i clock  // ticks per execution, for the LRU
}

// Its last owner says goodbye — a best-effort Terminate, once the server
// was spoken to — and the TcpConn then closes the TLS session or the
// socket with the rest of the fields.
% Drop PgConnImpl {
    @ drop PgConnImpl c → v {
        ? & == . c started 1 ! . c broken {
            : ( Vec u ) term ( vec_with_cap [u] 5 )
            ( pgw_terminate term )
            ?? ( tcp_write_all . c conn term ) { T _ → {} F _ → {} }
        } {}
    }
}

// A PgConn is a handle on its state in a Locked (stdlib/std/thread.nu):
// every copy is the same connection, the last owner closes it, and a
// request checks the state out (locked_take) for its round trip — copies
// on several threads take turns.
: PgConn { ( Locked PgConnImpl ) st }

@ PgConn_share PgConn h → PgConn { ^ @ PgConn { ( Locked_share [PgConnImpl] . h st ) } }

@ PgConn_drop sink PgConn h → v {}

// The connection's text fields, copied out. lasterr is the last
// ErrorResponse (`[SQLSTATE] message`), empty if none.
@ pg_conn_lasterr PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . c lasterr )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// The last error's SQLSTATE (`23505` a unique violation, …), empty if none.
@ pg_conn_sqlstate PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . . c err code )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

@ pg_conn_server_version PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . c srv_ver )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

@ pg_conn_db_name PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . c db_name )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

@ pg_conn_user_name PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . c user_name )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

@ pg_conn_host_name PgConn h → String {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : String r ( string_clone . c host_name )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// 1 when the connection runs over TLS, 0 when it is plaintext.
@ pg_conn_tls PgConn h → i {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : i r . c tls
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// F once an I/O or protocol failure lost the stream: every request then
// fails with PgConnFail, and a pool drops the connection.
@ pg_conn_ok PgConn h → b {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : b r ! . c broken
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// The transaction status the server last reported: 73 'I' idle, 84 'T'
// inside a transaction block, 69 'E' inside a failed one.
@ pg_conn_txn_status PgConn h → i {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : i r . c txn
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// How many prepared statements pg_query_params keeps (default
// PG_STMT_CACHE); 0 prepares each execution unnamed, keeping none. A
// smaller bound closes the least recently used ones on the next prepare.
@ pg_conn_set_stmt_cache PgConn h i n → v {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    = . c stmt_cap ? < n 0 0 n
    ( locked_restore [PgConnImpl] . h st c )
}

// The statements in the cache now.
@ pg_conn_stmt_count PgConn h → i {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : i r ( vec_len [PgStmt] . c stmts )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// ── byte helpers ──────────────────────────────────────────────────
@ __bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

@ __rd32 ( Vec u ) v i off → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 4 { = acc | << acc 8 ( __bget v + off k ) = k + k 1 }
    ^ acc
}

@ __push_raw ( Vec u ) v s raw → v { ( pgw_put_raw v raw ) }

@ __push_cstr ( Vec u ) v s raw → v { ( pgw_put_cstr v raw ) }

@ __push_strv ( Vec u ) v String s → v { ( pgw_put_slice v ( string_bytes s ) ) }

// Bytes [from,to) of a Vec u as a heap String.
@ __slice_str ( Vec u ) v i from i to → String {
    : ( Slice u ) b ( slice_from_vec [u] v )
    : i n ? > to from - to from 0
    : String out ( string_with_cap n )
    ? > n 0 { ( string_push_window out b from n ) } {}
    ^ out
}

// ── transport ─────────────────────────────────────────────────────
// Send the request in txbuf (and empty it). F when the write failed: the
// stream is lost.
@ __pg_flush inout PgConnImpl c → b {
    // A connection a fiber used has a non-blocking socket (std/net.nu's
    // fiber paths set it), and a thread's blocking calls on it would see
    // "no data yet" as a timeout: a pooled connection passes between
    // fibers and threads, so a thread's request puts it back first
    // (memoised in the runtime: no syscall when it already is).
    ? == ( nurl_fiber_current ) 0 { ( tcp_set_nonblock_conn . c conn 0 ) } {}
    ?? ( tcp_write_all . c conn . c txbuf ) {
        T _ → { ( vec_clear [u] . c txbuf ) ^ T }
        F _ → { ( vec_clear [u] . c txbuf ) = . c broken T ^ F }
    }
}

// One read onto rxbuf, first dropping the bytes already read when they
// are the larger part of it. F on EOF or error.
@ __pg_fill inout PgConnImpl c → b {
    ? > . c rpos 0 {
        ? | >= . c rpos ( vec_len [u] . c rxbuf ) >= * . c rpos 2 ( vec_len [u] . c rxbuf ) {
            ( bytes_drop_front . c rxbuf . c rpos )
            = . c rpos 0
        } {}
    } {}
    ?? ( tcp_read_into . c conn . c rxbuf 65536 ) {
        T n → { ? <= n 0 { = . c broken T ^ F } {} ^ T }
        F _ → { = . c broken T ^ F }
    }
}

// Read and fold the backend's answer to one request, up to its
// ReadyForQuery, into `col`. 0 ok, 1 the stream broke (I/O, a malformed
// message: the connection is lost), 3 the server reported an error.
@ __pg_await inout PgConnImpl c inout PgCollect col → i {
    ~ ! . col done {
        : i n ( pgw_frame . c rxbuf . c rpos )
        ? < n 0 { = . c broken T ^ 1 } {}
        ? == n 0 {
            ? ! ( __pg_fill c ) { ^ 1 } {}
        } {
            : i at . c rpos
            : i mtype ( __bget . c rxbuf at )
            ( pgw_collect_feed col mtype . c rxbuf + at 5 + at n )
            = . c rpos + at n
        }
    }
    = . c txn . col txn
    ? == . col rc 1 { = . c broken T ^ 1 } {}
    ? == . col rc 3 {
        = . c lasterr ( pgw_notice_text . col err )
        = . c err . col err
        ^ 3
    } {}
    ^ 0
}

// The next whole message during startup, its payload copied out.
: PgMsg {
    i mtype
    ( Vec u ) payload
}

@ __pg_next inout PgConnImpl c → !PgMsg PgErr {
    ~ T {
        : i n ( pgw_frame . c rxbuf . c rpos )
        ? < n 0 { = . c broken T ^ @ !PgMsg PgErr { F # PgErr PgProtocol } } {}
        ? > n 0 {
            : i at . c rpos
            : i mtype ( __bget . c rxbuf at )
            : ( Vec u ) payload ( bytes_slice . c rxbuf + at 5 + at n )
            = . c rpos + at n
            ^ @ !PgMsg PgErr { T @ PgMsg { mtype payload } }
        } {}
        ? ! ( __pg_fill c ) { ^ @ !PgMsg PgErr { F # PgErr PgProtocol } } {}
    }
}

// Frame and send a typed frontend message (authentication).
@ __pg_send_typed inout PgConnImpl c i mtype ( Vec u ) payload → i {
    : i at ( pgw_begin . c txbuf mtype )
    ( bytes_extend_bytes . c txbuf payload )
    ( pgw_end . c txbuf at )
    ^ ? ( __pg_flush c ) 1 0
}

// ── authentication ────────────────────────────────────────────────
// MD5: "md5" + md5_hex( md5_hex(password ++ user) ++ salt )
@ __pg_md5_auth inout PgConnImpl c s user s password ( Vec u ) salt → i {
    : ( Vec u ) inner ( vec_new [u] )
    ( __push_raw inner password )
    ( __push_raw inner user )
    : ( Vec u ) inner_d ( md5_pure inner )
    : String inner_hex ( bytes_to_hex inner_d )

    : ( Vec u ) outer ( vec_new [u] )
    ( __push_strv outer inner_hex )
    ( bytes_extend_bytes outer salt )
    : ( Vec u ) outer_d ( md5_pure outer )
    : String outer_hex ( bytes_to_hex outer_d )

    : ( Vec u ) payload ( vec_new [u] )
    ( __push_raw payload `md5` )
    ( __push_strv payload outer_hex )
    ( vec_push [u] payload # u 0 )
    : i ok ( __pg_send_typed c 112 payload )

    ^ ok
}

// SCRAM-SHA-256 exchange. Returns 1 on the messages being sent OK; the
// final server-signature check happens when SASLFinal arrives.
@ __pg_scram_init inout PgConnImpl c String cfb → i {
    : String full ( string_with_cap + 8 ( string_len cfb ) )
    ( string_push_str full `n,,` )
    ( string_push_str full ( string_data cfb ) )
    : ( Vec u ) payload ( vec_new [u] )
    ( __push_cstr payload `SCRAM-SHA-256` )
    ( pgw_put32 payload ( string_len full ) )
    ( __push_strv payload full )
    : i ok ( __pg_send_typed c 112 payload )
    ^ ok
}

// Run the whole startup→auth→ReadyForQuery sequence. `plain_fallback`:
// sslmode=prefer found no TLS — a password goes only through SCRAM.
@ __pg_authenticate inout PgConnImpl c s user s password b plain_fallback → !v PgErr {
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
                ? | == sub 3 == sub 5 {
                    // Cleartext (3) and MD5 (5) hand whoever asks the
                    // password, or a hash of it to crack offline: never
                    // to a server reached by falling back from TLS.
                    ? plain_fallback { = done 1 = rc 5 } {}
                } {}
                ? & == sub 3 == done 0 {
                    ? == ( nurl_str_len password ) 0 { = done 1 = rc 4 } {
                        : ( Vec u ) pw ( vec_new [u] )
                        ( __push_cstr pw password )
                        : i _o ( __pg_send_typed c 112 pw )
                    }
                } {}
                ? & == sub 5 == done 0 {
                    ? == ( nurl_str_len password ) 0 { = done 1 = rc 4 } {
                        : ( Vec u ) salt ( bytes_slice pl 4 ( vec_len [u] pl ) )
                        : i _o ( __pg_md5_auth c user password salt )
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
                    ? == . sres ok 0 {
                        ( string_free . sres client_final ) ( string_free . sres server_sig )
                        = done 1 = rc 2
                    } {
                        : ( Vec u ) cf ( vec_new [u] )
                        ( __push_strv cf . sres client_final )
                        : i _o ( __pg_send_typed c 112 cf )
                        ( string_free . sres client_final )
                        = scram_expect . sres server_sig
                    }
                } {}
                ? == sub 12 {
                    // SASLFinal: payload "v=<base64 server signature>"
                    : String got ( __slice_str pl 6 ( vec_len [u] pl ) )
                    ? ( string_eq got scram_expect ) {} { = done 1 = rc 2 }
                } {}
                ? & & & & != sub 0 != sub 3 != sub 5 != sub 10 & != sub 11 != sub 12 {
                    = done 1 = rc 2
                } {}
            } {
                ? == t 69 {
                    = . c err ( pgw_notice pl 0 ( vec_len [u] pl ) )
                    = . c lasterr ( pgw_notice_text . c err )
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
                            = . c srv_ver ( __slice_str pl vs ve )
                        } {}
                    } {}
                    ? == t 75 {
                        = . c be_pid ( __rd32 pl 0 )
                        = . c be_key ( __rd32 pl 4 )
                    } {}
                    ? == t 78 {} {}  // NoticeResponse
                    ? == t 90 { = . c txn ( __bget pl 0 ) = done 1 = rc 0 } {}  // ReadyForQuery
                }
            }
        }
    }
    ? == rc 0 { ^ @ !v PgErr { T 0 } } {}
    ? == rc 4 { ^ @ !v PgErr { F # PgErr PgNeedPassword } } {}
    ? == rc 5 { ^ @ !v PgErr { F # PgErr PgInsecureAuth } } {}
    ? == rc 3 { ^ @ !v PgErr { F # PgErr PgServerError } } {}
    ? == rc 1 { ^ @ !v PgErr { F # PgErr PgProtocol } } {}
    ^ @ !v PgErr { F # PgErr PgAuth }
}

// ── connection ────────────────────────────────────────────────────
// Ask the server for TLS (SSLRequest) on the plaintext connection. Returns
// 'S'(83) if it agrees, 'N'(78) if not, <0 on I/O failure.
@ __pg_ssl_request TcpConn conn → i {
    : ( Vec u ) req ( vec_new [u] )
    ( pgw_put32 req 8 )
    ( pgw_put32 req 80877103 )
    ?? ( tcp_write_all conn req ) { T _ → {} F _ → { ^ -1 } }
    ?? ( tcp_read_chunk conn 1 ) {
        T one → { ? == ( vec_len [u] one ) 0 { ^ -1 } {} ^ ( __bget one 0 ) }
        F _ → { ^ -1 }
    }
}

@ pg_connect s host i port s user s password s database i sslmode → !PgConn PgErr {
    : TcpConn conn ?? ( tcp_connect host port ) {
        T c → c
        F _ → { ^ @ !PgConn PgErr { F # PgErr PgConnFail } }
    }
    // ── optional TLS upgrade (SSLRequest → pure-NURL TLS, in place) ──
    : ~ i tls 0
    : ~ b plain_fallback F
    ? > sslmode 0 {
        : i resp ( __pg_ssl_request conn )
        ? == resp 83 {
            ?? ( tcp_starttls conn host >= sslmode 3 ) {
                T _ → { = tls 1 }
                F _ → { ^ @ !PgConn PgErr { F # PgErr PgTls } }
            }
        } {
            // The server declined TLS (or never answered the request).
            ? >= sslmode 2 { ^ @ !PgConn PgErr { F # PgErr PgTls } } {}
            ? < resp 0 { ^ @ !PgConn PgErr { F # PgErr PgConnFail } } {}
            = plain_fallback T
        }
    } {}
    // The state now: every early return below lets go of it, and its drop
    // closes the connection.
    : ~ PgConnImpl c @ PgConnImpl {
        conn
        tls
        ( vec_with_cap [u] 65536 )
        0
        ( vec_with_cap [u] 1024 )
        ( string_new )
        ( pgw_notice_empty )
        0
        0
        ( string_new )
        ( string_from database )
        ( string_from user )
        ( string_from host )
        0
        F
        0
        ( vec_new [PgStmt] )
        PG_STMT_CACHE
        0
        0
    }

    // ── StartupMessage ──
    : ( Vec u ) startup ( vec_new [u] )
    ( pgw_put32 startup 196608 )  // protocol 3.0
    ( __push_cstr startup `user` )
    ( __push_cstr startup user )
    ? > ( nurl_str_len database ) 0 {
        ( __push_cstr startup `database` )
        ( __push_cstr startup database )
    } {}
    ( __push_cstr startup `client_encoding` )
    ( __push_cstr startup `UTF8` )
    ( vec_push [u] startup # u 0 )  // trailing terminator

    ( pgw_put32 . c txbuf + 4 ( vec_len [u] startup ) )
    ( bytes_extend_bytes . c txbuf startup )
    = . c started 1
    ? ! ( __pg_flush c ) { ^ @ !PgConn PgErr { F # PgErr PgConnFail } } {}

    // Authentication failed: the connection is let go with the error (the
    // caller only inspects the PgErr).
    ?? ( __pg_authenticate c user password plain_fallback ) {
        T _ → { ^ @ !PgConn PgErr { T @ PgConn { ( locked_new [PgConnImpl] c ) } } }
        F e → { ^ @ !PgConn PgErr { F e } }
    }
}

// ── simple query ──────────────────────────────────────────────────
// Any number of statements (a script); text cells. The result is the
// last statement's.
@ pg_query PgConn h s sql → !PgResult PgErr {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : !PgResult PgErr r ( __pg_query c sql )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

@ __pg_fail i rc → PgErr {
    ^ ? == rc 3 # PgErr PgServerError # PgErr PgConnFail
}

@ __pg_query inout PgConnImpl c s sql → !PgResult PgErr {
    ? . c broken { ^ @ !PgResult PgErr { F # PgErr PgConnFail } } {}
    ( pgw_query . c txbuf sql )
    ? ! ( __pg_flush c ) { ^ @ !PgResult PgErr { F # PgErr PgConnFail } } {}
    : ~ PgCollect col ( pgw_collect_new )
    : i rc ( __pg_await c col )
    ? != rc 0 { ^ @ !PgResult PgErr { F ( __pg_fail rc ) } } {}
    ^ @ !PgResult PgErr { T . col res }
}

// ── extended query: parameters, binary cells, the statement cache ──
// `sql` with `$1 … $n` placeholders, `params` their values in order. The
// statement is prepared once per connection — Parse + Describe, the
// server inferring every parameter's type — and kept under its SQL text
// (the least recently used closed past the cache's bound); each run is one
// round trip: Bind (each value in the format its type takes best,
// pgw_param_fmt), Execute, Sync. Cells of the fixed-width types come
// binary, the rest as text.
@ pg_query_params PgConn h s sql ( Vec PgVal ) params → !PgResult PgErr {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : !PgResult PgErr r ( __pg_extended c sql params )
    ( locked_restore [PgConnImpl] . h st c )
    ^ r
}

// A cheap hash of the SQL text (FNV-1a), compared before the text.
@ __pg_hash s sql → i {
    : ( Slice u ) b ( slice_of_str sql )
    : i n ( slice_len [u] b )
    : ~ i hsh -3750763034362895579
    : ~ i k 0
    ~ < k n { = hsh * ^^ hsh ( slice_byte b k ) 1099511628211 = k + k 1 }
    ^ hsh
}

@ __pg_stmt_find inout PgConnImpl c s sql i hsh → i {
    : i n ( vec_len [PgStmt] . c stmts )
    : ~ i k 0
    ~ < k n {
        : PgStmt st ( vec_at [PgStmt] . c stmts k )
        ? & == . st hash hsh != 0 ( nurl_str_eq ( string_data . st sql ) sql ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Drop cache entries until fewer than `keep` remain, least recently used
// first, a Close for each appended to the request being built.
@ __pg_stmt_trim inout PgConnImpl c i keep → v {
    ~ & > ( vec_len [PgStmt] . c stmts ) 0 >= ( vec_len [PgStmt] . c stmts ) keep {
        : i n ( vec_len [PgStmt] . c stmts )
        : ~ i old 0
        : ~ i k 1
        ~ < k n {
            ? < . ( vec_at [PgStmt] . c stmts k ) used . ( vec_at [PgStmt] . c stmts old ) used { = old k } {}
            = k + k 1
        }
        ?? ( vec_remove [PgStmt] . c stmts old ) {
            T gone → { ( pgw_close . c txbuf 83 ( string_data . gone name ) ) }
            F → {}
        }
    }
}

// Parse + Describe + Sync: the statement as the server sees it. `name`
// "" prepares the unnamed statement (not cached).
@ __pg_prepare inout PgConnImpl c s sql s name → !PgStmt PgErr {
    ( pgw_parse . c txbuf name sql )
    ( pgw_describe . c txbuf 83 name )
    ( pgw_sync . c txbuf )
    ? ! ( __pg_flush c ) { ^ @ !PgStmt PgErr { F # PgErr PgConnFail } } {}
    : ~ PgCollect col ( pgw_collect_new )
    : i rc ( __pg_await c col )
    ? != rc 0 { ^ @ !PgStmt PgErr { F ( __pg_fail rc ) } } {}
    // The columns, each in the format it will be asked in.
    : i nc ( vec_len [PgCol] . . col res cols )
    : ( Vec PgCol ) cols ( vec_with_cap [PgCol] nc )
    : ( Vec i ) fmts ( vec_with_cap [i] nc )
    : ~ i nbin 0
    : ~ i k 0
    ~ < k nc {
        : PgCol d ( vec_at [PgCol] . . col res cols k )
        : i f ( pgw_result_fmt . d oid )
        = nbin + nbin f
        ( vec_push [PgCol] cols @ PgCol { ( string_clone . d name ) . d oid f } )
        ( vec_push [i] fmts f )
        = k + k 1
    }
    // Bind's codes: none when all are text, one when all are binary.
    : ( Vec i ) rfmts ( vec_new [i] )
    ? & > nbin 0 == nbin nc { ( vec_push [i] rfmts 1 ) } {
        ? > nbin 0 { ( vec_extend [i] rfmts fmts ) } {}
    }
    ^ @ !PgStmt PgErr { T @ PgStmt {
            ( string_from sql )
            ( __pg_hash sql )
            ( string_from name )
            ( vec_clone [i] . col param_oids )
            cols
            rfmts
            . c clock
        } }
}

// Bind + Execute + Sync of a prepared statement, and the rows.
@ __pg_execute inout PgConnImpl c PgStmt st ( Vec PgVal ) params → !PgResult PgErr {
    ( pgw_bind . c txbuf `` ( string_data . st name ) params . st param_oids . st rfmts )
    ( pgw_execute . c txbuf `` 0 )
    ( pgw_sync . c txbuf )
    ? ! ( __pg_flush c ) { ^ @ !PgResult PgErr { F # PgErr PgConnFail } } {}
    : ~ PgCollect col ( pgw_collect_new )
    ( pgw_collect_preset col . st cols )
    : i rc ( __pg_await c col )
    ? != rc 0 { ^ @ !PgResult PgErr { F ( __pg_fail rc ) } } {}
    ^ @ !PgResult PgErr { T . col res }
}

// The server no longer has the statement as it was described: it was
// deallocated (26000, DISCARD ALL / DEALLOCATE), or a table it reads
// changed shape under it (0A000, "cached plan must not change result type").
@ __pg_stale_stmt inout PgConnImpl c → b {
    : s code ( string_data . . c err code )
    ^ | != 0 ( nurl_str_eq code `26000` ) != 0 ( nurl_str_eq code `0A000` )
}

// The statement for `sql`: taken out of the cache (it goes back after
// the run), or prepared under a fresh name.
@ __pg_stmt_take inout PgConnImpl c s sql i hsh → !PgStmt PgErr {
    ?? ( vec_remove [PgStmt] . c stmts ( __pg_stmt_find c sql hsh ) ) {
        T x → { ^ @ !PgStmt PgErr { T x } }
        F → {}
    }
    ( __pg_stmt_trim c . c stmt_cap )
    : String name ( string_with_cap 24 )
    ( string_push_str name `nurl_s` )
    ( string_push_int name . c stmt_seq )
    = . c stmt_seq + . c stmt_seq 1
    ^ ( __pg_prepare c sql ( string_data name ) )
}

@ __pg_extended inout PgConnImpl c s sql ( Vec PgVal ) params → !PgResult PgErr {
    ? . c broken { ^ @ !PgResult PgErr { F # PgErr PgConnFail } } {}
    = . c clock + . c clock 1
    ? <= . c stmt_cap 0 {
        // No cache: the unnamed statement, prepared for this run alone.
        ( __pg_stmt_trim c 1 )
        : PgStmt st \ ( __pg_prepare c sql `` )
        ^ ( __pg_execute c st params )
    } {}
    : i hsh ( __pg_hash sql )
    : ~ i tries 0
    ~ T {
        // The statement, out of the cache for the run (and back in after),
        // or prepared now.
        : ~ PgStmt st \ ( __pg_stmt_take c sql hsh )
        = . st used . c clock
        : !PgResult PgErr r ( __pg_execute c st params )
        // A stale statement outside a transaction failed before it did
        // anything: close it, prepare it afresh and run it once more.
        ? & & & == tries 0 == . r 0 F == . c txn 73 ( __pg_stale_stmt c ) {
            ( pgw_close . c txbuf 83 ( string_data . st name ) )
            = tries 1
        } {
            ( vec_push [PgStmt] . c stmts st )
            ^ r
        }
    }
}

// ── connection pool ───────────────────────────────────────────────
// Connections made on demand with these settings and lent one caller at
// a time (stdlib/std/pool.nu). A connection coming back that lost its
// stream is dropped; one left inside a transaction is rolled back first
// — and dropped if that fails — so the next borrower starts clean.
@ pg_pool_new s host i port s user s password s database i sslmode PoolCfg cfg → ( Pool PgConn PgErr ) {
    : String h ( string_from host )
    : String u ( string_from user )
    : String pw ( string_from password )
    : String db ( string_from database )
    ^ ( pool_new [PgConn PgErr]
    \ → !PgConn PgErr { ^ ( pg_connect ( string_data h ) port ( string_data u ) ( string_data pw ) ( string_data db ) sslmode ) }
    \ PgConn c → b { ^ ( pg_conn_reset c ) }
    cfg
    # PgErr PgPoolTimeout
    # PgErr PgPoolClosed )
}

@ pg_pool_get ( Pool PgConn PgErr ) pool → !( Pooled PgConn PgErr ) PgErr {
    ^ ( pool_get [PgConn PgErr] pool )
}

// The connection a pool checkout holds, lent while the guard lives.
@ pg_pooled PgConn h → PgConn { ^ h }

// Ready the connection for its next user: T when it is usable and idle —
// rolled back first when it was left inside a transaction block.
@ pg_conn_reset PgConn h → b {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h st )
    : ~ b ok ! . c broken
    ? & ok != . c txn 73 {
        ?? ( __pg_query c `ROLLBACK` ) { T _ → {} F _ → { = ok F } }
        ? != . c txn 73 { = ok F } {}
    } {}
    ( locked_restore [PgConnImpl] . h st c )
    ^ ok
}

// ── result compatibility ──────────────────────────────────────────
// The cell as text, empty for NULL (pg_row_s, with NULL folded away).
@ pg_result_cell PgResult r i row i col → String {
    ?? ( pg_row_s r row col ) { T t → ^ t F → ^ ( string_new ) }
}

@ pg_result_is_null PgResult r i row i col → b { ^ ( pg_row_is_null r row col ) }

// A plain value: let go of `r` now rather than at the end of its owner's scope.
@ pg_result_free sink PgResult r → v {}

// ── teardown ──────────────────────────────────────────────────────
// Let go of `c` now rather than at the end of its owner's scope (the last
// owner closes the connection).
@ pg_close sink PgConn c → v {}
