// packages/psql/src/pg.nu — a PostgreSQL client in pure NURL. No libpq:
// the wire protocol (pgwire.nu), the authentication (trust / cleartext /
// MD5 / SCRAM-SHA-256) and the optional TLS upgrade (PostgreSQL's
// SSLRequest, then the pure-NURL TLS client) are all implemented here, so
// a secure connection works on a host with nothing installed.
//
//   ( pg_connect host port user password database sslmode ) → !PgConn PgErr
//   ( pg_connect_url url )                    → !PgConn PgErr  the same from a
//                                                postgres:// URI (DATABASE_URL)
//   ( pg_query conn sql )                   → !PgResult PgErr  simple protocol:
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
// owner closes it (Terminate, then the TLS session or the socket). Copies
// on several threads or fibers use it at the same time: their requests
// are pipelined on the one socket, and each answer comes back to the
// request that asked ("the connection" below). PgResult is a plain value
// (pgwire.nu: its typed accessors pg_row_i / pg_row_f / pg_row_b /
// pg_row_s / pg_row_bytes / pg_row_ts / pg_row_date). Nothing here is
// released by hand.
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
$ `stdlib/std/channel.nu`
$ `stdlib/std/async_ffi.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/arc.nu`

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
    PgBadUrl  // pg_connect_url: not a postgres:// URL, or a setting it cannot honour
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
        PgBadUrl → `PgBadUrl`
    }
}

// A statement the connection prepared: what Describe said of it, and the
// formats its results are asked in.
: PgStmt {
    String sql
    i hash  // of sql, compared before the text
    i seq  // its name is __pg_stmt_name seq
    String name
    ( Vec i ) param_oids
    ( Arc ( Vec PgCol ) ) cols  // fmt = the format asked for (pgw_result_fmt); every result shares them
    ( Vec i ) rfmts  // Bind's result-format codes for cols
    i used  // the connection's clock when last executed (LRU)
}

// The name a statement the connection prepares is given.
@ __pg_stmt_name i seq → String {
    : String name ( string_with_cap 24 )
    ( string_push_str name `nurl_s` )
    ( string_push_int name seq )
    ^ name
}

// How many prepared statements a connection keeps by default.
: i PG_STMT_CACHE 64

// The most a connection's send buffers keep between writes.
: i PG_BUF_KEEP 65536

// ── the connection ────────────────────────────────────────────────
//
// A PgConn's copies share one session, and they share it CONCURRENTLY:
// every request is queued with its messages (one Sync each) and the
// answers come back in the order the requests went out, so N fibers or
// threads on one connection keep up to N requests in flight — implicit
// pipelining. The state is in two halves:
//
//   PgTx, the send side, every copy's: the frontend bytes queued and not
//     written yet, the requests on their way (`pending`, in wire order),
//     the statement cache and what the server last reported. It is held
//     only between I/O, never across it, and a request is queued under it
//     in one step — its bytes appended AND its slot pushed — which is what
//     keeps the wire's order and `pending`'s the same.
//   PgConnImpl, the socket, its receive buffer and the answer being read:
//     the DRIVER's alone. A request queued while nobody drives makes its
//     caller the driver: it writes what is queued, reads, and hands each
//     answer to the request at the head of `pending` (through that
//     request's one-shot Channel), writing again whatever was queued
//     meanwhile, until its own answer is in — then it hands the socket to
//     the next waiting request and returns. No thread per connection, no
//     lock held during I/O; a waiting fiber parks and a thread blocks.
//
// One Sync per request: an error ends only its own request (the server
// skips to that request's Sync). A lost stream fails every request on its
// way with PgConnFail. The transaction status is the session's, as it
// always was: BEGIN … COMMIT through copies used at the same time
// interleaves with their other requests — the pool lends a connection to
// one borrower at a time for that.

// The socket and what reads it — the driver's. During startup, before the
// connection is shared, it is the whole state.
: PgConnImpl {
    TcpConn conn  // the transport: plaintext, or TLS once tcp_starttls ran
    i tls  // 0 plaintext, 1 TLS
    ( Vec u ) rxbuf  // backend bytes; messages from rpos on are not read yet
    i rpos
    ( Vec u ) txbuf  // the frontend messages being sent
    String lasterr  // startup's last ErrorResponse / failure text
    PgNotice err  // …in full
    i be_pid
    i be_key
    String srv_ver  // server_version from ParameterStatus (for the banner)
    i started  // 1 once the StartupMessage went out: say Terminate on close
    b broken  // an I/O or protocol failure: the stream is lost
    i txn  // ReadyForQuery's status at the end of startup
    ( Vec PgCollect ) partial  // the answer being read for the head of `pending`, when one is begun (at most one)
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

// What a waiting request is handed: its answer, or (`lead`) the socket —
// with an empty collector then, two buffers' worth. (A struct and not an
// enum: a payload moved out of an enum received from a Channel is
// dropped again with it today, agora #264.)
: PgReply {
    b lead
    PgCollect col
}

// A request on its way: where its answer goes, and the columns its rows
// come in — for an Execute of a cached statement, which sends no
// Describe, the statement's own description (shared); for any other
// request none, and the answer's own RowDescription says.
: PgSlot {
    i id
    ( Channel PgReply ) ch
    ( Arc ( Vec PgCol ) ) cols
}

// The send side: every copy's, held only between I/O.
: PgTx {
    ( Vec u ) buf  // frontend messages queued, not written yet
    ( Vec PgSlot ) pending  // requests whose answers have not come back, in wire order
    i next_id  // names the next request's slot
    b driving  // a request is driving the socket
    b broken  // the stream is lost: every request fails at once
    i txn  // the last ReadyForQuery status: 73 idle, 84 in a transaction, 69 failed one
    String lasterr  // last ErrorResponse (`[SQLSTATE] message`) / failure text
    PgNotice err  // …in full
    ( Vec PgStmt ) stmts  // the statement cache
    i stmt_cap
    i stmt_seq  // names the next statement
    i clock  // ticks per execution, for the LRU
    i tls
    String srv_ver
    String db_name  // connection identity, for the banner and \conninfo
    String user_name
    String host_name
    ( Arc ( Vec PgCol ) ) nocols  // the description of a request that brings its own
}

// A PgConn is a handle on both halves: every copy is the same connection,
// on any thread or fiber, and the last owner closes it.
: PgConn {
    ( Locked PgTx ) tx
    ( Locked PgConnImpl ) io
}

@ PgConn_share PgConn h → PgConn {
    ^ @ PgConn { ( Locked_share [PgTx] . h tx ) ( Locked_share [PgConnImpl] . h io ) }
}

@ PgConn_drop sink PgConn h → v {}

// The connection's text fields, copied out. lasterr is the last
// ErrorResponse (`[SQLSTATE] message`), empty if none.
@ pg_conn_lasterr PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . t lasterr )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

// The last error's SQLSTATE (`23505` a unique violation, …), empty if none.
@ pg_conn_sqlstate PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . . t err code )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

@ pg_conn_server_version PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . t srv_ver )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

@ pg_conn_db_name PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . t db_name )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

@ pg_conn_user_name PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . t user_name )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

@ pg_conn_host_name PgConn h → String {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : String r ( string_clone . t host_name )
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

// 1 when the connection runs over TLS, 0 when it is plaintext.
@ pg_conn_tls PgConn h → i {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : i r . t tls
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

// F once an I/O or protocol failure lost the stream: every request then
// fails with PgConnFail, and a pool drops the connection.
@ pg_conn_ok PgConn h → b {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : b r ! . t broken
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

// The transaction status the server last reported: 73 'I' idle, 84 'T'
// inside a transaction block, 69 'E' inside a failed one.
@ pg_conn_txn_status PgConn h → i {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : i r . t txn
    ( locked_restore [PgTx] . h tx t )
    ^ r
}

// How many prepared statements pg_query_params keeps (default
// PG_STMT_CACHE); 0 prepares each execution, keeping none. A smaller
// bound closes the least recently used ones on the next prepare.
@ pg_conn_set_stmt_cache PgConn h i n → v {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    = . t stmt_cap ? < n 0 0 n
    ( locked_restore [PgTx] . h tx t )
}

// The statements in the cache now.
@ pg_conn_stmt_count PgConn h → i {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : i r ( vec_len [PgStmt] . t stmts )
    ( locked_restore [PgTx] . h tx t )
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

// ── the pipeline ──────────────────────────────────────────────────
// A request goes on `pending` as its bytes go on `buf`, under one hold of
// the send side, so the wire's order and pending's agree. Its id says
// which answer is whose; the answer comes on `ch`.
@ __pg_slot inout PgTx t ( Channel PgReply ) ch ( Arc ( Vec PgCol ) ) cols → i {
    : i id . t next_id
    = . t next_id + id 1
    ( vec_push [PgSlot] . t pending @ PgSlot { id ( Channel_share [PgReply] ch ) ( arc_clone [( Vec PgCol )] cols ) } )
    ^ id
}

// …for a request whose answer describes its own rows.
@ __pg_slot_plain inout PgTx t ( Channel PgReply ) ch → i {
    : i id . t next_id
    = . t next_id + id 1
    ( vec_push [PgSlot] . t pending @ PgSlot { id ( Channel_share [PgReply] ch ) ( arc_clone [( Vec PgCol )] . t nocols ) } )
    ^ id
}

// Take the socket if nobody drives it (send side held): T when this
// request is now the driver.
@ __pg_claim inout PgTx t → b {
    ? . t driving { ^ F } {}
    = . t driving T
    ^ T
}

// The answer of a stream that was lost.
@ __pg_lost → PgCollect {
    : ~ PgCollect c ( pgw_collect_new )
    = . c rc 1
    = . c done T
    ^ c
}

// The answer to request `id`, queued by the caller (who has let the send
// side go; `drive` T when it took the socket): drive until it is in, or
// wait for it — and drive when the socket is handed over.
@ __pg_wait PgConn h ( Channel PgReply ) ch i id b drive → PgCollect {
    ? drive { ^ ( __pg_drive h id ) } {}
    ~ T {
        ?? ( chan_recv [PgReply] ch ) {
            T r → {
                ? . r lead { ^ ( __pg_drive h id ) } {}
                ^ . r col
            }
            F → { ^ ( __pg_lost ) }
        }
    }
    ^ ( __pg_lost )
}

// Queued requests go out. They are copied into the driver's buffer
// under the send side's lock and written outside it: a request is tens of
// bytes, so the copy costs less than the fresh buffer the send side was
// given before, and neither buffer is ever moved. A buffer a very large
// batch grew is let go, so its size is not kept for the connection's
// life. F when the write failed.
@ __pg_send_queued PgConn h inout PgConnImpl c → b {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    ( bytes_extend_bytes . c txbuf . t buf )
    ( vec_clear [u] . t buf )
    ? > ( vec_cap [u] . t buf ) PG_BUF_KEEP { = . t buf ( vec_with_cap [u] 1024 ) } {}
    ( locked_restore [PgTx] . h tx t )
    : ~ b ok T
    ? > ( vec_len [u] . c txbuf ) 0 {
        ?? ( tcp_write_all . c conn . c txbuf ) { T _ → {} F _ → { = ok F } }
    } {}
    ( vec_clear [u] . c txbuf )
    ? > ( vec_cap [u] . c txbuf ) PG_BUF_KEEP { = . c txbuf ( vec_with_cap [u] 1024 ) } {}
    ^ ok
}

// Drive the socket until the answer to request `id` is in: write what is
// queued — everything queued while the driver waited leaves in one write
// — read, and hand each answer to the request at the head of `pending`.
// Then the socket goes to the next waiting request (or nobody drives). A
// lost stream fails every request on its way.
//
// Every complete answer already read is handed over before the driver
// leaves, not only those up to its own: one read brings the answers of a
// whole batch, and stopping at its own made each of the others wait for
// the socket to change hands — a wake-up and a write per request rather
// than per batch. An answer is folded in a collector made when its first
// message is in (__pg_next_answer); one a read cut short waits in
// `partial` for whoever drives next.
@ __pg_drive PgConn h i id → PgCollect {
    : ~ PgConnImpl c ( locked_take [PgConnImpl] . h io )
    // A connection a fiber used has a non-blocking socket (std/net.nu's
    // fiber paths set it), and a thread's blocking calls on it would see
    // "no data yet" as a timeout: a pooled connection passes between
    // fibers and threads, so a thread driving it puts it back first
    // (memoised in the runtime: no syscall when it already is).
    ? == ( nurl_fiber_current ) 0 { ( tcp_set_nonblock_conn . c conn 0 ) } {}
    : ~ ? PgCollect mine @ ?PgCollect { F # PgCollect 0 }
    : ~ b have F
    : ~ b lost . c broken
    ~ & ! have ! lost {
        // Every answer already read, to its request.
        : ~ b more T
        ~ & more ! lost {
            ?? ( __pg_next_answer h c ) {
                T got → {
                    // The head's answer is complete: it leaves `pending`
                    // and goes to its request.
                    : ~ PgTx t ( locked_take [PgTx] . h tx )
                    = . t txn . got txn
                    : ?PgSlot head ( vec_remove [PgSlot] . t pending 0 )
                    ( locked_restore [PgTx] . h tx t )
                    ?? head {
                        T sl → {
                            ? == . sl id id { = mine @ ?PgCollect { T got } = have T } {
                                : b _sent ( chan_send [PgReply] . sl ch @ PgReply { F got } )
                            }
                        }
                        F → { = lost T }
                    }
                }
                F st → { ? < st 0 { = lost T } { = more F } }
            }
        }
        ? & ! have ! lost {
            // What was queued goes out, then the next answer is read.
            ? ! ( __pg_send_queued h c ) { = . c broken T = lost T } {}
            ? ! lost { ? ! ( __pg_fill c ) { = lost T } {} } {}
        } {}
    }
    // Leaving with its own answer: what was queued meanwhile goes out
    // first, so the next requests are on the wire while the socket
    // changes hands rather than after.
    ? & have ! lost {
        ? ! ( __pg_send_queued h c ) { = . c broken T = lost T } {}
    } {}
    ? lost { = . c broken T } {}
    ( locked_restore [PgConnImpl] . h io c )
    // The socket goes to the next waiting request, or nobody drives. A lost
    // stream fails every request still on its way, this one included.
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    ? lost {
        = . t broken T
        = . t driving F
        ~ > ( vec_len [PgSlot] . t pending ) 0 {
            ?? ( vec_remove [PgSlot] . t pending 0 ) {
                T sl → {
                    ? != . sl id id {
                        : b _sent ( chan_send [PgReply] . sl ch @ PgReply { F ( __pg_lost ) } )
                    } {}
                }
                F → {}
            }
        }
    } {
        ?? ( vec_get [PgSlot] . t pending 0 ) {
            T sl → { : b _sent ( chan_send [PgReply] . sl ch @ PgReply { T ( pgw_collect_for ( pgw_result_with . t nocols ) ) } ) }
            F → { = . t driving F }
        }
    }
    ( locked_restore [PgTx] . h tx t )
    // Its own answer — or, when the stream was lost before it came, the
    // lost stream's.
    ^ ?? mine { T x → x F → ( __pg_lost ) }
}

// The collector for request `sl`'s answer: in its statement's columns when
// it was a cached one's Execute (one share more of them), else in what
// its own RowDescription will say.
@ __pg_collect_for PgSlot sl → PgCollect {
    ^ ( pgw_collect_for ( pgw_result_with . sl cols ) )
}

// The collector for the answer of the head of `pending` — F when nobody is
// waiting for one, and an answer then means the stream is not what this
// side thinks it is.
@ __pg_head_collect inout PgTx t → ?PgCollect {
    ?? ( vec_get [PgSlot] . t pending 0 ) {
        T sl → { ^ @ ?PgCollect { T ( __pg_collect_for sl ) } }
        F → { ^ @ ?PgCollect { F # PgCollect 0 } }
    }
}

// The next answer, folded from the messages already read: the one begun
// before (held in `partial`), or a new one when a message of it is in. T
// with it when it is complete; F 0 when more must be read (what was
// folded so far waits in `partial`); F -1 when the stream is lost.
@ __pg_next_answer PgConn h inout PgConnImpl c → !PgCollect i {
    : i n0 ( pgw_frame . c rxbuf . c rpos )
    ? < n0 0 { ^ @ !PgCollect i { F -1 } } {}
    ? == n0 0 { ^ @ !PgCollect i { F 0 } } {}
    : ~ PgCollect col ?? ( vec_pop [PgCollect] . c partial ) {
        T x → x
        F → {
            : ~ PgTx t ( locked_take [PgTx] . h tx )
            : ?PgCollect fresh ( __pg_head_collect t )
            ( locked_restore [PgTx] . h tx t )
            ?? fresh { T x → x F → { ^ @ !PgCollect i { F -1 } } }
        }
    }
    ~ T {
        : i n ( pgw_frame . c rxbuf . c rpos )
        ? < n 0 { ^ @ !PgCollect i { F -1 } } {}
        ? == n 0 {
            ( vec_push [PgCollect] . c partial col )
            ^ @ !PgCollect i { F 0 }
        } {}
        : i at . c rpos
        ( pgw_collect_feed col ( __bget . c rxbuf at ) . c rxbuf + at 5 + at n )
        = . c rpos + at n
        ? . col done { ^ @ !PgCollect i { T col } } {}
    }
    ^ @ !PgCollect i { F -1 }
}

// A failed answer as its PgErr: the server's error (rc 3), kept as the
// connection's last, or the lost stream. The answer is lent: a caller
// whose answer succeeded moves its rows out itself (`. col res`), so a
// result is never copied on its way to the caller.
@ __pg_fail PgConn h PgCollect col → PgErr {
    ? == . col rc 3 {
        : ~ PgTx t ( locked_take [PgTx] . h tx )
        ?? . col err {
            T e → {
                = . t lasterr ( pgw_notice_text e )
                = . t err ( pgw_notice_clone e )
            }
            F → {}
        }
        ( locked_restore [PgTx] . h tx t )
        ^ # PgErr PgServerError
    } {}
    ^ # PgErr PgConnFail
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
        0
        F
        0
        ( vec_with_cap [PgCollect] 1 )
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
        T _ → {}
        F e → { ^ @ !PgConn PgErr { F e } }
    }
    // Ready: the send side starts empty, with what startup learned.
    : PgTx t @ PgTx {
        ( vec_with_cap [u] 1024 )
        ( vec_new [PgSlot] )
        0
        F
        F
        . c txn
        ( string_new )
        ( pgw_notice_empty )
        ( vec_new [PgStmt] )
        PG_STMT_CACHE
        0
        0
        tls
        ( string_clone . c srv_ver )
        ( string_from database )
        ( string_from user )
        ( string_from host )
        ( arc_new [( Vec PgCol )] ( vec_new [PgCol] ) )
    }
    ^ @ !PgConn PgErr { T @ PgConn { ( locked_new [PgTx] t ) ( locked_new [PgConnImpl] c ) } }
}

// ── connection URI ────────────────────────────────────────────────
// The URI that libpq, DATABASE_URL and hosting dashboards hand out:
//
//   postgres://[user[:password]@]host[:port][/database][?sslmode=…]
//
// (`postgresql://` too). User, password and database are percent-decoded;
// the port defaults to 5432, the user to `postgres` and the database to the
// user's name (the server's own default). sslmode is one of the four modes
// pg_connect implements — disable, prefer (the default, as libpq's),
// require, verify-full. Another scheme, no host, or any other query
// parameter is PgBadUrl: a setting the caller wrote is never ignored.
@ pg_connect_url s url → !PgConn PgErr {
    : Url u ?? ( url_parse url ) {
        T x → x
        F → { ^ @ !PgConn PgErr { F # PgErr PgBadUrl } }
    }
    : b pg_scheme | == 1 ( nurl_str_eq ( string_data . u scheme ) `postgres` ) == 1 ( nurl_str_eq ( string_data . u scheme ) `postgresql` )
    ? | ! pg_scheme == 0 ( string_len . u host ) { ^ @ !PgConn PgErr { F # PgErr PgBadUrl } } {}
    : ~ String user ( string_from `postgres` )
    : ~ String password ( string_new )
    : i ulen ( string_len . u userinfo )
    ? > ulen 0 {
        ?? ( string_index_of . u userinfo `:` ) {
            T at → {
                = user ( url_percent_decode ( string_data ( string_substr . u userinfo 0 at ) ) )
                = password ( url_percent_decode ( string_data ( string_substr . u userinfo + at 1 ulen ) ) )
            }
            F → { = user ( url_percent_decode ( string_data . u userinfo ) ) }
        }
    } {}
    : ~ String database ( string_clone user )
    : i plen ( string_len . u path )
    ? > plen 1 { = database ( url_percent_decode ( string_data ( string_substr . u path 1 plen ) ) ) } {}
    : ~ i sslmode 1
    : ( Vec UrlParam ) ps ( url_query_decode ( string_data . u query ) )
    : i n ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        : UrlParam p ( vec_at [UrlParam] ps k )
        : i m ? == 1 ( nurl_str_eq ( string_data . p key ) `sslmode` ) ( __pg_sslmode ( string_data . p val ) ) -1
        ? < m 0 { ^ @ !PgConn PgErr { F # PgErr PgBadUrl } } {}
        = sslmode m
        = k + k 1
    }
    : i port ? < . u port 0 5432 . u port
    ^ ( pg_connect ( string_data . u host ) port ( string_data user ) ( string_data password ) ( string_data database ) sslmode )
}

// libpq's name for an sslmode pg_connect implements, as its number; -1 for
// any other (allow and verify-ca are libpq modes this client does not
// offer, so they are refused rather than mapped to something else).
@ __pg_sslmode s name → i {
    ? == 1 ( nurl_str_eq name `disable` ) { ^ 0 } {}
    ? == 1 ( nurl_str_eq name `prefer` ) { ^ 1 } {}
    ? == 1 ( nurl_str_eq name `require` ) { ^ 2 } {}
    ? == 1 ( nurl_str_eq name `verify-full` ) { ^ 3 } {}
    ^ -1
}

// ── simple query ──────────────────────────────────────────────────
// Any number of statements (a script); text cells. The result is the
// last statement's.
@ pg_query PgConn h s sql → !PgResult PgErr {
    : ( Channel PgReply ) ch ( chan_new [PgReply] )
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    ? . t broken {
        ( locked_restore [PgTx] . h tx t )
        ^ @ !PgResult PgErr { F # PgErr PgConnFail }
    } {}
    ( pgw_query . t buf sql )
    : i id ( __pg_slot_plain t ch )
    : b drive ( __pg_claim t )
    ( locked_restore [PgTx] . h tx t )
    : PgCollect col ( __pg_wait h ch id drive )
    ? == . col rc 0 { ^ @ !PgResult PgErr { T . col res } } {}
    ^ @ !PgResult PgErr { F ( __pg_fail h col ) }
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
    ^ ( __pg_extended h sql params )
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

@ __pg_stmt_find inout PgTx t s sql i hsh → i {
    : i n ( vec_len [PgStmt] . t stmts )
    : ~ i k 0
    ~ < k n {
        : PgStmt st ( vec_at [PgStmt] . t stmts k )
        ? & == . st hash hsh != 0 ( nurl_str_eq ( string_data . st sql ) sql ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Drop cache entries until fewer than `keep` remain, least recently used
// first, a Close for each appended to the request being queued. A request
// queued earlier that runs one of them is ahead of its Close on the wire.
@ __pg_stmt_trim inout PgTx t i keep → v {
    ~ & > ( vec_len [PgStmt] . t stmts ) 0 >= ( vec_len [PgStmt] . t stmts ) keep {
        : i n ( vec_len [PgStmt] . t stmts )
        : ~ i old 0
        : ~ i k 1
        ~ < k n {
            ? < . ( vec_at [PgStmt] . t stmts k ) used . ( vec_at [PgStmt] . t stmts old ) used { = old k } {}
            = k + k 1
        }
        ?? ( vec_remove [PgStmt] . t stmts old ) {
            T gone → { ( pgw_close . t buf 83 ( string_data . gone name ) ) }
            F → {}
        }
    }
}

// Parse + Describe + Sync under `name`: the statement as the server sees
// it, the formats its results will be asked in decided from the columns.
@ __pg_prepare PgConn h s sql i seq → !PgStmt PgErr {
    : String name ( __pg_stmt_name seq )
    : ( Channel PgReply ) ch ( chan_new [PgReply] )
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    ? . t broken {
        ( locked_restore [PgTx] . h tx t )
        ^ @ !PgStmt PgErr { F # PgErr PgConnFail }
    } {}
    ( pgw_parse . t buf ( string_data name ) sql )
    ( pgw_describe . t buf 83 ( string_data name ) )
    ( pgw_sync . t buf )
    : i id ( __pg_slot_plain t ch )
    : b drive ( __pg_claim t )
    : i clock . t clock
    ( locked_restore [PgTx] . h tx t )
    : PgCollect col ( __pg_wait h ch id drive )
    ? != . col rc 0 { ^ @ !PgStmt PgErr { F ( __pg_fail h col ) } } {}
    // The columns, each in the format it will be asked in.
    : ( Vec PgCol ) desc ( _pg_cols . col res )
    : i nc ( vec_len [PgCol] desc )
    : ( Vec PgCol ) cols ( vec_with_cap [PgCol] nc )
    : ( Vec i ) fmts ( vec_with_cap [i] nc )
    : ~ i nbin 0
    : ~ i k 0
    ~ < k nc {
        : PgCol d ( vec_at [PgCol] desc k )
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
    : ( Vec i ) poids ?? . col param_oids { T v → ( vec_clone [i] v ) F → ( vec_new [i] ) }
    ^ @ !PgStmt PgErr { T @ PgStmt {
            ( string_from sql )
            ( __pg_hash sql )
            seq
            name
            poids
            ( arc_new [( Vec PgCol )] cols )
            rfmts
            clock
        } }
}

// The server no longer has the statement as it was described: it was
// deallocated (26000, DISCARD ALL / DEALLOCATE), or a table it reads
// changed shape under it (0A000, "cached plan must not change result type").
@ __pg_stale_err ? PgNotice err → b {
    ?? err {
        T e → {
            : s code ( string_data . e code )
            ^ | != 0 ( nurl_str_eq code `26000` ) != 0 ( nurl_str_eq code `0A000` )
        }
        F → { ^ F }
    }
}

// Take statement `name` out of the cache, its Close queued: the request
// queued next — the same caller's fresh prepare — carries it.
@ __pg_forget PgConn h String name → v {
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : i n ( vec_len [PgStmt] . t stmts )
    : ~ i at -1
    : ~ i k 0
    ~ < k n {
        ? ( string_eq . ( vec_at [PgStmt] . t stmts k ) name name ) { = at k } {}
        = k + k 1
    }
    ? >= at 0 { : ?PgStmt _gone ( vec_remove [PgStmt] . t stmts at ) } {}
    ( pgw_close . t buf 83 ( string_data name ) )
    ( locked_restore [PgTx] . h tx t )
}

@ __pg_extended PgConn h s sql ( Vec PgVal ) params → !PgResult PgErr {
    : i hsh ( __pg_hash sql )
    : ~ i tries 0
    ~ T {
        : ( Channel PgReply ) ch ( chan_new [PgReply] )
        : ~ PgTx t ( locked_take [PgTx] . h tx )
        ? . t broken {
            ( locked_restore [PgTx] . h tx t )
            ^ @ !PgResult PgErr { F # PgErr PgConnFail }
        } {}
        = . t clock + . t clock 1
        : i at ? > . t stmt_cap 0 ( __pg_stmt_find t sql hsh ) -1
        ? >= at 0 {
            // Cached: its run is queued under the same hold that found it,
            // so no Close a later request queues can overtake its Bind.
            : ~ PgStmt st ?? ( vec_remove [PgStmt] . t stmts at ) {
                T x → x
                F → {
                    ( locked_restore [PgTx] . h tx t )
                    ^ @ !PgResult PgErr { F # PgErr PgProtocol }
                }
            }
            = . st used . t clock
            ( pgw_bind . t buf `` ( string_data . st name ) params . st param_oids . st rfmts )
            ( pgw_execute . t buf `` 0 )
            ( pgw_sync . t buf )
            : i id ( __pg_slot t ch . st cols )
            : i sseq . st seq
            ( vec_push [PgStmt] . t stmts st )
            : b drive ( __pg_claim t )
            ( locked_restore [PgTx] . h tx t )
            : PgCollect col ( __pg_wait h ch id drive )
            // A stale statement outside a transaction failed before it did
            // anything: close it, prepare it afresh and run it once more.
            ? & & == tries 0 == . col rc 3 & == . col txn 73 ( __pg_stale_err . col err ) {
                = tries 1
                ( __pg_forget h ( __pg_stmt_name sseq ) )
            } {
                ? == . col rc 0 { ^ @ !PgResult PgErr { T . col res } } {}
                ^ @ !PgResult PgErr { F ( __pg_fail h col ) }
            }
        } {
            // Not cached, or no cache: prepare under a name of its own (an
            // unnamed statement could be replaced by another request's
            // Parse between the two round trips), then run.
            : i seq . t stmt_seq
            = . t stmt_seq + seq 1
            ( locked_restore [PgTx] . h tx t )
            : PgStmt st \ ( __pg_prepare h sql seq )
            : ~ PgTx t2 ( locked_take [PgTx] . h tx )
            ? . t2 broken {
                ( locked_restore [PgTx] . h tx t2 )
                ^ @ !PgResult PgErr { F # PgErr PgConnFail }
            } {}
            ( pgw_bind . t2 buf `` ( string_data . st name ) params . st param_oids . st rfmts )
            ( pgw_execute . t2 buf `` 0 )
            : i id ( __pg_slot t2 ch . st cols )
            // Into the cache — unless it has no room for any, or another
            // request prepared the same SQL meanwhile: then this one is
            // closed after its run, in the same request.
            ? & > . t2 stmt_cap 0 < ( __pg_stmt_find t2 sql hsh ) 0 {
                ( __pg_stmt_trim t2 . t2 stmt_cap )
                ( vec_push [PgStmt] . t2 stmts st )
            } {
                ( pgw_close . t2 buf 83 ( string_data . st name ) )
                // No cache any more: what it still holds goes too.
                ? <= . t2 stmt_cap 0 { ( __pg_stmt_trim t2 1 ) } {}
            }
            ( pgw_sync . t2 buf )
            : b drive ( __pg_claim t2 )
            ( locked_restore [PgTx] . h tx t2 )
            : PgCollect col ( __pg_wait h ch id drive )
            ? == . col rc 0 { ^ @ !PgResult PgErr { T . col res } } {}
            ^ @ !PgResult PgErr { F ( __pg_fail h col ) }
        }
    }
    ^ @ !PgResult PgErr { F # PgErr PgProtocol }
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
    : ~ PgTx t ( locked_take [PgTx] . h tx )
    : b ok ! . t broken
    : i txn . t txn
    ( locked_restore [PgTx] . h tx t )
    ? & ok != txn 73 {
        ?? ( pg_query h `ROLLBACK` ) { T _ → {} F _ → { ^ F } }
        ^ == ( pg_conn_txn_status h ) 73
    } {}
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
